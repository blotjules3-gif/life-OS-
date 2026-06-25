import UIKit
import UserNotifications

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Catégorie alarme — action "Ouvrir" pour amener l'app en foreground immédiatement
        let openAction = UNNotificationAction(
            identifier: "OPEN_ALARM",
            title: "Ouvrir LifeOS",
            options: [.foreground]
        )
        let alarmCategory = UNNotificationCategory(
            identifier: "LIFEOS_ALARM",
            actions: [openAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([alarmCategory])

        return true
    }
}

// MARK: - Délégué notifications (alarme)

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private override init() { super.init() }

    private let alarmIds: Set<String> = ["lifeos.wakeup", "lifeos.wakeup.snooze"]

    // App en FOREGROUND — notification arrive
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier

        if alarmIds.contains(id) {
            await MainActor.run { AlarmManager.shared.triggerAlarm() }
            // Laisser le son système jouer aussi : assure que l'alarme sonne
            // même si l'app est en foreground sur un autre écran
            return [.sound]
        }

        if id == "lifeos.wakeup.preview" {
            // App en foreground — démarre le widget si pas déjà actif
            if #available(iOS 16.1, *) {
                let info = notification.request.content.userInfo
                let h = info["alarmHour"] as? Int ?? 7
                let m = info["alarmMinute"] as? Int ?? 0
                let timeString = String(format: "%02d:%02d", h, m)
                await MainActor.run {
                    AlarmLiveActivityManager.shared.startScheduled(alarmTimeString: timeString)
                }
            }
            return [] // pas de bannière — le widget suffit
        }

        return [.banner, .sound, .list]
    }

    // App en BACKGROUND ou fermée — utilisateur tape la notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        if alarmIds.contains(id) {
            await MainActor.run { AlarmManager.shared.triggerAlarm() }
        }
        // Pour preview : l'app s'ouvre via tap, le widget est déjà actif (startScheduled au moment
        // de la programmation de l'alarme)
    }
}
