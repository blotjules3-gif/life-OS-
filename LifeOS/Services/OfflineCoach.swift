import Foundation
import SwiftData

/// Réponses locales du coach quand le serveur est injoignable.
/// Pas de LLM : on compose une réponse utile à partir des données SwiftData
/// (habitudes, eau, calories, sommeil) au lieu de laisser le chat muet.
enum OfflineCoach {

    @MainActor
    static func reply(to message: String, ctx: ModelContext?) -> String {
        let lower = message.lowercased()
        let data = snapshot(ctx)

        let body: String
        if lower.contains("eau") || lower.contains("hydrat") {
            body = data.waterML > 0
                ? "Tu as bu \(data.waterML) ml aujourd'hui. Objectif : \(data.waterGoal) ml — encore \(max(0, data.waterGoal - data.waterML)) ml pour y arriver."
                : "Aucune eau enregistrée aujourd'hui. Vise \(data.waterGoal) ml — commence par un grand verre maintenant."
        } else if lower.contains("calorie") || lower.contains("mang") || lower.contains("nutrition") {
            body = data.kcal > 0
                ? "Tu es à \(data.kcal) kcal aujourd'hui sur un objectif de \(data.kcalGoal) kcal."
                : "Aucun repas enregistré aujourd'hui. Pense à logger ce que tu manges pour garder le fil."
        } else if lower.contains("sommeil") || lower.contains("dormi") {
            body = data.sleepHours > 0
                ? "Tu as dormi environ \(data.sleepHours) h cette nuit."
                : "Pas de donnée de sommeil pour cette nuit. Fais ton check-in du matin pour la renseigner."
        } else {
            body = recap(data)
        }

        return body + "\n\nJe suis hors ligne — je te réponds avec tes données locales. Reviens me voir quand la connexion est rétablie pour une vraie analyse."
    }

    // MARK: - Données locales

    private struct Snapshot {
        var habitsDone = 0
        var habitsTotal = 0
        var nextHabit: String? = nil
        var bestStreak = 0
        var bestStreakName: String? = nil
        var waterML = 0
        var waterGoal = 2000
        var kcal = 0
        var kcalGoal = 2000
        var sleepHours = 0
    }

    @MainActor
    private static func snapshot(_ ctx: ModelContext?) -> Snapshot {
        var s = Snapshot()
        let ud = UserDefaults.standard
        s.waterGoal = ud.object(forKey: "waterGoal") != nil ? ud.integer(forKey: "waterGoal") : 2000
        s.kcalGoal = ud.object(forKey: "kcalGoal") != nil ? ud.integer(forKey: "kcalGoal") : 2000
        s.sleepHours = ud.integer(forKey: "lastSleepHours")
        guard let ctx else { return s }
        let cal = Calendar.current

        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? [])
            .filter { !$0.isPending && !$0.isArchived }
        s.habitsTotal = habits.count
        for habit in habits {
            let doneToday = habit.completions.contains { cal.isDateInToday($0.date) }
            if doneToday { s.habitsDone += 1 }
            else if s.nextHabit == nil { s.nextHabit = habit.name }
            let streak = currentStreak(habit, cal: cal)
            if streak > s.bestStreak {
                s.bestStreak = streak
                s.bestStreakName = habit.name
            }
        }

        s.waterML = ((try? ctx.fetch(FetchDescriptor<WaterEntry>())) ?? [])
            .filter { cal.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amountML }
        s.kcal = ((try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? [])
            .filter { cal.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.calories }
        return s
    }

    private static func currentStreak(_ habit: Habit, cal: Calendar) -> Int {
        var streak = 0
        var day = cal.startOfDay(for: .now)
        // Le jour courant ne casse pas la série s'il n'est pas encore fait.
        if !habit.completions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        while habit.completions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    private static func recap(_ d: Snapshot) -> String {
        var lines: [String] = []
        if d.habitsTotal > 0 {
            lines.append("Habitudes : \(d.habitsDone)/\(d.habitsTotal) faites aujourd'hui.")
            if let next = d.nextHabit {
                lines.append("Prochaine : \(next).")
            }
            if d.bestStreak >= 2, let name = d.bestStreakName {
                lines.append("Ta meilleure série : \(name), \(d.bestStreak) jours d'affilée.")
            }
        }
        if d.waterML > 0 { lines.append("Eau : \(d.waterML)/\(d.waterGoal) ml.") }
        if d.kcal > 0 { lines.append("Calories : \(d.kcal)/\(d.kcalGoal) kcal.") }
        if d.sleepHours > 0 { lines.append("Sommeil : \(d.sleepHours) h cette nuit.") }
        if lines.isEmpty {
            return "Rien d'enregistré aujourd'hui pour l'instant. Coche une habitude ou logge un verre d'eau pour lancer ta journée."
        }
        return "Voici où tu en es aujourd'hui :\n" + lines.map { "— " + $0 }.joined(separator: "\n")
    }
}
