import Foundation
import SwiftUI

@MainActor
final class ServerStatusMonitor: ObservableObject {
    static let shared = ServerStatusMonitor()

    @Published private(set) var isOnline: Bool? = nil

    private init() {
        Task { await runLoop() }
    }

    var dotColor: Color {
        switch isOnline {
        case .some(true):  return .green
        case .some(false): return .orange
        case .none:        return .clear
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
        let url = Configuration.baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            isOnline = (200..<300).contains(code)
        } catch {
            isOnline = false
        }
    }
}
