import SwiftUI
import Combine

/// Moteur de compte à rebours réutilisé par : power-nap, HIIT/Tabata, focus, respiration, mewing.
///
/// Compte a rebours base sur l'HORLOGE, pas sur un compteur interne.
///
/// LE DEFAUT CORRIGE ICI
///
/// L'ancienne version gardait `remaining` et le decrementait dans un `Timer` en
/// process. Un `Timer` ne tourne pas quand l'app est en arriere plan, et il n'existe
/// plus du tout si le processus est tue. Donc une sieste de 20 minutes lancee puis
/// telephone verrouille affichait encore 19:58 au retour : le temps reel etait ignore.
///
/// Maintenant l'autorite est une DATE DE FIN absolue. `remaining` se DEDUIT de
/// `deadline - maintenant`. Le timer d'une seconde ne sert plus qu'a rafraichir
/// l'affichage : meme s'il ne tourne pas, le compte reste juste.
///
/// L'etat est persiste, donc un arret complet du processus ne perd pas la session.
@Observable
final class CountdownEngine {
    /// Identifiant de session : deux timers (sieste, meditation) ne doivent pas se
    /// marcher dessus dans le stockage.
    private let key: String

    private(set) var total: Int = 1
    private(set) var isRunning = false
    var onFinish: (() -> Void)?

    /// Fin absolue quand ca tourne. `nil` en pause ou a l'arret.
    private(set) var deadline: Date?
    /// Temps restant fige pendant la pause.
    private var pausedRemaining: Int = 0
    private var finished = false
    // Invalidate every consumer of remaining/progress, including the HIIT screen.
    private var displayTick = 0

    private var cancellable: AnyCancellable?

    init(key: String = "default") {
        self.key = key
        restore()
    }

    /// DERIVE de l'horloge. C'est le coeur du correctif.
    var remaining: Int {
        _ = displayTick
        if let deadline { return max(0, Int(deadline.timeIntervalSinceNow.rounded(.up))) }
        return pausedRemaining
    }

    var progress: Double { total == 0 ? 0 : Double(total - remaining) / Double(total) }

    func start(seconds: Int) {
        total = max(1, seconds)
        pausedRemaining = total
        finished = false
        deadline = Date().addingTimeInterval(TimeInterval(total))
        isRunning = true
        persist(); startDisplayTimer()
    }

    func resume() {
        guard !isRunning, pausedRemaining > 0 else { return }
        finished = false
        deadline = Date().addingTimeInterval(TimeInterval(pausedRemaining))
        isRunning = true
        persist(); startDisplayTimer()
    }

    func pause() {
        pausedRemaining = remaining
        deadline = nil
        isRunning = false
        cancellable?.cancel()
        persist()
    }

    func reset() {
        pause()
        pausedRemaining = total
        finished = false
        persist()
    }

    func stop() {
        pause()
        pausedRemaining = 0
        clear()
    }

    /// A appeler au retour au premier plan : rattrape le temps ecoule pendant l'absence
    /// et declenche la fin si l'echeance est passee.
    func refresh() {
        guard isRunning else { return }
        if remaining == 0 { complete() } else { startDisplayTimer() }
    }

    // MARK: - Affichage

    private func startDisplayTimer() {
        cancellable?.cancel()
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.displayTick &+= 1
                // Ne decremente rien : il relit juste l'horloge.
                if self.isRunning, self.remaining == 0 { self.complete() }
            }
    }

    private func complete() {
        guard !finished else { return }
        finished = true
        isRunning = false
        deadline = nil
        pausedRemaining = 0
        cancellable?.cancel()
        clear()
        Haptics.success()
        onFinish?()
    }

    // MARK: - Persistance

    private var storeKey: String { "countdown.\(key)" }

    private func persist() {
        let d: [String: Any] = [
            "total": total,
            "isRunning": isRunning,
            "pausedRemaining": pausedRemaining,
            "deadline": deadline?.timeIntervalSince1970 ?? 0
        ]
        UserDefaults.standard.set(d, forKey: storeKey)
    }

    private func clear() { UserDefaults.standard.removeObject(forKey: storeKey) }

    private func restore() {
        guard let d = UserDefaults.standard.dictionary(forKey: storeKey) else { return }
        total = d["total"] as? Int ?? 1
        pausedRemaining = d["pausedRemaining"] as? Int ?? 0
        let ts = d["deadline"] as? TimeInterval ?? 0
        let running = d["isRunning"] as? Bool ?? false
        if running, ts > 0 {
            let end = Date(timeIntervalSince1970: ts)
            if end > Date() {
                deadline = end; isRunning = true; startDisplayTimer()
            } else {
                // L'echeance est passee pendant que l'app etait fermee.
                isRunning = false; pausedRemaining = 0; deadline = nil; clear()
            }
        }
    }
}

/// Vue circulaire de timer prête à l'emploi.
struct TimerDial: View {
    let engine: CountdownEngine
    var tint: Color = Theme.accent
    var caption: String = ""

    var body: some View {
        // TimelineView, et ce n'est pas decoratif.
        //
        // `remaining` se deduit maintenant de l'horloge, donc PLUS AUCUNE valeur
        // observable ne change chaque seconde : sans redessin periodique les chiffres
        // restaient figes jusqu'a ce qu'autre chose rafraichisse la vue. Le moteur est
        // juste, c'est l'affichage qui ne suivait pas. TimelineView redessine depuis la
        // meme horloge qui fait autorite.
        TimelineView(.periodic(from: .now, by: 1)) { _ in dial }
    }

    private var dial: some View {
        ZStack {
            ProgressRing(progress: engine.progress, lineWidth: 14, tint: tint)
            VStack(spacing: 4) {
                Text(formatHMS(engine.remaining))
                    .font(.system(size: 46, weight: .bold))
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
