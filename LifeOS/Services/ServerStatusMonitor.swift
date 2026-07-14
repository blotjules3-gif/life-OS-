import Foundation
import SwiftUI

/// Statut « coach » — depuis Option C, il n'y a plus de backend. Le coach
/// tourne on-device via `OnDeviceLLM`, donc l'app se présente toujours
/// « en ligne ». Le type est conservé pour ne pas casser les vues qui
/// affichaient un bandeau d'état — elles reçoivent maintenant `.online`.
enum CoachStatus: Equatable {
    case unknown
    case online
    case backendDown
    case llmDown(String?)
}

@MainActor
final class ServerStatusMonitor: ObservableObject {
    static let shared = ServerStatusMonitor()

    @Published private(set) var isOnline: Bool? = true
    @Published private(set) var coach: CoachStatus = .online

    /// Toujours vrai : le coach on-device peut répondre sans réseau.
    var canSendChatMessages: Bool { true }

    var dotColor: Color { .green }

    var statusLabel: String { "Coach on-device" }

    /// No-op — plus de ping serveur à faire.
    func pingNow() {}

    private init() {}
}
