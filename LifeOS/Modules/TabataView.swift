import SwiftUI
import Combine

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
    var round: Int = 1
    var cycle: Int = 1
    var running = false

    private var cancellable: AnyCancellable?

    init(cfg: TabataConfig) {
        self.cfg = cfg
        self.remaining = cfg.prepare
    }

    var roundsLeft: Int { max(0, cfg.rounds - round + 1) }
    var cyclesLeft: Int { max(0, cfg.cycles - cycle + 1) }

    func startOrPause() {
        if phase == .idle || phase == .done { begin() }
        else if running { pause() }
        else { run() }
    }

    func begin() {
        phase = .prepare; remaining = cfg.prepare; round = 1; cycle = 1
        Haptics.tap(); run()
    }

    func reset() {
        pause(); phase = .idle; remaining = cfg.prepare; round = 1; cycle = 1
    }

    private func run() {
        running = true
        cancellable = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }
    private func pause() { running = false; cancellable?.cancel() }

    private func tick() {
        if remaining > 1 { remaining -= 1; return }
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
            cycle += 1; round = 1
            enter(.work, cfg.work)
        case .cooldown:
            finish()
        }
    }

    private func enter(_ p: Phase, _ secs: Int) {
        phase = p
        remaining = max(1, secs)
        if secs <= 0 { advance() }
    }
    private func finish() { pause(); phase = .done; remaining = 0 }
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

    @State private var engine = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15, rounds: 8, cycles: 1, restCycle: 60, cooldown: 0))
    @State private var showSettings = false

    private var config: TabataConfig {
        TabataConfig(prepare: prepare, work: work, rest: rest, rounds: rounds, cycles: cycles, restCycle: restCycle, cooldown: cooldown)
    }

    var body: some View {
        ZStack {
            engine.phase.color.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                // Phase + chrono géant
                VStack(spacing: 4) {
                    Text(engine.phase.title)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(engine.phase.onColor)
                    Text(formatHMS(displayedTime))
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(engine.phase.onColor)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                Spacer()
                controlPanel
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
        .animation(.easeInOut(duration: 0.25), value: engine.phase)
        .statusBarHidden()
        .onAppear { engine.cfg = config; if engine.phase == .idle { engine.remaining = prepare } }
        .sheet(isPresented: $showSettings) {
            TabataSettings(prepare: $prepare, work: $work, rest: $rest, rounds: $rounds, cycles: $cycles, restCycle: $restCycle, cooldown: $cooldown)
                .onDisappear { engine.cfg = config; if engine.phase == .idle { engine.remaining = prepare } }
        }
    }

    private var displayedTime: Int {
        (engine.phase == .idle) ? prepare : engine.remaining
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.title3.bold()).foregroundStyle(engine.phase.onColor)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("TABATA").font(.headline.bold()).foregroundStyle(engine.phase.onColor)
                Text("\(work):\(rest)").font(.subheadline.weight(.semibold)).foregroundStyle(engine.phase.onColor.opacity(0.7))
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

    private var controlPanel: some View {
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
        .padding(.vertical, 26)
        .padding(.horizontal, 14)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    var body: some View {
        NavigationStack {
            List {
                Section("INTERVALLES") {
                    row(0xF2D43D, "PRÉPARATION", "Décompte avant de démarrer", $prepare, step: 5, time: true)
                    row(0x9BE14E, "EFFORT", "Durée de chaque exercice", $work, step: 5, time: true)
                    row(0xF0584B, "REPOS", "Récup entre les rounds", $rest, step: 5, time: true)
                    row(0x4FA8E0, "ROUNDS", "Un round = effort + repos", $rounds, step: 1, time: false)
                    row(0xF2D43D, "CYCLES", "Un cycle = N rounds", $cycles, step: 1, time: false)
                    row(0xF2A03D, "RÉCUP ENTRE CYCLES", "Pause entre les cycles", $restCycle, step: 5, time: true)
                    row(0x4FA8E0, "RETOUR AU CALME", "Cooldown final", $cooldown, step: 5, time: true)
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
