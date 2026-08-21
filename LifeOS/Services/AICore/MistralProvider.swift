import Foundation
import UIKit

/// Provider IA basé sur le backend Railway (proxy → Mistral Large).
///
/// Rôle : fallback quand `AppleIntelligenceProvider` n'est pas disponible
/// (iPhone < 15 Pro, modèle en téléchargement, iOS < 26, Apple Intelligence
/// désactivé). Mistral est plus puissant (~22B params, français natif) mais :
///   - Requiert le réseau
///   - Latence 2-5s vs <1s Apple Intelligence
///   - Les données du contexte user transitent par Railway → Mistral API
///   - Coût par token (facturation Mistral)
///
/// Sécurité : le backend gère l'auth via `X-API-Key`, la clé Mistral n'est
/// JAMAIS envoyée depuis l'app. L'app ne connaît que l'API_KEY du proxy.
///
/// Configuration : `API_BASE_URL` + `API_KEY` dans `LifeOS/Config.xcconfig`
/// (exposés dans Info.plist).
struct MistralProvider: AIProvider {

    let id = "mistral.via-railway-proxy"
    let displayName = "Mistral (proxy Railway)"

    var capabilities: AICapabilities {
        // Mistral Large : très bon en français, contexte 128k tokens, pas de
        // structured output ni tool calling ici (le proxy accepte juste text).
        [.textGeneration, .longContext]
    }

    @MainActor
    var availability: AIAvailability {
        // On considère disponible si l'URL est configurée. Le vrai check réseau
        // se fait à l'appel — si le device est offline, `complete` retournera
        // `.networkError` et le router n'a plus de fallback (LocalCoach prend
        // le relais côté OnDeviceLLM).
        guard Self.baseURL != nil, Self.apiKey != nil else {
            return .unavailable(reason: .invalidCredentials)
        }
        return .available
    }

    // MARK: - Config lookup

    private static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              !raw.isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    private static var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String,
              !raw.isEmpty else { return nil }
        return raw
    }

    /// Device ID stable (utilisé côté backend pour rate-limit + rattacher
    /// une conversation à un user anonyme). Persisté dans `identifierForVendor`
    /// qui est stable pour un vendor tant que l'app n'est pas désinstallée.
    private static var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    // MARK: - Complete

    func complete(_ request: AIRequest) async -> AIResponse {
        let start = Date()

        guard let baseURL = Self.baseURL, let apiKey = Self.apiKey else {
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .unavailable(.invalidCredentials)
            )
        }

        // Aplatit les messages au format proxy : le dernier .user devient
        // `message`, tout le reste (system + assistant précédents) est concaténé
        // dans `user_context`. Le proxy attend un shape ChatRequest simple,
        // pas un array messages OpenAI-like.
        guard let lastUser = request.messages.last(where: { $0.role == .user }) else {
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("no user message")
            )
        }
        let contextParts = request.messages.filter { $0.role != .user }.map(\.content)
        let userContext = contextParts.joined(separator: "\n\n")
        let trimmedContext = String(userContext.prefix(19_500))  // marge sous le max 20000 backend

        let body: [String: Any] = [
            "device_id": Self.deviceID,
            "message": lastUser.content,
            "user_context": trimmedContext,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .malformedResponse("cannot encode body")
            )
        }

        let endpoint = baseURL.appendingPathComponent("api/v1/chat")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = bodyData
        req.timeoutInterval = request.timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return AIResponse(
                    providerID: id, correlationID: request.correlationID,
                    duration: Date().timeIntervalSince(start),
                    error: .networkError("no HTTPURLResponse")
                )
            }
            if http.statusCode == 429 {
                return AIResponse(
                    providerID: id, correlationID: request.correlationID,
                    duration: Date().timeIntervalSince(start),
                    error: .rateLimited
                )
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                return AIResponse(
                    providerID: id, correlationID: request.correlationID,
                    duration: Date().timeIntervalSince(start),
                    error: .providerError("HTTP \(http.statusCode) \(msg)")
                )
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reply = json["reply"] as? String else {
                return AIResponse(
                    providerID: id, correlationID: request.correlationID,
                    duration: Date().timeIntervalSince(start),
                    error: .malformedResponse("no 'reply' field")
                )
            }
            return AIResponse(
                text: reply,
                providerID: id,
                correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start)
            )
        } catch let urlErr as URLError where urlErr.code == .notConnectedToInternet
                                          || urlErr.code == .networkConnectionLost {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .networkError("offline")
            )
        } catch let urlErr as URLError where urlErr.code == .timedOut {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .timeout
            )
        } catch {
            return AIResponse(
                providerID: id, correlationID: request.correlationID,
                duration: Date().timeIntervalSince(start),
                error: .networkError(error.localizedDescription)
            )
        }
    }
}
