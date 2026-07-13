import UIKit
import UserNotifications

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Enregistrement APNs — nécessaire pour les push distantes depuis le backend.
        // Le token est capturé dans didRegisterForRemoteNotificationsWithDeviceToken.
        application.registerForRemoteNotifications()

        // Fond système immédiat sur toutes les fenêtres — évite le flash blanc en mode sombre.
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .forEach { $0.backgroundColor = UIColor.systemBackground }
        }

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

        // Catégorie CONFIRMATION — « Tu as bien fait X ? » avec 2 boutons.
        let yes = UNNotificationAction(identifier: "CONFIRM_YES", title: "Oui", options: [])
        let no  = UNNotificationAction(identifier: "CONFIRM_NO",  title: "Pas encore", options: [])
        let confirmCategory = UNNotificationCategory(
            identifier: "LIFEOS_CONFIRM",
            actions: [yes, no],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([alarmCategory, confirmCategory])

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
                await AlarmLiveActivityManager.shared.startScheduled(alarmTimeString: timeString)
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
        if id == "lifeos.weekly_bilan" {
            await MainActor.run {
                NotificationCenter.default.post(name: .lifeOSOpenWeeklyBilan, object: nil)
            }
        }

        // Réponse à une notif de CONFIRMATION (compléments, salle, etc.)
        let content = response.notification.request.content
        if content.categoryIdentifier == "LIFEOS_CONFIRM" {
            let info = content.userInfo
            let key = info["confirmKey"] as? String ?? id
            let label = info["confirmLabel"] as? String ?? "ça"
            let action = response.actionIdentifier
            if action == "CONFIRM_YES" || action == UNNotificationDefaultActionIdentifier {
                ConfirmationStore.shared.markDone(key)
            } else if action == "CONFIRM_NO" {
                // Petit rappel dans 30 min.
                NotificationManager.shared.scheduleAfter(
                    id: "\(key).snooze",
                    title: "Petit rappel",
                    body: "\(label) — quand tu peux.",
                    seconds: 30 * 60
                )
            }
        }
    }
}

// MARK: - APNs Token

extension AppDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "apnsToken")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[APNs] Registration failed: \(error.localizedDescription)")
        #endif
    }
}

extension Notification.Name {
    static let lifeOSOpenAIChat      = Notification.Name("lifeOSOpenAIChat")
    static let lifeOSOpenWeeklyBilan = Notification.Name("lifeOSOpenWeeklyBilan")
    static let lifeOSOpenModule      = Notification.Name("lifeOSOpenModule")
}
