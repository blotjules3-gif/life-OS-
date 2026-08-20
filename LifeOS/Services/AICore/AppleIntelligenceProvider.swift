import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Provider IA basé sur Apple Intelligence (`SystemLanguageModel`).
///
/// Caractéristiques :
/// - 100% on-device (donnée user ne quitte jamais l'iPhone)
/// - Gratuit
/// - Contexte limité (~4k tokens)
/// - Structured output supporté via `@Generable` (iOS 26.1+) — non exposé ici encore
/// - Tool calling supporté (iOS 26.1+) — non exposé ici encore
///
/// Cette V1 wrap l'API `LanguageModelSession(instructions:).respond(to:)` existante.
/// La V2 (Phase 3 du plan) migrera vers `.respond(schema:)` + `session.tools`.
struct AppleIntelligenceProvider: AIProvider {

    let id = "apple.intelligence.on-device"
    let displayName = "Apple Intelligence"

    var capabilities: AICapabilities {
        // Aujourd'hui l'API respond(to:) supporte texte + streaming (non exposé ici)
        // Structured output + tools arrivent dans phase 3.
        [.textGeneration, .offline, .onDevice, .lowLatency]
    }

    @MainActor
    var availability: AIAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable(reason: .deviceNotEligible)
                case .appleIntelligenceNotEnabled:
                    return .unavailable(reason: .notEnabledInSettings)
                case .modelNotReady:
                    return .unavailable(reason: .modelDownloading)
                @unknown default:
                    return .unavailable(reason: .unknown)
                }
            }
        } else {
            return .unavailable(reason: .iosTooOld)
        }
        #else
        return .unavailable(reason: .iosTooOld)
        #endif
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        // Vérif disponibilité juste avant l'appel (peut changer entre le routing et l'exécution)
        let avail = await MainActor.run { self.availability }
        guard avail.isAvailable else {
            if case .unavailable(let reason) = avail {
                return AIResponse(
                    providerID: id,
                    correlationID: request.correlationID,
                    duration: Date().timeIntervalSince(start),
                    error: .unavailable(reason)
                )
            }
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .unavailable(.unknown)
            )
        }

        // Compose instructions (system) + prompt utilisateur (dernier message user)
        let systemMessages = request.messages.filter { $0.role == .system }
        let userMessages = request.messages.filter { $0.role == .user }
        let instructions = systemMessages.map(\.content).joined(separator: "\n\n")
        guard let lastUser = userMessages.last?.content else {
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("no user message")
            )
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await performAppleIntelligenceCall(
                instructions: instructions,
                prompt: lastUser,
                request: request,
                start: start
            )
        }
        #endif

        return AIResponse(
            providerID: id,
            correlationID: request.correlationID,
            duration: Date().timeIntervalSince(start),
            error: .unavailable(.iosTooOld)
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func performAppleIntelligenceCall(
        instructions: String,
        prompt: String,
        request: AIRequest,
        start: Date
    ) async -> AIResponse {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await withTimeout(seconds: request.timeout) {
                try await session.respond(to: prompt)
            }
            return AIResponse(
                text: response.content,
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: nil
            )
        } catch is CancellationError {
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .cancelled
            )
        } catch let AITimeoutError.timeout {
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .timeout
            )
        } catch {
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .providerError(error.localizedDescription)
            )
        }
    }
    #endif
}

// MARK: - Timeout helper

private enum AITimeoutError: Error {
    case timeout
}

/// Enveloppe une opération async avec un timeout. Si dépassement, throw
/// `AITimeoutError.timeout`. La tâche child est annulée.
private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AITimeoutError.timeout
        }
        guard let first = try await group.next() else {
            throw AITimeoutError.timeout
        }
        group.cancelAll()
        return first
    }
}
