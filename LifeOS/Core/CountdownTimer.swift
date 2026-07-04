import SwiftUI
import Combine

/// Moteur de compte à rebours réutilisé par : power-nap, HIIT/Tabata, focus, respiration, mewing.
@Observable
final class CountdownEngine {
    private(set) var remaining: Int = 0
    private(set) var total: Int = 1
    private(set) var isRunning = false
    var onFinish: (() -> Void)?

    private var cancellable: AnyCancellable?

    var progress: Double { total == 0 ? 0 : Double(total - remaining) / Double(total) }

    func start(seconds: Int) {
        total = max(1, seconds)
        remaining = seconds
        resume()
    }

    func resume() {
        guard !isRunning, remaining > 0 else { return }
        isRunning = true
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        isRunning = false
        cancellable?.cancel()
    }

    func reset() {
        pause()
        remaining = total
    }

    func stop() {
        pause()
        remaining = 0
    }

    private func tick() {
        guard remaining > 0 else { return }
        remaining -= 1
        if remaining == 0 {
            pause()
            Haptics.success()
            onFinish?()
        }
    }
}

/// Vue circulaire de timer prête à l'emploi.
struct TimerDial: View {
    let engine: CountdownEngine
    var tint: Color = Theme.accent
    var caption: String = ""

    var body: some View {
        ZStack {
            ProgressRing(progress: engine.progress, lineWidth: 14, tint: tint)
            VStack(spacing: 4) {
                Text(formatHMS(engine.remaining))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: 240, height: 240)
    }
}

enum Haptics {
    /// Réglage global (Profil › Sons & vibrations). Absent = activé par défaut.
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }
    static func success() {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func tap() {
        #if canImport(UIKit)
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func soft() {
        #if canImport(UIKit)
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
    static func medium() {
        #if canImport(UIKit)
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    static func warning() {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}
