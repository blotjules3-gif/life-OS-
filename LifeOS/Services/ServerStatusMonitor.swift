import Foundation
import SwiftUI

/// Statut réel du chat : le backend peut être debout mais le LLM KO.
enum CoachStatus: Equatable {
    case unknown            // pas encore pingé
    case online             // backend + LLM valides
    case backendDown        // /health injoignable
    case llmDown(String?)   // backend OK mais /health/llm renvoie ok=false
}

@MainActor
final class ServerStatusMonitor: ObservableObject {
    static let shared = ServerStatusMonitor()

    @Published private(set) var isOnline: Bool? = nil
    @Published private(set) var coach: CoachStatus = .unknown

    /// Backwards-compat pour dotColor / bannière existante.
    var canSendChatMessages: Bool { coach == .online }

    private init() {
        Task { await ping() }
        Task { await runLoop() }
    }

    var dotColor: Color {
        switch coach {
        case .online:                 return .green
        case .backendDown, .llmDown:  return .orange
        case .unknown:                return .clear
        }
    }

    var statusLabel: String {
        switch coach {
        case .online:            return "Coach en ligne"
        case .backendDown:       return "Coach hors ligne — serveur injoignable"
        case .llmDown:           return "Coach indisponible — service momentanément en panne"
        case .unknown:           return "…"
        }
    }

    func pingNow() {
        Task { await ping() }
    }

    private func runLoop() async {
        while true {
            await ping()
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
    }

    private func ping() async {
        // 1) Backend joignable ?
        let healthURL = Configuration.baseURL.appendingPathComponent("health")
        var healthReq = URLRequest(url: healthURL)
        healthReq.httpMethod = "HEAD"
        healthReq.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: healthReq)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200..<300).contains(code)
            isOnline = ok
            if !ok {
                coach = .backendDown
                return
            }
        } catch {
            isOnline = false
            coach = .backendDown
            return
        }

        // 2) Clé LLM valide ?
        let llmURL = Configuration.baseURL.appendingPathComponent("health/llm")
        var llmReq = URLRequest(url: llmURL)
        llmReq.httpMethod = "GET"
        llmReq.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: llmReq)
            struct LLMStatus: Decodable { let ok: Bool; let error: String? }
            let status = try JSONDecoder().decode(LLMStatus.self, from: data)
            coach = status.ok ? .online : .llmDown(status.error)
        } catch {
            // Backend up mais /health/llm rejeté → considère le coach down.
            coach = .llmDown(nil)
        }
    }
}
