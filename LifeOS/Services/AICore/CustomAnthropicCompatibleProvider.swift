import Foundation

/// Provider IA "générique" pour tout endpoint compatible Anthropic Messages API
/// (proxy interne d'entreprise, self-hosted, etc.).
///
/// Format Anthropic natif : messages avec role + content, header `x-api-key`
/// et `anthropic-version` obligatoires.
///
/// Sécurité : la clé n'est envoyée qu'à l'URL configurée par l'user.
struct CustomAnthropicCompatibleProvider: AIProvider {

    let configID: UUID

    var id: String { "custom.anthropic.\(configID.uuidString)" }

    @MainActor
    var displayName: String {
        CustomProviderStore.shared.configs.first { $0.id == configID }?.name ?? "Custom Anthropic"
    }

    var capabilities: AICapabilities {
        [.textGeneration, .longContext]
    }

    @MainActor
    var availability: AIAvailability {
        guard let c = CustomProviderStore.shared.configs.first(where: { $0.id == configID }),
              !c.baseURL.isEmpty, !c.model.isEmpty else {
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

        guard let snapshot, let apiKey = snapshot.apiKey, !apiKey.isEmpty else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .unavailable(.invalidCredentials)
            )
        }

        let config = snapshot.config
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        guard let url = URL(string: "\(base)/messages") else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("invalid baseURL")
            )
        }

        // Anthropic sépare le system prompt des messages user/assistant.
        var systemPrompt = ""
        var conversationMessages: [[String: Any]] = []
        for msg in request.messages {
            if msg.role == .system {
                systemPrompt += (systemPrompt.isEmpty ? "" : "\n\n") + msg.content
            } else {
                let role = (msg.role == .assistant) ? "assistant" : "user"
                conversationMessages.append(["role": role, "content": msg.content])
            }
        }

        var payload: [String: Any] = [
            "model": config.model,
            "messages": conversationMessages,
            "temperature": request.temperature,
            "max_tokens": request.maxOutputTokens ?? 800,
        ]
        if !systemPrompt.isEmpty {
            payload["system"] = systemPrompt
        }

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
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = body
        req.timeoutInterval = request.timeout

        return await AIProviderHTTP.perform(req, providerID: id, correlationID: request.correlationID, start: start) { json in
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            let text = content.compactMap { $0["text"] as? String }.joined()
            let usage = json["usage"] as? [String: Any]
            return (
                text: text,
                inputTokens: usage?["input_tokens"] as? Int,
                outputTokens: usage?["output_tokens"] as? Int
            )
        }
    }
}
