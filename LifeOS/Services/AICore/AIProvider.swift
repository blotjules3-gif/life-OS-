import Foundation

/// Abstraction d'un fournisseur de modèle IA (LLM).
///
/// Pourquoi cette couche : aujourd'hui `OnDeviceLLM` couple directement le code
/// à `SystemLanguageModel` d'Apple. Impossible de basculer vers un autre LLM
/// (Mistral, Claude, GPT) sans réécrire massivement. Ce protocole permet à
/// `AIModelRouter` de choisir dynamiquement le bon provider selon la tâche.
///
/// Contrats :
/// - Un provider est stateless côté données user (le contexte lui est fourni)
/// - Il expose ses capacités et sa disponibilité
/// - Il ne journalise PAS lui-même — `AIActivityLogger` s'en charge en amont
/// - Il ne connaît pas les tools — c'est `AIRequest.tools` qui les décrit
///
/// Concrete implementations :
/// - `AppleIntelligenceProvider` (iOS 26+, on-device, gratuit)
/// - `LocalRulesProvider` (fallback règles Swift, jamais réseau)
/// - Futurs : `MistralProvider`, `ClaudeProvider`, etc.
protocol AIProvider: Sendable {

    /// Identifiant unique du provider (usage logs, metrics, debug).
    var id: String { get }

    /// Nom humain court, ex: "Apple Intelligence", "Mistral Large".
    var displayName: String { get }

    /// Capacités du provider — utilisé par `AIModelRouter` pour matcher une requête.
    var capabilities: AICapabilities { get }

    /// Disponibilité runtime — le router doit vérifier avant chaque appel.
    @MainActor
    var availability: AIAvailability { get }

    /// Exécute une requête. Le provider adapte les messages à son propre format.
    /// Retourne toujours une réponse structurée (jamais nil) — utilise `AIResponse.error`
    /// si échec.
    func complete(_ request: AIRequest) async -> AIResponse
}

// MARK: - Capabilities

/// Ce que le provider sait faire. Le router filtre les providers éligibles selon
/// la tâche demandée.
struct AICapabilities: OptionSet, Sendable {
    let rawValue: Int

    /// Génération de texte libre.
    static let textGeneration = AICapabilities(rawValue: 1 << 0)
    /// Sortie structurée typée (JSON validé).
    static let structuredOutput = AICapabilities(rawValue: 1 << 1)
    /// Function calling / tool use natif.
    static let toolCalling = AICapabilities(rawValue: 1 << 2)
    /// Streaming token-par-token.
    static let streaming = AICapabilities(rawValue: 1 << 3)
    /// Multimodal (image en entrée).
    static let vision = AICapabilities(rawValue: 1 << 4)
    /// Fonctionne sans réseau.
    static let offline = AICapabilities(rawValue: 1 << 5)
    /// Traite les données 100% on-device (aucune sortie de l'iPhone).
    static let onDevice = AICapabilities(rawValue: 1 << 6)
    /// Latence < 500 ms typique.
    static let lowLatency = AICapabilities(rawValue: 1 << 7)
    /// Contexte long (> 8k tokens).
    static let longContext = AICapabilities(rawValue: 1 << 8)
}

// MARK: - Availability

/// État runtime du provider — recalculé à chaque requête (peut changer selon device state).
enum AIAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: UnavailabilityReason)

    enum UnavailabilityReason: String, Sendable {
        case iosTooOld
        case deviceNotEligible
        case notEnabledInSettings
        case modelDownloading
        case noNetwork
        case rateLimited
        case invalidCredentials
        case unknown
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

// MARK: - Request

/// Requête envoyée à un provider. Composée par `AIModelRouter` à partir du
/// message user + contexte + tools disponibles.
struct AIRequest: Sendable {

    /// Messages de la conversation (système + user + assistant précédents).
    let messages: [AIChatMessage]

    /// Tools que le provider peut appeler si sa capacité `.toolCalling` le permet.
    /// Si vide, réponse texte simple attendue.
    let tools: [AIToolDefinition]

    /// Contrainte de sortie structurée. `nil` = texte libre.
    let responseSchema: AIResponseSchema?

    /// Budget max en tokens output. Le provider peut ignorer si non supporté.
    let maxOutputTokens: Int?

    /// Température de génération (0.0 = déterministe, 1.0 = créatif). Défaut 0.7.
    let temperature: Double

    /// Timeout runtime en secondes. Défaut 20s — au-delà, un chat coach devient
    /// insupportable et le fallback LocalCoach répondra en <100ms.
    let timeout: TimeInterval

    /// Correlation ID pour tracer une requête à travers les logs.
    let correlationID: UUID

    init(
        messages: [AIChatMessage],
        tools: [AIToolDefinition] = [],
        responseSchema: AIResponseSchema? = nil,
        maxOutputTokens: Int? = nil,
        temperature: Double = 0.7,
        timeout: TimeInterval = 20,
        correlationID: UUID = UUID()
    ) {
        self.messages = messages
        self.tools = tools
        self.responseSchema = responseSchema
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.timeout = timeout
        self.correlationID = correlationID
    }
}

// MARK: - Message

/// Message dans la conversation. Compatible avec le format OpenAI / Anthropic / Mistral.
struct AIChatMessage: Sendable, Equatable {

    enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    let content: String
    /// Si `role == .tool`, l'id du tool_call auquel on répond.
    let toolCallID: String?
    /// Si `role == .assistant`, les tool_calls que l'assistant demande d'exécuter.
    let toolCalls: [AIToolCall]

    init(role: Role, content: String, toolCallID: String? = nil, toolCalls: [AIToolCall] = []) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }

    // Convenience
    static func system(_ content: String) -> AIChatMessage { .init(role: .system, content: content) }
    static func user(_ content: String) -> AIChatMessage { .init(role: .user, content: content) }
    static func assistant(_ content: String) -> AIChatMessage { .init(role: .assistant, content: content) }
}

// MARK: - Tool definitions (référencées, définies dans ToolRegistry.swift)

/// Description légère d'un tool envoyée au provider. La logique d'exécution
/// vit dans `ToolRegistry` — le provider ne fait que retourner l'intention d'appel.
struct AIToolDefinition: Sendable, Equatable {
    let name: String
    let description: String
    let parametersSchema: String   // JSON schema en string, ex: {"type":"object","properties":{...}}

    init(name: String, description: String, parametersSchema: String) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
    }
}

/// Un appel de tool réclamé par le LLM. L'orchestrateur amont exécute puis
/// renvoie le résultat en `AIChatMessage(role: .tool)`.
struct AIToolCall: Sendable, Equatable {
    let id: String
    let toolName: String
    let arguments: String   // JSON serialized
}

// MARK: - Response schema (structured output)

/// Décrit une structure de sortie que le provider DOIT respecter.
/// Si le provider a `.structuredOutput` dans ses capabilities, il garantit
/// que `AIResponse.text` respecte ce schéma.
struct AIResponseSchema: Sendable, Equatable {
    let name: String               // ex: "ExtractedFields"
    let jsonSchema: String         // JSON schema serialized
}

// MARK: - Response

/// Réponse retournée par un provider.
struct AIResponse: Sendable {

    /// Texte généré. Peut être vide si `toolCalls` est présent.
    let text: String

    /// Tool calls demandés par le modèle (à exécuter puis relancer une requête).
    let toolCalls: [AIToolCall]

    /// ID du provider ayant répondu (pour logs).
    let providerID: String

    /// Correlation ID rappelé.
    let correlationID: UUID

    /// Durée en secondes.
    let duration: TimeInterval

    /// Tokens en entrée si le provider les reporte (nil sinon).
    let inputTokens: Int?

    /// Tokens en sortie si reporté.
    let outputTokens: Int?

    /// Erreur si l'appel a échoué. Coexiste avec text vide.
    let error: AIError?

    init(
        text: String = "",
        toolCalls: [AIToolCall] = [],
        providerID: String,
        correlationID: UUID,
        duration: TimeInterval,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        error: AIError? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.providerID = providerID
        self.correlationID = correlationID
        self.duration = duration
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.error = error
    }

    var isSuccess: Bool { error == nil }
    var hasToolCalls: Bool { !toolCalls.isEmpty }
}

// MARK: - Error

/// Erreurs communes à tous les providers. Le router s'en sert pour choisir un fallback.
enum AIError: Error, Sendable, Equatable {
    case unavailable(AIAvailability.UnavailabilityReason)
    case timeout
    case malformedResponse(String)
    case schemaViolation(String)
    case rateLimited
    case networkError(String)
    case providerError(String)
    case cancelled
}
