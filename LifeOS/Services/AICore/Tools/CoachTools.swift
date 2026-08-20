import Foundation
import SwiftData

/// Suite d'outils prêts à l'emploi pour le coach.
///
/// Chaque tool respecte le protocol `AITool` — arguments typés + permissions
/// vérifiées par le registry + résultat JSON structuré avec provenance.
///
/// Enregistrement : appeler `CoachToolsBootstrap.registerAll()` au boot app.
///
/// Aujourd'hui : ces tools sont préparés pour la future migration
/// `LanguageModelSession(tools:)` iOS 26.1+. Ils sont déjà callables via
/// `ToolRegistry.shared.execute(...)`.

// MARK: - GetUserProfileTool

/// Retourne un résumé compact du profil (dernières valeurs + confidences).
struct GetUserProfileTool: AITool {
    struct Arguments: Codable, Sendable {}
    struct Result: Codable, Sendable {
        let fields: [FieldSummary]
        struct FieldSummary: Codable, Sendable {
            let id: String
            let displayName: String
            let value: String
            let confidence: Double
            let source: String
            let updatedAt: Date
        }
    }

    static let definition = AIToolDefinition(
        name: "get_user_profile",
        description: "Retourne les données de profil utilisateur (poids, taille, objectifs, préférences) avec leur confiance et date de dernière mise à jour.",
        parametersSchema: #"{"type":"object","properties":{},"required":[]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.profileRead]

    func execute(_ args: Arguments) async throws -> Result {
        let fields = await MainActor.run {
            ProfileStore.shared.allFields().compactMap { field -> Result.FieldSummary? in
                guard let spec = ProfileFieldCatalog.all[field.fieldID] else { return nil }
                return Result.FieldSummary(
                    id: field.fieldID,
                    displayName: spec.displayName,
                    value: field.valueString,
                    confidence: field.confidence,
                    source: field.source,
                    updatedAt: field.updatedAt
                )
            }
        }
        return Result(fields: fields)
    }
}

// MARK: - GetProfileFieldTool

/// Retourne UNE valeur précise par fieldID. Plus efficient si le coach sait ce qu'il cherche.
struct GetProfileFieldTool: AITool {
    struct Arguments: Codable, Sendable {
        let fieldID: String
    }
    struct Result: Codable, Sendable {
        let fieldID: String
        let displayName: String
        let value: String?
        let confidence: Double?
        let source: String?
        let updatedAt: Date?
        let notFound: Bool
    }

    static let definition = AIToolDefinition(
        name: "get_profile_field",
        description: "Retourne la valeur d'un champ précis du profil. fieldID exemples : 'body.currentWeightKg', 'nutrition.kcalGoal', 'fitness.gymFrequency'.",
        parametersSchema: #"{"type":"object","properties":{"fieldID":{"type":"string"}},"required":["fieldID"]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.profileRead]

    func execute(_ args: Arguments) async throws -> Result {
        let field = await MainActor.run { ProfileStore.shared.field(args.fieldID) }
        let spec = ProfileFieldCatalog.all[args.fieldID]
        guard let field, let spec else {
            return Result(
                fieldID: args.fieldID,
                displayName: spec?.displayName ?? args.fieldID,
                value: nil, confidence: nil, source: nil, updatedAt: nil,
                notFound: true
            )
        }
        return Result(
            fieldID: field.fieldID,
            displayName: spec.displayName,
            value: field.valueString,
            confidence: field.confidence,
            source: field.source,
            updatedAt: field.updatedAt,
            notFound: false
        )
    }
}

// MARK: - SearchMemoryTool

/// Cherche dans la mémoire long terme du coach (MemoryEntry) par mot-clé.
struct SearchMemoryTool: AITool {
    struct Arguments: Codable, Sendable {
        let query: String
        let limit: Int?
    }
    struct Result: Codable, Sendable {
        let memories: [Memory]
        struct Memory: Codable, Sendable {
            let content: String
            let category: String
            let source: String
            let createdAt: Date
            let isPinned: Bool
        }
    }

    static let definition = AIToolDefinition(
        name: "search_memory",
        description: "Cherche dans la mémoire long terme du coach (préférences, objectifs, faits durables déjà dits par le user). Retourne les entrées qui matchent la query.",
        parametersSchema: #"{"type":"object","properties":{"query":{"type":"string"},"limit":{"type":"integer","default":5}},"required":["query"]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.memoryRead]

    func execute(_ args: Arguments) async throws -> Result {
        let limit = min(max(args.limit ?? 5, 1), 20)
        let queryLower = args.query.lowercased()
        let memories = try await MainActor.run { () throws -> [Result.Memory] in
            let ctx = try LocalStore.container().mainContext
            let all = (try? ctx.fetch(FetchDescriptor<MemoryEntry>())) ?? []
            let filtered = all
                .filter { $0.content.lowercased().contains(queryLower) || $0.category.lowercased().contains(queryLower) }
                .sorted { $0.created > $1.created }
                .prefix(limit)
            return filtered.map {
                Result.Memory(
                    content: $0.content,
                    category: $0.category,
                    source: $0.source,
                    createdAt: $0.created,
                    isPinned: $0.isPinned
                )
            }
        }
        return Result(memories: memories)
    }
}

// MARK: - CreateHabitTool

/// Crée une habitude directement dans SwiftData (utilisé par le coach si tool calling activé).
struct CreateHabitTool: AITool {
    struct Arguments: Codable, Sendable {
        let name: String
        let module: String?     // ex: "fitness", "nutrition", "mind"
    }
    struct Result: Codable, Sendable {
        let created: Bool
        let name: String
        let module: String?
    }

    static let definition = AIToolDefinition(
        name: "create_habit",
        description: "Crée une nouvelle habitude quotidienne à traquer. name = nom court ('Méditer 10 min'). module = catégorie parmi fitness/nutrition/mind/productivity/sleep/looks/medical.",
        parametersSchema: #"{"type":"object","properties":{"name":{"type":"string"},"module":{"type":"string"}},"required":["name"]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.habitsWrite]

    func execute(_ args: Arguments) async throws -> Result {
        let trimmed = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            throw ToolExecutionError.invalidArguments("name trop court")
        }
        try await MainActor.run {
            let ctx = try LocalStore.container().mainContext
            let defaults = HabitDefaults.iconAndColor(for: args.module ?? "")
            let habit = Habit(
                name: trimmed,
                icon: defaults.icon,
                colorHex: defaults.colorHex,
                isPending: false,
                moduleTag: args.module ?? ""
            )
            ctx.insert(habit)
            try ctx.save()
        }
        return Result(created: true, name: trimmed, module: args.module)
    }
}

// MARK: - CreateTodoTool

/// Crée une tâche one-shot dans le TodoList.
struct CreateTodoTool: AITool {
    struct Arguments: Codable, Sendable {
        let title: String
        let priority: Int?      // 0=basse, 1=normale, 2=urgente
    }
    struct Result: Codable, Sendable {
        let created: Bool
        let title: String
        let priority: Int
    }

    static let definition = AIToolDefinition(
        name: "create_todo",
        description: "Crée une tâche à faire une fois. title = intitulé court. priority = 0 (basse), 1 (normale, défaut), 2 (urgente).",
        parametersSchema: #"{"type":"object","properties":{"title":{"type":"string"},"priority":{"type":"integer","default":1}},"required":["title"]}"#
    )
    static let requiredPermissions: Set<AIPermission> = [.todosWrite]

    func execute(_ args: Arguments) async throws -> Result {
        let trimmed = args.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            throw ToolExecutionError.invalidArguments("title trop court")
        }
        let priority = min(max(args.priority ?? 1, 0), 2)
        try await MainActor.run {
            let ctx = try LocalStore.container().mainContext
            ctx.insert(TodoItem(title: trimmed, priority: priority))
            try ctx.save()
        }
        return Result(created: true, title: trimmed, priority: priority)
    }
}

// MARK: - Bootstrap

/// Enregistre tous les tools coach au démarrage de l'app.
/// À appeler dans `LifeOSApp.onAppear` après `ProfileStore.shared.setContext(...)`.
@MainActor
enum CoachToolsBootstrap {
    static func registerAll() {
        let registry = ToolRegistry.shared
        registry.register(GetUserProfileTool())
        registry.register(GetProfileFieldTool())
        registry.register(SearchMemoryTool())
        registry.register(CreateHabitTool())
        registry.register(CreateTodoTool())
        registry.register(PhotoAnalysisTool())
    }
}
