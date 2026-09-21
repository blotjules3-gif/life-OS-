import Foundation

// Sorti de Models_Reminders.swift: ce n'est pas un modele, et il appelle
// NotificationManager, qui n'existe que dans l'app iPhone. Les modeles doivent
// compiler seuls pour l'app Apple Watch.

// MARK: - Rappel du matin (« n'oublie pas… » 5 min après le réveil)

/// Détecte que l'utilisateur est réveillé (1re ouverture de l'app dans la fenêtre du
/// matin) et programme une notif 5 min plus tard. Une seule fois par jour.
enum MorningReminder {
    static let defaultText = "N'oublie pas : un grand verre d'eau et tes compléments du matin"

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
            title: "Bien réveillé ?",
            body: text,
            seconds: 5 * 60
        )
    }
}
