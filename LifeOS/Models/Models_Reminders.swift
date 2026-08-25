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

    // MARK: - Extensions rappels intelligents (nouveaux champs optionnels
    // avec valeurs par défaut → aucune migration cassante requise).

    /// Mode de fréquence — voir `Frequency` enum. Par défaut "daily" =
    /// comportement historique (1 déclenchement à hour:minute chaque jour).
    var frequencyRaw: String = "daily"

    /// Intervalle en heures pour `.everyXHours`. Ignoré sinon.
    var intervalHours: Int = 2

    /// Fenêtre horaire pendant laquelle le rappel peut se déclencher
    /// (pour `.everyXHours` ou `.multipleTimes`). Ignoré pour `.daily`.
    var windowStartHour: Int = 8
    var windowEndHour: Int = 20

    /// Bitmask des jours actifs (Lun=1, Mar=2, Mer=4, Jeu=8, Ven=16,
    /// Sam=32, Dim=64). 127 = tous les jours (défaut).
    var weekdayMask: Int = 127

    /// JSON `[Int]` d'heures HH:00 pour `.multipleTimes` (ex: [9, 12, 15, 18]).
    var specificHoursJSON: String = "[]"

    /// Catégorie associée pour tri/couleur (ex: "sleep", "fitness"…).
    /// Valeur = `AppCategory.rawValue` ou `""`.
    var categoryRaw: String = ""

    init(title: String = "", message: String = "", hour: Int = 9, minute: Int = 0,
         enabled: Bool = true, confirm: Bool = false,
         frequencyRaw: String = "daily", intervalHours: Int = 2,
         windowStartHour: Int = 8, windowEndHour: Int = 20,
         weekdayMask: Int = 127, specificHoursJSON: String = "[]",
         categoryRaw: String = "") {
        self.title = title; self.message = message; self.hour = hour; self.minute = minute
        self.enabled = enabled; self.confirm = confirm; self.created = Date()
        self.frequencyRaw = frequencyRaw
        self.intervalHours = intervalHours
        self.windowStartHour = windowStartHour
        self.windowEndHour = windowEndHour
        self.weekdayMask = weekdayMask
        self.specificHoursJSON = specificHoursJSON
        self.categoryRaw = categoryRaw
    }

    /// Mode de fréquence typé.
    enum Frequency: String, CaseIterable {
        case daily          // 1x/jour à hour:minute (historique)
        case everyXHours    // toutes les X heures dans la fenêtre
        case multipleTimes  // liste d'horaires précis

        var displayName: String {
            switch self {
            case .daily:         return "Une fois par jour"
            case .everyXHours:   return "Toutes les X heures"
            case .multipleTimes: return "Plusieurs horaires précis"
            }
        }
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Heures spécifiques parsées depuis `specificHoursJSON`.
    var specificHours: [Int] {
        get {
            guard let data = specificHoursJSON.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
            return arr.filter { $0 >= 0 && $0 < 24 }.sorted()
        }
        set {
            let clean = newValue.filter { $0 >= 0 && $0 < 24 }.sorted()
            if let data = try? JSONEncoder().encode(clean),
               let s = String(data: data, encoding: .utf8) {
                specificHoursJSON = s
            }
        }
    }
}

// MARK: - Weekday bitmask helpers

/// Mapping Lun=0..Dim=6 vers bit position (Lun=1, Dim=64).
enum WeekdayMask {
    static let all: Int = 127        // 1+2+4+8+16+32+64
    static let weekdays: Int = 31    // Lun→Ven = 1+2+4+8+16
    static let weekend: Int = 96     // Sam+Dim = 32+64

    /// Retourne true si le jour est actif dans le mask. `weekdayIndex` 0=Lun … 6=Dim.
    static func isActive(_ mask: Int, weekdayIndex: Int) -> Bool {
        guard (0...6).contains(weekdayIndex) else { return false }
        return (mask & (1 << weekdayIndex)) != 0
    }

    /// Convertit un weekday Calendar (1=Dim, 2=Lun … 7=Sam) en index 0=Lun … 6=Dim.
    static func indexFromCalendarWeekday(_ w: Int) -> Int {
        // Calendar: 1=Sun, 2=Mon, ..., 7=Sat → index 0=Mon...6=Sun
        // Sun (1) → 6, Mon (2) → 0, Sat (7) → 5
        (w == 1) ? 6 : (w - 2)
    }

    /// Convertit un index (0=Lun … 6=Dim) en weekday Calendar (1=Dim … 7=Sam).
    static func calendarWeekdayFromIndex(_ i: Int) -> Int {
        // 0 (Mon) → 2, ..., 5 (Sat) → 7, 6 (Sun) → 1
        (i == 6) ? 1 : (i + 2)
    }

    static let dayLabels = ["L", "M", "M", "J", "V", "S", "D"]
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
