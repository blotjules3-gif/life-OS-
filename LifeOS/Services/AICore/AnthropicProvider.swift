import Foundation

/// Provider IA basé sur Anthropic (Claude Haiku / Sonnet).
///
/// API format différent d'OpenAI : le message system va dans un champ dédié
/// `system` (pas dans `messages`), et les headers requièrent `x-api-key` +
/// `anthropic-version`.
struct AnthropicProvider: AIProvider {

    let id = "anthropic.claude"
    let displayName = "Anthropic (Claude Haiku)"
    let model: String

    init(model: String = "claude-haiku-4-5-20251001") {
        self.model = model
    }

    var capabilities: AICapabilities {
        [.textGeneration, .structuredOutput, .toolCalling, .longContext]
    }

    @MainActor
    var availability: AIAvailability {
        guard AIProviderCredentials.shared.hasKey(for: .anthropic) else {
            return .unavailable(reason: .invalidCredentials)
        }
        return .available
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        let apiKey = await MainActor.run { AIProviderCredentials.shared.key(for: .anthropic) }
        guard let apiKey else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .unavailable(.invalidCredentials)
            )
        }

        // Anthropic sépare le system prompt des messages user/assistant.
        let systemMessages = request.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let convo = request.messages.filter { $0.role != .system }.map { msg -> [String: Any] in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        var payload: [String: Any] = [
            "model": model,
            "messages": convo,
            "max_tokens": request.maxOutputTokens ?? 800,
            "temperature": request.temperature,
        ]
        if !systemMessages.isEmpty {
            payload["system"] = systemMessages
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("cannot encode body")
            )
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = body
        req.timeoutInterval = request.timeout

        return await AIProviderHTTP.perform(req, providerID: id, correlationID: request.correlationID, start: start) { json in
            // Anthropic renvoie {"content": [{"type":"text","text":"..."}], "usage":{"input_tokens":N,"output_tokens":M}}
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let usage = json["usage"] as? [String: Any]
            return (
                text: text,
                inputTokens: usage?["input_tokens"] as? Int,
                outputTokens: usage?["output_tokens"] as? Int
            )
        }
    }
}
