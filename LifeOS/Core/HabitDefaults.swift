import SwiftData

enum HabitDefaults {
    private static let catalog: [String: (name: String, icon: String, colorHex: Int)] = [
        "fitness":      ("Seance de sport",             "figure.run",                0xFF2E33),
        "nutrition":    ("Objectif calories du jour",   "fork.knife",                0x47CC5C),
        "sleep":        ("Coucher a l'heure cible",     "moon.stars.fill",           0x6B66F2),
        "productivity": ("Valider mes habitudes",        "checklist",                 0x24C7CC),
        "mind":         ("5 min de meditation",          "brain.head.profile",        0xA852F5),
        "looks":        ("Routine soin du soir",         "face.smiling",              0xFF8A1A),
        "learning":     ("15 min d'apprentissage",       "book.fill",                 0xFFCC2E),
        "social":       ("Contacter quelqu'un",          "person.2.fill",             0xFF338C),
        "finance":      ("Verifier mon budget",          "creditcard.fill",           0x2185FF),
        "career":       ("Avancer sur mes objectifs",    "briefcase.fill",            0xFFB83D),
        "invest":       ("Suivre mon portefeuille",      "chart.line.uptrend.xyaxis", 0x29CC9E),
        "home":         ("Tache maison du jour",         "house.fill",                0x3D8FF5),
        "medical":      ("Prendre mes medicaments",      "pills.fill",                0xFF2E33),
    ]

    /// Returns the icon name and colorHex for a given module key.
    static func iconAndColor(for module: String) -> (icon: String, colorHex: Int) {
        guard let d = catalog[module] else { return ("checkmark.circle", 0x47CC5C) }
        return (d.icon, d.colorHex)
    }

    /// Inserts a pending habit for each module that doesn't already have one.
    static func insertPendingHabits(for modules: [String], into context: ModelContext) {
        guard !modules.isEmpty else { return }
        let existingTags = Set((try? context.fetch(FetchDescriptor<Habit>()))?.map { $0.moduleTag } ?? [])
        for module in modules {
            guard let d = catalog[module], !existingTags.contains(module) else { continue }
            context.insert(Habit(name: d.name, icon: d.icon, colorHex: d.colorHex, isPending: true, moduleTag: module))
        }
        do { try context.save() } catch { AppLog.data.error("insertPendingHabits failed: \(error.localizedDescription, privacy: .public)") }
    }
}
