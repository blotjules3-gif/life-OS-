import Foundation
import UserNotifications

/// Planifie une notification récurrente le 1er de chaque mois à 10h pour
/// proposer à l'user d'ouvrir son bilan mensuel dans le chat coach.
///
/// Tap → deep link `lifeos://coach?prefill=<bilan généré>` — le coach
/// reçoit le résumé texte et peut réagir dessus (analyser, féliciter,
/// suggérer des ajustements).
///
/// Idempotent : re-schedule uniquement si la config a changé (activation).
/// Vérif permission notif avant scheduling.
@MainActor
enum MonthlyReviewScheduler {

    private static let notifID = "coach.monthly.review"
    private static let enabledKey = "coach.monthly.enabled"
    private static let lastConfigKey = "coach.monthly.lastConfig"

    /// Activation user (défaut : true).
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            UserDefaults.standard.removeObject(forKey: lastConfigKey)
        }
    }

    /// À appeler au boot depuis `LifeOSApp.onAppear`. Idempotent.
    static func scheduleIfNeeded() {
        let currentConfig = "\(isEnabled)"
        let lastConfig = UserDefaults.standard.string(forKey: lastConfigKey)
        guard currentConfig != lastConfig else { return }

        Task { @MainActor in
            await performScheduling()
            UserDefaults.standard.set(currentConfig, forKey: lastConfigKey)
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notifID])
        UserDefaults.standard.removeObject(forKey: lastConfigKey)
    }

    private static func performScheduling() async {
        cancel()
        guard isEnabled else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            AppLog.coach.warning("MonthlyReviewScheduler: notifications non autorisées")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Ton bilan du mois"
        content.body = "30 jours résumés — habitudes, sommeil, progrès. Ouvre le chat pour en discuter."
        content.sound = .default
        content.threadIdentifier = "coach.monthly"

        // Deep link vers le chat avec le résumé pré-rempli — généré au tap
        // via `MonthlyReviewGenerator.generateSummary()`.
        content.userInfo = [
            "lifeos.deeplink": "lifeos://coach?prefill=%5BMONTHLY_REVIEW%5D",
            "lifeos.signal": "monthly_review"
        ]

        var comps = DateComponents()
        comps.day = 1
        comps.hour = 10
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: notifID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
