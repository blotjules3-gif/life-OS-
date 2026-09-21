import Foundation
import SwiftData

/// Lecture des donnees du jour pour le Score d'Energie.
///
/// Separe du calcul lui meme, qui ne depend que de Foundation. Ce n'est pas
/// de la coquetterie: le calcul peut ainsi etre execute et teste sans
/// simulateur, et c'est justement lui qui s'etait trompe.
extension EnergyScore {

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

        let result = compute(Input(
            sleepHours: sleepHours,
            sleepQuality: sleepQuality,
            mood: todayMood,
            fatigue: nil,   // pas encore capturé côté iOS — safe à nil
            waterML: waterML,
            habitsDone: total > 0 ? done : nil,
            habitsTotal: total > 0 ? total : nil
        ))
        // Trop peu de criteres renseignes: on ne montre rien plutot qu'un
        // chiffre qui dirait n'importe quoi, dans le widget comme dans l'app.
        return result.coverage >= minimumCoverage ? result : nil
    }
}
