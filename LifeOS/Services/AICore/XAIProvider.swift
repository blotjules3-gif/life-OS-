import Foundation

/// Provider IA basé sur xAI — modèles Grok (Elon Musk / X).
///
/// Grok 2 et Grok 3 sont compétitifs sur le raisonnement et l'humour, avec
/// une intégration native au réseau X pour les infos temps réel.
///
/// API OpenAI-compatible.
///
/// Nécessite : clé API user stockée dans le Keychain via
/// `AIProviderCredentials.shared.setKey(_, for: .xai)`.
///
/// Sécurité : la clé n'est envoyée qu'à `api.x.ai` via HTTPS.
struct XAIProvider: AIProvider {

    let id = "xai.grok"
    let displayName = "xAI (Grok)"
    let model: String

    init(model: String = "grok-2-latest") {
        self.model = model
    }

    var capabilities: AICapabilities {
        [.textGeneration, .longContext]
    }

    @MainActor
    var availability: AIAvailability {
        guard AIProviderCredentials.shared.hasKey(for: .xai) else {
            return .unavailable(reason: .invalidCredentials)
        }
        return .available
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        let apiKey = await MainActor.run { AIProviderCredentials.shared.key(for: .xai) }
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

        var req = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!)
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
