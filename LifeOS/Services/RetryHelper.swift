import Foundation

/// Retry avec backoff exponentiel pour les opérations async qui peuvent
/// échouer temporairement (réseau, LLM guardrail, modèle indisponible).
///
/// **Usage** :
/// ```swift
/// let text = try await RetryHelper.withBackoff(attempts: 3) {
///     try await someAsyncCall()
/// }
/// ```
///
/// **Défaut** : 3 tentatives, delays [1s, 3s, 7s].
/// La dernière erreur est propagée si toutes échouent.
enum RetryHelper {

    /// Exécute une closure async avec retry. Chaque échec log via `AppLog.net.warning`.
    /// - Parameters:
    ///   - attempts: nombre max de tentatives (défaut 3)
    ///   - delays: durées d'attente en secondes entre chaque tentative (par défaut 1, 3, 7)
    ///   - operation: identifiant pour les logs (défaut "op")
    ///   - action: closure à exécuter
    static func withBackoff<T: Sendable>(
        attempts: Int = 3,
        delays: [UInt64] = [1, 3, 7],
        operation: String = "op",
        action: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                return try await action()
            } catch {
                lastError = error
                let isLast = attempt == attempts
                AppLog.net.warning(
                    "\(operation, privacy: .public) attempt \(attempt)/\(attempts) failed: \(error.localizedDescription, privacy: .public)"
                )
                if isLast { break }
                let seconds = delays[min(attempt - 1, delays.count - 1)]
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
        throw lastError ?? NSError(
            domain: "RetryHelper",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "All \(attempts) retry attempts failed"]
        )
    }

    /// Variante qui retourne nil au lieu de throw (utile pour les fallbacks silencieux).
    static func withBackoffOrNil<T: Sendable>(
        attempts: Int = 3,
        delays: [UInt64] = [1, 3, 7],
        operation: String = "op",
        action: @Sendable () async throws -> T
    ) async -> T? {
        try? await withBackoff(attempts: attempts, delays: delays, operation: operation, action: action)
    }
}
