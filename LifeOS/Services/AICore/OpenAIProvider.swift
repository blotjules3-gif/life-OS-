import Foundation

/// Provider IA basé sur OpenAI (GPT-4o / GPT-4o-mini).
///
/// Nécessite : clé API user stockée dans le Keychain via
/// `AIProviderCredentials.shared.setKey(_, for: .openai)`.
///
/// Le user paie directement OpenAI — LifeOS n'a aucune visibilité sur
/// les tokens consommés. Aucun coût côté LifeOS.
///
/// Sécurité : la clé n'est envoyée qu'à `api.openai.com` via HTTPS.
struct OpenAIProvider: AIProvider {

    let id = "openai.gpt"
    let displayName = "OpenAI (GPT-4o mini)"
    let model: String

    init(model: String = "gpt-4o-mini") {
        self.model = model
    }

    var capabilities: AICapabilities {
        // Pas .toolCalling ni .structuredOutput : le provider ne parse pas
        // les tool_calls de la réponse (feature à ajouter dans une prochaine
        // itération). Déclarer honnêtement pour que le router ne route pas
        // vers nous des requêtes qu'on ne saurait pas gérer.
        [.textGeneration, .longContext]
    }

    @MainActor
    var availability: AIAvailability {
        guard AIProviderCredentials.shared.hasKey(for: .openai) else {
            return .unavailable(reason: .invalidCredentials)
        }
        return .available
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        let apiKey = await MainActor.run { AIProviderCredentials.shared.key(for: .openai) }
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

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
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
