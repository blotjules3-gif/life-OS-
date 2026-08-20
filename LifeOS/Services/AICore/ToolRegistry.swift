import Foundation

/// Registry central des outils exposés au LLM.
///
/// Responsabilités :
/// - Enregistrement statique + description exposée aux providers
/// - Validation des arguments JSON avant exécution
/// - Vérification des permissions
/// - Exécution safe (try/catch → AIToolResult.error)
/// - Journalisation via AIActivityLogger
///
/// Utilisation :
///   ToolRegistry.shared.register(GetUserWeightTool())
///   let result = await ToolRegistry.shared.execute("get_user_weight", argsJSON: "{}")
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private var tools: [String: RegisteredTool] = [:]
    private let permissionGate = AIPermissionGate.shared

    private init() {}

    // MARK: - Registration

    /// Wrapper type-erased pour stocker des tools de types différents.
    private struct RegisteredTool {
        let definition: AIToolDefinition
        let requiredPermissions: Set<AIPermission>
        let execute: @Sendable (String) async throws -> Data  // takes JSON args, returns JSON result Data
    }

    /// Enregistre un tool. Idempotent — remplace si nom existe déjà.
    func register<T: AITool>(_ tool: T) {
        let definition = T.definition
        let permissions = T.requiredPermissions
        let executor: @Sendable (String) async throws -> Data = { argsJSON in
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let argsData = argsJSON.data(using: .utf8) ?? Data("{}".utf8)
            let args: T.Arguments
            do {
                args = try decoder.decode(T.Arguments.self, from: argsData)
            } catch {
                throw ToolExecutionError.invalidArguments(error.localizedDescription)
            }
            let result = try await tool.execute(args)
            return try encoder.encode(result)
        }
        tools[definition.name] = RegisteredTool(
            definition: definition,
            requiredPermissions: permissions,
            execute: executor
        )
    }

    // MARK: - Introspection (exposé au LLM)

    /// Toutes les définitions disponibles — utilisé pour peupler `AIRequest.tools`.
    var allDefinitions: [AIToolDefinition] {
        tools.values.map(\.definition).sorted { $0.name < $1.name }
    }

    /// Retourne uniquement les tools accessibles avec les permissions actuellement
    /// accordées — filtre invisible pour le LLM.
    func availableDefinitions() -> [AIToolDefinition] {
        tools.values.compactMap { registered in
            let missing = registered.requiredPermissions.subtracting(permissionGate.grantedPermissions())
            return missing.isEmpty ? registered.definition : nil
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Exécution

    /// Exécute un tool par nom. Retourne toujours un `AIToolResult`, même en erreur.
    func execute(_ name: String, argsJSON: String, correlationID: UUID = UUID()) async -> AIToolResult {
        guard let registered = tools[name] else {
            AppLog.coach.warning("ToolRegistry: unknown tool \(name, privacy: .public)")
            return .error("Outil inconnu : \(name)")
        }
        // Vérif permissions
        let missing = registered.requiredPermissions.subtracting(permissionGate.grantedPermissions())
        if !missing.isEmpty {
            let list = missing.map { $0.displayDescription }.joined(separator: ", ")
            return .error("Permission manquante : \(list)")
        }
        // Exécution
        do {
            let data = try await registered.execute(argsJSON)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return AIToolResult(json: json)
        } catch let error as ToolExecutionError {
            return .error(error.localizedDescription)
        } catch {
            AppLog.coach.error("ToolRegistry \(name, privacy: .public) execution failed: \(error.localizedDescription, privacy: .public)")
            return .error("Erreur d'exécution : \(error.localizedDescription)")
        }
    }
}

// MARK: - Erreurs

enum ToolExecutionError: Error, LocalizedError {
    case invalidArguments(String)
    case runtimeError(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg): return "Arguments invalides : \(msg)"
        case .runtimeError(let msg): return "Erreur : \(msg)"
        }
    }
}

// MARK: - AIPermissionGate

/// Portail central des permissions accordées par l'utilisateur.
/// Aujourd'hui : simple set en mémoire + persistance UserDefaults.
/// Demain : Consent Center UI + explication contextuelle.
@MainActor
final class AIPermissionGate {
    static let shared = AIPermissionGate()

    private let storageKey = "ai.permission.granted.set"

    private init() {}

    /// Set des permissions actuellement accordées.
    func grantedPermissions() -> Set<AIPermission> {
        guard let arr = UserDefaults.standard.stringArray(forKey: storageKey) else {
            // Par défaut : autoriser les permissions "internes" à l'app.
            // Les permissions Apple (HealthKit, EventKit) restent explicites.
            return [.profileRead, .profileWrite, .memoryRead, .memoryWrite,
                    .habitsRead, .habitsWrite, .todosWrite, .remindersWrite]
        }
        return Set(arr.compactMap { AIPermission(rawValue: $0) })
    }

    /// Accorde une permission (appelé par le Consent Center ou après un flow système).
    func grant(_ permission: AIPermission) {
        var current = grantedPermissions()
        current.insert(permission)
        persist(current)
    }

    /// Révoque une permission.
    func revoke(_ permission: AIPermission) {
        var current = grantedPermissions()
        current.remove(permission)
        persist(current)
    }

    /// Vérifie si une permission est accordée (helper).
    func isGranted(_ permission: AIPermission) -> Bool {
        grantedPermissions().contains(permission)
    }

    private func persist(_ set: Set<AIPermission>) {
        UserDefaults.standard.set(set.map(\.rawValue).sorted(), forKey: storageKey)
    }
}
