import Foundation

/// Détecte automatiquement les "à côté" du coach en observant le
/// comportement user : si l'user reformule sa question dans les 90 sec après
/// une réponse coach, c'est probablement un signal que le coach a raté.
///
/// Cela remonte dans `CoachFeedbackStore` comme dislike implicite silencieux
/// (pas de toast, pas d'action UI) — enrichit la boucle d'apprentissage sans
/// forcer l'user à taper "Pas top" activement.
///
/// Utilisation :
///   `CoachOffTopicDetector.trackUserMessage(text: content, previousAssistant: last)`
///   → si détection, enregistre auto dans CoachFeedbackStore
@MainActor
enum CoachOffTopicDetector {

    /// Fenêtre en secondes pendant laquelle une reformulation est considérée
    /// comme un signal d'à côté.
    private static let windowSec: TimeInterval = 90

    /// Seuil de similarité (Jaccard sur tokens ≥3 chars) au-delà duquel on
    /// considère que l'user a reformulé.
    /// Loop 12 fix M3 — passe 0.5 → 0.7 pour réduire les faux positifs
    /// (user qui améliore sa propre question sans que le coach ait raté).
    private static let similarityThreshold: Double = 0.7

    /// Analyse un nouveau message user contre le message précédent.
    /// Enregistre un dislike implicite si :
    /// - Un message user précédent existe dans les `windowSec`
    /// - Sa similarité avec le nouveau est ≥ seuil
    /// - Un message coach a répondu entre les deux
    static func trackUserMessage(
        currentText: String,
        previousUserText: String?,
        previousUserDate: Date?,
        assistantResponse: String?
    ) {
        guard let prev = previousUserText,
              let prevDate = previousUserDate,
              let assistant = assistantResponse,
              !assistant.isEmpty else { return }

        let elapsed = Date().timeIntervalSince(prevDate)
        guard elapsed < windowSec else { return }

        let similarity = jaccardSimilarity(prev, currentText)
        guard similarity >= similarityThreshold else { return }

        // Signal d'à côté détecté → dislike implicite sur la réponse coach.
        CoachFeedbackStore.record(.dislike, response: assistant, reason: .offTopic)
        CoachUpgradeSuggestion.shared.refresh()
        AppLog.coach.info("CoachOffTopicDetector: reformulation détectée (similarité \(similarity, privacy: .public))")
    }

    // MARK: - Similarity

    /// Jaccard : |A∩B| / |A∪B| sur tokens normalisés ≥ 3 chars.
    static func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let tokensA = tokenize(a)
        let tokensB = tokenize(b)
        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0 }
        let intersection = tokensA.intersection(tokensB).count
        let union = tokensA.union(tokensB).count
        return Double(intersection) / Double(union)
    }

    private static let stopwords: Set<String> = [
        "que", "qui", "quoi", "quand", "comment", "pourquoi", "est", "sont",
        "avec", "pour", "dans", "sur", "par", "les", "des", "une", "mon", "ton"
    ]

    private static func tokenize(_ text: String) -> Set<String> {
        let normalized = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopwords.contains($0) }
        )
    }
}
