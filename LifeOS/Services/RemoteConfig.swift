import Foundation

// Feature flags pilotés côté serveur — permettent de désactiver le coach
// sans nouveau build si Apple rejette la review, ou en cas d'incident.
//
// Endpoint : GET /api/v1/config → { "chat_enabled": bool, ... }
// Cache 5 min, fallback sur dernière valeur connue, fail-open à true.

@Observable
@MainActor
final class RemoteConfig {
    static let shared = RemoteConfig()

    private(set) var chatEnabled: Bool
    private var lastFetch: Date?
    private let cacheDuration: TimeInterval = 300 // 5 min
    private let defaultsKey = "rc_remoteConfig"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let cached = try? JSONDecoder().decode(CachedConfig.self, from: data) {
            self.chatEnabled = cached.chatEnabled
        } else {
            self.chatEnabled = true
        }
    }

    func refreshIfNeeded() async {
        if let last = lastFetch, Date().timeIntervalSince(last) < cacheDuration {
            return
        }
        await refresh()
    }

    func refresh() async {
        do {
            let fetched = try await AgentAPI.shared.fetchRemoteConfig()
            self.chatEnabled = fetched.chatEnabled
            self.lastFetch = Date()
            if let data = try? JSONEncoder().encode(fetched) {
                UserDefaults.standard.set(data, forKey: defaultsKey)
            }
        } catch {
            // Fail-open : on garde la valeur cachée (ou true par défaut)
        }
    }
}

struct CachedConfig: Codable {
    let chatEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case chatEnabled = "chat_enabled"
    }
}
