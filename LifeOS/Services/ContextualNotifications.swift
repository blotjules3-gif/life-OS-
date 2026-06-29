import Foundation
import UserNotifications

final class ContextualNotifications {
    static let shared = ContextualNotifications()
    private init() {}

    private let prefix = "lifeos.ctx."

    // Annule les anciennes notifs ctx.* PUIS planifie les nouvelles dans le même callback
    // — évite la race condition entre cancelAll (async) et scheduleDaily (sync).
    func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }

            // 1. Annuler les anciennes
            let oldIDs = requests
                .filter { $0.identifier.hasPrefix(self.prefix) }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)

            // 2. Planifier les nouvelles depuis le même thread de callback
            DispatchQueue.main.async { self.scheduleAll() }
        }
    }

    // MARK: - Planification

    private func scheduleAll() {
        let ud = UserDefaults.standard
        let modules = activeModules()
        let wakeupHour  = ud.integer(forKey: "wakeupHour")
        let wakeupMin   = ud.integer(forKey: "wakeupMinute")
        let wakeupTotal = wakeupHour * 60 + wakeupMin

        func enabled(_ key: String) -> Bool {
            ud.object(forKey: "notifEnabled.\(key)") as? Bool ?? true
        }

        // 1. Bilan du matin (réveil +30 min) — si sleep / fitness / mind
        if enabled("morning") && (modules.contains("sleep") || modules.contains("fitness") || modules.contains("mind")) {
            let t = (wakeupTotal + 30) % (24 * 60)
            scheduleDaily(id: "morning",
                          title: "Bilan du matin",
                          body: "Comment as-tu dormi ? Lance ton score d'énergie du jour.",
                          hour: t / 60, minute: t % 60)
        }

        // 2. Sport (heure config ou 18h) — si fitness
        if enabled("sport") && modules.contains("fitness") {
            let h = ud.integer(forKey: "sportHour")
            scheduleDaily(id: "sport",
                          title: "C'est l'heure de bouger",
                          body: "Ta séance t'attend.",
                          hour: h > 0 ? h : 18, minute: 0)
        }

        // 3. Nutrition soir (19h30) — si nutrition
        if enabled("nutrition") && modules.contains("nutrition") {
            scheduleDaily(id: "nutrition_evening",
                          title: "Objectif nutrition",
                          body: "Note ton dîner et vérifie tes calories du jour.",
                          hour: 19, minute: 30)
        }

        // 4. Habitudes soir (20h) — si au moins un module actif
        if enabled("habits") && (modules.contains("productivity") || modules.contains("fitness") ||
                                   modules.contains("mind") || modules.contains("sleep")) {
            scheduleDaily(id: "habits_evening",
                          title: "Tes habitudes du jour",
                          body: "Quelques secondes pour cocher ce que tu as fait.",
                          hour: 20, minute: 0)
        }

        // 5. Coucher (bedtime −30 min) — si sleep
        if enabled("bedtime") && modules.contains("sleep") {
            let bedH = ud.integer(forKey: "bedHour")
            let bedM = ud.integer(forKey: "bedMinute")
            let bed  = ((bedH > 0 ? bedH : 23) * 60 + bedM - 30 + 1440) % 1440
            scheduleDaily(id: "bedtime",
                          title: "Prépare-toi à dormir",
                          body: "Écrans off, décompresse 30 minutes avant de te coucher.",
                          hour: bed / 60, minute: bed % 60)
        }
    }

    // MARK: - Helpers

    private func activeModules() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: "recommendedModules") ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }

    private func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.interruptionLevel = .active
        var comps = DateComponents()
        comps.hour   = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: "\(prefix)\(id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
