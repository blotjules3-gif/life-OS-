import Foundation
import SwiftData

#if DEBUG
/// Un an d'usage synthetique, pour mesurer la fluidite avec un vrai volume.
///
/// La graine de demo tient en une journee: avec 30 lignes tout est rapide, et
/// les ecrans qui ralentissent avec 1 500 repas ne se voient jamais. Reserve aux
/// builds Debug, declenche uniquement par `-seedYear`, une fois par installation,
/// et seulement sur un simulateur de test: rien de ces donnees n'est reel.
@MainActor
enum YearSeed {
    static func runIfAsked(_ ctx: ModelContext) {
        guard DebugLaunchFlags.has("-seedYear") else { return }
        guard !UserDefaults.standard.bool(forKey: "yearSeed.done") else { return }
        UserDefaults.standard.set(true, forKey: "yearSeed.done")
        seed(ctx)
    }

    private static func day(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
    }

    private static func seed(_ ctx: ModelContext) {
        var rng = SystemRandomNumberGenerator()
        let habits = (0..<6).map { i in
            Habit(name: ["Eau", "Marche", "Lecture", "Etirements", "Meditation", "Sans ecran"][i],
                  createdAt: day(370, 8), scheduledHour: 8 + i * 2)
        }
        habits.forEach { ctx.insert($0) }
        let account = Account(name: "Compte courant", kind: "Courant", balance: 0)
        ctx.insert(account)
        let meals = [("Petit-dejeuner", 8, 420), ("Dejeuner", 13, 650), ("Collation", 16, 220), ("Diner", 20, 700)]
        let cats = ["Courses", "Transport", "Sorties", "Abonnement", "Sante", "Maison"]

        for d in 0..<365 {
            for (name, h, kcal) in meals {
                ctx.insert(FoodEntry(date: day(d, h), name: "\(name) \(d)",
                                     calories: kcal + Int.random(in: -80...80, using: &rng),
                                     protein: 25, carbs: 60, fat: 15, meal: name))
            }
            for h in [8, 11, 14, 17, 20] { ctx.insert(WaterEntry(date: day(d, h), amountML: 300)) }
            for (i, habit) in habits.enumerated() where (d + i) % 5 != 0 {
                habit.completions.append(HabitCompletion(date: day(d, habit.scheduledHour)))
            }
            ctx.insert(SleepNight(date: day(d, 7), bedtime: day(d + 1, 23), wake: day(d, 7),
                                  quality: Int.random(in: 2...5, using: &rng)))
            ctx.insert(MoodEntry(date: day(d, 20), score: Int.random(in: 2...5, using: &rng)))
            ctx.insert(StepEntry(day: day(d, 0), steps: Int.random(in: 3000...14000, using: &rng)))
            ctx.insert(VitalRecord(date: day(d, 7), type: "poids", value: 72 + Double(d % 9) / 10,
                                   unit: "kg"))
            for k in 0..<3 {
                let t = Txn(date: day(d, 9 + k * 4), amount: -Double(Int.random(in: 3...90, using: &rng)),
                            category: cats[(d + k) % cats.count], account: account.name,
                            note: "Operation \(d)-\(k)", accountID: account.id)
                t.setAmount(t.amount)
                ctx.insert(t)
            }
            if d % 3 == 0 {
                ctx.insert(TodoItem(title: "Tache \(d)", due: day(d, 10), done: d > 0, priority: d % 3))
            }
            if d % 4 == 0 { ctx.insert(Note(title: "Note \(d)", body: String(repeating: "Texte. ", count: 40),
                                             created: day(d, 21))) }
            if d % 28 < 5 { ctx.insert(CycleEntry(date: day(d, 9), flow: 2)) }
            if d % 2 == 0 { ctx.insert(DreamEntry(date: day(d, 7), title: "Reve \(d)", text: "Un reve.")) }
        }
        LedgerService.recompute(ctx, account: account)
        try? ctx.save()
    }
}
#endif
