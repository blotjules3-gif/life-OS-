import Foundation
import NaturalLanguage

/// Classification légère du message utilisateur AVANT d'appeler Apple Intelligence.
///
/// Objectif : router chaque message vers le prompt le mieux adapté au lieu
/// d'envoyer un mégaprompt uniforme. Apple Intelligence a une fenêtre contexte
/// limitée → chaque token économisé compte.
///
/// Approche : NLTagger (framework Apple, gratuit, local) + heuristiques regex.
/// Aucun réseau, aucune latence perceptible.
enum MessageClassifier {

    // MARK: - Types

    struct Classification {
        let sentiment: Sentiment
        let intentType: IntentType
        let complexity: Complexity
        let dominantLanguage: Language
        let topicsDetected: [String]     // AppCategory.rawValue
        let containsQuestion: Bool
        let containsNumbers: Bool
        let charCount: Int
    }

    /// Ton émotionnel dominant. Utilisé pour choisir le style de réponse.
    enum Sentiment: String {
        case positive      // joie, fierté, motivation
        case neutral       // factuel
        case frustrated    // agacement, colère
        case discouraged   // fatigue, découragement, tristesse
        case anxious       // stress, doute, peur
    }

    /// Type d'intent principal. Le prompt système s'adapte à ce type.
    enum IntentType: String {
        case actionRequest          // "crée une habitude", "ajoute une tâche"
        case profileUpdate          // "je pèse 74 kg"
        case factualQuestion        // "combien de protéines je devrais manger ?"
        case adviceRequest          // "comment mieux dormir ?"
        case emotionalShare         // "j'ai encore craqué"
        case chitchat               // "salut", "ça va ?"
        case complaint              // "tu comprends rien"
        case unknown
    }

    /// Complexité — détermine si on injecte le corpus training FULL ou COMPACT.
    enum Complexity: String {
        case simple      // < 30 chars, 1 intent
        case moderate    // 30-100 chars
        case complex     // > 100 chars OU multi-intent
    }

    enum Language: String {
        case fr, en, other
    }

    // MARK: - Entry point

    /// Analyse le message et retourne sa classification.
    /// Latence typique : < 5 ms.
    static func classify(_ message: String) -> Classification {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.folding(options: .diacriticInsensitive, locale: .current).lowercased()

        return Classification(
            sentiment: detectSentiment(lower),
            intentType: detectIntentType(lower),
            complexity: detectComplexity(trimmed),
            dominantLanguage: detectLanguage(trimmed),
            topicsDetected: detectTopics(trimmed),
            containsQuestion: trimmed.contains("?"),
            containsNumbers: trimmed.rangeOfCharacter(from: .decimalDigits) != nil,
            charCount: trimmed.count
        )
    }

    // MARK: - Sentiment (heuristiques FR)

    private static func detectSentiment(_ m: String) -> Sentiment {
        // Frustration — priorité haute (bug user est frustré, on doit s'aligner)
        let frustrated = [
            "tu comprends rien", "tu piges pas", "c'est pas ca", "cest pas ca",
            "j'ai deja dit", "jai deja dit", "encore une fois", "pourquoi tu",
            "putain", "merde", "chier", "n'importe quoi", "n'importe quoi",
            "j'en peux plus", "jen peux plus", "j'ai pas demande",
        ]
        if frustrated.contains(where: { m.contains($0) }) { return .frustrated }

        // Découragement
        let discouraged = [
            "j'ai craque", "jai craque", "j'ai rate", "jai rate",
            "j'arrive pas", "jarrive pas", "je n'y arrive pas", "je ny arrive pas",
            "j'ai pas la force", "jai pas la force", "ca sert a rien",
            "j'abandonne", "jabandonne", "je suis nul", "je suis fatigue",
            "epuise", "au bout", "vide",
        ]
        if discouraged.contains(where: { m.contains($0) }) { return .discouraged }

        // Anxiété / doute
        let anxious = [
            "je stress", "je suis stresse", "j'ai peur", "jai peur", "anxieux",
            "j'hesite", "jhesite", "je sais pas quoi", "je me demande",
            "je crains", "angoisse", "inquiet",
        ]
        if anxious.contains(where: { m.contains($0) }) { return .anxious }

        // Positif
        let positive = [
            "j'ai reussi", "jai reussi", "j'ai fait", "jai fait", "content",
            "fier", "enfin", "genial", "top", "excellent", "parfait",
            "bien joue", "regarde",
        ]
        if positive.contains(where: { m.contains($0) }) { return .positive }

        return .neutral
    }

    // MARK: - Intent type

    private static func detectIntentType(_ m: String) -> IntentType {
        // Complaint — se traite AVANT tout car recouvre frustration
        let complaint = ["tu comprends rien", "tu piges pas", "j'ai pas demande",
                         "cest pas ce que", "c'est pas ce que", "n'importe quoi"]
        if complaint.contains(where: { m.contains($0) }) { return .complaint }

        // Action request
        let actionVerbs = [
            "ajoute", "rajoute", "cree", "creer", "crée", "créer",
            "traque", "tracker", "suivre", "note-moi", "note moi",
            "rappelle-moi", "rappelle moi", "programme", "planifie",
            "mets en habitude", "tu peux creer", "tu peux ajouter",
            "je veux tracker", "il faut que je"
        ]
        if actionVerbs.contains(where: { m.contains($0) }) { return .actionRequest }

        // Profile update — mention de valeur factuelle sur soi
        let profileMarkers = [
            "je pese", "je pèse", "je fais ", "je mesure", "j'ai ", "je bois",
            "je mange", "mon poids", "ma taille", "mon age", "mon objectif"
        ]
        let hasProfileMarker = profileMarkers.contains(where: { m.contains($0) })
        let hasNumber = m.rangeOfCharacter(from: .decimalDigits) != nil
        if hasProfileMarker && hasNumber { return .profileUpdate }

        // Factual question — commence par "combien", "quel", "où", ou contient "?"
        let questionStarters = ["combien", "quel", "quelle", "quelles", "quels",
                                "ou en suis", "j'en suis ou", "montre"]
        if questionStarters.contains(where: { m.hasPrefix($0) || m.contains(" \($0)") }) {
            return .factualQuestion
        }

        // Advice request
        let adviceMarkers = ["comment", "aide", "que faire", "que dois", "conseil",
                             "recommande", "propose", "suggere"]
        if adviceMarkers.contains(where: { m.contains($0) }) { return .adviceRequest }

        // Emotional share — sentiment déjà détecté ≠ neutral, pas d'action
        if detectSentiment(m) != .neutral { return .emotionalShare }

        // Chitchat court
        let chitchat = ["salut", "hello", "bonjour", "bonsoir", "coucou",
                        "ca va", "ça va", "quoi de neuf", "merci"]
        if m.count < 25, chitchat.contains(where: { m.contains($0) }) { return .chitchat }

        return .unknown
    }

    // MARK: - Complexity

    private static func detectComplexity(_ message: String) -> Complexity {
        let count = message.count
        // Comptage rapide de intents/mentions
        let separators = message.components(separatedBy: CharacterSet(charactersIn: ",;.!?\n"))
        let phrases = separators.filter { $0.trimmingCharacters(in: .whitespaces).count > 5 }
        if count > 100 || phrases.count > 3 { return .complex }
        if count > 30 { return .moderate }
        return .simple
    }

    // MARK: - Language

    private static func detectLanguage(_ message: String) -> Language {
        guard message.count > 5 else { return .fr }  // trop court, on assume FR
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(message)
        switch recognizer.dominantLanguage?.rawValue {
        case "fr": return .fr
        case "en": return .en
        default: return .other
        }
    }

    // MARK: - Topics (délégué à CategoryDetector)

    private static func detectTopics(_ message: String) -> [String] {
        CategoryDetector.detect(from: message).map { $0.category }
    }
}
