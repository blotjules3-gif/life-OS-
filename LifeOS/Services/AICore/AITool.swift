import Foundation

/// Un outil que le LLM peut appeler. Contrat strict :
/// - Arguments typés (Codable)
/// - Résultat typé (Codable)
/// - Permissions déclarées (le registry refuse l'exécution si permission manquante)
/// - Provenance retournée (source, timestamp, confidence)
///
/// Implémentation :
///   struct GetUserWeightTool: AITool {
///     struct Arguments: Codable {} // pas d'args
///     struct Result: Codable {
///       let weightKg: Double
///       let lastUpdated: Date
///       let source: String
///     }
///     static let definition = AIToolDefinition(...)
///     static let requiredPermissions: Set<AIPermission> = [.profileRead]
///     func execute(_ args: Arguments) async throws -> Result { ... }
///   }
protocol AITool: Sendable {
    associatedtype Arguments: Codable & Sendable
    associatedtype Result: Codable & Sendable

    /// Métadonnées exposées au LLM.
    static var definition: AIToolDefinition { get }

    /// Permissions requises. Le registry vérifie avant exécution.
    static var requiredPermissions: Set<AIPermission> { get }

    /// Exécute l'outil. Peut throw — le registry catch et retourne une erreur JSON.
    func execute(_ args: Arguments) async throws -> Result
}

// MARK: - Permissions

/// Portée d'accès demandée par un outil. Utilisé par `AIPermissionGate` pour
/// vérifier ce que l'utilisateur a autorisé.
enum AIPermission: String, Sendable, Codable, Hashable {
    // Données internes app
    case profileRead
    case profileWrite
    case memoryRead
    case memoryWrite
    case habitsRead
    case habitsWrite
    case todosWrite
    case remindersWrite

    // Frameworks Apple (mappés aux entitlements)
    case healthRead
    case healthWrite
    case calendarRead
    case calendarWrite
    case contactsRead
    case photosMetadataRead
    case locationRead

    /// Description lisible pour le Consent Center.
    var displayDescription: String {
        switch self {
        case .profileRead:  return "Lire ton profil"
        case .profileWrite: return "Modifier ton profil"
        case .memoryRead:   return "Lire ta mémoire coach"
        case .memoryWrite:  return "Écrire dans ta mémoire coach"
        case .habitsRead:   return "Lire tes habitudes"
        case .habitsWrite:  return "Créer/modifier tes habitudes"
        case .todosWrite:   return "Créer des tâches"
        case .remindersWrite: return "Créer des rappels"
        case .healthRead:   return "Lire tes données Santé"
        case .healthWrite:  return "Écrire dans Santé"
        case .calendarRead: return "Lire ton calendrier"
        case .calendarWrite: return "Créer des événements"
        case .contactsRead: return "Lire tes contacts"
        case .photosMetadataRead: return "Lire les métadonnées de tes photos"
        case .locationRead: return "Lire ta position"
        }
    }
}

// MARK: - Result envelope

/// Ce que le registry retourne au LLM après exécution d'un outil.
/// Toujours typé — jamais du texte libre.
struct AIToolResult: Sendable, Codable {
    /// Résultat JSON serialized. Pour un succès, correspond au Result.encode.
    let json: String
    /// Provenance du résultat (source, timestamp, confidence). Facultatif.
    let provenance: AIProvenance?
    /// Erreur textuelle si l'outil a échoué. `success = json est valide` sinon.
    let error: String?

    var success: Bool { error == nil }

    init(json: String, provenance: AIProvenance? = nil, error: String? = nil) {
        self.json = json
        self.provenance = provenance
        self.error = error
    }

    static func error(_ message: String) -> AIToolResult {
        AIToolResult(json: "{}", provenance: nil, error: message)
    }
}

/// Provenance d'une donnée retournée par un tool.
/// Le coach peut la citer dans sa réponse ("d'après HealthKit synced il y a 2h").
struct AIProvenance: Sendable, Codable {
    enum SourceType: String, Codable, Sendable {
        case userDeclared        // écrit ou dit par l'user
        case userConfirmed       // proposé par le coach + validé user
        case healthKit
        case eventKit
        case contacts
        case photos
        case appProfile          // ProfileField interne
        case appMemory           // MemoryEntry interne
        case appHabits           // Habit interne
        case computed            // calculé (ex: score énergie)
    }

    let source: SourceType
    let identifier: String?      // ex: fieldID, healthDataType, uuid entry
    let acquiredAt: Date
    let userConfirmed: Bool
    let confidence: Double       // 0.0 - 1.0

    init(source: SourceType, identifier: String? = nil, acquiredAt: Date = .now,
         userConfirmed: Bool = false, confidence: Double = 1.0) {
        self.source = source
        self.identifier = identifier
        self.acquiredAt = acquiredAt
        self.userConfirmed = userConfirmed
        self.confidence = min(max(confidence, 0), 1)
    }
}
