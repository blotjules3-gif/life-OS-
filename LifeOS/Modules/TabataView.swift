import SwiftUI
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
        // .playback => sortie courante (Bluetooth/écouteurs/enceinte) + joue en mode silencieux.
        // mixWithOthers + duckOthers => la musique continue mais baisse pendant le bip.
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

    private func play(_ key: String, _ segments: [(Double, Double)], vol: Double) {
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
    enum Phase {
        case idle, prepare, work, rest, restCycle, cooldown, done
        var title: String {
            switch self {
            case .idle, .prepare: return "PRÊT"
            case .work: return "EFFORT"
            case .rest: return "REPOS"
            case .restCycle: return "RÉCUP"
            case .cooldown: return "RETOUR AU CALME"
            case .done: return "TERMINÉ"
            }
        }
        var color: Color {
            switch self {
            case .idle, .prepare: return Color(hex: 0xF2D43D)   // jaune
            case .work: return Color(hex: 0x9BE14E)             // vert
            case .rest: return Color(hex: 0xF0584B)             // rouge
            case .restCycle: return Color(hex: 0xF2A03D)        // orange
            case .cooldown: return Color(hex: 0x4FA8E0)         // bleu
            case .done: return Color(hex: 0x9BE14E)
            }
        }
        var onColor: Color {
            switch self {
            case .rest, .cooldown: return .white
            default: return .black
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

    private var cancellable: AnyCancellable?

    init(cfg: TabataConfig) {
        self.cfg = cfg
        self.remaining = cfg.prepare
        self.intervalTotal = cfg.prepare
    }

    var roundsLeft: Int { max(0, cfg.rounds - round + 1) }
    var cyclesLeft: Int { max(0, cfg.cycles - cycle + 1) }

    // Fraction restante de l'intervalle courant (1 → plein, 0 → vide) pour l'anneau.
    var intervalFraction: Double { Double(remaining) / Double(max(1, intervalTotal)) }

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

    func begin() {
        phase = .prepare; remaining = cfg.prepare; intervalTotal = cfg.prepare; round = 1; cycle = 1
        Haptics.tap(); TabataSound.shared.prime(); run()
    }

    func reset() {
        pause(); phase = .idle; remaining = cfg.prepare; intervalTotal = cfg.prepare; round = 1; cycle = 1
        TabataSound.shared.end()
    }

    private func run() {
        running = true
        cancellable = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }
    private func pause() { running = false; cancellable?.cancel() }

    private func tick() {
        if remaining > 1 {
            remaining -= 1
            // Décompte sonore sur les 3 dernières secondes de chaque intervalle.
            if remaining <= 3, phase != .idle, phase != .done { TabataSound.shared.countdown() }
            return
        }
        advance()   // remaining == 1 → transition (son joué dans enter/finish)
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
            cycle += 1; round = 1
            enter(.work, cfg.work)
        case .cooldown:
            finish()
        }
    }

    private func enter(_ p: Phase, _ secs: Int) {
        phase = p
        remaining = max(1, secs)
        intervalTotal = max(1, secs)
        // Bip de transition : aigu pour l'effort, grave pour repos/récup/retour au calme.
        switch p {
        case .work:                          TabataSound.shared.work()
        case .rest, .restCycle, .cooldown:   TabataSound.shared.rest()
        default:                             break
        }
        if secs <= 0 { advance() }
    }
    private func finish() {
        pause(); phase = .done; remaining = 0
        TabataSound.shared.finish()
    }

    // Navigation manuelle entre les séries (ex: j'ai loupé/fini une série).
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
}

// MARK: - Séance (préréglages intégrés + programme Sport)

struct TabataSession: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let exercises: [String]
    var subtitle: String? = nil
}

/// Séances prêtes à l'emploi — chacune = 6 exercices différents (base de l'app).
enum TabataPresets {
    static let all: [TabataSession] = [
        .init(id: "full", name: "Full body", icon: "figure.strengthtraining.functional",
              exercises: ["Squats", "Pompes", "Fentes", "Gainage", "Mountain climbers", "Burpees"]),
        .init(id: "upper", name: "Haut du corps", icon: "figure.arms.open",
              exercises: ["Pompes", "Dips", "Pompes diamant", "Superman", "Pike push-ups", "Gainage épaules"]),
        .init(id: "lower", name: "Bas du corps", icon: "figure.walk",
              exercises: ["Squats", "Fentes avant", "Fentes arrière", "Chaise murale", "Mollets", "Squats sautés"]),
        .init(id: "hiit", name: "Cardio HIIT", icon: "flame.fill",
              exercises: ["Jumping jacks", "Montées de genoux", "Burpees", "Mountain climbers", "Talons-fesses", "Squats sautés"]),
        .init(id: "core", name: "Abdos / Core", icon: "figure.core.training",
              exercises: ["Crunchs", "Gainage", "Russian twists", "Relevés de jambes", "Bicyclette", "Gainage latéral"]),
    ]
}

// MARK: - Écran immersif

struct TabataView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tabPrepare") private var prepare = 10
    @AppStorage("tabWork") private var work = 30
    @AppStorage("tabRest") private var rest = 15
    @AppStorage("tabRounds") private var rounds = 8
    @AppStorage("tabCycles") private var cycles = 1
    @AppStorage("tabRestCycle") private var restCycle = 60
    @AppStorage("tabCooldown") private var cooldown = 0
    @AppStorage("tabSets") private var sets = 4          // séries = passages sur les 6 exercices

    @State private var engine = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15, rounds: 8, cycles: 1, restCycle: 60, cooldown: 0))
    @State private var showSettings = false
    @State private var chosenSession: TabataSession?    // séance choisie (préréglage ou programme)
    @State private var showChooser = true               // écran de choix à l'arrivée

    // Programme Sport de l'utilisateur → converti en séances Tabata.
    @Query private var gymDays: [GymDay]
    private var programSessions: [TabataSession] {
        gymWeekOrder.compactMap { w -> TabataSession? in
            guard let d = gymDays.first(where: { $0.weekday == w && !$0.isRest && !$0.title.isEmpty }) else { return nil }
            let exos = d.focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !exos.isEmpty else { return nil }
            return TabataSession(id: "gym-\(d.weekday)", name: d.title, icon: "dumbbell.fill",
                                 exercises: exos, subtitle: gymWeekdayName(d.weekday))
        }
    }
    /// Toutes les séances proposées : ton programme d'abord, puis les préréglages.
    private var availableSessions: [TabataSession] { programSessions + TabataPresets.all }

    private var sessionExercises: [String] { chosenSession?.exercises ?? [] }
    /// Exercice affiché pour un round donné (boucle si plus de rounds que d'exos).
    private func exercise(forRound r: Int) -> String? {
        guard !sessionExercises.isEmpty else { return nil }
        let i = (max(1, r) - 1) % sessionExercises.count
        return sessionExercises[i]
    }
    private var currentExercise: String? { exercise(forRound: engine.round) }
    private var nextExercise: String? { exercise(forRound: engine.round + 1) }

    private var config: TabataConfig {
        // Séance = un round par exercice (6), répétés « sets » fois (4 séries par défaut).
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
        withAnimation(.easeInOut(duration: 0.25)) { showChooser = false }
    }

    /// Nom d'exercice affiché en gros (uniquement pendant l'effort).
    private var exerciseLabel: String? { engine.phase == .work ? currentExercise : nil }
    /// Sous-titre : prochain exercice pendant la prépa / le repos.
    private var phaseSubLabel: String? {
        switch engine.phase {
        case .idle:      return exercise(forRound: 1).map { "Commence par : \($0)" }
        case .prepare:   return exercise(forRound: 1).map { "Commence par : \($0)" }
        case .rest:      return nextExercise.map { "À suivre : \($0)" }
        case .restCycle: return exercise(forRound: 1).map { "À suivre : \($0)" }
        default:         return nil
        }
    }

    /// Prochain exercice (prépa / repos) pour afficher son dessin en aperçu.
    private var upcomingExercise: String? {
        switch engine.phase {
        case .idle, .prepare, .restCycle: return exercise(forRound: 1)
        case .rest:                       return nextExercise
        default:                          return nil
        }
    }

    var body: some View {
        ZStack {
            engine.phase.color.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                totalBar
                Spacer(minLength: 6)
                centerRing
                Spacer(minLength: 6)
                controlPanel
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            if showChooser { chooserOverlay.transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.25), value: engine.phase)
        .statusBarHidden()
        .onAppear { engine.cfg = config; if engine.phase == .idle { engine.remaining = prepare } }
        .onDisappear { TabataSound.shared.end() }   // libère la session audio (musique dé-duckée)
        .sheet(isPresented: $showSettings) {
            TabataSettings(prepare: $prepare, work: $work, rest: $rest, rounds: $rounds, cycles: $cycles, restCycle: $restCycle, cooldown: $cooldown, sets: $sets)
                .onDisappear { engine.cfg = config; if engine.phase == .idle { engine.remaining = prepare } }
        }
    }

    private var displayedTime: Int {
        (engine.phase == .idle) ? prepare : engine.remaining
    }

    /// Dessin (pictogramme SF Symbol) associé à un exercice / une machine.
    @ViewBuilder private func exerciseArt(_ name: String, size: CGFloat) -> some View {
        Image(systemName: exerciseSymbol(name))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(engine.phase.onColor)
            .symbolRenderingMode(.hierarchical)
            .frame(height: size)
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

    // MARK: - Temps restant total (en haut) + progression globale

    private var onColor: Color { engine.phase.onColor }

    private var globalProgress: Double {
        engine.phase == .idle ? 0 : Double(engine.totalElapsed) / Double(max(1, engine.totalDuration))
    }

    private var totalBar: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "hourglass").font(.system(size: 13, weight: .bold))
                Text("TEMPS RESTANT").font(.system(size: 12, weight: .heavy, design: .rounded)).kerning(1)
                Spacer()
                Text(formatHMS(engine.phase == .idle ? engine.totalDuration : engine.totalRemaining))
                    .font(.system(size: 30, weight: .black, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(onColor)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(onColor.opacity(0.20))
                    Capsule().fill(onColor)
                        .frame(width: max(0, geo.size.width * globalProgress))
                        .animation(.linear(duration: 0.9), value: globalProgress)
                }
            }
            .frame(height: 6)
        }
        .padding(.top, 14)
    }

    // MARK: - Anneau central (chrono de l'intervalle qui se vide)

    private var centerRing: some View {
        let working = engine.phase == .work
        return VStack(spacing: 12) {
            if let exo = exerciseLabel {
                exerciseArt(exo, size: 58)
            } else if let up = upcomingExercise {
                exerciseArt(up, size: 50).opacity(0.85)
            }
            ZStack {
                Circle().stroke(onColor.opacity(0.18), lineWidth: 13)
                Circle()
                    .trim(from: 0, to: engine.phase == .idle ? 1 : max(0.0001, engine.intervalFraction))
                    .stroke(onColor, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.95), value: engine.remaining)
                VStack(spacing: 2) {
                    Text(working ? "EXERCICE \(engine.round)/\(engine.cfg.rounds)" : engine.phase.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(onColor.opacity(0.75))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(formatHMS(displayedTime))
                        .font(.system(size: 74, weight: .black, design: .rounded)).monospacedDigit()
                        .foregroundStyle(onColor)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    if working, let exo = currentExercise {
                        Text(exo).font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(onColor).multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6).lineLimit(2)
                    } else if let sub = phaseSubLabel {
                        Text(sub).font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(onColor.opacity(0.85)).multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7).lineLimit(2)
                    }
                }
                .padding(.horizontal, 30)
            }
            .frame(width: 290, height: 290)
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.title3.bold()).foregroundStyle(engine.phase.onColor)
            }
            Spacer()
            Button { withAnimation(.easeInOut(duration: 0.25)) { showChooser = true } } label: {
                VStack(spacing: 0) {
                    Text("TABATA").font(.headline.bold()).foregroundStyle(engine.phase.onColor)
                    HStack(spacing: 4) {
                        Text((chosenSession?.name ?? "Intervalles libres").uppercased())
                            .font(.caption.weight(.bold)).foregroundStyle(engine.phase.onColor.opacity(0.75))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(engine.phase.onColor.opacity(0.6))
                    }
                }
            }
            Spacer()
            HStack(spacing: 16) {
                Button { engine.reset() } label: { Image(systemName: "arrow.counterclockwise").font(.title3.bold()) }
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").font(.title3.bold()) }
            }
            .foregroundStyle(engine.phase.onColor)
        }
        .padding(.top, 8)
    }

    // MARK: - Écran de choix de séance (à l'arrivée)

    private var chooserOverlay: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choisis ta séance").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("6 exercices · \(sets) séries").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline.bold()).foregroundStyle(.white.opacity(0.7))
                            .frame(width: 38, height: 38).background(.white.opacity(0.12), in: Circle())
                    }
                }
                .padding(.top, 12)

                quickConfigStrip

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(availableSessions) { s in
                            Button { pick(s) } label: { sessionCard(s) }
                                .buttonStyle(PressableButtonStyle())
                        }
                        Button { pick(nil) } label: { freeIntervalCard }
                            .buttonStyle(PressableButtonStyle())
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // Réglage rapide effort / repos / séries directement sur l'écran de choix.
    private var quickConfigStrip: some View {
        HStack(spacing: 10) {
            cfgStepper("EFFORT", value: $work, unit: "s", step: 5, min: 5, color: 0x9BE14E)
            cfgStepper("REPOS", value: $rest, unit: "s", step: 5, min: 0, color: 0xF0584B)
            cfgStepper("SÉRIES", value: $sets, unit: "", step: 1, min: 1, color: 0xF2A03D)
        }
    }

    private func cfgStepper(_ label: String, value: Binding<Int>, unit: String, step: Int, min: Int, color: UInt) -> some View {
        VStack(spacing: 7) {
            Text(label).font(.system(size: 11, weight: .heavy, design: .rounded)).kerning(0.5)
                .foregroundStyle(Color(hex: color))
            HStack(spacing: 10) {
                Button { Haptics.tap(); value.wrappedValue = Swift.max(min, value.wrappedValue - step) } label: {
                    Image(systemName: "minus").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(.white.opacity(0.12), in: Circle())
                }
                Text("\(value.wrappedValue)\(unit)")
                    .font(.system(size: 20, weight: .black, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white).frame(minWidth: 40)
                Button { Haptics.tap(); value.wrappedValue += step } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(.white.opacity(0.12), in: Circle())
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func sessionCard(_ s: TabataSession) -> some View {
        HStack(spacing: 14) {
            Image(systemName: s.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color(hex: 0x9BE14E).opacity(0.25), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.name).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    if let sub = s.subtitle {
                        Text(sub).font(.caption2.weight(.semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: 0x9BE14E), in: Capsule())
                    }
                }
                Text(s.exercises.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.4))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private var freeIntervalCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Intervalles libres").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text("Chrono \(work)s / \(rest)s · réglable").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.white.opacity(0.4))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private var controlPanel: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                counter("ROUNDS", engine.roundsLeft, Color(hex: 0x4FA8E0))
                Spacer()
                Button { engine.startOrPause() } label: {
                    ZStack {
                        Circle().fill(engine.phase.onColor.opacity(0.12))
                        Circle().stroke(engine.phase.onColor, lineWidth: 4)
                        Image(systemName: engine.running ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(engine.phase.onColor)
                            .offset(x: engine.running ? 0 : 3)
                    }
                    .frame(width: 96, height: 96)
                }
                Spacer()
                counter("CYCLES", engine.cyclesLeft, engine.phase.onColor)
            }
            // Navigation manuelle entre les séries (loupé/fini une série).
            HStack(spacing: 40) {
                skipButton("backward.fill", "Série préc.") { engine.skipBackward() }
                skipButton("forward.fill", "Série suiv.") { engine.skipForward() }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 14)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func skipButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .bold))
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(.white.opacity(0.14), in: Capsule())
        }
    }

    private func counter(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption.bold()).foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 90)
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
                    row(0xF2D43D, "PRÉPARATION", "Décompte avant de démarrer", $prepare, step: 5, time: true)
                    row(0x9BE14E, "EFFORT", "Durée de chaque exercice", $work, step: 5, time: true)
                    row(0xF0584B, "REPOS", "Récup entre les exercices", $rest, step: 5, time: true)
                    row(0xF2A03D, "SÉRIES", "Passages sur les 6 exercices", $sets, step: 1, time: false)
                    row(0xF2A03D, "RÉCUP ENTRE SÉRIES", "Pause entre les séries", $restCycle, step: 5, time: true)
                    row(0x4FA8E0, "RETOUR AU CALME", "Cooldown final", $cooldown, step: 5, time: true)
                }
                Section("INTERVALLES LIBRES (sans séance)") {
                    row(0x4FA8E0, "ROUNDS", "Un round = effort + repos", $rounds, step: 1, time: false)
                    row(0xF2D43D, "CYCLES", "Un cycle = N rounds", $cycles, step: 1, time: false)
                }
                Section {
                    HStack {
                        Text("Durée totale").bold()
                        Spacer()
                        Text(formatHMS(totalSeconds)).bold().foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Tabata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() }.bold() }
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
