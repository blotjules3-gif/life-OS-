import AppIntents
import Foundation
import SwiftData

/// Raccourcis Siri : "Ajoute de l'eau dans LifeOS", "Valide une habitude dans LifeOS".

/// Ouvre l'app directement sur la caméra de scan de repas (module Nutrition,
/// PhotoCalorieView). Utilisé par :
/// - le bouton Control Center iOS 18+ (`FoodScanControl`)
/// - le widget Home Screen `FoodScanWidget`
/// - la phrase Siri « Scanne mon repas »
struct OpenFoodScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Scanner un repas"
    static let description = IntentDescription("Ouvre la caméra LifeOS pour analyser une assiette et enregistrer calories + protéines.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .lifeOSOpenFoodScan, object: nil)
        return .result()
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter de l'eau"
    static let description = IntentDescription("Ajoute une quantité d'eau à ton suivi d'hydratation.")

    @Parameter(title: "Quantité (ml)", default: 250)
    var amountML: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = try LocalStore.container().mainContext
        ctx.insert(WaterEntry(date: .now, amountML: amountML))
        try ctx.save()
        let start = Calendar.current.startOfDay(for: .now)
        let today = try ctx.fetch(FetchDescriptor<WaterEntry>(
            predicate: #Predicate { $0.date >= start }
        ))
        let total = today.reduce(0) { $0 + $1.amountML }
        return .result(dialog: "C'est noté : \(amountML) ml. Total du jour : \(total) ml.")
    }
}

struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habitude"
    static let defaultQuery = HabitEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HabitEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [HabitEntity] {
        try activeHabits()
            .filter { identifiers.contains($0.name) }
            .map { HabitEntity(id: $0.name, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        try activeHabits().map { HabitEntity(id: $0.name, name: $0.name) }
    }

    @MainActor
    private func activeHabits() throws -> [Habit] {
        try LocalStore.container().mainContext.fetch(
            FetchDescriptor<Habit>(predicate: #Predicate { !$0.isArchived && !$0.isPending })
        )
    }
}

struct CompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Valider une habitude"
    static let description = IntentDescription("Marque une habitude comme faite pour aujourd'hui.")

    @Parameter(title: "Habitude")
    var habit: HabitEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = try LocalStore.container().mainContext
        let name = habit.name
        guard let target = try ctx.fetch(
            FetchDescriptor<Habit>(predicate: #Predicate { $0.name == name })
        ).first else {
            return .result(dialog: "Je n'ai pas trouvé cette habitude.")
        }
        if target.completions.contains(where: { Calendar.current.isDateInToday($0.date) }) {
            return .result(dialog: "\(name) est déjà validée aujourd'hui.")
        }
        target.completions.append(HabitCompletion(date: .now))
        try ctx.save()
        return .result(dialog: "\(name) validée. Bien joué.")
    }
}

// MARK: - Log mood (humeur)

struct LogMoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Enregistrer mon humeur"
    static let description = IntentDescription("Enregistre ton humeur du moment (1 = triste, 5 = super).")

    @Parameter(title: "Note (1 à 5)", default: 3)
    var score: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clamped = max(1, min(5, score))
        let ctx = try LocalStore.container().mainContext
        ctx.insert(MoodEntry(date: .now, score: clamped, note: "", gratitude: ""))
        try ctx.save()
        return .result(dialog: "Humeur \(clamped)/5 notée. Merci de partager.")
    }
}

// MARK: - Add todo

struct AddTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter une tâche"
    static let description = IntentDescription("Crée une tâche dans ton to-do LifeOS.")

    @Parameter(title: "Tâche")
    var title: String

    @Parameter(title: "Urgente", default: false)
    var urgent: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = try LocalStore.container().mainContext
        let priority = urgent ? 2 : 0
        ctx.insert(TodoItem(title: title, priority: priority))
        try ctx.save()
        return .result(dialog: "C'est noté : \(title).")
    }
}

// MARK: - Open coach

struct OpenCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Parler à mon coach"
    static let description = IntentDescription("Ouvre le chat avec ton coach personnel LifeOS.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .lifeOSOpenAIChat, object: nil)
        return .result()
    }
}

// MARK: - Today energy

struct TodayEnergyIntent: AppIntent {
    static let title: LocalizedStringResource = "Mon énergie du jour"
    static let description = IntentDescription("Donne ton score d'énergie actuel calculé depuis Santé + ton bilan.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let score = UserDefaults.standard.integer(forKey: "todayEnergyScore")
        let label = UserDefaults.standard.string(forKey: "todayEnergyLabel") ?? ""
        if score > 0 {
            let dialog = label.isEmpty
                ? "Ton énergie du jour est de \(score) sur 100."
                : "Ton énergie du jour est de \(score) sur 100 : \(label)."
            return .result(dialog: LocalizedStringResource(stringLiteral: dialog))
        } else {
            return .result(dialog: "Tu n'as pas encore fait ton bilan matinal aujourd'hui.")
        }
    }
}

// MARK: - Open module

enum ModuleChoice: String, AppEnum {
    case fitness, nutrition, sleep, mind, productivity, finance, invest, career, learning, home, mobility, social, admin, travel, looks

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Module"
    static let caseDisplayRepresentations: [ModuleChoice: DisplayRepresentation] = [
        .fitness: "Sport",
        .nutrition: "Nutrition",
        .sleep: "Sommeil",
        .mind: "Mental",
        .productivity: "Productivité",
        .finance: "Finances",
        .invest: "Investissement",
        .career: "Carrière",
        .learning: "Apprentissage",
        .home: "Maison",
        .mobility: "Mobilité",
        .social: "Social",
        .admin: "Admin",
        .travel: "Voyage",
        .looks: "Looks"
    ]
}

struct OpenModuleIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir un module"
    static let description = IntentDescription("Ouvre directement l'un des 15 modules LifeOS.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Module")
    var module: ModuleChoice

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .lifeOSOpenModule,
            object: nil,
            userInfo: ["module": module.rawValue]
        )
        return .result()
    }
}

// MARK: - Log workout set

struct LogWorkoutSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Enregistrer une série muscu"
    static let description = IntentDescription("Ajoute une série d'exercice à ton journal fitness.")

    @Parameter(title: "Exercice")
    var exercise: String

    @Parameter(title: "Poids (kg)", default: 0)
    var weight: Double

    @Parameter(title: "Répétitions", default: 10)
    var reps: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = try LocalStore.container().mainContext
        ctx.insert(WorkoutSet(date: .now, exercise: exercise, weightKg: weight, reps: reps, rpe: 8))
        try ctx.save()
        let vol = Int(weight * Double(reps))
        return .result(dialog: "Série \(exercise) enregistrée : \(reps) reps à \(Int(weight)) kg (volume \(vol)).")
    }
}

// MARK: - AppShortcutsProvider (10 max, on en a 9)

struct LifeOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCoachIntent(),
            phrases: [
                "Parle à mon coach dans \(.applicationName)",
                "Ouvre le chat de \(.applicationName)"
            ],
            shortTitle: "Parler au coach",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: OpenFoodScanIntent(),
            phrases: [
                "Scanne mon repas avec \(.applicationName)",
                "Prends en photo mon assiette dans \(.applicationName)",
                "Analyse mon plat avec \(.applicationName)"
            ],
            shortTitle: "Scanner un repas",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Ajoute de l'eau dans \(.applicationName)",
                "J'ai bu un verre d'eau dans \(.applicationName)"
            ],
            shortTitle: "Ajouter de l'eau",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogMoodIntent(),
            phrases: [
                "Enregistre mon humeur dans \(.applicationName)",
                "Note mon humeur avec \(.applicationName)"
            ],
            shortTitle: "Enregistrer mon humeur",
            systemImageName: "face.smiling"
        )
        AppShortcut(
            intent: TodayEnergyIntent(),
            phrases: [
                "Quel est mon énergie sur \(.applicationName)",
                "Mon score du jour dans \(.applicationName)"
            ],
            shortTitle: "Mon énergie du jour",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: CompleteHabitIntent(),
            phrases: [
                "Valide une habitude dans \(.applicationName)",
                "J'ai fait mon habitude dans \(.applicationName)"
            ],
            shortTitle: "Valider une habitude",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: AddTodoIntent(),
            phrases: [
                "Ajoute une tâche dans \(.applicationName)",
                "Note une tâche avec \(.applicationName)"
            ],
            shortTitle: "Ajouter une tâche",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: LogWorkoutSetIntent(),
            phrases: [
                "Enregistre une série dans \(.applicationName)",
                "Log ma série muscu avec \(.applicationName)"
            ],
            shortTitle: "Enregistrer une série muscu",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: OpenModuleIntent(),
            phrases: [
                "Ouvre un module dans \(.applicationName)",
                "Va sur un module de \(.applicationName)"
            ],
            shortTitle: "Ouvrir un module",
            systemImageName: "square.grid.2x2"
        )
    }
}
