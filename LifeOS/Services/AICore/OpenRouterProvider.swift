import Foundation

/// Provider IA basé sur OpenRouter — hub qui expose 200+ modèles avec 1 seule clé.
///
/// L'utilisateur choisit le modèle qu'il veut (Claude, GPT, Gemini, Llama,
/// DeepSeek, Grok, etc.) via `model`. OpenRouter facture l'user directement,
/// LifeOS n'a aucune visibilité sur les tokens.
///
/// C'est le provider recommandé pour un user grand public qui veut la
/// compatibilité maximale sans gérer plusieurs clés.
///
/// Nécessite : clé API user stockée dans le Keychain via
/// `AIProviderCredentials.shared.setKey(_, for: .openrouter)`.
///
/// Sécurité : la clé n'est envoyée qu'à `openrouter.ai` via HTTPS.
struct OpenRouterProvider: AIProvider {

    let id = "openrouter.universal"
    let displayName = "OpenRouter"
    let model: String

    /// Modèle par défaut : Claude Haiku (rapport qualité/prix imbattable en 2026).
    /// L'user peut changer via un futur écran de config avancée.
    init(model: String = "anthropic/claude-3.5-haiku") {
        self.model = model
    }

    var capabilities: AICapabilities {
        [.textGeneration, .longContext]
    }

    @MainActor
    var availability: AIAvailability {
        guard AIProviderCredentials.shared.hasKey(for: .openrouter) else {
            return .unavailable(reason: .invalidCredentials)
        }
        return .available
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        let apiKey = await MainActor.run { AIProviderCredentials.shared.key(for: .openrouter) }
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

        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // OpenRouter demande un HTTP-Referer pour son tracking anonyme des apps.
        req.setValue("https://lifeos.app", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("LifeOS", forHTTPHeaderField: "X-Title")
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
