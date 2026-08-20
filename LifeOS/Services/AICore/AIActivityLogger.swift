import Foundation
import Combine

/// Journal structuré de l'activité IA — ce qui se passe à chaque tour du chat.
///
/// Objectif : observer précisément pour améliorer.
/// - Quel provider a répondu ?
/// - Combien de tokens ? Combien de temps ?
/// - Quels tools ont été appelés ?
/// - Quels intents détectés ? Confidence ?
/// - Fallback utilisé ?
///
/// Ce logger est INDÉPENDANT d'`AppLog` (os.Logger) :
/// - os.Logger = log système, pour Console.app + Sentry
/// - AIActivityLogger = log applicatif structuré, accessible dans une vue debug interne
///
/// Ne stocke QUE les métadonnées (jamais le contenu textuel du message user)
/// pour respecter la confidentialité même en mode debug.
@MainActor
final class AIActivityLogger: ObservableObject {
    static let shared = AIActivityLogger()

    /// Sessions récentes (max 100 en mémoire, ring buffer).
    @Published private(set) var sessions: [AISession] = []

    private let maxSessions = 100

    private init() {}

    // MARK: - Publication

    /// Démarre une session (avant l'appel LLM). Retourne l'ID à propager.
    @discardableResult
    func startSession(
        messageLength: Int,
        classification: MessageClassifier.Classification?
    ) -> UUID {
        let id = UUID()
        let session = AISession(
            id: id,
            startedAt: .now,
            messageLength: messageLength,
            classification: classification.map { AISessionClassification(from: $0) }
        )
        sessions.append(session)
        if sessions.count > maxSessions {
            sessions.removeFirst(sessions.count - maxSessions)
        }
        return id
    }

    /// Enregistre le prompt assemblé (tokens estimés).
    func recordContext(
        sessionID: UUID,
        totalTokens: Int,
        budgetTokens: Int,
        sectionUsage: [String: Int],
        truncations: [String]
    ) {
        update(sessionID: sessionID) { s in
            s.contextTokens = totalTokens
            s.contextBudget = budgetTokens
            s.sectionUsage = sectionUsage
            s.truncations = truncations
        }
    }

    /// Enregistre la sélection du provider.
    func recordProviderSelection(
        sessionID: UUID,
        providerID: String,
        wasFallback: Bool
    ) {
        update(sessionID: sessionID) { s in
            s.providerID = providerID
            s.wasFallback = wasFallback
        }
    }

    /// Enregistre le résultat.
    func recordResponse(
        sessionID: UUID,
        response: AIResponse
    ) {
        update(sessionID: sessionID) { s in
            s.durationMs = Int(response.duration * 1000)
            s.outputTokens = response.outputTokens
            s.inputTokens = response.inputTokens
            s.error = response.error.map(String.init(describing:))
            s.toolCallsRequested = response.toolCalls.map(\.toolName)
            s.completedAt = .now
        }
    }

    /// Enregistre l'exécution d'un tool (post-appel LLM).
    func recordToolExecution(
        sessionID: UUID,
        toolName: String,
        success: Bool,
        durationMs: Int
    ) {
        update(sessionID: sessionID) { s in
            s.toolsExecuted.append(AIToolExecution(
                toolName: toolName,
                success: success,
                durationMs: durationMs
            ))
        }
    }

    /// Enregistre le nom des post-processors appliqués (issues corrigées).
    func recordPostProcessing(sessionID: UUID, issues: [String]) {
        update(sessionID: sessionID) { s in
            s.postProcessingIssues = issues
        }
    }

    /// Clear tout (bouton debug).
    func clear() {
        sessions.removeAll()
    }

    // MARK: - Internal

    private func update(sessionID: UUID, mutation: (inout AISession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = sessions[index]
        mutation(&session)
        sessions[index] = session
    }
}

// MARK: - Session models

/// Snapshot d'une session IA — un tour complet du chat.
/// Aucun contenu textuel utilisateur stocké (confidentialité).
struct AISession: Identifiable {
    let id: UUID
    let startedAt: Date
    let messageLength: Int
    let classification: AISessionClassification?

    // Renseignés au fur et à mesure
    var contextTokens: Int?
    var contextBudget: Int?
    var sectionUsage: [String: Int] = [:]
    var truncations: [String] = []
    var providerID: String?
    var wasFallback: Bool = false
    var durationMs: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var error: String?
    var toolCallsRequested: [String] = []
    var toolsExecuted: [AIToolExecution] = []
    var postProcessingIssues: [String] = []
    var completedAt: Date?

    var isCompleted: Bool { completedAt != nil }
    var hasError: Bool { error != nil }
}

/// Snapshot anonymisé de la classification (pas de contenu texte).
struct AISessionClassification {
    let sentiment: String
    let intentType: String
    let complexity: String
    let language: String
    let topicsCount: Int
    let containsQuestion: Bool
    let containsNumbers: Bool

    init(from c: MessageClassifier.Classification) {
        sentiment = c.sentiment.rawValue
        intentType = c.intentType.rawValue
        complexity = c.complexity.rawValue
        language = c.dominantLanguage.rawValue
        topicsCount = c.topicsDetected.count
        containsQuestion = c.containsQuestion
        containsNumbers = c.containsNumbers
    }
}

struct AIToolExecution {
    let toolName: String
    let success: Bool
    let durationMs: Int
}
