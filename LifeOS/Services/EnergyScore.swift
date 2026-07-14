import Foundation
import SwiftData

/// Calcul local du Score d'Énergie (0–100), 100 % on-device.
///
/// Portage de l'algo backend (`backend/app/services/energy.py`) qui tournait
/// jusqu'ici sur Railway. Depuis Option C, le score est calculé sur l'iPhone
/// à partir des données SwiftData déjà présentes localement (sommeil, humeur,
/// eau, habitudes du jour).
enum EnergyScore {

    /// Résultat consolidé — utilisable directement en UI.
    struct Result {
        let score: Int         // 0…100
        let label: String      // Excellent / Bon / Correct / Faible / Très faible
        let colorHex: String   // "#RRGGBB"
    }

    /// Snapshot brut d'entrée du calcul — évite d'aller lire les Query 6 fois.
    struct Input {
        var sleepHours: Double?     // heures dormies dernière nuit
        var sleepQuality: Int?      // 1…5
        var mood: Int?              // 1…5
        var fatigue: Int?           // 1 (reposé) … 5 (épuisé)
        var waterML: Int?
        var habitsDone: Int?
        var habitsTotal: Int?
    }

    // MARK: - Calcul du score

    /// Pondération miroir du backend Python d'origine :
    /// sommeil qualité 30 · sommeil durée 10 · hydratation 20 · habitudes 20 ·
    /// humeur 15 · anti-fatigue 5 = 100 pts au total.
    static func compute(_ input: Input) -> Result {
        var score = 0.0

        if let q = input.sleepQuality {
            score += (Double(q) / 5.0) * 30
        }
        if let h = input.sleepHours {
            let ratio = min(h / 8.0, 1.0)
            score += ratio * 10
        }
        if let ml = input.waterML {
            let ratio = min(Double(ml) / 2500.0, 1.0)
            score += ratio * 20
        }
        if let total = input.habitsTotal, total > 0, let done = input.habitsDone {
            let ratio = min(Double(done) / Double(total), 1.0)
            score += ratio * 20
        }
        if let m = input.mood {
            score += (Double(m) / 5.0) * 15
        }
        if let f = input.fatigue {
            score += (Double(6 - f) / 5.0) * 5
        }

        let clamped = Int(score.rounded().clamped(to: 0...100))
        return Result(score: clamped, label: label(clamped), colorHex: colorHex(clamped))
    }

    // MARK: - Lecture SwiftData

    /// Calcule le score du jour à partir de SwiftData + UserDefaults (sommeil
    /// stocké manuellement par SleepCheckSheet). Retourne nil s'il n'y a
    /// vraiment aucune donnée pour aujourd'hui.
    @MainActor
    static func today(_ ctx: ModelContext) -> Result? {
        let cal = Calendar.current
        let ud = UserDefaults.standard

        // Sommeil : SleepCheckSheet écrit dans UserDefaults à chaque check du matin.
        let sleepHoursRaw = ud.double(forKey: "lastSleepHours")
        let sleepQualityRaw = ud.integer(forKey: "lastSleepQuality")
        let sleepHours: Double? = sleepHoursRaw > 0 ? sleepHoursRaw : nil
        let sleepQuality: Int? = sleepQualityRaw > 0 ? sleepQualityRaw : nil

        // Humeur : dernier MoodEntry du jour.
        let moods = (try? ctx.fetch(FetchDescriptor<MoodEntry>())) ?? []
        let todayMood = moods.first(where: { cal.isDateInToday($0.date) })?.score

        // Eau bue aujourd'hui.
        let waters = (try? ctx.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let ml = waters.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }
        let waterML: Int? = ml > 0 ? ml : nil

        // Habitudes du jour.
        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? [])
            .filter { !$0.isPending && !$0.isArchived }
        let total = habits.count
        let done = habits.filter { h in
            h.completions.contains { cal.isDateInToday($0.date) }
        }.count

        // Rien du tout aujourd'hui → pas de score à montrer.
        let anyData = sleepHours != nil || sleepQuality != nil || todayMood != nil
            || waterML != nil || total > 0
        guard anyData else { return nil }

        return compute(Input(
            sleepHours: sleepHours,
            sleepQuality: sleepQuality,
            mood: todayMood,
            fatigue: nil,   // pas encore capturé côté iOS — safe à nil
            waterML: waterML,
            habitsDone: total > 0 ? done : nil,
            habitsTotal: total > 0 ? total : nil
        ))
    }

    // MARK: - Palettes

    private static func label(_ score: Int) -> String {
        switch score {
        case 85...: return "Excellent"
        case 70...: return "Bon"
        case 50...: return "Correct"
        case 30...: return "Faible"
        default:    return "Très faible"
        }
    }

    private static func colorHex(_ score: Int) -> String {
        switch score {
        case 85...: return "#34C759"
        case 70...: return "#30D158"
        case 50...: return "#FF9F0A"
        case 30...: return "#FF6B35"
        default:    return "#FF3B30"
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
