import Foundation

/// Provider IA "générique" pour tout endpoint compatible OpenAI (Ollama, LM Studio,
/// Perplexity, Together AI, Fireworks, proxy interne d'entreprise, etc.).
///
/// L'utilisateur configure via `CustomProviderStore` :
///   - URL base (ex: "http://localhost:11434/v1")
///   - Nom du modèle (ex: "llama3.2:latest")
///   - Clé API (optionnelle — les endpoints locaux type Ollama n'exigent rien)
///
/// Ce provider suit strictement le format OpenAI `/chat/completions`. La clé,
/// si présente, est envoyée en `Authorization: Bearer <key>`.
///
/// Sécurité : la clé n'est envoyée qu'à l'URL configurée par l'user. L'user
/// est responsable de son endpoint (HTTP possible pour du local, HTTPS obligé
/// sur internet public — pas de validation forcée pour laisser Ollama tourner
/// sur son LAN sans certificat).
struct CustomOpenAICompatibleProvider: AIProvider {

    let configID: UUID

    var id: String { "custom.openai.\(configID.uuidString)" }

    @MainActor
    private var config: CustomProviderStore.Config? {
        CustomProviderStore.shared.configs.first { $0.id == configID }
    }

    @MainActor
    var displayName: String { config?.name ?? "Custom OpenAI" }

    var capabilities: AICapabilities {
        [.textGeneration, .longContext]
    }

    @MainActor
    var availability: AIAvailability {
        guard let config, !config.baseURL.isEmpty, !config.model.isEmpty else {
            return .unavailable(reason: .invalidCredentials)
        }
        return .available
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        let snapshot: (config: CustomProviderStore.Config, apiKey: String?)? = await MainActor.run {
            guard let c = CustomProviderStore.shared.configs.first(where: { $0.id == configID }) else {
                return nil
            }
            return (c, CustomProviderStore.shared.key(for: c))
        }

        guard let snapshot else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .unavailable(.invalidCredentials)
            )
        }

        let config = snapshot.config
        let apiKey = snapshot.apiKey

        // Assemble l'URL /chat/completions en tolérant slash final.
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: "\(base)/chat/completions") else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("invalid baseURL")
            )
        }

        let payload: [String: Any] = [
            "model": config.model,
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

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
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
