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
            return []   // on gère nous-mêmes l'UI — pas de bannière système
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
    }
}
