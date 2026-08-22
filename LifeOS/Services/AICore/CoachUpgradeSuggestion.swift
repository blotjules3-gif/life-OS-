import Combine
import Foundation

/// Décide s'il faut suggérer à l'user d'upgrader vers un provider cloud plus
/// puissant, en analysant les signaux de frustration.
///
/// Règles :
/// - **Aucune suggestion** si l'user a déjà branché une clé cloud (il connaît).
/// - **Aucune suggestion** si l'user a explicitement fermé la bannière
///   récemment (respect du choix — pas de spam).
/// - **Suggestion active** si : ≥3 dislikes dans les 24h AND provider actuel =
///   Apple Intelligence ou LocalCoach.
///
/// L'user peut fermer la bannière → snoozée 7 jours. Après il revoit une
/// suggestion si les critères de frustration réapparaissent.
@MainActor
final class CoachUpgradeSuggestion: ObservableObject {
    static let shared = CoachUpgradeSuggestion()

    private let dismissedAtKey = "coach.upgrade.suggestion.dismissedAt"
    private let snoozeDurationSec: TimeInterval = 7 * 86_400   // 7 jours
    private let recentWindowSec: TimeInterval = 24 * 3_600     // 24h
    private let dislikeThreshold = 3

    /// Publie les changements → la vue observe et affiche/cache la bannière.
    @Published private(set) var lastEval: Date = .now

    private init() {}

    /// Devrait-on afficher la bannière d'upgrade en ce moment ?
    func shouldSuggestUpgrade() -> Bool {
        // Snoozed récemment ? Silence.
        if let dismissed = UserDefaults.standard.object(forKey: dismissedAtKey) as? Date,
           Date().timeIntervalSince(dismissed) < snoozeDurationSec {
            return false
        }

        // A déjà une clé cloud ? Silence.
        let hasAnyCloudKey = AIProviderCredentials.Slot.allCases.contains { slot in
            AIProviderCredentials.shared.hasKey(for: slot)
        }
        if hasAnyCloudKey { return false }

        // Frustration détectée ?
        let recentDislikes = CoachFeedbackStore.recentDislikeCount(within: recentWindowSec)
        guard recentDislikes >= dislikeThreshold else { return false }

        return true
    }

    /// User a fermé la bannière → snooze 7 jours.
    func dismissForNow() {
        UserDefaults.standard.set(Date(), forKey: dismissedAtKey)
        lastEval = .now
    }

    /// Reset le snooze (utilisé par DataEraser + debug).
    func reset() {
        UserDefaults.standard.removeObject(forKey: dismissedAtKey)
        lastEval = .now
    }

    /// À appeler après chaque dislike enregistré → refresh la publication
    /// pour que la vue re-évalue.
    func refresh() {
        lastEval = .now
    }
}
