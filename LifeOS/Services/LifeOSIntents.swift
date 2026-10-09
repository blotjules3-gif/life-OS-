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
        guard (1...3000).contains(amountML) else {
            return .result(dialog: "Indique une quantité entre 1 et 3000 ml.")
        }
        let ctx = try LocalStore.container().mainContext
        let e = WaterEntry(date: .now, amountML: amountML)
        e.volumeML = amountML
        ctx.insert(e)
        try ctx.save()
        // Le processus peut s'arreter juste apres : on publie tout de suite (widget eau,
        // total lu par le coach, score energie).
        WidgetPublisher.shared.publishNow([.water, .energy], ctx: ctx)
        let total = UserDefaults(suiteName: LifeOSGroup.id)?.integer(forKey: WidgetKeys.waterToday) ?? amountML
        return .result(dialog: "C'est noté : \(amountML) ml. Total du jour : \(total) ml.")
    }
}

/// Habitude exposee a Siri et Raccourcis. L'identifiant est l'identifiant stable
/// (`Habit.uid`) : deux habitudes du meme nom ne se confondent plus. Un ancien
/// raccourci enregistre avec le NOM comme identifiant est encore reconnu, s'il ne
/// designe qu'une seule habitude.
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
        let habits = try activeHabits()
        return identifiers.compactMap { id in
            if let h = habits.first(where: { $0.uid == id }) { return HabitEntity(id: h.uid, name: h.name) }
            let byName = habits.filter { $0.name == id }
            return byName.count == 1 ? HabitEntity(id: byName[0].uid, name: byName[0].name) : nil
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        try activeHabits().map { HabitEntity(id: $0.uid, name: $0.name) }
    }

    @MainActor
    private func activeHabits() throws -> [Habit] {
        let ctx = try LocalStore.container().mainContext
        HabitSync.ensureIDs(ctx)
        return try ctx.fetch(FetchDescriptor<Habit>(predicate: #Predicate { !$0.isArchived && !$0.isPending }))
            .filter { !$0.uid.isEmpty }
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
        HabitSync.ensureIDs(ctx)
        // Resolution par identifiant stable ; nom seulement s'il est unique.
        let entity = try await HabitEntityQuery().entities(for: [habit.id]).first
        guard let uid = entity?.id, !uid.isEmpty else {
            return .result(dialog: "Je n'ai pas trouvé cette habitude.")
        }
        let name = entity?.name ?? habit.name
        let today = HabitOps.businessDay(.now, timeZone: .current)
        var fd = FetchDescriptor<Habit>(predicate: #Predicate { $0.uid == uid })
        fd.fetchLimit = 1
        if let h = try ctx.fetch(fd).first,
           h.completions.contains(where: { HabitOps.businessDay($0.date, timeZone: .current) == today }) {
            return .result(dialog: "\(name) est déjà validée aujourd'hui.")
        }
        // Meme chemin que le widget : ordre explicite par identifiant, applique puis
        // acquitte apres sauvegarde (un rejeu ne coche pas deux fois).
        try HabitOps.enqueue(HabitOp(habitID: uid, action: .complete, source: "siri"))
        HabitSync.drain(ctx)
        WidgetPublisher.shared.publishNow([.habits, .energy], ctx: ctx)
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
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .result(dialog: "Dis-moi le texte de la tâche.") }
        ctx.insert(TaskInbox.makeTodo(trimmed, priority: priority))
        try ctx.save()
        WidgetPublisher.shared.publishNow([.tasks, .agenda], ctx: ctx)
        return .result(dialog: "C'est noté : \(trimmed).")
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
            let text = label.isEmpty
                ? "Ton énergie du jour est de \(score) sur 100."
                : "Ton énergie du jour est de \(score) sur 100 : \(label)."
            return .result(dialog: IntentDialog(stringLiteral: text))
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
        try GymSessionService.logStandalone(exercise: exercise, weightText: String(weight), reps: reps, in: ctx)
        let vol = Int(weight * Double(reps))
        return .result(dialog: "Série \(exercise) enregistrée : \(reps) reps à \(Int(weight)) kg (volume \(vol)).")
    }
}

// MARK: - Ingest profile text (Raccourci iOS pour dictée libre)

/// Accepte un texte libre depuis un Raccourci iOS, l'analyse avec
/// `IntelligentExtractor` et met à jour le profil.
///
/// Exemple d'usage : l'utilisateur crée un Raccourci qui prend une entrée vocale
/// ("Cette semaine j'ai dormi 7h et je vais 4x à la salle"), puis passe ce texte
/// à cet Intent → le profil est mis à jour en tâche de fond.
///
/// 100% on-device : aucune donnée n'est envoyée à un serveur. La transcription
/// vocale est faite par le raccourci (dictée iOS native), l'analyse par
/// Apple Intelligence local + regex FR.
struct IngestProfileTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter au profil (texte libre)"
    static let description = IntentDescription(
        "Analyse un texte libre (dictée ou saisie) et met à jour ton profil LifeOS automatiquement."
    )

    @Parameter(title: "Texte à analyser")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else {
            return .result(dialog: "Message trop court pour être analysé.")
        }
        // S'assure que le store a un context même si l'app n'a jamais démarré
        // (le raccourci peut être exécuté à froid).
        let ctx = try LocalStore.container().mainContext
        ProfileStore.shared.setContext(ctx)

        let changes = await IntelligentExtractor.extractAndPersist(from: trimmed, source: .shortcut)

        guard !changes.isEmpty else {
            return .result(dialog: "Rien de nouveau détecté. Reformule avec des chiffres ou des mots-clés (poids, kcal, séances par semaine…).")
        }
        // Invalider le cache pour que le prochain chat utilise la nouvelle valeur
        UserContextBuilder.shared.invalidateCache()
        let summary = changes.prefix(3).map { $0.displayName }.joined(separator: ", ")
        return .result(dialog: "Profil mis à jour : \(summary).")
    }
}

// MARK: - AppShortcutsProvider (10 max, on en a 10)

struct LifeOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCoachIntent(),
            phrases: [
                "Parle à mon coach dans \(.applicationName)",
                "Ouvre le chat de \(.applicationName)"
            ],
            shortTitle: "Parler au coach",
            systemImageName: "infinity"
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
        AppShortcut(
            intent: IngestProfileTextIntent(),
            phrases: [
                "Ajoute au profil \(.applicationName)",
                "Note dans mon profil \(.applicationName)",
                "Enregistre dans \(.applicationName)"
            ],
            shortTitle: "Dicter au profil",
            systemImageName: "waveform.badge.plus"
        )
    }
}
