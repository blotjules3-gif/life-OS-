import Foundation
import BackgroundTasks
import UserNotifications
import SwiftData

/// Orchestre le déclenchement quotidien de `CoachProactiveEngine.scanNudges`
/// et transforme les nudges en notifications locales avec deep link vers le chat.
///
/// Cycle :
/// - Enregistre un `BGAppRefreshTask` (identifier : "com.blotjules.lifeos.coach.proactive")
/// - iOS le déclenche opportunistiquement (~1×/jour selon usage)
/// - Le task scan les nudges → envoie 1 notif pour le nudge le plus urgent
/// - Le tap notif ouvre l'app avec un deep link `lifeos://coach?prefill=…`
///
/// Anti-spam : max 1 notif proactive par jour, cooldown 20h entre deux du même signal.
@MainActor
enum CoachProactiveScheduler {

    static let backgroundTaskIdentifier = "com.blotjules.lifeos.coach.proactive"
    static let notifIdPrefix = "coach.proactive."
    private static let lastSentKey = "coach.proactive.lastSentDate"
    private static let lastSignalKey = "coach.proactive.lastSignal"

    // MARK: - Registration (à appeler dans AppDelegate.didFinishLaunching)

    /// Enregistre le BGTask handler. À appeler UNE FOIS au démarrage.
    /// Si non appelé, iOS ne lancera jamais notre task.
    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }

    /// Planifie le prochain refresh (idéalement 24h+ dans le futur).
    /// À appeler après chaque exécution du task pour rearmer.
    nonisolated static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Demande au moins 12h plus tard, iOS décidera de l'heure exacte.
        request.earliestBeginDate = Date().addingTimeInterval(12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handler

    nonisolated private static func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Rearme immédiatement pour le prochain cycle
        scheduleNextRefresh()

        let workItem = Task { @MainActor in
            defer { task.setTaskCompleted(success: true) }
            await runProactiveScan()
        }

        task.expirationHandler = {
            workItem.cancel()
        }
    }

    // MARK: - Coeur

    /// Scan + envoi notif — appelable aussi manuellement (bouton debug).
    static func runProactiveScan() async {
        // Anti-spam : max 1 par jour
        let ud = UserDefaults.standard
        if let last = ud.object(forKey: lastSentKey) as? Date,
           Date().timeIntervalSince(last) < 20 * 3600 {
            return
        }

        let ctx: ModelContext
        do {
            ctx = try LocalStore.container().mainContext
        } catch {
            return
        }

        let nudges = CoachProactiveEngine.scanNudges(context: ctx)
        guard let top = nudges.first else { return }

        // Cooldown par signal — ne pas répéter le même signal 2 jours d'affilée
        let lastSignal = ud.string(forKey: lastSignalKey)
        if let last = ud.object(forKey: lastSentKey) as? Date,
           lastSignal == top.signal.rawValue,
           Date().timeIntervalSince(last) < 48 * 3600 {
            // Prend le suivant si dispo, sinon skip
            guard let alt = nudges.dropFirst().first else { return }
            await sendNotification(for: alt)
            ud.set(Date(), forKey: lastSentKey)
            ud.set(alt.signal.rawValue, forKey: lastSignalKey)
            return
        }

        await sendNotification(for: top)
        ud.set(Date(), forKey: lastSentKey)
        ud.set(top.signal.rawValue, forKey: lastSignalKey)
    }

    // MARK: - Notification

    private static func sendNotification(for nudge: CoachProactiveEngine.ProactiveNudge) async {
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.body = nudge.body
        content.sound = .default
        content.threadIdentifier = "coach.proactive"

        // Deep link : encodage du prefill via URL (utf8 percent-encoded)
        let prefillEncoded = nudge.prefilledMessage
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        content.userInfo = [
            "lifeos.deeplink": "lifeos://coach?prefill=\(prefillEncoded)",
            "lifeos.signal": nudge.signal.rawValue,
            "lifeos.category": nudge.category
        ]

        let identifier = notifIdPrefix + UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
