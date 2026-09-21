import SwiftUI
import WatchKit

struct TabataPage: View {
    @State private var startedAt: Date?
    @State private var now = Date()
    @State private var lastPhase: TabataClock.Phase?
    private let clock = TabataClock()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var state: TabataClock.State? {
        startedAt.map { clock.state(elapsed: Int(now.timeIntervalSince($0))) }
    }

    var body: some View {
        VStack(spacing: 6) {
            if let s = state, s.phase != .done {
                Text(s.phase == .work ? "EFFORT" : "REPOS")
                    .font(.headline)
                    .foregroundStyle(s.phase == .work ? .orange : .green)
                Text("\(s.remaining)").font(.system(size: 52, weight: .bold, design: .rounded))
                Text("Série \(s.round)/\(clock.rounds)").font(.footnote).foregroundStyle(.secondary)
                Button("Arrêter", role: .destructive) { startedAt = nil; lastPhase = nil }
            } else {
                Text("Tabata").font(.headline)
                Text("\(clock.work) s / \(clock.rest) s × \(clock.rounds)")
                    .font(.footnote).foregroundStyle(.secondary)
                if state?.phase == .done { Text("Terminé 💪").font(.title3) }
                Button("Démarrer") {
                    startedAt = .now; now = .now; lastPhase = .work
                    WKInterfaceDevice.current().play(.start)
                }
                .tint(.orange)
            }
        }
        .onReceive(tick) { t in
            guard startedAt != nil else { return }
            now = t
            // Une vibration a chaque changement de phase: au poignet on ne
            // regarde pas l'ecran pendant l'effort.
            if let p = state?.phase, p != lastPhase {
                WKInterfaceDevice.current().play(p == .done ? .success : (p == .work ? .start : .stop))
                lastPhase = p
            }
        }
    }
}
