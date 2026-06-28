import Foundation
import UserNotifications

/// Gestion centralisée des notifications locales (rappels hydratation, coucher, skincare,
/// échéances admin, anniversaires, maintenance, etc.).
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
        } catch {
            // Retry without criticalAlert (requires Apple entitlement)
            return (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Alarme réveil — time-sensitive, perce le mode Ne pas déranger, déclenche l'app au tap.
    func scheduleAlarm(hour: Int, minute: Int, userName: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["lifeos.wakeup", "lifeos.wakeup.preview"]
        )

        // Alarme principale
        let content = UNMutableNotificationContent()
        content.title = "Réveil LifeOS"
        content.body = userName.isEmpty
            ? "C'est l'heure. Lance ta journée."
            : "Bonjour \(userName) ! C'est l'heure."
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "LIFEOS_ALARM"

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "lifeos.wakeup", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        // Preview H-5 min — prépare le widget si l'app est ouverte, sinon montre une bannière
        let previewContent = UNMutableNotificationContent()
        previewContent.title = "Réveil dans 5 minutes"
        previewContent.body = "Ton briefing du matin est prêt."
        previewContent.sound = .default
        previewContent.interruptionLevel = .timeSensitive
        previewContent.categoryIdentifier = "LIFEOS_ALARM"
        previewContent.userInfo = ["type": "wakeup_preview", "alarmHour": hour, "alarmMinute": minute,
                                   "userName": userName]

        let totalMinutes = hour * 60 + minute - 5
        var preComps = DateComponents()
        preComps.hour = ((totalMinutes / 60) % 24 + 24) % 24
        preComps.minute = ((totalMinutes % 60) + 60) % 60
        let preTrigger = UNCalendarNotificationTrigger(dateMatching: preComps, repeats: true)
        let preRequest = UNNotificationRequest(
            identifier: "lifeos.wakeup.preview",
            content: previewContent,
            trigger: preTrigger
        )
        UNUserNotificationCenter.current().add(preRequest)
    }

    /// Notification ponctuelle à une date précise.
    func schedule(id: String, title: String, body: String, at date: Date) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rappel quotidien récurrent (ex: hydratation, coucher progressif, mewing).
    func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rappel quotidien récurrent AVEC boutons d'action (catégorie) + payload.
    /// Sert aux notifs de confirmation « Tu as bien fait X ? → Oui ✓ / Pas encore ».
    func scheduleDailyAction(id: String, title: String, body: String,
                             hour: Int, minute: Int,
                             categoryId: String, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = userInfo
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rappel après un intervalle (ex: fin de sieste, fenêtre de sommeil léger).
    func scheduleAfter(id: String, title: String, body: String, seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
