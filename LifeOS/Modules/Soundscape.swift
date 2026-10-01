import SwiftUI
import AVFoundation
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
        case .white: return "Concentration, masque les bruits"
        case .pink:  return "Doux, équilibré — sommeil"
        case .brown: return "Grave, profond — détente"
        case .ocean: return "Vagues lentes — endormissement"
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

/// Génère le bruit en temps réel via AVAudioSourceNode. Pas d'assets, 100% calculé.
final class NoiseEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var failed = false
    @Published var volume: Float = 0.7 { didSet { engine.mainMixerNode.outputVolume = volume } }
    /// Le son choisi, cote interface. Chaque changement est recopie dans
    /// `pendingKind`, seul pont vers le fil audio: lire `kind` (un @Published)
    /// depuis le bloc temps reel pendant que le fil principal l'ecrit etait une
    /// course de donnees.
    @Published private(set) var kind: NoiseKind = .pink {
        didSet { let k = kind; pendingKind.withLock { $0 = k } }
    }
    /// Vrai quand un appel (ou une autre app) a coupe le son. Le son reprend seul
    /// si iOS l'autorise a la fin de l'interruption.
    @Published private(set) var interrupted = false

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let pendingKind = OSAllocatedUnfairLock(initialState: NoiseKind.pink)
    /// Copie lue par le bloc temps reel uniquement.
    private var renderKind: NoiseKind = .pink
    private var observers: [NSObjectProtocol] = []

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
        case .resume: interrupted = false; play(kind)
        case .forget: interrupted = false
        case .ignore: break
        }
    }

    private func handleConfigurationChange() {
        guard isPlaying, !engine.isRunning else { return }
        do { try engine.start() } catch { tearDown(); failed = true }
    }

    // État des générateurs (touché uniquement par le bloc temps réel)
    private var rng: UInt32 = 0x9E3779B9
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brownLast: Float = 0
    private var lfoPhase: Float = 0

    @inline(__always) private func nextWhite() -> Float {
        // xorshift32 — rapide et sûr en temps réel
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return (Float(rng) / Float(UInt32.max)) * 2 - 1
    }

    @inline(__always) private func nextSample(_ k: NoiseKind) -> Float {
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

    func play(_ k: NoiseKind) {
        interrupted = false
        kind = k
        if isPlaying { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch { failed = true; return }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // Jamais bloquant sur le fil audio: si le verrou est pris, on garde
            // le son precedent pour ce tampon.
            if let k = self.pendingKind.withLockIfAvailable({ $0 }) { self.renderKind = k }
            let current = self.renderKind
            for frame in 0..<Int(frameCount) {
                let v = self.nextSample(current)
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
    /// la fin d'un appel relancerait un son qu'il a coupe.
    func stop() {
        interrupted = false
        tearDown()
    }

    private func tearDown() {
        guard isPlaying else { return }
        engine.stop()
        if let s = source { engine.detach(s); source = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isPlaying = false
    }

    func toggle(_ k: NoiseKind) {
        if isPlaying && kind == k { stop() }
        else if isPlaying { kind = k }   // changement de son sans couper
        else { play(k) }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if isPlaying { engine.stop() }
    }
}

// MARK: - Vue

struct SoundscapeView: View {
    @StateObject private var noise = NoiseEngine()
    @State private var selected: NoiseKind = .pink
    @State private var timerMinutes = 0      // 0 = illimité
    @State private var sleepTask: DispatchWorkItem?
    @State private var remaining = 0
    @State private var ticker: Timer?

    private let timerOptions = [0, 15, 30, 45, 60]
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    if noise.failed { errorCard }
                    if noise.interrupted { interruptedCard }
                    soundGrid
                    timerCard
                    volumeCard
                    playBar
                }
                .padding()
            }
        }
        .navigationTitle("Sons relaxants").navigationBarTitleDisplayMode(.inline)
        .onDisappear { noise.stop(); cancelTimer() }
        // Le son peut s'arreter sans bouton (appel, casque): le minuteur suit
        // l'etat reel au lieu de compter sur du silence.
        .onChange(of: noise.isPlaying) { _, playing in
            if !playing { cancelTimer() }
            else if timerMinutes > 0 && sleepTask == nil { armTimer() }
        }
    }

    private var interruptedCard: some View {
        Label("Son coupé par un appel ou une autre app. Il reprend seul si iOS le permet, sinon relance-le.",
              systemImage: "phone.arrow.down.left")
            .font(.subheadline).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.bg2, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var errorCard: some View {
        Label("Lecture audio indisponible sur cet appareil.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline).foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.warning.opacity(0.20), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var soundGrid: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(NoiseKind.allCases) { k in
                let active = noise.isPlaying && noise.kind == k
                Button {
                    selected = k
                    noise.toggle(k)
                    if noise.isPlaying { armTimer() } else { cancelTimer() }
                    Haptics.soft()
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: k.icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(Color.mindTint))
                            .frame(width: 56, height: 56)
                            .background(active ? AnyShapeStyle(Color.mindTint.gradient) : AnyShapeStyle(Theme.bg2),
                                       in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                if active {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white).padding(5)
                                        .background(Circle().fill(Color.mindTint))
                                        .offset(x: 4, y: 4)
                                }
                            }
                        Text(k.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        Text(k.subtitle).font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .stroke(active ? Color.mindTint : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Minuteur de sommeil", systemImage: "moon.zzz.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if noise.isPlaying && timerMinutes > 0 {
                    Text(timeString(remaining)).font(.subheadline.monospacedDigit())
                        .foregroundStyle(.mindTint)
                }
            }
            HStack(spacing: 8) {
                ForEach(timerOptions, id: \.self) { m in
                    Button {
                        timerMinutes = m
                        if noise.isPlaying { armTimer() }
                        Haptics.soft()
                    } label: {
                        Text(m == 0 ? "∞" : "\(m)m")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(timerMinutes == m ? AnyShapeStyle(Color.mindTint) : AnyShapeStyle(Theme.bg2),
                                       in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(timerMinutes == m ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Volume", systemImage: "speaker.wave.3.fill").font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                Slider(value: $noise.volume, in: 0...1).tint(.mindTint)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var playBar: some View {
        Button {
            if noise.isPlaying { noise.stop(); cancelTimer() }
            else { noise.play(selected); armTimer() }
            Haptics.soft()
        } label: {
            Label(noise.isPlaying ? "Arrêter" : "Lancer \(selected.label)",
                  systemImage: noise.isPlaying ? "stop.fill" : "play.fill")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(noise.isPlaying ? AnyShapeStyle(Theme.danger.gradient) : AnyShapeStyle(Color.mindTint.gradient),
                           in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: minuteur

    private func armTimer() {
        cancelTimer()
        guard timerMinutes > 0 else { return }
        remaining = timerMinutes * 60
        let work = DispatchWorkItem { noise.stop(); cancelTimer() }
        sleepTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(timerMinutes * 60), execute: work)
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remaining > 0 { remaining -= 1 } else { cancelTimer() }
        }
    }
    private func cancelTimer() {
        sleepTask?.cancel(); sleepTask = nil
        ticker?.invalidate(); ticker = nil
        remaining = 0
    }
    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}
