import Foundation
import UserNotifications

// Planifie les notifications contextuelles selon les modules actifs et les horaires de l'utilisateur.
// Appeler `reschedule()` après chaque changement de modules ou de réveil.

final class ContextualNotifications {
    static let shared = ContextualNotifications()
    private init() {}

    // Préfixe pour identifier et annuler toutes les notifs contextuelles
    private let prefix = "lifeos.ctx."

    func reschedule() {
        cancelAll()

        let modules = activeModules()
        let wakeupHour = UserDefaults.standard.integer(forKey: "wakeupHour")
        let wakeupMin  = UserDefaults.standard.integer(forKey: "wakeupMinute")
        let wakeupTotal = wakeupHour * 60 + wakeupMin

        // — Après réveil (wakeup + 20 min) —
        // Pose la question qualité de sommeil si le module Sleep ou bilan matin est actif
        if modules.contains("sleep") || modules.contains("fitness") || modules.isEmpty {
            let afterWake = (wakeupTotal + 20) % (24 * 60)
            scheduleDaily(
                id: "morning_checkin",
                title: "Bilan du matin",
                body: "Comment as-tu dormi ? Remplis ton bilan pour calculer ton Score d'Énergie.",
                hour: afterWake / 60,
                minute: afterWake % 60
            )
        }

        // — Avant déjeuner (12h15) —
        if modules.contains("nutrition") {
            scheduleDaily(
                id: "lunch_reminder",
                title: "C'est bientôt l'heure du déjeuner",
                body: "Pense à noter ton repas pour suivre tes objectifs nutrition.",
                hour: 12, minute: 15
            )
        }

        // — Hydratation (20h) —
        if modules.contains("nutrition") || modules.isEmpty {
            scheduleDaily(
                id: "water_evening",
                title: "Hydratation",
                body: "Combien d'eau as-tu bu aujourd'hui ? Rappel d'atteindre ton objectif.",
                hour: 20, minute: 0
            )
        }

        // — Avant dîner (19h15) —
        if modules.contains("nutrition") {
            scheduleDaily(
                id: "dinner_reminder",
                title: "Soirée qui approche",
                body: "Pense à noter ton dîner ce soir pour rester dans tes objectifs.",
                hour: 19, minute: 15
            )
        }

        // — Sport (18h si module fitness actif) —
        if modules.contains("fitness") {
            let sportHour = UserDefaults.standard.integer(forKey: "sportHour")
            let h = sportHour > 0 ? sportHour : 18
            scheduleDaily(
                id: "sport_reminder",
                title: "Heure du sport",
                body: "Prépare ta séance. N'oublie pas de me dire comment elle s'est passée.",
                hour: h, minute: 0
            )
        }

        // — Habitudes (20h30) — toujours actif si au moins 1 habitude
        scheduleDaily(
            id: "habits_evening",
            title: "Tes habitudes du jour",
            body: "As-tu complété tes habitudes aujourd'hui ? Quelques minutes peuvent faire la différence.",
            hour: 20, minute: 30
        )

        // — Coucher (bedtime - 30 min) —
        if modules.contains("sleep") {
            let bedHour = UserDefaults.standard.integer(forKey: "bedHour")
            let bedMin  = UserDefaults.standard.integer(forKey: "bedMinute")
            let bedTotal = (bedHour > 0 ? bedHour : 23) * 60 + bedMin
            let reminderTotal = ((bedTotal - 30) + 24 * 60) % (24 * 60)
            scheduleDaily(
                id: "bedtime_reminder",
                title: "Bientôt l'heure de dormir",
                body: "Prépare-toi pour une bonne nuit. Évite les écrans encore 20 minutes.",
                hour: reminderTotal / 60,
                minute: reminderTotal % 60
            )
        }

        // — Mind / Méditation (8h) —
        if modules.contains("mind") {
            let meditHour = wakeupTotal + 60  // 1h après réveil
            let mh = (meditHour % (24 * 60)) / 60
            let mm = meditHour % 60
            scheduleDaily(
                id: "mind_morning",
                title: "5 minutes de calme",
                body: "Commence ta journée avec une courte séance de respiration ou méditation.",
                hour: mh, minute: mm
            )
        }

        // — Productivité (9h) —
        if modules.contains("productivity") {
            scheduleDaily(
                id: "productivity_morning",
                title: "Ta priorité du jour",
                body: "Quelle est la tâche la plus importante à accomplir aujourd'hui ?",
                hour: 9, minute: 0
            )
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix(self.prefix) }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Private

    private func activeModules() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: "recommendedModules") ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }

    private func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: "\(prefix)\(id)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
