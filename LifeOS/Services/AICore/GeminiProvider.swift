import Foundation

/// Provider IA basé sur Google Gemini (2.0 Flash / Pro).
///
/// API format Google : la clé passe en query string `?key=...`, les messages
/// sont dans `contents` (pas `messages`), le rôle "assistant" s'appelle
/// "model", pas de rôle system natif (on l'injecte en premier user message).
struct GeminiProvider: AIProvider {

    let id = "google.gemini"
    let displayName = "Google Gemini (Flash)"
    let model: String

    init(model: String = "gemini-2.0-flash") {
        self.model = model
    }

    var capabilities: AICapabilities {
        [.textGeneration, .structuredOutput, .longContext]
    }

    @MainActor
    var availability: AIAvailability {
        guard AIProviderCredentials.shared.hasKey(for: .gemini) else {
            return .unavailable(reason: .invalidCredentials)
        }
        return .available
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        let apiKey = await MainActor.run { AIProviderCredentials.shared.key(for: .gemini) }
        guard let apiKey else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .unavailable(.invalidCredentials)
            )
        }

        // Gemini n'a pas de rôle "system" natif — on préfixe le contexte au
        // premier message user. Le rôle "assistant" s'appelle "model" chez Google.
        let systemContent = request.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        var contents: [[String: Any]] = []
        var systemInjected = false
        for msg in request.messages where msg.role != .system {
            let role = msg.role == .assistant ? "model" : "user"
            var text = msg.content
            if role == "user", !systemInjected, !systemContent.isEmpty {
                text = systemContent + "\n\n" + text
                systemInjected = true
            }
            contents.append([
                "role": role,
                "parts": [["text": text]],
            ])
        }

        let payload: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": request.temperature,
                "maxOutputTokens": request.maxOutputTokens ?? 800,
            ],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("cannot encode body")
            )
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("invalid URL")
            )
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = request.timeout

        return await AIProviderHTTP.perform(req, providerID: id, correlationID: request.correlationID, start: start) { json in
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let usage = json["usageMetadata"] as? [String: Any]
            return (
                text: text,
                inputTokens: usage?["promptTokenCount"] as? Int,
                outputTokens: usage?["candidatesTokenCount"] as? Int
            )
        }
    }
}
