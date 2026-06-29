import SwiftData

enum HabitDefaults {
    private static let catalog: [String: (name: String, icon: String, colorHex: Int)] = [
        "fitness":      ("Seance de sport",             "figure.run",                0xF1746C),
        "nutrition":    ("Objectif calories du jour",   "fork.knife",                0x4CC38A),
        "sleep":        ("Coucher a l'heure cible",     "moon.stars.fill",           0x6C7BF1),
        "productivity": ("Valider mes habitudes",        "checklist",                 0x3CB2E0),
        "mind":         ("5 min de meditation",          "brain.head.profile",        0x9B6CF1),
        "looks":        ("Routine soin du soir",         "face.smiling",              0xE0A23C),
        "learning":     ("15 min d'apprentissage",       "book.fill",                 0xF97316),
        "social":       ("Contacter quelqu'un",          "person.2.fill",             0xF16CB0),
        "finance":      ("Verifier mon budget",          "creditcard.fill",           0x4CC38A),
        "career":       ("Avancer sur mes objectifs",    "briefcase.fill",            0xE07B3C),
        "invest":       ("Suivre mon portefeuille",      "chart.line.uptrend.xyaxis", 0x46C9A8),
        "home":         ("Tache maison du jour",         "house.fill",                0x6CA0F1),
    ]

    /// Inserts a pending habit for each module that doesn't already have one.
    static func insertPendingHabits(for modules: [String], into context: ModelContext) {
        guard !modules.isEmpty else { return }
        let existingTags = Set((try? context.fetch(FetchDescriptor<Habit>()))?.map { $0.moduleTag } ?? [])
        for module in modules {
            guard let d = catalog[module], !existingTags.contains(module) else { continue }
            context.insert(Habit(name: d.name, icon: d.icon, colorHex: d.colorHex, isPending: true, moduleTag: module))
        }
        try? context.save()
    }
}
