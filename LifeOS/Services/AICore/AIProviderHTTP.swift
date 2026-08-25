import Foundation

/// Helper HTTP factorisé pour les providers cloud (OpenAI, Anthropic, Mistral,
/// Gemini). Chaque provider construit sa `URLRequest`, on exécute + parse ici.
///
/// La closure `extract` transforme le JSON top-level en texte + tokens I/O.
/// Retourne `nil` = JSON malformé → `AIResponse` erreur.
enum AIProviderHTTP {

    /// Loop 17 — retry backoff sur rate limit 429.
    /// Rate limits providers cloud sont souvent transient (< 5s). Sans retry,
    /// on bascule direct sur le suivant → user perd la qualité du provider
    /// choisi pour un souci temporaire. Un simple retry après 2s résout ~80%
    /// des cas OpenAI/Anthropic free tier.
    ///
    /// Ordre : appel initial → si 429, sleep 2s puis 1 retry → si encore 429,
    /// laisse le router faire son fallback.
    static func perform(
        _ req: URLRequest,
        providerID: String,
        correlationID: UUID,
        start: Date,
        extract: @Sendable @escaping ([String: Any]) -> (text: String, inputTokens: Int?, outputTokens: Int?)?
    ) async -> AIResponse {
        // Premier essai
        let firstResponse = await performOnce(req, providerID: providerID, correlationID: correlationID, start: start, extract: extract)
        if case .rateLimited = firstResponse.error {
            // Backoff 2s puis 1 seul retry — au-delà, on considère que le
            // provider est vraiment saturé et le router prend le relais.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            AppLog.coach.info("AIProviderHTTP: \(providerID, privacy: .public) rate limited, retry after 2s")
            return await performOnce(req, providerID: providerID, correlationID: correlationID, start: start, extract: extract)
        }
        return firstResponse
    }

    /// Un seul appel HTTP sans retry — extrait de `perform` pour permettre le
    /// pattern retry sans dupliquer la logique de parsing/mapping erreur.
    private static func performOnce(
        _ req: URLRequest,
        providerID: String,
        correlationID: UUID,
        start: Date,
        extract: @Sendable @escaping ([String: Any]) -> (text: String, inputTokens: Int?, outputTokens: Int?)?
    ) async -> AIResponse {
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .networkErr(providerID: providerID, correlationID: correlationID, start: start, msg: "no HTTPURLResponse")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return .fail(providerID: providerID, correlationID: correlationID, start: start,
                             err: .unavailable(.invalidCredentials))
            }
            if http.statusCode == 429 {
                return .fail(providerID: providerID, correlationID: correlationID, start: start, err: .rateLimited)
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                return .fail(providerID: providerID, correlationID: correlationID, start: start,
                             err: .providerError("HTTP \(http.statusCode) \(msg)"))
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsed = extract(json) else {
                return .fail(providerID: providerID, correlationID: correlationID, start: start,
                             err: .malformedResponse("cannot parse response"))
            }
            return AIResponse(
                text: parsed.text,
                providerID: providerID,
                correlationID: correlationID,
                duration: Date().timeIntervalSince(start),
                inputTokens: parsed.inputTokens,
                outputTokens: parsed.outputTokens
            )
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .networkConnectionLost {
            return .networkErr(providerID: providerID, correlationID: correlationID, start: start, msg: "offline")
        } catch let e as URLError where e.code == .timedOut {
            return .fail(providerID: providerID, correlationID: correlationID, start: start, err: .timeout)
        } catch {
            return .networkErr(providerID: providerID, correlationID: correlationID, start: start, msg: error.localizedDescription)
        }
    }
}

// MARK: - Helpers de construction AIResponse d'échec.

private extension AIResponse {
    static func fail(providerID: String, correlationID: UUID, start: Date, err: AIError) -> AIResponse {
        AIResponse(
            providerID: providerID,
            correlationID: correlationID,
            duration: Date().timeIntervalSince(start),
            error: err
        )
    }
    static func networkErr(providerID: String, correlationID: UUID, start: Date, msg: String) -> AIResponse {
        .fail(providerID: providerID, correlationID: correlationID, start: start, err: .networkError(msg))
    }
}
