import Foundation
import SwiftData

#if DEBUG
/// Remplit une journee credible pour les captures d'ecran de la fiche App Store.
/// Un ecran vide ne montre pas ce que fait l'app, il la fait passer pour cassee.
///
/// Reserve aux builds Debug, et declenche uniquement par `-seedDemo`.
/// Ne s'execute qu'une fois par installation.
@MainActor
enum DemoSeed {

    static func runIfAsked(_ ctx: ModelContext) {
        guard DebugLaunchFlags.has("-seedDemo") else { return }
        guard !UserDefaults.standard.bool(forKey: "demoSeed.done") else { return }
        UserDefaults.standard.set(true, forKey: "demoSeed.done")
        seed(ctx)
    }

    private static func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int = 0) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func seed(_ ctx: ModelContext) {
        // Habitudes, avec un historique pour que les series affichent un vrai chiffre.
        let habits: [(String, String, Int, Int, Int)] = [
            ("Boire 2 L d'eau",   "drop.fill",         8, 0,  0x4CC38A),
            ("Marcher 8 000 pas", "figure.walk",      12, 30, 0x618EF1),
            ("Lire 20 minutes",   "book.fill",        21, 0,  0xC98FE8),
            ("Etirements",        "figure.flexibility", 7, 15, 0xF2A65A)
        ]
        for (i, h) in habits.enumerated() {
            let habit = Habit(name: h.0, icon: h.1, colorHex: h.4,
                              createdAt: at(8, daysAgo: 40),
                              scheduledHour: h.2, scheduledMinute: h.3)
            // Serie continue jusqu'a hier, plus aujourd'hui pour les deux premieres.
            let streak = [21, 14, 9, 5][i]
            for d in stride(from: streak, through: (i < 2 ? 0 : 1), by: -1) {
                habit.completions.append(HabitCompletion(date: at(h.2, h.3, daysAgo: d)))
            }
            ctx.insert(habit)
        }

        // Taches du jour.
        let todos: [(String, Int, Int, Bool, Int)] = [
            ("Appeler le dentiste",        10, 0,  true,  1),
            ("Preparer la reunion equipe", 14, 0,  false, 2),
            ("Courses de la semaine",      18, 30, false, 0)
        ]
        for t in todos {
            ctx.insert(TodoItem(title: t.0, due: at(t.1, t.2), done: t.3, priority: t.4))
        }

        // Nutrition du jour.
        let meals: [(String, Int, Double, Double, Double, String, Int)] = [
            ("Flocons d'avoine, banane", 420, 14, 68, 9,  "Petit-dejeuner", 8),
            ("Poulet, riz, brocoli",     610, 45, 62, 18, "Dejeuner",       13),
            ("Yaourt grec, amandes",     230, 18, 12, 12, "Collation",      16)
        ]
        for m in meals {
            ctx.insert(FoodEntry(date: at(m.6), name: m.0, calories: m.1,
                                 protein: m.2, carbs: m.3, fat: m.4, meal: m.5))
        }
        for (h, ml) in [(8, 300), (11, 250), (14, 400), (17, 350)] {
            ctx.insert(WaterEntry(date: at(h), amountML: ml))
        }

        // Sommeil des sept dernieres nuits.
        let qualities = [4, 3, 4, 5, 3, 4, 4]
        for d in 0..<7 {
            ctx.insert(SleepNight(date: at(7, 10, daysAgo: d),
                                  bedtime: at(23, 20, daysAgo: d + 1),
                                  wake: at(7, 10, daysAgo: d),
                                  quality: qualities[d]))
        }

        // Humeur.
        for (d, score) in [(0, 4), (1, 3), (2, 4), (3, 5), (4, 3)] {
            ctx.insert(MoodEntry(date: at(20, daysAgo: d), score: score))
        }

        // Argent. Les soldes passent par LedgerService, jamais ecrits a la main.
        let courant = Account(name: "Compte courant", kind: "Courant", balance: 2480)
        let epargne = Account(name: "Livret", kind: "Epargne", balance: 6150)
        ctx.insert(courant); ctx.insert(epargne)
        let ops: [(Double, String, String, Int)] = [
            (-38.40,  "Courses",    "Supermarche",       0),
            (-12.90,  "Transport",  "Abonnement bus",    1),
            (-64.00,  "Sorties",    "Restaurant",        2),
            (2150.00, "Salaire",    "Salaire septembre", 4),
            (-29.99,  "Abonnement", "Salle de sport",    5)
        ]
        for o in ops {
            LedgerService.addTransaction(ctx, amount: o.0, category: o.1,
                                         account: courant, note: o.2,
                                         date: at(12, daysAgo: o.3))
        }

        let envelopes: [(String, Double, Double, Int)] = [
            ("Courses",    400, 238.40, 0x4CC38A),
            ("Sorties",    150, 114.00, 0xF2A65A),
            ("Transport",   80,  12.90, 0x618EF1)
        ]
        for e in envelopes {
            ctx.insert(Envelope(name: e.0, monthlyBudget: e.1, spent: e.2, colorHex: e.3))
        }

        try? ctx.save()
    }
}
#endif
