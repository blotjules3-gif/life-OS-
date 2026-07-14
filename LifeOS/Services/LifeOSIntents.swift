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

struct LifeOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
            intent: CompleteHabitIntent(),
            phrases: [
                "Valide une habitude dans \(.applicationName)",
                "J'ai fait mon habitude dans \(.applicationName)"
            ],
            shortTitle: "Valider une habitude",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
