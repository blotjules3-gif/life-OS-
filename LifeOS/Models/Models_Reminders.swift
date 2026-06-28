import Foundation
import SwiftData

// MARK: - Rappel personnalisé créé par l'utilisateur (centre de notifications)

@Model final class CustomReminder {
    var title: String = ""
    var message: String = ""
    var hour: Int = 9
    var minute: Int = 0
    var enabled: Bool = true
    var confirm: Bool = false      // notif de confirmation ~1h30 après
    var created: Date = Date()
    init(title: String = "", message: String = "", hour: Int = 9, minute: Int = 0,
         enabled: Bool = true, confirm: Bool = false) {
        self.title = title; self.message = message; self.hour = hour; self.minute = minute
        self.enabled = enabled; self.confirm = confirm; self.created = Date()
    }
}

// MARK: - Programme de sport (1 séance par jour de la semaine)

@Model final class GymDay {
    var weekday: Int = 2       // 1=Dimanche … 7=Samedi (convention Calendar)
    var title: String = ""     // ex: "Dos + Biceps"
    var focus: String = ""     // exercices / notes
    var isRest: Bool = false
    init(weekday: Int = 2, title: String = "", focus: String = "", isRest: Bool = false) {
        self.weekday = weekday; self.title = title; self.focus = focus; self.isRest = isRest
    }
}

// MARK: - Rappel du matin (« n'oublie pas… » 5 min après le réveil)

/// Détecte que l'utilisateur est réveillé (1re ouverture de l'app dans la fenêtre du
/// matin) et programme une notif 5 min plus tard. Une seule fois par jour.
enum MorningReminder {
    static let defaultText = "N'oublie pas : un grand verre d'eau et tes compléments du matin 💧💊"

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: "morningReminderOn") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "morningReminderOn")
    }
    static var text: String {
        let t = UserDefaults.standard.string(forKey: "morningReminderText") ?? ""
        return t.isEmpty ? defaultText : t
    }

    /// À appeler quand l'app devient active. Arme la notif si on est le matin et que
    /// ce n'est pas déjà fait aujourd'hui.
    static func checkAndArm() {
        guard isOn else { return }
        let cal = Calendar.current
        let now = Date()
        let h = cal.component(.hour, from: now)
        guard h >= 4 && h < 12 else { return }   // fenêtre « matin »

        let d = UserDefaults.standard
        let today = cal.startOfDay(for: now)
        let last = d.object(forKey: "morningReminderLast") as? Date ?? .distantPast
        guard !cal.isDate(last, inSameDayAs: today) else { return }
        d.set(today, forKey: "morningReminderLast")

        NotificationManager.shared.scheduleAfter(
            id: "lifeos.morningReminder",
            title: "Bien réveillé ? ☀️",
            body: text,
            seconds: 5 * 60
        )
    }
}
