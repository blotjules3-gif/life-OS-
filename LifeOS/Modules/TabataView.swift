import SwiftUI
import UIKit
import SwiftData
import Combine
import AVFoundation

// MARK: - Sons du minuteur (bips synthétisés, routés vers la sortie connectée)
// Joue via AVAudioSession .playback : passe sur les enceintes, les écouteurs filaires
// OU le Bluetooth connecté, même en mode silencieux, en se mélangeant à la musique.
final class TabataSound {
    static let shared = TabataSound()
    private var players: [String: AVAudioPlayer] = [:]
    private var sessionActive = false

    /// À appeler au démarrage : prépare la session pour un premier bip sans latence.
    func prime() { activateSession() }

    private func activateSession() {
        guard !sessionActive else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try? s.setActive(true)
        sessionActive = true
    }

    /// Libère la session (rend le volume à la musique). Appelé à la fin / sortie.
    func end() {
        guard sessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionActive = false
    }

    // Décompte 3-2-1 : bip court et léger.
    func countdown() { play("cd", [(1046, 0.08)], vol: 0.6) }
    // Début d'effort : double bip aigu et net.
    func work()      { play("work", [(1400, 0.15), (0, 0.05), (1400, 0.15)], vol: 1.0) }
    // Début de repos/récup : bip grave plus long.
    func rest()      { play("rest", [(620, 0.30)], vol: 0.95) }
    // Fin de séance : arpège montant.
    func finish()    { play("fin", [(880, 0.16), (0, 0.05), (1108, 0.16), (0, 0.05), (1318, 0.36)], vol: 1.0) }

    /// Réglage global (Profil › Sons & vibrations). Absent = activé par défaut.
    var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "timerSoundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "timerSoundEnabled") }
    }

    private func play(_ key: String, _ segments: [(Double, Double)], vol: Double) {
        guard soundEnabled else { return }
        activateSession()
        let player: AVAudioPlayer
        if let existing = players[key] {
            player = existing
        } else {
            let data = Self.toneWAV(segments: segments.map { (freq: $0.0, dur: $0.1) }, volume: vol)
            guard let p = try? AVAudioPlayer(data: data) else { return }
            p.prepareToPlay()
            players[key] = p
            player = p
        }
        player.currentTime = 0
        player.play()
    }

    // MARK: Synthèse d'un WAV PCM 16 bits mono en mémoire (aucun fichier bundle).
    private static func toneWAV(segments: [(freq: Double, dur: Double)],
                                sampleRate: Double = 44_100, volume: Double) -> Data {
        var samples: [Int16] = []
        let fade = 0.008 * sampleRate   // fondu 8 ms pour éviter les clics
        for seg in segments {
            let n = Int(seg.dur * sampleRate)
            guard n > 0 else { continue }
            if seg.freq <= 0 {
                samples.append(contentsOf: repeatElement(0, count: n))
                continue
            }
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let env = min(1.0, min(Double(i) / fade, Double(n - i) / fade))
                let v = sin(2 * .pi * seg.freq * t) * volume * env
                samples.append(Int16(max(-1, min(1, v)) * 32_767))
            }
        }
        return wavData(samples: samples, sampleRate: Int(sampleRate))
    }

    private static func wavData(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var d = Data(capacity: 44 + dataSize)
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        for s in samples { var x = UInt16(bitPattern: s).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        return d
    }
}

// MARK: - Configuration

struct TabataConfig: Codable, Equatable {
    var prepare: Int
    var work: Int
    var rest: Int
    var rounds: Int            // rounds (work+rest) par cycle
    var cycles: Int
    var restCycle: Int         // récup entre cycles
    var cooldown: Int
}

// MARK: - Étape de la séquence

/// Une étape de la séance: préparation, effort, repos, récup de série, calme.
/// `index` est sa position dans la séquence complète, calculée depuis la config.
struct TabataStep: Identifiable, Equatable {
    let index: Int
    let phase: TabataEngine.Phase
    let round: Int
    let cycle: Int
    let duration: Int
    var id: Int { index }
}

/// Position d'une étape par rapport à l'étape courante.
enum TabataStepStatus: Equatable {
    case past, current, future
}

// MARK: - Moteur

@Observable
final class TabataEngine {
    enum Phase: String, Codable, Equatable {
        case idle, prepare, work, rest, restCycle, cooldown, done
        var title: String {
            switch self {
            case .idle:      return "PRÊT"
            case .prepare:   return "PRÉPARATION"
            case .work:      return "EFFORT"
            case .rest:      return "REPOS"
            case .restCycle: return "RÉCUP SÉRIE"
            case .cooldown:  return "RÉCUPÉRATION"
            case .done:      return "TERMINÉ"
            }
        }
        var shortTitle: String {
            switch self {
            case .idle, .prepare: return "PRÊT"
            case .work:           return "EFFORT"
            case .rest:           return "REPOS"
            case .restCycle:      return "RÉCUP"
            case .cooldown:       return "CALME"
            case .done:           return "BRAVO"
            }
        }
        var icon: String {
            switch self {
            case .idle, .prepare: return "bolt.fill"
            case .work:           return "flame.fill"
            case .rest:           return "lungs.fill"
            case .restCycle:      return "arrow.triangle.2.circlepath"
            case .cooldown:       return "heart.fill"
            case .done:           return "trophy.fill"
            }
        }
        /// Palette sportive néon haut de gamme (Nike / Apple Fitness+)
        var color: Color {
            switch self {
            case .idle, .prepare: return Color(hex: 0xFFB800)   // or solaire
            case .work:           return Color(hex: 0x00F076)   // volt / vert néon électrique
            case .rest:           return Color(hex: 0xFF5252)   // corail éclatant
            case .restCycle:      return Color(hex: 0x00D2FF)   // cyan givré
            case .cooldown:       return Color(hex: 0x7E72F2)   // indigo doux
            case .done:           return Color(hex: 0x00F076)
            }
        }
        var gradientColors: [Color] {
            switch self {
            case .idle, .prepare: return [Color(hex: 0xFFCA28), Color(hex: 0xFF9800)]
            case .work:           return [Color(hex: 0x00F076), Color(hex: 0x00B853)]
            case .rest:           return [Color(hex: 0xFF6B4A), Color(hex: 0xFF3B30)]
            case .restCycle:      return [Color(hex: 0x00D2FF), Color(hex: 0x0072FF)]
            case .cooldown:       return [Color(hex: 0x9B84FF), Color(hex: 0x5E5CE6)]
            case .done:           return [Color(hex: 0x00F076), Color(hex: 0xFFD700)]
            }
        }
        var onColor: Color {
            switch self {
            case .rest, .cooldown: return .white
            default: return .white
            }
        }
    }

    var cfg: TabataConfig {
        didSet { if cfg != oldValue { rebuildSteps() } }
    }
    var phase: Phase = .idle
    var remaining: Int = 0
    var intervalTotal: Int = 0     // durée totale de l'intervalle courant (pour l'anneau)
    var round: Int = 1
    var cycle: Int = 1
    var running = false

    /// Identifiant de la tentative en cours. Change à chaque `begin()`.
    /// C'est lui qui garantit UNE écriture Santé par séance, jamais deux.
    private(set) var sessionID = UUID()

    /// Séance choisie (preset ou programme), portée par le moteur pour survivre
    /// à la fermeture de l'écran et au relancement.
    private(set) var sessionKey: String?
    private(set) var sessionName: String?
    private(set) var sessionIcon: String?
    private(set) var accentColorHex: UInt?
    private(set) var exercises: [String] = []

    /// Séquence complète (préparation, efforts, repos, récups, calme).
    private(set) var steps: [TabataStep] = []
    /// Étapes dont le temps a été ENTIÈREMENT fait via l'horloge. Un saut n'en
    /// ajoute jamais une: sauter n'est pas faire.
    private(set) var completedSteps: Set<Int> = []
    /// Secondes réellement écoulées en séance, tous intervalles confondus.
    private(set) var activeSeconds = 0
    /// Secondes réellement écoulées en effort.
    private(set) var workSecondsDone = 0

    /// Absence au-delà de laquelle on met en pause au lieu de rattraper.
    /// Verrouiller l'écran pendant un round: rattrapé. Poser le téléphone
    /// une heure: pause, rien n'est crédité.
    static let maxUnattendedGap: TimeInterval = 5 * 60
    /// Durée de l'absence qui a mis la séance en pause (bandeau à l'écran).
    private(set) var interruptionGap: TimeInterval?

    /// Appelé après chaque changement d'état (persistance).
    var onStateChange: (() -> Void)?
    /// Appelé une fois quand la séance passe à `.done` par le temps ou un saut.
    var onFinished: (() -> Void)?

    /// Horodatages pour un balayage fluide à 60/120 fps sans lag
    private(set) var intervalStart: Date?
    private(set) var intervalEnd: Date?

    private var cancellable: AnyCancellable?
    /// Horodatage du dernier battement, pour rattraper le temps passé en arrière-plan.
    private var lastTick: Date?
    /// Source de l'heure, remplaçable dans les tests.
    var now: () -> Date = { Date() }

    init(cfg: TabataConfig) {
        self.cfg = cfg
        self.remaining = cfg.prepare
        self.intervalTotal = cfg.prepare
        rebuildSteps()
    }

    // MARK: Séance choisie

    func attach(session: TabataSession?) {
        sessionKey = session?.id
        sessionName = session?.name
        sessionIcon = session?.icon
        accentColorHex = session?.accentColorHex
        exercises = session?.exercises ?? []
    }

    /// Exercice du round `r` (boucle sur la liste), nil sans séance.
    func exercise(forRound r: Int) -> String? {
        guard !exercises.isEmpty else { return nil }
        return exercises[(max(1, r) - 1) % exercises.count]
    }

    // MARK: Séquence

    /// Construit la séquence depuis la config: prépa, puis pour chaque série les
    /// rounds effort/repos, une récup entre deux séries, et le calme final.
    static func buildSteps(_ cfg: TabataConfig) -> [TabataStep] {
        var out: [TabataStep] = []
        func add(_ p: Phase, _ r: Int, _ c: Int, _ d: Int) {
            out.append(TabataStep(index: out.count, phase: p, round: r, cycle: c, duration: max(1, d)))
        }
        // Un repos a 0 s est saute d'un coup par le moteur (`enter` avance tout
        // de suite): il n'apparait donc pas dans la sequence.
        if cfg.prepare > 0 { add(.prepare, 1, 1, cfg.prepare) }
        let cycles = max(1, cfg.cycles), rounds = max(1, cfg.rounds)
        for c in 1...cycles {
            for r in 1...rounds {
                add(.work, r, c, cfg.work)
                if r < rounds, cfg.rest > 0 { add(.rest, r, c, cfg.rest) }
            }
            if c < cycles, cfg.restCycle > 0 { add(.restCycle, rounds, c, cfg.restCycle) }
        }
        if cfg.cooldown > 0 { add(.cooldown, rounds, cycles, cfg.cooldown) }
        return out
    }

    private func rebuildSteps() {
        steps = Self.buildSteps(cfg)
    }

    /// Index de l'étape courante. nil au repos; `steps.count` une fois terminé.
    var currentStepIndex: Int? {
        switch phase {
        case .idle: return nil
        case .done: return steps.count
        default:
            return steps.firstIndex { $0.phase == phase && $0.round == round && $0.cycle == cycle }
        }
    }

    func status(of step: TabataStep) -> TabataStepStatus {
        guard let cur = currentStepIndex else { return .future }
        if step.index == cur { return .current }
        return step.index < cur ? .past : .future
    }

    func isCompleted(_ step: TabataStep) -> Bool { completedSteps.contains(step.index) }

    var workStepsTotal: Int { steps.filter { $0.phase == .work }.count }
    var workStepsCompleted: Int { steps.filter { $0.phase == .work && completedSteps.contains($0.index) }.count }

    /// Se place sur une étape choisie. Explicite: c'est un saut, pas du travail
    /// fait. L'état lecture/pause est conservé; en pause, on reste en pause sur
    /// la nouvelle étape.
    func select(stepIndex: Int) {
        guard steps.indices.contains(stepIndex) else { return }
        let step = steps[stepIndex]
        Haptics.tap()
        if phase == .idle || phase == .done {
            if startedAt == nil { startedAt = now() }
            if phase == .idle { sessionID = UUID() }
            TabataSound.shared.prime()
        }
        phase = step.phase
        round = step.round
        cycle = step.cycle
        remaining = step.duration
        intervalTotal = step.duration
        let currentNow = now()
        intervalStart = currentNow
        intervalEnd = running ? currentNow.addingTimeInterval(Double(remaining)) : nil
        if running {
            lastTick = currentNow
            switch step.phase {
            case .work:                        TabataSound.shared.work()
            case .rest, .restCycle, .cooldown: TabataSound.shared.rest()
            default:                           break
            }
        }
        onStateChange?()
    }

    var roundsLeft: Int { max(0, cfg.rounds - round + 1) }
    var cyclesLeft: Int { max(0, cfg.cycles - cycle + 1) }

    /// Fraction statique discrète (utilisée si chrono en pause ou tests)
    var intervalFraction: Double { Double(remaining) / Double(max(1, intervalTotal)) }

    /// Fraction continue 60 fps pour l'anneau (balayage fluide)
    func smoothFraction(at date: Date = Date()) -> Double {
        guard phase != .idle && phase != .done else {
            return phase == .idle ? 1.0 : 0.0
        }
        guard running, let end = intervalEnd, intervalTotal > 0 else {
            return Double(remaining) / Double(max(1, intervalTotal))
        }
        let left = end.timeIntervalSince(date)
        return max(0.0, min(1.0, left / Double(intervalTotal)))
    }

    private var fullCycle: Int { cfg.rounds * cfg.work + max(0, cfg.rounds - 1) * cfg.rest }

    /// Durée totale de toute la séance.
    var totalDuration: Int {
        cfg.prepare + cfg.cycles * fullCycle + max(0, cfg.cycles - 1) * cfg.restCycle + cfg.cooldown
    }

    /// Temps restant sur TOUTE la séance (intervalle courant + tout ce qui suit).
    var totalRemaining: Int {
        switch phase {
        case .idle:    return totalDuration
        case .done:    return 0
        case .prepare: return remaining + cfg.cycles * fullCycle + max(0, cfg.cycles - 1) * cfg.restCycle + cfg.cooldown
        case .work:    return remaining + (cfg.rounds - round) * (cfg.work + cfg.rest)
                              + (cfg.cycles - cycle) * (cfg.restCycle + fullCycle) + cfg.cooldown
        case .rest:    return remaining + (cfg.rounds - round) * cfg.work + max(0, cfg.rounds - round - 1) * cfg.rest
                              + (cfg.cycles - cycle) * (cfg.restCycle + fullCycle) + cfg.cooldown
        case .restCycle: return remaining + (cfg.cycles - cycle) * fullCycle
                              + max(0, cfg.cycles - cycle - 1) * cfg.restCycle + cfg.cooldown
        case .cooldown: return remaining
        }
    }
    var totalElapsed: Int { max(0, totalDuration - totalRemaining) }

    func startOrPause() {
        if phase == .idle || phase == .done { begin() }
        else if running { pause() }
        else { run() }
    }

    /// Début de la séance en cours, pour pouvoir l'enregistrer dans Santé.
    private(set) var startedAt: Date?
    /// Fin réelle de la séance (`.done` atteint). Posée UNE fois, jamais
    /// recalculée: en rattrapage c'est la frontière réelle de la dernière
    /// seconde consommée, pas l'heure du relancement. Voyage dans le snapshot.
    private(set) var finishedAt: Date?
    /// Pendant un rattrapage, l'heure réelle de la seconde en cours de
    /// traitement, pour dater une fin qui tombe au milieu de l'absence.
    private var catchUpBoundary: Date?

    func begin() {
        sessionID = UUID()
        completedSteps = []
        activeSeconds = 0
        workSecondsDone = 0
        interruptionGap = nil
        let first = steps.first
        phase = first?.phase ?? .prepare
        remaining = first?.duration ?? max(1, cfg.prepare)
        intervalTotal = remaining
        round = first?.round ?? 1
        cycle = first?.cycle ?? 1
        let currentNow = now()
        startedAt = currentNow
        finishedAt = nil
        intervalStart = currentNow
        intervalEnd = currentNow.addingTimeInterval(Double(remaining))
        Haptics.tap()
        TabataSound.shared.prime()
        run()
    }

    func reset() {
        pause()
        phase = .idle
        remaining = cfg.prepare
        intervalTotal = cfg.prepare
        round = 1
        cycle = 1
        startedAt = nil
        finishedAt = nil
        intervalStart = nil
        intervalEnd = nil
        completedSteps = []
        activeSeconds = 0
        workSecondsDone = 0
        interruptionGap = nil
        TabataSound.shared.end()
        onStateChange?()
    }

    private func run() {
        running = true
        interruptionGap = nil
        let currentNow = now()
        lastTick = currentNow
        intervalStart = currentNow
        intervalEnd = currentNow.addingTimeInterval(Double(remaining))
        UIApplication.shared.isIdleTimerDisabled = true
        cancellable = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
        onStateChange?()
    }

    private func pause() {
        running = false
        cancellable?.cancel()
        lastTick = nil
        intervalEnd = nil
        UIApplication.shared.isIdleTimerDisabled = false
        onStateChange?()
    }

    /// Avance d'autant de secondes qu'il s'en est RÉELLEMENT écoulé.
    ///
    /// Absence courte (écran verrouillé pendant un round): rattrapée d'un coup.
    /// Absence plus longue que `maxUnattendedGap`: la séance se met en PAUSE là
    /// où elle en était, et `interruptionGap` le dit à l'écran. Personne ne se
    /// voit créditer une heure d'effort pour avoir posé son téléphone.
    func tick() {
        let currentNow = self.now()
        let base = lastTick ?? currentNow
        var steps = 1
        if let last = lastTick {
            let gap = currentNow.timeIntervalSince(last)
            if running, gap > Self.maxUnattendedGap {
                pause()
                interruptionGap = gap
                onStateChange?()
                return
            }
            steps = Int(gap.rounded())
        }
        lastTick = currentNow
        guard steps > 0 else { return }
        let catchUp = steps > 1
        steps = min(steps, 3600)
        for i in 0..<steps {
            guard running, phase != .idle, phase != .done else { break }
            // Heure réelle de la seconde consommée: une fin en rattrapage est
            // datée de sa vraie frontière, jamais de l'heure du retour.
            catchUpBoundary = min(currentNow, base.addingTimeInterval(Double(i + 1)))
            step(silent: catchUp)
        }
        catchUpBoundary = nil
        if running && intervalTotal > 0 {
            intervalEnd = currentNow.addingTimeInterval(Double(remaining))
        }
        onStateChange?()
    }

    private func step(silent: Bool) {
        activeSeconds += 1
        if phase == .work { workSecondsDone += 1 }
        if remaining > 1 {
            remaining -= 1
            if !silent, remaining <= 3, phase != .idle, phase != .done {
                TabataSound.shared.countdown()
                Haptics.tap()
            }
            return
        }
        // Le temps de cette étape est entièrement fait: c'est la SEULE façon
        // d'entrer dans `completedSteps`.
        if let idx = currentStepIndex, steps.indices.contains(idx) {
            completedSteps.insert(idx)
        }
        advance()
    }

    private func advance() {
        Haptics.success()
        switch phase {
        case .idle, .done:
            return
        case .prepare:
            enter(.work, cfg.work)
        case .work:
            if round < cfg.rounds {
                enter(.rest, cfg.rest)
            } else if cycle < cfg.cycles {
                enter(.restCycle, cfg.restCycle)
            } else if cfg.cooldown > 0 {
                enter(.cooldown, cfg.cooldown)
            } else { finish() }
        case .rest:
            round += 1
            enter(.work, cfg.work)
        case .restCycle:
            cycle += 1
            round = 1
            enter(.work, cfg.work)
        case .cooldown:
            finish()
        }
    }

    private func enter(_ p: Phase, _ secs: Int) {
        phase = p
        remaining = max(1, secs)
        intervalTotal = max(1, secs)
        let currentNow = now()
        intervalStart = currentNow
        intervalEnd = currentNow.addingTimeInterval(Double(remaining))

        switch p {
        case .work:                          TabataSound.shared.work()
        case .rest, .restCycle, .cooldown:   TabataSound.shared.rest()
        default:                             break
        }
        if secs <= 0 { advance() }
    }

    private func finish() {
        pause()
        phase = .done
        if finishedAt == nil { finishedAt = catchUpBoundary ?? now() }
        remaining = 0
        intervalStart = nil
        intervalEnd = nil
        TabataSound.shared.finish()
        onFinished?()
        onStateChange?()
    }

    // Navigation manuelle entre les rounds d'effort. Ce sont des sauts: l'étape
    // quittée n'est pas marquée faite.
    func skipForward() {
        guard let cur = currentStepIndex else {
            if let first = steps.first { select(stepIndex: first.index) }
            return
        }
        if let next = steps.first(where: { $0.index > cur && $0.phase == .work }) {
            select(stepIndex: next.index)
        } else if phase != .done {
            Haptics.tap()
            finish()
        }
    }

    func skipBackward() {
        guard let cur = currentStepIndex else { return }
        let before = steps.last(where: { $0.index < cur && $0.phase == .work })
        if let target = before ?? steps.first {
            select(stepIndex: target.index)
        }
    }

    func adjustSeconds(_ delta: Int) {
        Haptics.tap()
        let newRemaining = max(1, remaining + delta)
        remaining = newRemaining
        intervalTotal = max(intervalTotal, newRemaining)
        if running {
            intervalEnd = now().addingTimeInterval(Double(remaining))
        }
        onStateChange?()
    }

    // MARK: Snapshot / reprise

    func snapshot(healthSaved: Bool, savedAt: Date) -> TabataSessionSnapshot {
        TabataSessionSnapshot(sessionID: sessionID,
                              sessionKey: sessionKey,
                              sessionName: sessionName,
                              sessionIcon: sessionIcon,
                              accentColorHex: accentColorHex,
                              exercises: exercises,
                              config: cfg,
                              phase: phase.rawValue,
                              round: round, cycle: cycle,
                              remaining: remaining, intervalTotal: intervalTotal,
                              running: running,
                              startedAt: startedAt,
                              finishedAt: finishedAt,
                              savedAt: savedAt,
                              activeSeconds: activeSeconds,
                              workSecondsDone: workSecondsDone,
                              completedSteps: Array(completedSteps).sorted(),
                              healthSaved: healthSaved)
    }

    /// Reconstruit un moteur depuis un snapshot.
    /// - En pause: repris tel quel, quel que soit le temps passé.
    /// - En cours: le temps depuis `savedAt` est traité par `tick()`, donc
    ///   rattrapé si court, sinon mis en pause (`interruptionGap`).
    /// - `catchUp: false` remet le moteur en marche SANS ce premier `tick()`:
    ///   l'appelant le lance lui-même après avoir posé `onFinished`. Sinon une
    ///   séance qui se termine pendant le rattrapage finit sans que personne ne
    ///   soit prévenu, et Santé n'est jamais écrit.
    static func restore(_ s: TabataSessionSnapshot, now: @escaping () -> Date,
                        catchUp: Bool = true) -> TabataEngine {
        let e = TabataEngine(cfg: s.config)
        e.now = now
        e.sessionID = s.sessionID
        e.sessionKey = s.sessionKey
        e.sessionName = s.sessionName
        e.sessionIcon = s.sessionIcon
        e.accentColorHex = s.accentColorHex
        e.exercises = s.exercises
        e.phase = Phase(rawValue: s.phase) ?? .idle
        e.round = s.round
        e.cycle = s.cycle
        e.remaining = max(e.phase == .done ? 0 : 1, s.remaining)
        e.intervalTotal = max(1, s.intervalTotal)
        e.startedAt = s.startedAt
        e.finishedAt = s.finishedAt
        e.activeSeconds = s.activeSeconds
        e.workSecondsDone = s.workSecondsDone
        e.completedSteps = Set(s.completedSteps)
        if e.phase == .idle || e.phase == .done { return e }
        e.intervalStart = now()
        if s.running {
            e.run()
            e.lastTick = s.savedAt
            if catchUp { e.tick() }
        }
        return e
    }
}

// MARK: - Séance (préréglages intégrés + programme Sport)

struct TabataSession: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let exercises: [String]
    var subtitle: String? = nil
    var tag: String? = nil
    var accentColorHex: UInt = 0x00F076
}

/// Séances prêtes à l'emploi avec thèmes visuels dédiés
enum TabataPresets {
    static let all: [TabataSession] = [
        .init(id: "hiit", name: "Cardio HIIT", icon: "flame.fill",
              exercises: ["Jumping jacks", "Montées de genoux", "Burpees", "Mountain climbers", "Talons-fesses", "Squats sautés"],
              tag: "Cardio Intense", accentColorHex: 0xFF5252),
        .init(id: "full", name: "Full Body Athlète", icon: "figure.strengthtraining.functional",
              exercises: ["Squats", "Pompes", "Fentes", "Gainage", "Mountain climbers", "Burpees"],
              tag: "Complet & Puissant", accentColorHex: 0x00F076),
        .init(id: "core", name: "Abdos & Core 360°", icon: "figure.core.training",
              exercises: ["Crunchs", "Gainage planche", "Russian twists", "Relevés de jambes", "Bicyclette", "Gainage latéral"],
              tag: "Gainage & Silhouette", accentColorHex: 0xFFB800),
        .init(id: "upper", name: "Haut du Corps", icon: "figure.arms.open",
              exercises: ["Pompes", "Dips", "Pompes diamant", "Superman", "Pike push-ups", "Gainage épaules"],
              tag: "Pectoraux / Épaules", accentColorHex: 0x00D2FF),
        .init(id: "lower", name: "Jambes & Fessiers", icon: "figure.walk",
              exercises: ["Squats", "Fentes avant", "Fentes arrière", "Chaise murale", "Mollets explosifs", "Squats sautés"],
              tag: "Force & Explosion", accentColorHex: 0x7E72F2),
    ]
}

// MARK: - Écran immersif Haute Performance

/// Couleurs neutres de Tabata, qui suivent le theme choisi.
///
/// L'ecran forcait `.preferredColorScheme(.dark)` et peignait tout en blanc sur
/// `#07080A`: en theme clair on ouvrait un minuteur noir. Les accents neon restent
/// (ils portent la phase: effort, repos, recup), mais le fond, les textes et les
/// filets suivent le theme. En clair, les accents servant de TEXTE prennent une
/// teinte plus profonde: un vert volt sur blanc tombe a 1,4:1 de contraste.
struct TabataPalette {
    let scheme: ColorScheme
    var dark: Bool { scheme == .dark }
    /// Encre principale: textes, icones, filets (a opacite reduite).
    var ink: Color { dark ? .white : Color(hex: 0x0B0C0E) }
    var background: Color { dark ? Color(hex: 0x07080A) : Color(hex: 0xF3F4F6) }
    var sheet: Color { dark ? Color(hex: 0x111318) : Color(hex: 0xF7F8FA) }
    var panel: Color { dark ? Color(hex: 0x12141A) : .white }
    var card: Color { dark ? Color(hex: 0x13151D) : .white }
    /// Couleur du voile qui assourdit le fond derriere un element.
    var scrim: Color { dark ? .black : .white }
    var shadowOpacity: Double { dark ? 0.6 : 0.12 }

    /// Accent utilise comme texte: teinte profonde en clair pour rester lisible.
    func text(_ accent: Color) -> Color {
        guard !dark else { return accent }
        switch accent {
        case Color(hex: 0x00F076): return Color(hex: 0x008A43)
        case Color(hex: 0x00D2FF): return Color(hex: 0x0078A8)
        case Color(hex: 0xFFB800): return Color(hex: 0xA86F00)
        case Color(hex: 0xFF5252): return Color(hex: 0xC62828)
        case Color(hex: 0x7E72F2): return Color(hex: 0x4F43C9)
        default: return accent
        }
    }
}

struct TabataView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var pal: TabataPalette { TabataPalette(scheme: colorScheme) }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKeys.tabPrepare) private var prepare = 10
    @AppStorage(AppStorageKeys.tabWork) private var work = 30
    @AppStorage(AppStorageKeys.tabRest) private var rest = 15
    @AppStorage(AppStorageKeys.tabRounds) private var rounds = 8
    @AppStorage(AppStorageKeys.tabCycles) private var cycles = 1
    @AppStorage(AppStorageKeys.tabRestCycle) private var restCycle = 60
    @AppStorage(AppStorageKeys.tabCooldown) private var cooldown = 0
    @AppStorage(AppStorageKeys.tabSets) private var sets = 4

    /// Le moteur vit dans le gardien, pas dans la vue: fermer l'écran ne le
    /// remplace pas, et le relancement de l'app le relit depuis le disque.
    private let keeper = TabataSessionKeeper.shared
    private var engine: TabataEngine { keeper.engine }
    @State private var showSettings = false
    @State private var showChooser = false
    @State private var showSequence = false
    @State private var showResetDialog = false
    @State private var soundMuted = false

    // Préréglages perso et historique (SwiftData).
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TabataPreset.createdAt) private var customPresets: [TabataPreset]
    @Query(sort: \TabataSessionLog.date, order: .reverse) private var tabataLogs: [TabataSessionLog]
    @State private var creatingPreset = false
    @State private var editingPreset: TabataPreset?
    @State private var pendingPresetDelete: TabataPreset?
    @State private var historyError: String?
    /// Garde en mémoire : `onAppear` et `onChange` peuvent voir la même fin avant
    /// que la requête SwiftData ne se rafraîchisse.
    @State private var loggedSessionIDs: Set<UUID> = []

    @Query private var gymDays: [GymDay]
    private var programSessions: [TabataSession] {
        gymWeekOrder.compactMap { w -> TabataSession? in
            guard let d = gymDays.first(where: { $0.weekday == w && !$0.isRest && !$0.title.isEmpty }) else { return nil }
            let exos = d.focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !exos.isEmpty else { return nil }
            return TabataSession(id: "gym-\(d.weekday)", name: d.title, icon: "dumbbell.fill",
                                 exercises: exos, subtitle: gymWeekdayName(d.weekday), tag: "Mon Programme", accentColorHex: 0x00F076)
        }
    }
    private var availableSessions: [TabataSession] { programSessions + TabataPresets.all }

    /// Un préréglage perso devient une séance sans exercices : ses intervalles
    /// passent par les réglages libres, son nom suit la séance.
    private func presetSession(_ p: TabataPreset) -> TabataSession {
        TabataSession(id: "preset-\(p.id.uuidString)", name: p.name, icon: "timer", exercises: [],
                      subtitle: nil, tag: "Mon préréglage", accentColorHex: 0x00D2FF)
    }

    /// Séance affichée: celle que porte le moteur. Si elle ne figure plus dans
    /// la liste (programme modifié), on la reconstruit depuis le snapshot pour
    /// ne pas perdre le nom et les exercices en cours.
    private var chosenSession: TabataSession? {
        guard let key = engine.sessionKey else { return nil }
        if let found = (availableSessions + customPresets.map(presetSession)).first(where: { $0.id == key }) { return found }
        return TabataSession(id: key, name: engine.sessionName ?? "Séance", icon: engine.sessionIcon ?? "timer",
                             exercises: engine.exercises, accentColorHex: engine.accentColorHex ?? 0x00F076)
    }
    private var sessionExercises: [String] { engine.exercises }
    private var sessionActive: Bool { engine.phase != .idle && engine.phase != .done }

    private func exercise(forRound r: Int) -> String? { engine.exercise(forRound: r) }
    private var currentExercise: String? { exercise(forRound: engine.round) }
    private var nextExercise: String? {
        if engine.phase == .rest || engine.phase == .work {
            if engine.round < engine.cfg.rounds {
                return exercise(forRound: engine.round + 1)
            } else if engine.cycle < engine.cfg.cycles {
                return exercise(forRound: 1)
            }
        }
        return nil
    }

    private var config: TabataConfig {
        if sessionExercises.isEmpty {
            return TabataConfig(prepare: prepare, work: work, rest: rest, rounds: rounds, cycles: cycles, restCycle: restCycle, cooldown: cooldown)
        }
        return TabataConfig(prepare: prepare, work: work, rest: rest, rounds: sessionExercises.count, cycles: sets, restCycle: restCycle, cooldown: cooldown)
    }

    private func pick(_ session: TabataSession?) {
        // Choisir une autre séance abandonne celle en cours: le choix est
        // explicite (feuille ouverte par l'utilisateur), pas une sortie d'écran.
        engine.reset()
        engine.attach(session: session)
        engine.cfg = config
        engine.remaining = prepare
        keeper.persist()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showChooser = false
        }
    }

    /// Charge les intervalles du préréglage dans les réglages, puis le choisit
    /// comme séance (mêmes règles que `pick`).
    private func pickPreset(_ p: TabataPreset) {
        let c = TabataPresetRules.sanitized(p.config)
        prepare = c.prepare; work = c.work; rest = c.rest; rounds = c.rounds
        cycles = c.cycles; restCycle = c.restCycle; cooldown = c.cooldown
        pick(presetSession(p))
    }

    /// Journalise la séance finie, une fois par identifiant de séance. Appelé à la
    /// fin ET à l'ouverture de l'écran : une séance finie écran fermé est
    /// journalisée au retour.
    private func logFinishedIfNeeded() {
        guard engine.phase == .done else { return }
        let id = engine.sessionID
        guard !loggedSessionIDs.contains(id),
              FitnessHistory.shouldRecord(id, existing: tabataLogs.map(\.sessionID)) else { return }
        guard let log = FitnessHistory.tabataLog(sessionID: id, finishedAt: engine.finishedAt ?? Date(),
                                                 name: engine.sessionName,
                                                 completedRounds: engine.workStepsCompleted,
                                                 totalRounds: engine.workStepsTotal,
                                                 activeSeconds: engine.activeSeconds,
                                                 workSeconds: engine.workSecondsDone) else { return }
        ctx.insert(log)
        do {
            try ctx.save()
            loggedSessionIDs.insert(id)
            historyError = nil
        } catch {
            ctx.delete(log)
            historyError = "Séance non ajoutée à l'historique : \(error.localizedDescription)"
        }
    }

    private func deleteLog(_ log: TabataSessionLog) {
        ctx.delete(log)
        do { try ctx.save(); historyError = nil } catch {
            ctx.rollback()
            historyError = "Suppression impossible : \(error.localizedDescription)"
        }
    }

    private func deletePreset(_ p: TabataPreset) {
        ctx.delete(p)
        do { try ctx.save(); historyError = nil } catch {
            ctx.rollback()
            historyError = "Suppression impossible : \(error.localizedDescription)"
        }
    }

    /// Applique la config des réglages SEULEMENT si aucune séance n'est en
    /// cours. Une séance reprise garde la config avec laquelle elle a démarré.
    private func applyConfigIfIdle() {
        guard engine.phase == .idle else { return }
        engine.cfg = config
        engine.remaining = prepare
    }

    var body: some View {
        ZStack {
            // Fond noir profond OLED
            pal.background.ignoresSafeArea()

            // Lueur d'ambiance dynamique (Aura Bloom)
            ambientAuroraGlow

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                workoutTimelineBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                Spacer(minLength: 8)

                heroTimerHUD
                    .padding(.horizontal, 20)

                Spacer(minLength: 8)

                controlDock
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            if engine.phase == .done {
                completionCelebrationView
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .statusBarHidden()
        // Écran immersif: pas de barre d'onglets. Présenté en plein écran partout
        // aujourd'hui; ce modificateur couvre le cas où il serait poussé dans une pile.
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showChooser) {
            chooserSheetContent
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(pal.sheet)
        }
        .sheet(isPresented: $showSequence) {
            sequenceSheetContent
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(pal.sheet)
        }
        .confirmationDialog("Que veux-tu faire de cette séance ?", isPresented: $showResetDialog, titleVisibility: .visible) {
            Button("Recommencer depuis le début") {
                engine.reset()
                engine.begin()
            }
            Button("Abandonner la séance", role: .destructive) {
                keeper.discard()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Recommencer relance la même séance à zéro. Abandonner l'efface sans rien enregistrer. Pour la garder, ferme simplement l'écran : elle continue.")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: engine.tick()
            case .background, .inactive: keeper.persist()
            @unknown default: break
            }
        }
        .onAppear {
            // Reprise d'abord, config par défaut ensuite: une séance en cours
            // (vivante ou relue du disque) garde sa propre config.
            applyConfigIfIdle()
            soundMuted = !TabataSound.shared.soundEnabled
            logFinishedIfNeeded()
        }
        .onChange(of: engine.phase) { _, phase in
            if phase == .done { logFinishedIfNeeded() }
        }
        .onDisappear {
            // Quitter l'écran n'est ni une pause ni un abandon: la séance continue
            // avec ses bips. On ne coupe la session audio que si rien ne tourne.
            keeper.persist()
            if !engine.running { TabataSound.shared.end() }
        }
        .sheet(isPresented: $showSettings) {
            TabataSettings(prepare: $prepare, work: $work, rest: $rest, rounds: $rounds, cycles: $cycles, restCycle: $restCycle, cooldown: $cooldown, sets: $sets)
                .onDisappear { applyConfigIfIdle() }
        }
    }

    // MARK: - Lueur d'ambiance (Ambient Radial Glow)

    private var ambientAuroraGlow: some View {
        ZStack {
            RadialGradient(
                colors: [
                    engine.phase.color.opacity(engine.running ? 0.30 : 0.15),
                    engine.phase.color.opacity(0.06),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 320
            )
            .blur(radius: 60)
            .animation(.easeInOut(duration: 0.6), value: engine.phase)
            .ignoresSafeArea()

            // Grille sportive très subtile
            Rectangle()
                .fill(LinearGradient(
                    colors: [pal.scrim.opacity(pal.dark ? 0.4 : 0.25), Color.clear, pal.scrim.opacity(pal.dark ? 0.7 : 0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .ignoresSafeArea()
        }
    }

    // MARK: - Barre supérieure de navigation

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(pal.ink)
                    .frame(width: 40, height: 40)
                    .raisedSurface(Circle())
                    .overlay(Circle().stroke(pal.ink.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel(sessionActive ? "Quitter l'écran, la séance continue" : "Fermer")
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showChooser = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: chosenSession?.icon ?? "timer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pal.text(engine.phase.color))

                    Text(chosenSession?.name ?? "Intervalles libres")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(pal.ink)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(pal.ink.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .raisedSurface(Capsule())
                .overlay(Capsule().stroke(pal.ink.opacity(0.12), lineWidth: 1))
            }

            Spacer()

            HStack(spacing: 8) {
                // Bouton Son rapide
                Button {
                    soundMuted.toggle()
                    TabataSound.shared.soundEnabled = !soundMuted
                    Haptics.tap()
                } label: {
                    Image(systemName: soundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(soundMuted ? pal.ink.opacity(0.4) : engine.phase.color)
                        .frame(width: 40, height: 40)
                        .raisedSurface(Circle())
                        .overlay(Circle().stroke(pal.ink.opacity(0.12), lineWidth: 1))
                }

                // Bouton Réglages
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(pal.ink)
                        .frame(width: 40, height: 40)
                        .raisedSurface(Circle())
                        .overlay(Circle().stroke(pal.ink.opacity(0.12), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Barre de progression de la séance totale

    private var workoutTimelineBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(pal.ink.opacity(0.6))
                    Text("TEMPS RESTANT")
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(0.8)
                        .foregroundStyle(pal.ink.opacity(0.6))
                }

                Spacer()

                Text(formatHMS(engine.phase == .idle ? engine.totalDuration : engine.totalRemaining))
                    .font(AppFont.sans(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(pal.ink)
            }

            // Timeline segmentée moderne
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let progress = engine.totalDuration > 0
                    ? max(0.0, min(1.0, Double(engine.totalElapsed) / Double(engine.totalDuration)))
                    : 0.0

                ZStack(alignment: .leading) {
                    // Track arrière
                    Capsule()
                        .fill(pal.ink.opacity(0.10))
                        .frame(height: 5)

                    // Jauge avant
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [engine.phase.color.opacity(0.8), engine.phase.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, totalWidth * progress), height: 5)
                        .shadow(color: engine.phase.color.opacity(0.6), radius: 4, x: 0, y: 0)
                }
            }
            .frame(height: 5)

            // Badge Série / Round + séquence complète (passé / en cours / à venir)
            HStack(spacing: 8) {
                Label {
                    Text("S\(engine.cycle)/\(engine.cfg.cycles) · R\(engine.round)/\(engine.cfg.rounds)")
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "target")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(engine.phase == .work ? pal.text(engine.phase.color) : pal.ink.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(engine.phase == .work ? engine.phase.color.opacity(0.15) : pal.ink.opacity(0.06), in: Capsule())
                .overlay(
                    Capsule().stroke(engine.phase == .work ? engine.phase.color.opacity(0.35) : Color.clear, lineWidth: 1)
                )
                .accessibilityLabel("Série \(engine.cycle) sur \(engine.cfg.cycles), round \(engine.round) sur \(engine.cfg.rounds)")

                stepStrip

                Button {
                    showSequence = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(pal.ink)
                        .frame(width: 30, height: 30)
                        .raisedSurface(Circle())
                }
                .accessibilityLabel("Voir la séquence complète")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .raisedSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(pal.ink.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Bande des étapes (une pastille par étape, défilement horizontal)

    private var stepStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(engine.steps) { step in
                        stepChip(step)
                            .id(step.index)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 30)
            .onChange(of: engine.currentStepIndex) { _, idx in
                guard let idx, engine.steps.indices.contains(idx) else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(idx, anchor: .center) }
            }
            .onAppear {
                if let idx = engine.currentStepIndex, engine.steps.indices.contains(idx) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }

    private func stepChip(_ step: TabataStep) -> some View {
        let status = engine.status(of: step)
        let done = engine.isCompleted(step)
        let accent = step.phase.color
        return Button {
            engine.select(stepIndex: step.index)
        } label: {
            ZStack {
                Capsule()
                    .fill(status == .current ? accent : accent.opacity(status == .past ? 0.18 : 0.10))
                Capsule()
                    .stroke(status == .future ? accent.opacity(0.45) : Color.clear, lineWidth: 1)
                if done && status == .past {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(pal.text(accent))
                } else {
                    Text(stepShortLabel(step))
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(status == .current ? Color.black : (status == .past ? pal.ink.opacity(0.45) : pal.text(accent)))
                }
            }
            .frame(width: step.phase == .work ? 30 : 22, height: 22)
            .opacity(status == .past && !done ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stepAccessibilityLabel(step, status: status, done: done))
        .accessibilityAddTraits(status == .current ? .isSelected : [])
        .accessibilityHint("Se placer sur cette étape")
    }

    private func stepShortLabel(_ step: TabataStep) -> String {
        switch step.phase {
        case .prepare:   return "P"
        case .work:      return "E\(step.round)"
        case .rest:      return "r"
        case .restCycle: return "S"
        case .cooldown:  return "C"
        default:         return ""
        }
    }

    private func stepTitle(_ step: TabataStep) -> String {
        switch step.phase {
        case .work:
            if let exo = exercise(forRound: step.round) { return "Effort · \(exo)" }
            return "Effort"
        default:
            return step.phase.title.capitalized
        }
    }

    private func stepDetail(_ step: TabataStep) -> String {
        var parts: [String] = []
        if engine.cfg.cycles > 1 { parts.append("Série \(step.cycle)") }
        if step.phase == .work || step.phase == .rest { parts.append("Round \(step.round)") }
        parts.append("\(step.duration) s")
        return parts.joined(separator: " · ")
    }

    private func stepStatusText(_ status: TabataStepStatus, done: Bool) -> String {
        switch status {
        case .current: return "en cours"
        case .future:  return "à venir"
        case .past:    return done ? "fait" : "sauté"
        }
    }

    private func stepAccessibilityLabel(_ step: TabataStep, status: TabataStepStatus, done: Bool) -> String {
        "\(stepTitle(step)), \(stepDetail(step)), \(stepStatusText(status, done: done))"
    }

    // MARK: - Feuille de la séquence complète

    private var sequenceSheetContent: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Séquence de la séance")
                        .font(AppFont.sans(size: 22, weight: .bold))
                        .foregroundStyle(pal.ink)
                    Text("\(engine.workStepsCompleted) effort\(engine.workStepsCompleted > 1 ? "s" : "") fait\(engine.workStepsCompleted > 1 ? "s" : "") sur \(engine.workStepsTotal) · \(formatHMS(engine.totalDuration)) au total")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(pal.ink.opacity(0.6))
                }
                Spacer()
                Button {
                    showSequence = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pal.ink.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .raisedSurface(Circle())
                }
                .accessibilityLabel("Fermer la séquence")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Text("Toucher une étape s'y place tout de suite. Sauter une étape ne la compte pas comme faite.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(pal.ink.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(engine.steps) { step in
                            sequenceRow(step)
                                .id("row-\(step.index)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
                .onAppear {
                    if let idx = engine.currentStepIndex, engine.steps.indices.contains(idx) {
                        proxy.scrollTo("row-\(idx)", anchor: .center)
                    }
                }
            }
        }
    }

    private func sequenceRow(_ step: TabataStep) -> some View {
        let status = engine.status(of: step)
        let done = engine.isCompleted(step)
        let accent = step.phase.color
        return Button {
            engine.select(stepIndex: step.index)
            showSequence = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: step.phase.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(pal.text(accent))
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(status == .current ? 0.28 : 0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(stepTitle(step))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(pal.ink)
                        .lineLimit(1)
                    Text(stepDetail(step))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(pal.ink.opacity(0.55))
                }

                Spacer()

                HStack(spacing: 5) {
                    if status == .current {
                        Image(systemName: engine.running ? "play.fill" : "pause.fill")
                            .font(.system(size: 10, weight: .bold))
                    } else if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                    }
                    Text(stepStatusText(status, done: done))
                        .font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(status == .current ? pal.text(accent) : pal.ink.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(status == .current ? accent.opacity(0.10) : pal.ink.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(status == .current ? accent.opacity(0.45) : pal.ink.opacity(0.08), lineWidth: 1)
            )
            .opacity(status == .past ? 0.7 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(stepAccessibilityLabel(step, status: status, done: done))
        .accessibilityAddTraits(status == .current ? .isSelected : [])
        .accessibilityHint("Se placer sur cette étape")
    }

    // MARK: - Anneau central Ultra-Fluide à 60/120 fps

    private var heroTimerHUD: some View {
        VStack(spacing: 16) {
            // Bandeau Exercice Actuel avec Icône
            exerciseHeaderCard

            // L'anneau chronomètre ultra-fluide via TimelineView
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let fraction = engine.smoothFraction(at: context.date)
                ringGraphic(fraction: fraction)
            }

            // Bandeau d'interruption (absence longue: mise en pause, rien crédité)
            if let gap = engine.interruptionGap, !engine.running {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pal.text(Color(hex: 0xFFB800)))
                    Text("En pause après \(max(1, Int(gap / 60))) min d'absence. Reprends quand tu veux.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(pal.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(pal.scrim.opacity(0.5), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: 0xFFB800).opacity(0.4), lineWidth: 1))
                .accessibilityElement(children: .combine)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            // Bandeau "À SUIVRE" (Next Exercise)
            else if let next = nextExercise, (engine.phase == .rest || engine.phase == .work || engine.phase == .restCycle) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pal.text(Color(hex: 0x00D2FF)))

                    Text("À SUIVRE :")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(pal.ink.opacity(0.6))

                    Text(next)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(pal.ink)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(pal.scrim.opacity(0.5), in: Capsule())
                .overlay(Capsule().stroke(pal.ink.opacity(0.12), lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                // Espace réservé pour éviter les sauts de mise en page
                Color.clear.frame(height: 30)
            }
        }
    }

    // MARK: - Carte de l'exercice actuel

    private var exerciseHeaderCard: some View {
        VStack(spacing: 6) {
            if let current = currentExercise, engine.phase == .work {
                HStack(spacing: 12) {
                    Image(systemName: exerciseSymbol(current))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(pal.text(engine.phase.color))
                        .frame(width: 44, height: 44)
                        .background(engine.phase.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXERCICE EN COURS")
                            .font(.system(size: 10, weight: .heavy))
                            .kerning(0.8)
                            .foregroundStyle(pal.text(engine.phase.color))
                        Text(current)
                            .font(AppFont.sans(size: 20, weight: .bold))
                            .foregroundStyle(pal.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .raisedSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(engine.phase.color.opacity(0.3), lineWidth: 1))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: engine.phase.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(pal.text(engine.phase.color))

                    VStack(alignment: .center, spacing: 2) {
                        Text(engine.phase.title)
                            .font(AppFont.sans(size: 17, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(pal.ink)
                        if let firstExo = exercise(forRound: engine.round) {
                            Text("Prochain : \(firstExo)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(pal.ink.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .raisedSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.ink.opacity(0.08), lineWidth: 1))
            }
        }
        .frame(height: 64)
    }

    // MARK: - Dessin de l'anneau central avec tête lumineuse

    @ViewBuilder
    private func ringGraphic(fraction: Double) -> some View {
        let size: CGFloat = 280
        let lineWidth: CGFloat = 16
        let effectiveFraction = engine.phase == .idle ? 1.0 : max(0.0001, fraction)

        ZStack {
            // Halo lumineux d'arrière-plan de l'anneau
            Circle()
                .stroke(engine.phase.color.opacity(0.15), lineWidth: lineWidth + 8)
                .blur(radius: 12)
                .frame(width: size, height: size)

            // Piste d'arrière-plan
            Circle()
                .stroke(pal.ink.opacity(0.08), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Anneau de progression actif
            Circle()
                .trim(from: 0, to: effectiveFraction)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            engine.phase.color.opacity(0.6),
                            engine.phase.color
                        ]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)

            // Tête lumineuse (indicator dot)
            GeometryReader { geo in
                let radius = (size / 2)
                let angle = (effectiveFraction * 360.0 - 90.0) * .pi / 180.0
                let x = geo.size.width / 2 + radius * CGFloat(cos(angle))
                let y = geo.size.height / 2 + radius * CGFloat(sin(angle))

                Circle()
                    .fill(pal.dark ? Color.white : engine.phase.color)
                    .frame(width: lineWidth - 4, height: lineWidth - 4)
                    .shadow(color: engine.phase.color, radius: 8, x: 0, y: 0)
                    .position(x: x, y: y)
            }
            .frame(width: size, height: size)

            // Contenu textuel central
            VStack(spacing: 4) {
                // Badge de phase capsule
                HStack(spacing: 5) {
                    Image(systemName: engine.phase.icon)
                        .font(.system(size: 11, weight: .heavy))
                    Text(engine.phase.shortTitle)
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(0.8)
                }
                .foregroundStyle(pal.text(engine.phase.color))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(engine.phase.color.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(engine.phase.color.opacity(0.4), lineWidth: 1))

                // Chronomètre en gros caractères (Monospace de précision)
                let displayVal = engine.phase == .idle ? prepare : engine.remaining
                Text(String(format: "%02d", displayVal))
                    .font(AppFont.mono(size: 84, weight: .bold))
                    .foregroundStyle(pal.ink)
                    .shadow(color: engine.phase.color.opacity(0.35), radius: 10, x: 0, y: 0)

                // Indication sous le chiffre
                if engine.phase == .work {
                    Text("DONNE TOUT !")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(pal.text(engine.phase.color))
                } else if engine.phase == .rest || engine.phase == .restCycle {
                    Text("RÉCUPÈRE")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(pal.ink.opacity(0.6))
                } else {
                    Text("PRÉPARE-TOI")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(pal.text(Color(hex: 0xFFB800)))
                }
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Panneau de contrôle inférieur (Floating Glass Dock)

    private var controlDock: some View {
        VStack(spacing: 14) {
            // Boutons d'ajustement rapide (+/- 5 secondes)
            HStack(spacing: 12) {
                Button {
                    engine.adjustSeconds(-5)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 12, weight: .bold))
                        Text("-5s")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(pal.ink.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .raisedSurface(Capsule())
                }

                Spacer()

                Button {
                    showResetDialog = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text("Recommencer")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(pal.ink.opacity(sessionActive ? 0.6 : 0.3))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .raisedSurface(Capsule())
                }
                .disabled(!sessionActive)
                .accessibilityLabel("Recommencer ou abandonner la séance")

                Spacer()

                Button {
                    engine.adjustSeconds(+5)
                } label: {
                    HStack(spacing: 4) {
                        Text("+5s")
                            .font(.system(size: 12, weight: .bold))
                        Image(systemName: "goforward.5")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(pal.ink.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .raisedSurface(Capsule())
                }
            }
            .padding(.horizontal, 8)

            // Barre principale : Précédent / Play-Pause Géant / Suivant
            HStack(spacing: 24) {
                // Série / Round précédent
                Button {
                    engine.skipBackward()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(pal.ink)
                        Text("Préc.")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(pal.ink.opacity(0.5))
                    }
                    .frame(width: 58, height: 58)
                    .raisedSurface(Circle())
                    .overlay(Circle().stroke(pal.ink.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PressableButtonStyle())

                // Bouton PLAY / PAUSE CENTRAL GÉANT
                Button {
                    engine.startOrPause()
                } label: {
                    ZStack {
                        // Halo de pulsation
                        Circle()
                            .fill(engine.phase.color.opacity(0.25))
                            .frame(width: 88, height: 88)
                            .blur(radius: 6)

                        // Bouton principal
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: engine.phase.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 78, height: 78)
                            .shadow(color: engine.phase.color.opacity(0.5), radius: 12, x: 0, y: 4)

                        Image(systemName: engine.running ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(.black)
                            .offset(x: engine.running ? 0 : 2)
                    }
                }
                .buttonStyle(PressableButtonStyle())

                // Série / Round suivant
                Button {
                    engine.skipForward()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(pal.ink)
                        Text("Suiv.")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(pal.ink.opacity(0.5))
                    }
                    .frame(width: 58, height: 58)
                    .raisedSurface(Circle())
                    .overlay(Circle().stroke(pal.ink.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(pal.panel.opacity(0.92))
                .shadow(color: Color.black.opacity(pal.shadowOpacity), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(pal.ink.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Écran de choix de séance (Native Modal Sheet)

    private var chooserSheetContent: some View {
        VStack(spacing: 0) {
            // Barre d'en-tête
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Entraînements HIIT")
                        .font(AppFont.sans(size: 22, weight: .bold))
                        .foregroundStyle(pal.ink)
                    Text("Sélectionne un programme prêt ou personnalise tes intervalles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(pal.ink.opacity(0.6))
                }
                Spacer()
                Button {
                    showChooser = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(pal.ink.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .raisedSurface(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Strip de réglage rapide
            quickConfigStrip
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)

            // Liste déroulante des séances
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(availableSessions) { s in
                        Button {
                            pick(s)
                        } label: {
                            sessionCard(s)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }

                    Button {
                        pick(nil)
                    } label: {
                        freeIntervalCard
                    }
                    .buttonStyle(PressableButtonStyle())

                    customPresetsSection
                    historySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $creatingPreset) {
            TabataPresetEditor(initial: TabataConfig(prepare: prepare, work: work, rest: rest, rounds: rounds,
                                                     cycles: cycles, restCycle: restCycle, cooldown: cooldown))
        }
        .sheet(item: $editingPreset) { p in TabataPresetEditor(initial: p.config, editing: p) }
        .confirmationDialog("Supprimer ce préréglage ?",
                            isPresented: Binding(get: { pendingPresetDelete != nil }, set: { if !$0 { pendingPresetDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingPresetDelete) { p in
            Button("Supprimer", role: .destructive) { deletePreset(p) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in Text("L'historique des séances faites avec reste intact.") }
    }

    // MARK: - Préréglages perso

    private var customPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MES PRÉRÉGLAGES")
                    .font(.system(size: 11, weight: .heavy)).kerning(0.8)
                    .foregroundStyle(pal.ink.opacity(0.6))
                Spacer()
                Button {
                    creatingPreset = true
                } label: {
                    Label("Nouveau", systemImage: "plus").font(.caption.bold())
                }
                .accessibilityLabel("Nouveau préréglage")
            }
            .padding(.top, 10)
            if customPresets.isEmpty {
                Text("Enregistre tes intervalles sous un nom pour les relancer d'un geste.")
                    .font(.caption).foregroundStyle(pal.ink.opacity(0.55))
            }
            ForEach(customPresets) { p in
                HStack(spacing: 10) {
                    Button { pickPreset(p) } label: { presetCard(p) }
                        .buttonStyle(PressableButtonStyle())
                    Menu {
                        Button("Modifier") { editingPreset = p }
                        Button("Supprimer", role: .destructive) { pendingPresetDelete = p }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(pal.ink.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .raisedSurface(Circle())
                    }
                    .accessibilityLabel("Options du préréglage")
                }
            }
        }
    }

    private func presetCard(_ p: TabataPreset) -> some View {
        let isChosen = chosenSession?.id == presetSession(p).id
        let accent = Color(hex: 0x00D2FF)
        let c = p.config
        return HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(pal.text(accent))
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.system(size: 15, weight: .bold)).foregroundStyle(pal.ink)
                Text("\(c.work)s / \(c.rest)s · \(c.rounds) rounds × \(c.cycles) · \(formatHMS(TabataPresetRules.totalSeconds(c)))")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(pal.ink.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            if isChosen {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(pal.text(accent))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isChosen ? accent.opacity(0.08) : pal.ink.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(isChosen ? accent.opacity(0.4) : pal.ink.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Historique des séances

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HISTORIQUE")
                .font(.system(size: 11, weight: .heavy)).kerning(0.8)
                .foregroundStyle(pal.ink.opacity(0.6))
                .padding(.top, 10)
            if let historyError {
                Text(historyError).font(.caption).foregroundStyle(Theme.warning)
            }
            if tabataLogs.isEmpty {
                Text("Tes séances terminées apparaîtront ici, et comptent dans Streakz.")
                    .font(.caption).foregroundStyle(pal.ink.opacity(0.55))
            }
            ForEach(tabataLogs.prefix(15)) { log in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(pal.ink)
                        Text("\(log.date.formatted(.dateTime.day().month().hour().minute())) · \(log.completedRounds)/\(log.totalRounds) efforts")
                            .font(.system(size: 12)).foregroundStyle(pal.ink.opacity(0.55))
                    }
                    Spacer()
                    Text(formatHMS(log.activeSeconds))
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(pal.text(Color(hex: 0x00F076)))
                    Button(role: .destructive) { deleteLog(log) } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .foregroundStyle(Theme.danger.opacity(0.7))
                    .accessibilityLabel("Supprimer la séance")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.ink.opacity(0.05)))
            }
        }
    }

    private var quickConfigStrip: some View {
        HStack(spacing: 10) {
            cfgStepper("EFFORT", value: $work, unit: "s", step: 5, min: 5, color: 0x00F076)
            cfgStepper("REPOS", value: $rest, unit: "s", step: 5, min: 0, color: 0xFF5252)
            cfgStepper("SÉRIES", value: $sets, unit: "", step: 1, min: 1, color: 0xFFB800)
        }
    }

    private func cfgStepper(_ label: String, value: Binding<Int>, unit: String, step: Int, min: Int, color: UInt) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .kerning(0.8)
                .foregroundStyle(Color(hex: color))

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    value.wrappedValue = Swift.max(min, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(pal.ink)
                        .frame(width: 28, height: 28)
                        .raisedSurface(Circle())
                }

                Text("\(value.wrappedValue)\(unit)")
                    .font(AppFont.sans(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(pal.ink)
                    .frame(minWidth: 36)

                Button {
                    Haptics.tap()
                    value.wrappedValue += step
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(pal.ink)
                        .frame(width: 28, height: 28)
                        .raisedSurface(Circle())
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .raisedSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(pal.ink.opacity(0.08), lineWidth: 1))
    }

    private func sessionCard(_ s: TabataSession) -> some View {
        let isChosen = chosenSession?.id == s.id
        let accent = Color(hex: s.accentColorHex)

        return HStack(spacing: 14) {
            // Icône stylisée
            Image(systemName: s.icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(pal.text(accent))
                .frame(width: 52, height: 52)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accent.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(s.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(pal.ink)

                    if let tag = s.tag {
                        Text(tag)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(pal.text(accent))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.15), in: Capsule())
                    }
                }

                Text(s.exercises.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(pal.ink.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            if isChosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(pal.text(accent))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(pal.ink.opacity(0.3))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isChosen ? accent.opacity(0.08) : pal.ink.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isChosen ? accent.opacity(0.4) : pal.ink.opacity(0.08), lineWidth: 1)
        )
    }

    private var freeIntervalCard: some View {
        let isChosen = chosenSession == nil
        return HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(pal.text(Color(hex: 0x00D2FF)))
                .frame(width: 52, height: 52)
                .background(Color(hex: 0x00D2FF).opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0x00D2FF).opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("Intervalles Libres")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(pal.ink)
                Text("Chrono personnalisé : \(work)s effort / \(rest)s repos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(pal.ink.opacity(0.55))
            }

            Spacer()

            if isChosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(pal.text(Color(hex: 0x00D2FF)))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(pal.ink.opacity(0.3))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isChosen ? Color(hex: 0x00D2FF).opacity(0.08) : pal.ink.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isChosen ? Color(hex: 0x00D2FF).opacity(0.4) : pal.ink.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Vue de célébration / Séance terminée

    private var completionCelebrationView: some View {
        ZStack {
            pal.background.opacity(0.95).ignoresSafeArea()

            VStack(spacing: 20) {
                // Trophée lumineux
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x00F076).opacity(0.2))
                        .frame(width: 120, height: 120)
                        .blur(radius: 14)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 60, weight: .black))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: 0xFFD700), Color(hex: 0xF59E0B)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .padding(.top, 20)

                VStack(spacing: 6) {
                    Text("SÉANCE TERMINÉE !")
                        .font(AppFont.sans(size: 28, weight: .bold))
                        .foregroundStyle(pal.ink)

                    Text(engine.workStepsCompleted == engine.workStepsTotal
                         ? "Tous les efforts sont faits"
                         : "\(engine.workStepsCompleted) effort\(engine.workStepsCompleted > 1 ? "s" : "") sur \(engine.workStepsTotal), le reste a été sauté")
                        .font(.subheadline)
                        .foregroundStyle(pal.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                // Statistiques de la séance: ce qui a VRAIMENT été fait
                HStack(spacing: 12) {
                    statBox("ACTIF", formatHMS(engine.activeSeconds), "clock.fill")
                    statBox("EFFORT", formatHMS(engine.workSecondsDone), "flame.fill")
                    statBox("ROUNDS", "\(engine.workStepsCompleted)/\(engine.workStepsTotal)", "target")
                }
                .padding(.horizontal, 10)

                // Badge Apple Santé, honnête: accepté, en cours, refusé (avec
                // un nouvel essai), ou rien à écrire, et pourquoi.
                let healthState = keeper.healthState(for: engine.sessionID)
                HStack(spacing: 8) {
                    switch healthState {
                    case .saved:
                        Image(systemName: "heart.fill").foregroundStyle(Theme.danger)
                        healthBadgeText("Envoyé à Apple Santé")
                    case .pending:
                        ProgressView().controlSize(.small)
                        healthBadgeText("Envoi à Apple Santé en cours")
                    case .failed:
                        Image(systemName: "heart.slash").foregroundStyle(Theme.warning)
                        healthBadgeText("Apple Santé a refusé l'écriture")
                        Button("Réessayer") { keeper.retryHealthWrite() }
                            .font(.caption.bold())
                            .buttonStyle(.borderless)
                    case .notEligible:
                        Image(systemName: "heart.slash").foregroundStyle(pal.ink.opacity(0.5))
                        healthBadgeText("Pas dans Apple Santé : moins d'une minute d'activité")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .raisedSurface(Capsule())
                .accessibilityElement(children: healthState == .failed ? .contain : .combine)

                if let historyError {
                    Text(historyError).font(.caption).foregroundStyle(Theme.warning).multilineTextAlignment(.center)
                }

                // Boutons d'action
                VStack(spacing: 10) {
                    Button {
                        keeper.discard()
                        dismiss()
                    } label: {
                        Text("Terminer & Fermer")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(hex: 0x00F076))
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button {
                        engine.reset()
                        engine.begin()
                    } label: {
                        Text("Recommencer la séance")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(pal.ink.opacity(0.10))
                            .foregroundStyle(pal.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.top, 10)
            }
            .padding(26)
            .background(pal.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(pal.ink.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 24)
        }
    }

    private func healthBadgeText(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(pal.ink.opacity(0.8))
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }

    private func statBox(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(pal.text(Color(hex: 0x00F076)))
            Text(value)
                .font(AppFont.sans(size: 20, weight: .bold))
                .foregroundStyle(pal.ink)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(pal.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .raisedSurface(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func exerciseSymbol(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("squat") || n.contains("chaise") || n.contains("mur")            { return "figure.cross.training" }
        if n.contains("pompe") || n.contains("dips") || n.contains("push") || n.contains("pike") { return "figure.strengthtraining.traditional" }
        if n.contains("fente") || n.contains("lunge") || n.contains("mollet")          { return "figure.walk" }
        if n.contains("gainage") || n.contains("plank") || n.contains("core") || n.contains("crunch")
            || n.contains("abdo") || n.contains("twist") || n.contains("bicyclette") || n.contains("jambe") { return "figure.core.training" }
        if n.contains("burpee") || n.contains("saut") || n.contains("jump")            { return "figure.highintensity.intervaltraining" }
        if n.contains("mountain") || n.contains("climber") || n.contains("genou") || n.contains("talon") || n.contains("run") { return "figure.run" }
        if n.contains("jack") || n.contains("cardio")                                  { return "figure.mixed.cardio" }
        if n.contains("superman") || n.contains("stretch") || n.contains("flex")       { return "figure.flexibility" }
        return "dumbbell.fill"
    }
}

// L'enregistrement dans Apple Santé est fait par `TabataSessionKeeper`, une
// seule fois par identifiant de séance, même si cet écran est fermé à la fin.

// MARK: - Réglages des intervalles

struct TabataSettings: View {
    @Environment(\.colorScheme) private var colorScheme
    private var pal: TabataPalette { TabataPalette(scheme: colorScheme) }
    @Environment(\.dismiss) private var dismiss
    @Binding var prepare: Int
    @Binding var work: Int
    @Binding var rest: Int
    @Binding var rounds: Int
    @Binding var cycles: Int
    @Binding var restCycle: Int
    @Binding var cooldown: Int
    @Binding var sets: Int

    var body: some View {
        NavigationStack {
            List {
                Section("INTERVALLES") {
                    row(0xFFB800, "PRÉPARATION", "Décompte avant de démarrer", $prepare, step: 5, time: true)
                    row(0x00F076, "EFFORT", "Durée de chaque exercice", $work, step: 5, time: true)
                    row(0xFF5252, "REPOS", "Récup entre les exercices", $rest, step: 5, time: true)
                    row(0x00D2FF, "SÉRIES", "Passages sur les exercices", $sets, step: 1, time: false)
                    row(0x00D2FF, "RÉCUP ENTRE SÉRIES", "Pause entre les séries", $restCycle, step: 5, time: true)
                    row(0x7E72F2, "RETOUR AU CALME", "Cooldown final", $cooldown, step: 5, time: true)
                }
                Section("INTERVALLES LIBRES (sans séance)") {
                    row(0x00D2FF, "ROUNDS", "Un round = effort + repos", $rounds, step: 1, time: false)
                    row(0xFFB800, "CYCLES", "Un cycle = N rounds", $cycles, step: 1, time: false)
                }
                Section {
                    HStack {
                        Text("Durée totale").bold()
                        Spacer()
                        Text(formatHMS(totalSeconds)).bold().foregroundStyle(pal.text(Color(hex: 0x00F076)))
                    }
                }
            }
            .navigationTitle("Réglages Tabata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.bold()
                }
            }
        }
    }

    private var totalSeconds: Int {
        let perCycle = work * rounds + rest * max(0, rounds - 1)
        return prepare + perCycle * cycles + restCycle * max(0, cycles - 1) + cooldown
    }

    private func row(_ hex: UInt, _ title: String, _ sub: String, _ value: Binding<Int>, step: Int, time: Bool) -> some View {
        HStack(spacing: 14) {
            Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold))
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(time ? formatHMS(value.wrappedValue) : "\(value.wrappedValue)")
                .font(.title3.weight(.heavy)).monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
            Stepper("", value: value, in: (time ? 0 : 1)...3600, step: step).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Éditeur de préréglage perso

struct TabataPresetEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var presets: [TabataPreset]
    let initial: TabataConfig
    var editing: TabataPreset? = nil
    @State private var name = ""
    @State private var cfg = TabataConfig(prepare: 10, work: 30, rest: 15, rounds: 8, cycles: 1, restCycle: 60, cooldown: 0)
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("NOM") { TextField("Ex: Tabata du matin", text: $name) }
                Section("INTERVALLES") {
                    stepper("Préparation", $cfg.prepare, 0...3600, 5, time: true)
                    stepper("Effort", $cfg.work, 5...3600, 5, time: true)
                    stepper("Repos", $cfg.rest, 0...3600, 5, time: true)
                    stepper("Rounds", $cfg.rounds, 1...100, 1, time: false)
                    stepper("Cycles", $cfg.cycles, 1...50, 1, time: false)
                    stepper("Récup entre cycles", $cfg.restCycle, 0...3600, 5, time: true)
                    stepper("Retour au calme", $cfg.cooldown, 0...3600, 5, time: true)
                }
                Section {
                    HStack { Text("Durée totale").bold(); Spacer(); Text(formatHMS(TabataPresetRules.totalSeconds(cfg))).bold() }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
            }
            .navigationTitle(editing == nil ? "Nouveau préréglage" : "Modifier le préréglage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.bold() }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                cfg = TabataPresetRules.sanitized(initial)
                name = editing?.name ?? ""
            }
        }
    }

    private func stepper(_ title: String, _ v: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int, time: Bool) -> some View {
        Stepper(value: v, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(time ? formatHMS(v.wrappedValue) : "\(v.wrappedValue)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let others = presets.filter { $0.id != editing?.id }.map(\.name)
        if let msg = TabataPresetRules.validate(name: name, existing: others, original: editing?.name) { error = msg; return }
        let n = name.trimmingCharacters(in: .whitespaces)
        let c = TabataPresetRules.sanitized(cfg)
        if let p = editing {
            let old = (p.name, p.config)
            p.name = n; p.apply(c)
            do { try ctx.save(); dismiss() } catch {
                p.name = old.0; p.apply(old.1)
                self.error = "Préréglage non enregistré : \(error.localizedDescription)"
            }
        } else {
            let p = TabataPreset(name: n, config: c)
            ctx.insert(p)
            do { try ctx.save(); dismiss() } catch {
                ctx.delete(p)
                self.error = "Préréglage non enregistré : \(error.localizedDescription)"
            }
        }
    }
}
