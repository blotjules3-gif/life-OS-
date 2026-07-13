import Foundation

// Feature flags serveur : kill switch coach sans redéploiement iOS.
// Cache 5 min. Fail-open à true si le serveur ne répond pas.

@Observable
@MainActor
final class RemoteConfig {
    static let shared = RemoteConfig()

    struct Snapshot: Codable {
        let chatEnabled: Bool

        enum CodingKeys: String, CodingKey {
            case chatEnabled = "chat_enabled"
        }
    }

    private(set) var chatEnabled: Bool
    private var lastFetch: Date?
    private let cacheDuration: TimeInterval = 300
    private static let storageKey = "rc_remoteConfig"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let cached = try? JSONDecoder().decode(Snapshot.self, from: data) {
            chatEnabled = cached.chatEnabled
        } else {
            chatEnabled = true
        }
    }

    func refreshIfNeeded() async {
        if let last = lastFetch, Date().timeIntervalSince(last) < cacheDuration {
            return
        }
        await refresh()
    }

    func refresh() async {
        guard let snapshot = try? await AgentAPI.shared.fetchRemoteConfig() else {
            return
        }
        chatEnabled = snapshot.chatEnabled
        lastFetch = Date()
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
