import Foundation
import UserNotifications

/// Planifie 2 notifications quotidiennes pour créer un rythme d'engagement
/// coach : bilan matin + bilan soir aux heures choisies par l'user.
///
/// Loop 12 fixes :
///   - B5 : vérif permission notification avant d'ajouter les requests
///   - B6 : heures configurables via UserDefaults (défaut 8h / 21h)
///   - M6 : `scheduleAllIfNeeded` idempotent avec flag — ne re-schedule que
///          si la config a changé, pas à chaque foreground
@MainActor
enum CoachDailyBilan {

    private static let morningID = "coach.bilan.morning"
    private static let eveningID = "coach.bilan.evening"

    // Clés UserDefaults — user-configurable via CoachAIProviderView.
    private static let enabledKey = "coach.bilan.enabled"
    private static let morningHourKey = "coach.bilan.morning.hour"
    private static let eveningHourKey = "coach.bilan.evening.hour"
    private static let lastScheduledConfigKey = "coach.bilan.lastConfigHash"

    static let defaultMorningHour = 8
    static let defaultEveningHour = 21

    // MARK: - Preferences

    /// Vrai si l'user a activé les bilans quotidiens. Défaut : true.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            // Après changement, re-planifie (force re-schedule).
            UserDefaults.standard.removeObject(forKey: lastScheduledConfigKey)
        }
    }

    static var morningHour: Int {
        get {
            let h = UserDefaults.standard.integer(forKey: morningHourKey)
            return (5...12).contains(h) ? h : defaultMorningHour
        }
        set {
            UserDefaults.standard.set(newValue, forKey: morningHourKey)
            UserDefaults.standard.removeObject(forKey: lastScheduledConfigKey)
        }
    }

    static var eveningHour: Int {
        get {
            let h = UserDefaults.standard.integer(forKey: eveningHourKey)
            return (18...23).contains(h) ? h : defaultEveningHour
        }
        set {
            UserDefaults.standard.set(newValue, forKey: eveningHourKey)
            UserDefaults.standard.removeObject(forKey: lastScheduledConfigKey)
        }
    }

    // MARK: - Scheduling

    /// Point d'entrée idempotent (Loop 12 fix M6) — appelable à chaque
    /// `onAppear` sans coût iOS répété. Ne re-schedule que si la config
    /// a changé (hash calculé sur enabled + heures).
    static func scheduleAllIfNeeded() {
        let currentHash = configHash()
        let lastHash = UserDefaults.standard.string(forKey: lastScheduledConfigKey)
        guard currentHash != lastHash else { return }

        Task { @MainActor in
            await performScheduling()
            UserDefaults.standard.set(currentHash, forKey: lastScheduledConfigKey)
        }
    }

    /// Force le re-schedule (utilisé par l'écran Réglages après un changement).
    static func rescheduleNow() {
        UserDefaults.standard.removeObject(forKey: lastScheduledConfigKey)
        scheduleAllIfNeeded()
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [morningID, eveningID]
        )
        UserDefaults.standard.removeObject(forKey: lastScheduledConfigKey)
    }

    /// Effectue le vrai scheduling après vérif permission (Loop 12 fix B5).
    private static func performScheduling() async {
        // Cancel existant d'abord — évite doublons si l'user a changé les heures.
        cancelAll()

        guard isEnabled else {
            AppLog.coach.info("CoachDailyBilan: désactivé, no-op")
            return
        }

        // Loop 12 fix B5 — check permission avant scheduling
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            AppLog.coach.warning("CoachDailyBilan: notifications non autorisées, no-op")
            return
        }

        scheduleMorning()
        scheduleEvening()
    }

    // MARK: - Notifications

    private static func scheduleMorning() {
        let content = UNMutableNotificationContent()
        content.title = "Ton bilan du matin"
        content.body = "Ouvre le chat pour voir ton sommeil et ton énergie du jour."
        content.sound = .default
        content.threadIdentifier = "coach.bilan"
        content.userInfo = [
            "lifeos.deeplink": deepLink(prefill: "Fais le bilan de ma nuit et suggère-moi une priorité pour aujourd'hui."),
            "lifeos.signal": "daily_morning"
        ]

        var comps = DateComponents()
        comps.hour = morningHour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: morningID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private static func scheduleEvening() {
        let content = UNMutableNotificationContent()
        content.title = "Ton récap du soir"
        content.body = "Comment s'est passée ta journée ? On fait le point ?"
        content.sound = .default
        content.threadIdentifier = "coach.bilan"
        content.userInfo = [
            "lifeos.deeplink": deepLink(prefill: "Fais le récap de ma journée : habitudes, énergie, progrès."),
            "lifeos.signal": "daily_evening"
        ]

        var comps = DateComponents()
        comps.hour = eveningHour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: eveningID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Helpers

    /// Construit le deep link chat avec prefill URL-encodé proprement (fix m4).
    private static func deepLink(prefill: String) -> String {
        var components = URLComponents()
        components.scheme = "lifeos"
        components.host = "coach"
        components.queryItems = [URLQueryItem(name: "prefill", value: prefill)]
        return components.url?.absoluteString ?? "lifeos://coach"
    }

    /// Hash simple de la config → détecte les changements sans re-scheduler.
    private static func configHash() -> String {
        "\(isEnabled)-\(morningHour)-\(eveningHour)"
    }
}
