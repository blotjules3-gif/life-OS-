import Foundation
import UserNotifications

/// Décide si un provider cloud doit être bloqué pour la journée courante,
/// selon le seuil de coût configuré par l'user via `AICostGuardPreference`.
///
/// Contrat :
/// - Vérifie AVANT chaque `AIProvider.complete()` dans le router
/// - Si `dailyCapEUR == 0` (défaut) → jamais bloqué, comportement identique
///   à avant Loop 6
/// - Sinon, calcule le cumul du jour tous providers cloud confondus via
///   `AIProviderUsageTracker.monthlySnapshot` filtré sur aujourd'hui
/// - Renvoie `true` si cumul >= cap
/// - Bloque UNIQUEMENT les providers tarifés (Apple Intelligence + LocalCoach
///   passent toujours — le user garde son coach fonctionnel)
/// - Envoie une notification unique par jour quand le cap est franchi
///   (pas de spam)
@MainActor
enum AICostGuard {

    /// Vrai si ce provider doit être bloqué pour la journée courante.
    static func isBlocked(providerID: String) -> Bool {
        // Providers gratuits : jamais bloqués (Apple Intelligence, LocalCoach)
        guard AIProviderUsageTracker.pricing(for: providerID) != nil else { return false }

        let cap = AICostGuardPreference.shared.dailyCapEUR
        guard cap > 0 else { return false }  // pas de cap actif

        let totalEUR = todayCumulativeCostEUR()
        return totalEUR >= cap
    }

    /// Cumul EUR de tous les providers cloud aujourd'hui.
    static func todayCumulativeCostEUR() -> Double {
        var totalUSD: Double = 0
        for slot in AIProviderCredentials.Slot.allCases {
            let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: slot.providerID)
            totalUSD += snap.estimatedCostUSD
        }
        return AIProviderUsageTracker.usdToEUR(totalUSD)
    }

    /// À appeler APRÈS chaque enregistrement dans le tracker. Vérifie si le
    /// cap vient d'être franchi et envoie une notif unique/jour.
    static func checkAndNotifyIfCapReached() {
        let pref = AICostGuardPreference.shared
        guard pref.isEnabled else { return }

        let today = AIProviderUsageTracker.today()
        // Déjà notifié aujourd'hui ? Skip.
        guard pref.lastNotifiedDay != today else { return }

        let cumul = todayCumulativeCostEUR()
        guard cumul >= pref.dailyCapEUR else { return }

        // Marque comme notifié AVANT l'envoi — évite double envoi si le user
        // enchaîne 2 requêtes très vite.
        pref.lastNotifiedDay = today

        let content = UNMutableNotificationContent()
        content.title = "Coach — limite atteinte"
        content.body = String(
            format: "Ton seuil quotidien de %.2f € est atteint. Ton coach reste actif via Apple Intelligence ou en local, mais les providers cloud sont mis en pause jusqu'à demain.",
            pref.dailyCapEUR
        )
        content.sound = .default
        content.threadIdentifier = "coach.costguard"

        let request = UNNotificationRequest(
            identifier: "coach.costguard.\(today)",
            content: content,
            trigger: nil  // livraison immédiate
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
