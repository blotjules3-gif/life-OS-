import SwiftUI
import SwiftData
import AVFoundation
import MediaPlayer
import Combine
import CoreAudio
import os

// MARK: - Sons relaxants — générateur de bruit on-device (aucun fichier audio)

enum NoiseKind: String, CaseIterable, Identifiable {
    case white, pink, brown, ocean
    var id: String { rawValue }
    var label: String {
        switch self {
        case .white: return "Bruit blanc"
        case .pink:  return "Bruit rose"
        case .brown: return "Bruit brun"
        case .ocean: return "Océan"
        }
    }
    var subtitle: String {
        switch self {
        case .white: return "Spectre plat, masque les bruits"
        case .pink:  return "Plus doux que le blanc"
        case .brown: return "Grave, profond"
        case .ocean: return "Vagues lentes"
        }
    }
    var icon: String {
        switch self {
        case .white: return "waveform"
        case .pink:  return "waveform.path"
        case .brown: return "waveform.path.ecg"
        case .ocean: return "water.waves"
        }
    }
}

/// Mélange de deux couches au plus. Les niveaux sont propres à chaque couche,
/// le volume général reste celui du mixeur.
struct NoiseMix: Equatable {
    var a: NoiseKind = .pink
    var levelA: Float = 0.8
    var b: NoiseKind? = nil
    var levelB: Float = 0.4

    var label: String {
        guard let b else { return a.label }
        return "\(a.label) + \(b.label)"
    }
}

/// Réglages de départ par usage. Ce sont des combinaisons de nos propres
/// générateurs, rien de plus: aucune promesse d'effet.
enum SoundMode: String, CaseIterable, Identifiable {
    case focus, detente, sommeil
    var id: String { rawValue }
    var label: String {
        switch self {
        case .focus: return "Focus"
        case .detente: return "Détente"
        case .sommeil: return "Sommeil"
        }
    }
    var icon: String {
        switch self {
        case .focus: return "scope"
        case .detente: return "leaf"
        case .sommeil: return "moon.zzz"
        }
    }
    var mix: NoiseMix {
        switch self {
        case .focus: return NoiseMix(a: .brown, levelA: 0.8, b: .white, levelB: 0.2)
        case .detente: return NoiseMix(a: .ocean, levelA: 0.8, b: .brown, levelB: 0.3)
        case .sommeil: return NoiseMix(a: .pink, levelA: 0.7, b: .ocean, levelB: 0.4)
        }
    }
    var timerMinutes: Int { self == .sommeil ? 45 : 0 }
}

/// État d'un générateur. Une copie par couche: deux couches qui partageraient
/// le même filtre se mélangeraient dans un seul son.
struct NoiseLayerState {
    var rng: UInt32
    var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    var brownLast: Float = 0
    var lfoPhase: Float = 0

    init(seed: UInt32) { rng = seed == 0 ? 0x9E3779B9 : seed }

    @inline(__always) mutating func nextWhite() -> Float {
        // xorshift32 — rapide et sûr en temps réel
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return (Float(rng) / Float(UInt32.max)) * 2 - 1
    }

    @inline(__always) mutating func next(_ k: NoiseKind) -> Float {
        let w = nextWhite()
        switch k {
        case .white:
            return w * 0.35
        case .pink:
            // Filtre rose économique de Paul Kellet
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.1538520
            b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
            b6 = w * 0.115926
            return pink * 0.11
        case .brown:
            brownLast = (brownLast + w * 0.02)
            if brownLast > 1 { brownLast = 1 }; if brownLast < -1 { brownLast = -1 }
            return brownLast * 3.5 * 0.35
        case .ocean:
            // Bruit brun modulé par un LFO lent (≈0.08 Hz) = ressac
            brownLast = (brownLast + w * 0.02)
            if brownLast > 1 { brownLast = 1 }; if brownLast < -1 { brownLast = -1 }
            lfoPhase += 0.08 * 2 * .pi / 44100
            if lfoPhase > 2 * .pi { lfoPhase -= 2 * .pi }
            let env = 0.5 + 0.5 * sin(lfoPhase)
            return brownLast * 3.5 * env * 0.4
        }
    }
}

/// Génère le bruit en temps réel via AVAudioSourceNode. Pas d'assets, 100% calculé.
final class NoiseEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var failed = false
    @Published var volume: Float = 0.7 { didSet { engine.mainMixerNode.outputVolume = volume } }
    /// Couche principale, cote interface.
    @Published private(set) var kind: NoiseKind = .pink
    /// Le mélange voulu. Chaque changement est recopié dans `pendingMix`, seul
    /// pont vers le fil audio: lire une propriété @Published depuis le bloc temps
    /// réel pendant que le fil principal l'écrit serait une course de données.
    @Published private(set) var mix = NoiseMix() {
        didSet { let m = mix; pendingMix.withLock { $0 = m }; kind = m.a }
    }
    /// Vrai quand un appel (ou une autre app) a coupé le son. Le son reprend seul
    /// si iOS l'autorise à la fin de l'interruption.
    @Published private(set) var interrupted = false
    /// Vrai pendant le fondu de sortie qui précède l'arrêt.
    @Published private(set) var fadingOut = false
    /// Durée des fondus d'entrée et de sortie, en secondes.
    var fadeSeconds: Double = 8

    private struct GainTarget { var target: Float; var step: Float }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let pendingMix = OSAllocatedUnfairLock(initialState: NoiseMix())
    private let pendingGain = OSAllocatedUnfairLock(initialState: GainTarget(target: 1, step: 1))
    private var observers: [NSObjectProtocol] = []
    private var fadeOutWork: DispatchWorkItem?

    // Copies lues et écrites par le bloc temps réel uniquement.
    private var renderMix = NoiseMix()
    private var renderGain: Float = 0
    private var renderTarget: Float = 1
    private var renderStep: Float = 1
    private var layerA = NoiseLayerState(seed: 0x9E3779B9)
    private var layerB = NoiseLayerState(seed: 0x85EBCA6B)

    private static let sampleRate = 44100.0

    /// Ce que fait le moteur face a une notification d'interruption.
    enum InterruptionAction: Equatable { case pause, resume, forget, ignore }

    /// Decision pure, testable sans session audio.
    /// Avant, aucune interruption n'etait observee: apres un appel iOS coupait
    /// le moteur mais `isPlaying` restait vrai, l'ecran affichait "en lecture"
    /// sur du silence et le minuteur de sommeil continuait a tourner.
    static func interruptionAction(typeRaw: UInt?, optionsRaw: UInt?,
                                   isPlaying: Bool, resumePending: Bool) -> InterruptionAction {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return .ignore }
        switch type {
        case .began:
            return isPlaying ? .pause : .ignore
        case .ended:
            guard resumePending else { return .ignore }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            return options.contains(.shouldResume) ? .resume : .forget
        @unknown default:
            return .ignore
        }
    }

    init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            self?.handleInterruption(n)
        })
        // Changement de sortie (casque debranche...): AVAudioEngine s'arrete seul.
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        })
    }

    private func handleInterruption(_ n: Notification) {
        let action = Self.interruptionAction(
            typeRaw: n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            optionsRaw: n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
            isPlaying: isPlaying, resumePending: interrupted)
        switch action {
        case .pause:  tearDown(); interrupted = true
        case .resume: interrupted = false; play(mix, fadeIn: true)
        case .forget: interrupted = false
        case .ignore: break
        }
    }

    private func handleConfigurationChange() {
        guard isPlaying, !engine.isRunning else { return }
        do { try engine.start() } catch { tearDown(); failed = true }
    }

    /// Change le mélange sans couper le son.
    func setMix(_ m: NoiseMix) { mix = m }

    func play(_ k: NoiseKind) {
        var m = mix; m.a = k
        play(m, fadeIn: false)
    }

    func play(_ m: NoiseMix, fadeIn: Bool) {
        interrupted = false
        mix = m
        let step = EndloLogic.fadeStep(fadeSeconds: fadeIn ? fadeSeconds : 0.05, sampleRate: Self.sampleRate)
        if isPlaying {
            // Relance pendant un fondu de sortie: on annule l'arret et on remonte.
            if fadingOut {
                fadeOutWork?.cancel(); fadeOutWork = nil; fadingOut = false
                pendingGain.withLock { $0 = GainTarget(target: 1, step: step) }
            }
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch { failed = true; return }

        // Le bloc temps reel n'existe pas encore: on peut regler ses copies ici.
        renderGain = 0
        renderTarget = 1
        renderStep = step
        renderMix = m
        pendingGain.withLock { $0 = GainTarget(target: 1, step: step) }

        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // Jamais bloquant sur le fil audio: si le verrou est pris, on garde
            // le reglage precedent pour ce tampon.
            if let m = self.pendingMix.withLockIfAvailable({ $0 }) { self.renderMix = m }
            if let g = self.pendingGain.withLockIfAvailable({ $0 }) { self.renderTarget = g.target; self.renderStep = g.step }
            let current = self.renderMix
            for frame in 0..<Int(frameCount) {
                let a = self.layerA.next(current.a)
                let b: Float = current.b.map { self.layerB.next($0) } ?? 0
                self.renderGain = EndloLogic.advance(gain: self.renderGain, target: self.renderTarget, step: self.renderStep)
                let v = EndloLogic.mix(a, b, levelA: current.levelA, levelB: current.b == nil ? 0 : current.levelB) * self.renderGain
                for buffer in abl {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = v
                }
            }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        do {
            try engine.start()
            failed = false
            isPlaying = true
        } catch { failed = true }
    }

    /// Arret voulu par l'utilisateur: oublie aussi une reprise en attente, sinon
    /// la fin d'un appel relancerait un son qu'il a coupe. Avec `fade`, le son
    /// descend pendant `fadeSeconds` avant l'arret reel.
    func stop(fade: Bool = false) {
        interrupted = false
        guard fade, isPlaying, fadeSeconds > 0 else { tearDown(); return }
        guard !fadingOut else { return }
        fadingOut = true
        let step = EndloLogic.fadeStep(fadeSeconds: fadeSeconds, sampleRate: Self.sampleRate)
        pendingGain.withLock { $0 = GainTarget(target: 0, step: step) }
        let work = DispatchWorkItem { [weak self] in self?.tearDown() }
        fadeOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeSeconds + 0.15, execute: work)
    }

    private func tearDown() {
        fadeOutWork?.cancel(); fadeOutWork = nil
        fadingOut = false
        guard isPlaying else { return }
        engine.stop()
        if let s = source { engine.detach(s); source = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isPlaying = false
    }

    func toggle(_ k: NoiseKind) {
        if isPlaying && kind == k { stop() }
        else if isPlaying { var m = mix; m.a = k; mix = m }   // changement de son sans couper
        else { play(k) }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if isPlaying { engine.stop() }
    }
}

// MARK: - Contrôleur partagé (vit hors de l'écran)

/// Un seul moteur pour toute l'app. Avant, le moteur appartenait à l'écran et
/// `onDisappear` coupait le son: impossible d'écouter en allant dans Tâches.
/// Revenir sur l'écran retrouve ce même moteur, jamais un second.
@MainActor
final class SoundscapeController: ObservableObject {
    static let shared = SoundscapeController()

    let noise = NoiseEngine()
    @Published var mix: NoiseMix { didSet { noise.setMix(mix); persist(); updateNowPlaying() } }
    @Published var timerMinutes: Int { didSet { persist() } }
    @Published var fadeSeconds: Int { didSet { noise.fadeSeconds = Double(fadeSeconds); persist() } }
    @Published private(set) var sleepDeadline: Date?

    private var sleepWork: DispatchWorkItem?
    private var bag: Set<AnyCancellable> = []
    private var remoteReady = false
    private let defaults: UserDefaults

    static let configKey = "endlo.config"

    struct Config: Codable, Equatable {
        var a: String = NoiseKind.pink.rawValue
        var levelA: Double = 0.8
        var b: String = ""
        var levelB: Double = 0.4
        var timerMinutes: Int = 0
        var fadeSeconds: Int = 8
        var volume: Double = 0.7

        var mix: NoiseMix {
            NoiseMix(a: NoiseKind(rawValue: a) ?? .pink, levelA: Float(levelA),
                     b: NoiseKind(rawValue: b), levelB: Float(levelB))
        }
        init() {}
        init(mix: NoiseMix, timerMinutes: Int, fadeSeconds: Int, volume: Double) {
            a = mix.a.rawValue; levelA = Double(mix.levelA)
            b = mix.b?.rawValue ?? ""; levelB = Double(mix.levelB)
            self.timerMinutes = timerMinutes; self.fadeSeconds = fadeSeconds; self.volume = volume
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let cfg = (defaults.data(forKey: Self.configKey)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        mix = cfg.mix
        timerMinutes = cfg.timerMinutes
        fadeSeconds = cfg.fadeSeconds
        noise.setMix(cfg.mix)
        noise.fadeSeconds = Double(cfg.fadeSeconds)
        noise.volume = Float(cfg.volume)
        // Les changements du moteur (lecture, interruption, erreur) redessinent l'écran.
        noise.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        noise.$isPlaying.dropFirst().removeDuplicates().sink { [weak self] playing in
            guard let self else { return }
            // Le son peut s'arreter sans bouton (appel, casque): le minuteur suit
            // l'etat reel au lieu de compter sur du silence.
            if !playing { self.cancelTimer() }
            else if self.timerMinutes > 0 && self.sleepWork == nil { self.armTimer() }
            self.updateNowPlaying(playing: playing)
        }.store(in: &bag)
    }

    var volume: Float {
        get { noise.volume }
        set { noise.volume = newValue; persist() }
    }

    func persist() {
        let cfg = Config(mix: mix, timerMinutes: timerMinutes, fadeSeconds: fadeSeconds, volume: Double(noise.volume))
        if let d = try? JSONEncoder().encode(cfg) { defaults.set(d, forKey: Self.configKey) }
    }

    func start() {
        setupRemoteCommands()
        noise.fadeSeconds = Double(fadeSeconds)
        noise.play(mix, fadeIn: fadeSeconds > 0)
        if noise.isPlaying { armTimer() }
        updateNowPlaying()
    }

    func stop(fade: Bool = true) {
        cancelTimer()
        noise.stop(fade: fade)
        updateNowPlaying(playing: false)
    }

    func toggle() { noise.isPlaying && !noise.fadingOut ? stop() : start() }

    func apply(mode: SoundMode) {
        mix = mode.mix
        timerMinutes = mode.timerMinutes
        if noise.isPlaying { armTimer() }
    }

    func apply(preset: SoundMixPreset) {
        var c = Config()
        c.a = preset.kindA; c.levelA = preset.levelA; c.b = preset.kindB; c.levelB = preset.levelB
        mix = c.mix
        timerMinutes = preset.timerMinutes
        fadeSeconds = preset.fadeSeconds
        if noise.isPlaying { armTimer() }
    }

    func apply(config: Config) {
        mix = config.mix
        timerMinutes = config.timerMinutes
        fadeSeconds = config.fadeSeconds
    }

    var currentConfig: Config { Config(mix: mix, timerMinutes: timerMinutes, fadeSeconds: fadeSeconds, volume: Double(noise.volume)) }

    // MARK: minuteur de sommeil (échéance absolue, survit à la navigation)

    func armTimer() {
        cancelTimer()
        guard timerMinutes > 0 else { return }
        let seconds = Double(timerMinutes * 60)
        sleepDeadline = Date().addingTimeInterval(seconds)
        // Le fondu de sortie se termine pile a l'echeance.
        let lead = min(Double(fadeSeconds), seconds)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.noise.stop(fade: true)
            self.sleepWork = nil
            self.sleepDeadline = nil
        }
        sleepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds - lead, execute: work)
    }

    func cancelTimer() {
        sleepWork?.cancel(); sleepWork = nil
        sleepDeadline = nil
    }

    // MARK: À l'écoute / écran verrouillé

    private func updateNowPlaying(playing: Bool? = nil) {
        let isOn = playing ?? noise.isPlaying
        guard isOn || MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: mix.label,
            MPMediaItemPropertyArtist: "Endlo · LifeOS",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isOn ? 1.0 : 0.0
        ]
    }

    private func setupRemoteCommands() {
        guard !remoteReady else { return }
        remoteReady = true
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.isEnabled = true
        rc.pauseCommand.isEnabled = true
        rc.togglePlayPauseCommand.isEnabled = true
        rc.stopCommand.isEnabled = true
        rc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.start() }
            return .success
        }
        rc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop(fade: false) }
            return .success
        }
        rc.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop(fade: false) }
            return .success
        }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
    }
}

// MARK: - Vue

struct SoundscapeView: View {
    @ObservedObject private var ctl = SoundscapeController.shared
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SoundMixPreset.createdAt) private var presets: [SoundMixPreset]

    @AppStorage("endlo.schedule.on") private var scheduleOn = false
    @AppStorage("endlo.schedule.hour") private var scheduleHour = 22
    @AppStorage("endlo.schedule.minute") private var scheduleMinute = 30
    @AppStorage("endlo.schedule.config") private var scheduleConfigRaw = ""
    @AppStorage("endlo.schedule.lastAutoStart") private var lastAutoStartDay = ""
    @State private var autoStarted = false
    @State private var naming = false
    @State private var presetName = ""
    @State private var pendingDelete: SoundMixPreset?
    @State private var notifDenied = false

    private let timerOptions = [0, 15, 30, 45, 60, 90]
    private let cols = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    static let scheduleNotificationID = "endlo.schedule"

    private var noise: NoiseEngine { ctl.noise }
    private var suggested: SoundMode {
        SoundMode(rawValue: EndloLogic.suggestedModeRaw(hour: Calendar.current.component(.hour, from: .now))) ?? .focus
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    if noise.failed { errorCard }
                    if noise.interrupted { interruptedCard }
                    if autoStarted { infoCard("Séance programmée lancée.", icon: "alarm") }
                    modesCard
                    layerACard
                    layerBCard
                    timerCard
                    fadeVolumeCard
                    playBar
                    presetsCard
                    scheduleCard
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Sons relaxants").navigationBarTitleDisplayMode(.inline)
        // Plus d'arret en quittant l'ecran: le son continue (lecture persistante),
        // l'arret se fait ici, depuis l'ecran verrouille ou par le minuteur.
        .onAppear { checkAutoStart() }
        .alert("Nom du mélange", isPresented: $naming) {
            TextField("Ex. Lecture du soir", text: $presetName)
            Button("Enregistrer") { savePreset() }
            Button("Annuler", role: .cancel) { presetName = "" }
        }
        .confirmationDialog("Supprimer ce mélange ?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let p = pendingDelete { ctx.delete(p) }
                pendingDelete = nil
            }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: cartes

    private func infoCard(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var interruptedCard: some View {
        infoCard("Son coupé par un appel ou une autre app. Il reprend seul si iOS le permet, sinon relance-le.",
                 icon: "phone.arrow.down.left")
    }

    private var errorCard: some View {
        Label("Lecture audio indisponible sur cet appareil.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline).foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.warning.opacity(0.20), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var modesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Réglages de départ", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
            Text("Suggestion selon l'heure : \(suggested.label).").font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(SoundMode.allCases) { m in
                    Button {
                        ctl.apply(mode: m); Haptics.soft()
                    } label: {
                        Label(m.label, systemImage: m.icon)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(ctl.mix == m.mix ? AnyShapeStyle(Color.mindTint) : AnyShapeStyle(Theme.bg2),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(ctl.mix == m.mix ? .white : .primary)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(m == suggested ? Color.mindTint : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(m == suggested ? "Suggéré pour cette heure" : "")
                }
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var layerACard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couche 1", systemImage: "square.stack.3d.up").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(NoiseKind.allCases) { k in
                    let active = ctl.mix.a == k
                    Button {
                        var m = ctl.mix; m.a = k
                        if m.b == k { m.b = nil }
                        ctl.mix = m
                        Haptics.soft()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: k.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(Color.mindTint))
                                .frame(width: 42, height: 42)
                                .background(active ? AnyShapeStyle(Color.mindTint.gradient) : AnyShapeStyle(Theme.bg2),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.label).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(k.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .stroke(active ? Color.mindTint : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            levelSlider(title: "Niveau", value: Binding(get: { Double(ctl.mix.levelA) },
                                                        set: { var m = ctl.mix; m.levelA = Float($0); ctl.mix = m }))
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var layerBCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Couche 2", systemImage: "square.stack.3d.up.fill").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Couche 2", selection: Binding(get: { ctl.mix.b?.rawValue ?? "" },
                                                      set: { var m = ctl.mix; m.b = NoiseKind(rawValue: $0); ctl.mix = m })) {
                    Text("Aucune").tag("")
                    ForEach(NoiseKind.allCases.filter { $0 != ctl.mix.a }) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.menu).tint(.mindTint)
            }
            if ctl.mix.b != nil {
                levelSlider(title: "Niveau", value: Binding(get: { Double(ctl.mix.levelB) },
                                                            set: { var m = ctl.mix; m.levelB = Float($0); ctl.mix = m }))
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func levelSlider(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: 0...1).tint(.mindTint)
            Text("\(Int((value.wrappedValue * 100).rounded())) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Minuteur de sommeil", systemImage: "moon.zzz.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let end = ctl.sleepDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(formatHMS(Int(end.timeIntervalSinceNow.rounded(.up))))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.mindTint)
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(timerOptions, id: \.self) { m in
                    Button {
                        ctl.timerMinutes = m
                        if noise.isPlaying { ctl.armTimer() }
                        Haptics.soft()
                    } label: {
                        Text(m == 0 ? "∞" : "\(m)m")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(ctl.timerMinutes == m ? AnyShapeStyle(Color.mindTint) : AnyShapeStyle(Theme.bg2),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(ctl.timerMinutes == m ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m == 0 ? "Sans minuteur" : "\(m) minutes")
                }
            }
            Text("Le son baisse en fondu et s'arrête à la fin du minuteur.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var fadeVolumeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: $ctl.fadeSeconds, in: 0...30, step: 2) {
                Label(ctl.fadeSeconds == 0 ? "Fondu : aucun" : "Fondu : \(ctl.fadeSeconds) s", systemImage: "waveform.path.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
            Label("Volume", systemImage: "speaker.wave.3.fill").font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { ctl.volume }, set: { ctl.volume = $0 }), in: 0...1).tint(.mindTint)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var playBar: some View {
        let playing = noise.isPlaying && !noise.fadingOut
        return Button {
            ctl.toggle()
            Haptics.soft()
        } label: {
            Label(playing ? "Arrêter" : "Lancer \(ctl.mix.label)",
                  systemImage: playing ? "stop.fill" : "play.fill")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(playing ? AnyShapeStyle(Theme.danger.gradient) : AnyShapeStyle(Color.mindTint.gradient),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Mes mélanges", systemImage: "bookmark").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Enregistrer") { presetName = ""; naming = true }.font(.subheadline)
            }
            if presets.isEmpty {
                Text("Enregistre le mélange actuel pour le retrouver, même hors ligne.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(presets) { p in
                HStack {
                    Button {
                        ctl.apply(preset: p); Haptics.soft()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                            Text(presetSummary(p)).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) { pendingDelete = p } label: { Image(systemName: "trash").font(.caption) }
                        .foregroundStyle(Theme.danger.opacity(0.7))
                        .accessibilityLabel("Supprimer \(p.name)")
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func presetSummary(_ p: SoundMixPreset) -> String {
        var c = SoundscapeController.Config()
        c.a = p.kindA; c.b = p.kindB
        let timer = p.timerMinutes > 0 ? " · \(p.timerMinutes) min" : ""
        return c.mix.label + timer
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { scheduleOn }, set: { on in Task { await setSchedule(on) } })) {
                Label("Séance programmée", systemImage: "alarm").font(.subheadline.weight(.semibold))
            }
            .tint(.mindTint)
            if scheduleOn {
                DatePicker("Heure", selection: scheduleTime, displayedComponents: .hourAndMinute)
                Text("Chaque jour à cette heure, une notification ouvre Endlo et lance le mélange enregistré (\(scheduledLabel)). iOS ne permet pas de démarrer le son sans que tu touches la notification.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Button("Utiliser le mélange actuel") { saveScheduledConfig(); Haptics.soft() }.font(.subheadline)
            }
            if notifDenied {
                Text("Les notifications sont refusées pour LifeOS.").font(.caption).foregroundStyle(Theme.warning)
                Button("Ouvrir Réglages") { MindNotifications.openSettings() }.font(.subheadline)
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .task { notifDenied = await MindNotifications.isDenied() }
    }

    private var scheduleTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: scheduleHour, minute: scheduleMinute, second: 0, of: .now) ?? .now
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            scheduleHour = c.hour ?? 22; scheduleMinute = c.minute ?? 30
            reschedule()
        })
    }

    private var scheduledConfig: SoundscapeController.Config? {
        scheduleConfigRaw.data(using: .utf8).flatMap { try? JSONDecoder().decode(SoundscapeController.Config.self, from: $0) }
    }

    private var scheduledLabel: String { (scheduledConfig ?? ctl.currentConfig).mix.label }

    private func saveScheduledConfig() {
        if let d = try? JSONEncoder().encode(ctl.currentConfig), let s = String(data: d, encoding: .utf8) {
            scheduleConfigRaw = s
        }
        reschedule()
    }

    private func setSchedule(_ on: Bool) async {
        guard on else {
            scheduleOn = false
            NotificationManager.shared.cancel(id: Self.scheduleNotificationID)
            return
        }
        let granted = await MindNotifications.ensureAuthorized()
        notifDenied = !granted
        guard granted else { scheduleOn = false; return }
        scheduleOn = true
        if scheduledConfig == nil { saveScheduledConfig() } else { reschedule() }
    }

    private func reschedule() {
        guard scheduleOn else { return }
        MindNotifications.scheduleDaily(id: Self.scheduleNotificationID, title: "Endlo",
                                        body: "C'est l'heure de ta séance : \(scheduledLabel). Touche pour lancer.",
                                        hour: scheduleHour, minute: scheduleMinute, route: "endlo")
    }

    private func checkAutoStart() {
        guard EndloLogic.shouldAutoStart(enabled: scheduleOn, hour: scheduleHour, minute: scheduleMinute,
                                         lastAutoStartDay: lastAutoStartDay, isPlaying: noise.isPlaying, now: .now) else { return }
        lastAutoStartDay = MindDay.key(.now)
        if let cfg = scheduledConfig { ctl.apply(config: cfg) }
        ctl.start()
        autoStarted = true
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let c = ctl.currentConfig
        ctx.insert(SoundMixPreset(name: name, kindA: c.a, levelA: c.levelA, kindB: c.b, levelB: c.levelB,
                                  timerMinutes: c.timerMinutes, fadeSeconds: c.fadeSeconds))
        presetName = ""
    }
}
