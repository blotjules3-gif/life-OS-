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

struct TabataConfig {
    var prepare: Int
    var work: Int
    var rest: Int
    var rounds: Int            // rounds (work+rest) par cycle
    var cycles: Int
    var restCycle: Int         // récup entre cycles
    var cooldown: Int
}

// MARK: - Moteur

@Observable
final class TabataEngine {
    enum Phase: Equatable {
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

    var cfg: TabataConfig
    var phase: Phase = .idle
    var remaining: Int = 0
    var intervalTotal: Int = 0     // durée totale de l'intervalle courant (pour l'anneau)
    var round: Int = 1
    var cycle: Int = 1
    var running = false

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

    func begin() {
        phase = .prepare
        remaining = cfg.prepare
        intervalTotal = cfg.prepare
        round = 1
        cycle = 1
        let currentNow = now()
        startedAt = currentNow
        intervalStart = currentNow
        intervalEnd = currentNow.addingTimeInterval(Double(cfg.prepare))
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
        intervalStart = nil
        intervalEnd = nil
        TabataSound.shared.end()
    }

    private func run() {
        running = true
        let currentNow = now()
        lastTick = currentNow
        intervalStart = currentNow
        intervalEnd = currentNow.addingTimeInterval(Double(remaining))
        UIApplication.shared.isIdleTimerDisabled = true
        cancellable = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func pause() {
        running = false
        cancellable?.cancel()
        lastTick = nil
        intervalEnd = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Avance d'autant de secondes qu'il s'en est RÉELLEMENT écoulé.
    func tick() {
        let currentNow = self.now()
        var steps = 1
        if let last = lastTick {
            steps = Int(currentNow.timeIntervalSince(last).rounded())
        }
        lastTick = currentNow
        guard steps > 0 else { return }
        let catchUp = steps > 1
        steps = min(steps, 3600)
        for _ in 0..<steps {
            guard running, phase != .idle, phase != .done else { break }
            step(silent: catchUp)
        }
        if running && intervalTotal > 0 {
            intervalEnd = currentNow.addingTimeInterval(Double(remaining))
        }
    }

    private func step(silent: Bool) {
        if remaining > 1 {
            remaining -= 1
            if !silent, remaining <= 3, phase != .idle, phase != .done {
                TabataSound.shared.countdown()
                Haptics.tap()
            }
            return
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
        remaining = 0
        intervalStart = nil
        intervalEnd = nil
        TabataSound.shared.finish()
    }

    // Navigation manuelle entre les séries
    func skipForward() {
        Haptics.tap()
        if round < cfg.rounds { round += 1 }
        else if cycle < cfg.cycles { cycle += 1; round = 1 }
        else { finish(); return }
        enter(.work, cfg.work)
    }

    func skipBackward() {
        Haptics.tap()
        if phase == .done { phase = .work }
        if round > 1 { round -= 1 }
        else if cycle > 1 { cycle -= 1; round = cfg.rounds }
        enter(.work, cfg.work)
    }

    func adjustSeconds(_ delta: Int) {
        Haptics.tap()
        let newRemaining = max(1, remaining + delta)
        remaining = newRemaining
        intervalTotal = max(intervalTotal, newRemaining)
        if running {
            intervalEnd = now().addingTimeInterval(Double(remaining))
        }
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

struct TabataView: View {
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

    @State private var engine = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15, rounds: 8, cycles: 1, restCycle: 60, cooldown: 0))
    @State private var showSettings = false
    @State private var chosenSession: TabataSession? = TabataPresets.all[0]
    @State private var showChooser = false
    @State private var soundMuted = false

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
    private var sessionExercises: [String] { chosenSession?.exercises ?? [] }

    private func exercise(forRound r: Int) -> String? {
        guard !sessionExercises.isEmpty else { return nil }
        let i = (max(1, r) - 1) % sessionExercises.count
        return sessionExercises[i]
    }
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
        chosenSession = session
        engine.reset()
        engine.cfg = config
        engine.remaining = prepare
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showChooser = false
        }
    }

    var body: some View {
        ZStack {
            // Fond noir profond OLED
            Color(hex: 0x07080A).ignoresSafeArea()

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
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showChooser) {
            chooserSheetContent
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: 0x111318))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.tick() }
        }
        .onAppear {
            engine.cfg = config
            if engine.phase == .idle { engine.remaining = prepare }
            soundMuted = !TabataSound.shared.soundEnabled
        }
        .onChange(of: engine.phase) { _, phase in
            guard phase == .done else { return }
            Task { await saveSessionToHealth() }
        }
        .onDisappear {
            TabataSound.shared.end()
        }
        .sheet(isPresented: $showSettings) {
            TabataSettings(prepare: $prepare, work: $work, rest: $rest, rounds: $rounds, cycles: $cycles, restCycle: $restCycle, cooldown: $cooldown, sets: $sets)
                .onDisappear {
                    engine.cfg = config
                    if engine.phase == .idle { engine.remaining = prepare }
                }
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
                    colors: [Color.black.opacity(0.4), Color.clear, Color.black.opacity(0.7)],
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
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showChooser = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: chosenSession?.icon ?? "timer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(engine.phase.color)

                    Text(chosenSession?.name ?? "Intervalles libres")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
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
                        .foregroundStyle(soundMuted ? .white.opacity(0.4) : engine.phase.color)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }

                // Bouton Réglages
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
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
                        .foregroundStyle(.white.opacity(0.6))
                    Text("TEMPS RESTANT")
                        .font(.system(size: 11, weight: .heavy))
                        .kerning(0.8)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Text(formatHMS(engine.phase == .idle ? engine.totalDuration : engine.totalRemaining))
                    .font(AppFont.sans(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
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
                        .fill(Color.white.opacity(0.10))
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

            // Badges d'état Série / Round
            HStack(spacing: 8) {
                Label {
                    Text("SÉRIE \(engine.cycle)/\(engine.cfg.cycles)")
                        .font(.system(size: 11, weight: .heavy))
                } icon: {
                    Image(systemName: "repeat")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())

                Spacer()

                Label {
                    Text("ROUND \(engine.round)/\(engine.cfg.rounds)")
                        .font(.system(size: 11, weight: .heavy))
                } icon: {
                    Image(systemName: "target")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(engine.phase == .work ? engine.phase.color : .white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(engine.phase == .work ? engine.phase.color.opacity(0.15) : Color.white.opacity(0.06), in: Capsule())
                .overlay(
                    Capsule().stroke(engine.phase == .work ? engine.phase.color.opacity(0.35) : Color.clear, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
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

            // Bandeau "À SUIVRE" (Next Exercise)
            if let next = nextExercise, (engine.phase == .rest || engine.phase == .work || engine.phase == .restCycle) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x00D2FF))

                    Text("À SUIVRE :")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(next)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.5), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
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
                        .foregroundStyle(engine.phase.color)
                        .frame(width: 44, height: 44)
                        .background(engine.phase.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXERCICE EN COURS")
                            .font(.system(size: 10, weight: .heavy))
                            .kerning(0.8)
                            .foregroundStyle(engine.phase.color)
                        Text(current)
                            .font(AppFont.sans(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(engine.phase.color.opacity(0.3), lineWidth: 1))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: engine.phase.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(engine.phase.color)

                    VStack(alignment: .center, spacing: 2) {
                        Text(engine.phase.title)
                            .font(AppFont.sans(size: 17, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(.white)
                        if let firstExo = exercise(forRound: engine.round) {
                            Text("Prochain : \(firstExo)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
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
                    .fill(Color.white)
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
                .foregroundStyle(engine.phase.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(engine.phase.color.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(engine.phase.color.opacity(0.4), lineWidth: 1))

                // Chronomètre en gros caractères (Monospace de précision)
                let displayVal = engine.phase == .idle ? prepare : engine.remaining
                Text(String(format: "%02d", displayVal))
                    .font(AppFont.mono(size: 84, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: engine.phase.color.opacity(0.35), radius: 10, x: 0, y: 0)

                // Indication sous le chiffre
                if engine.phase == .work {
                    Text("DONNE TOUT !")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(engine.phase.color)
                } else if engine.phase == .rest || engine.phase == .restCycle {
                    Text("RÉCUPÈRE")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("PRÉPARE-TOI")
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(Color(hex: 0xFFB800))
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
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }

                Spacer()

                Button {
                    engine.reset()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text("Recommencer")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05), in: Capsule())
                }

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
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())
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
                            .foregroundStyle(.white)
                        Text("Préc.")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
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
                            .foregroundStyle(.white)
                        Text("Suiv.")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: 0x12141A).opacity(0.92))
                .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
                        .foregroundStyle(.white)
                    Text("Sélectionne un programme prêt ou personnalise tes intervalles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button {
                    showChooser = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())
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
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
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
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12), in: Circle())
                }

                Text("\(value.wrappedValue)\(unit)")
                    .font(AppFont.sans(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(minWidth: 36)

                Button {
                    Haptics.tap()
                    value.wrappedValue += step
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func sessionCard(_ s: TabataSession) -> some View {
        let isChosen = chosenSession?.id == s.id
        let accent = Color(hex: s.accentColorHex)

        return HStack(spacing: 14) {
            // Icône stylisée
            Image(systemName: s.icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 52, height: 52)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accent.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(s.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    if let tag = s.tag {
                        Text(tag)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.15), in: Capsule())
                    }
                }

                Text(s.exercises.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            if isChosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(accent)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isChosen ? accent.opacity(0.08) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isChosen ? accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var freeIntervalCard: some View {
        let isChosen = chosenSession == nil
        return HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x00D2FF))
                .frame(width: 52, height: 52)
                .background(Color(hex: 0x00D2FF).opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0x00D2FF).opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("Intervalles Libres")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text("Chrono personnalisé : \(work)s effort / \(rest)s repos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if isChosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0x00D2FF))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isChosen ? Color(hex: 0x00D2FF).opacity(0.08) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isChosen ? Color(hex: 0x00D2FF).opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Vue de célébration / Séance terminée

    private var completionCelebrationView: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

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
                        .foregroundStyle(.white)

                    Text("Performance enregistrée avec succès")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                // Statistiques de la séance
                HStack(spacing: 12) {
                    statBox("DURÉE", formatHMS(engine.totalDuration), "clock.fill")
                    statBox("SÉRIES", "\(engine.cfg.cycles)", "repeat")
                    statBox("ROUNDS", "\(engine.cfg.rounds * engine.cfg.cycles)", "flame.fill")
                }
                .padding(.horizontal, 10)

                // Badge Apple Santé
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("Synchronisé avec Apple Santé")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())

                // Boutons d'action
                VStack(spacing: 10) {
                    Button {
                        engine.reset()
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
                            .background(Color.white.opacity(0.10))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.top, 10)
            }
            .padding(26)
            .background(Color(hex: 0x13151D), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 24)
        }
    }

    private func statBox(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x00F076))
            Text(value)
                .font(AppFont.sans(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

// MARK: - Enregistrement Santé

private extension TabataView {
    static var minimumDuration: TimeInterval { 60 }

    func saveSessionToHealth() async {
        guard let start = engine.startedAt else { return }
        let end = Date()
        guard end.timeIntervalSince(start) >= Self.minimumDuration else { return }
        await HealthService.shared.saveWorkout(kind: .hiit, start: start, end: end, kcal: 0)
    }
}

// MARK: - Réglages des intervalles

struct TabataSettings: View {
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
                        Text(formatHMS(totalSeconds)).bold().foregroundStyle(Color(hex: 0x00F076))
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
        .preferredColorScheme(.dark)
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
