import Foundation

/// Provider IA basé sur Groq — hébergement de modèles open-source (Llama, Mixtral)
/// avec une inférence ultra-rapide (500+ tokens/seconde).
///
/// Free tier généreux + payant pas cher. Idéal pour un coach qui répond vite.
///
/// API OpenAI-compatible.
///
/// Nécessite : clé API user stockée dans le Keychain via
/// `AIProviderCredentials.shared.setKey(_, for: .groq)`.
///
/// Sécurité : la clé n'est envoyée qu'à `api.groq.com` via HTTPS.
struct GroqProvider: AIProvider {

    let id = "groq.llama"
    let displayName = "Groq"
    let model: String

    /// Modèle par défaut : Llama 3.3 70B (bon compromis qualité/vitesse fin 2026).
    init(model: String = "llama-3.3-70b-versatile") {
        self.model = model
    }

    var capabilities: AICapabilities {
        [.textGeneration, .lowLatency]
    }

    @MainActor
    var availability: AIAvailability {
        guard AIProviderCredentials.shared.hasKey(for: .groq) else {
            return .unavailable(reason: .invalidCredentials)
        }
        return .available
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        let apiKey = await MainActor.run { AIProviderCredentials.shared.key(for: .groq) }
        guard let apiKey else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .unavailable(.invalidCredentials)
            )
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": request.messages.map { msg -> [String: Any] in
                ["role": msg.role.rawValue, "content": msg.content]
            },
            "temperature": request.temperature,
            "max_tokens": request.maxOutputTokens ?? 800,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("cannot encode body")
            )
        }

        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        req.timeoutInterval = request.timeout

        return await AIProviderHTTP.perform(req, providerID: id, correlationID: request.correlationID, start: start) { json in
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            let usage = json["usage"] as? [String: Any]
            return (
                text: content,
                inputTokens: usage?["prompt_tokens"] as? Int,
                outputTokens: usage?["completion_tokens"] as? Int
            )
        }
    }
}
