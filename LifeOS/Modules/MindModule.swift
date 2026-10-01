import SwiftUI
import SwiftData
import AVFoundation
import Combine
import UserNotifications
import UniformTypeIdentifiers
import PhotosUI

extension ShapeStyle where Self == Color { static var mindTint: Color { AppCategory.mind.tint } }

// MARK: - Outils communs (rappels, voix, cloche)

enum MindNotifications {
    /// Requete quotidienne qui ouvre l'outil au toucher (`userInfo["route"]`).
    /// Construite a part pour etre testable sans centre de notifications.
    static func makeDailyRequest(id: String, title: String, body: String,
                                 hour: Int, minute: Int, route: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": route]
        var comps = DateComponents()
        comps.hour = hour; comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    static func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int, route: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(makeDailyRequest(id: id, title: title, body: body, hour: hour, minute: minute, route: route))
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Demande l'autorisation si besoin. Faux = refus (l'ecran l'affiche avec un lien vers Reglages).
    static func ensureAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return await NotificationManager.shared.requestAuthorization()
        }
    }

    @MainActor static func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }
}

/// Rappel quotidien d'un outil: interrupteur, heure, et refus affiche avec une sortie.
struct MindReminderCard: View {
    let id: String
    let label: String
    let title: String
    let message: String
    let route: String
    @AppStorage private var enabled: Bool
    @AppStorage private var hour: Int
    @AppStorage private var minute: Int
    @State private var denied = false

    init(id: String, label: String, title: String, message: String, route: String, defaultHour: Int) {
        self.id = id; self.label = label; self.title = title; self.message = message; self.route = route
        _enabled = AppStorage(wrappedValue: false, "\(id).reminder.on")
        _hour = AppStorage(wrappedValue: defaultHour, "\(id).reminder.hour")
        _minute = AppStorage(wrappedValue: 0, "\(id).reminder.minute")
    }

    private var notificationID: String { "\(id).daily" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { enabled }, set: { on in Task { await set(on) } })) {
                Label(label, systemImage: "bell").font(.subheadline.weight(.semibold))
            }
            .tint(.mindTint)
            if enabled {
                DatePicker("Heure", selection: time, displayedComponents: .hourAndMinute)
            }
            if denied {
                Text("Les notifications sont refusées pour LifeOS : le rappel ne peut pas sonner.")
                    .font(.caption).foregroundStyle(Theme.warning)
                Button("Ouvrir Réglages") { MindNotifications.openSettings() }.font(.subheadline)
            }
        }
        .card()
        .task { denied = await MindNotifications.isDenied() }
    }

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            hour = c.hour ?? hour; minute = c.minute ?? 0
            schedule()
        })
    }

    private func set(_ on: Bool) async {
        guard on else {
            enabled = false
            NotificationManager.shared.cancel(id: notificationID)
            return
        }
        let ok = await MindNotifications.ensureAuthorized()
        denied = !ok
        enabled = ok
        if ok { schedule() }
    }

    private func schedule() {
        guard enabled else { return }
        MindNotifications.scheduleDaily(id: notificationID, title: title, body: message,
                                        hour: hour, minute: minute, route: route)
    }
}

/// Voix francaise du telephone (AVSpeechSynthesizer), coupee a chaque nouvelle consigne.
@MainActor
final class MindSpeech {
    static let shared = MindSpeech()
    private let synth = AVSpeechSynthesizer()
    func say(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synth.speak(u)
    }
    func stop() { synth.stopSpeaking(at: .immediate) }
}

/// Cloche synthetisee sur l'appareil (aucun fichier audio): trois partiels qui decroissent.
@MainActor
final class MindBell {
    static let shared = MindBell()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?

    func ring() {
        do {
            if buffer == nil {
                guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else { return }
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                buffer = Self.makeBuffer(format: format)
            }
            let session = AVAudioSession.sharedInstance()
            // Ne change pas la categorie si un autre son de l'app joue deja en lecture.
            if session.category != .playback {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
            if let buffer { player.scheduleBuffer(buffer, at: nil, options: .interrupts); player.play() }
        } catch {
            // Son indisponible: la vibration reste comme repere.
            Haptics.medium()
        }
    }

    static func makeBuffer(format: AVAudioFormat, seconds: Double = 4) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        let sr = Float(format.sampleRate)
        let partials: [(freq: Float, amp: Float, decay: Float)] = [(528, 0.5, 1.2), (1457, 0.22, 2.4), (2851, 0.1, 4.0)]
        for i in 0..<Int(frames) {
            let t = Float(i) / sr
            let attack = min(1, t / 0.005)
            var v: Float = 0
            for p in partials { v += p.amp * sin(2 * .pi * p.freq * t) * exp(-p.decay * t) }
            data[i] = v * attack * 0.6
        }
        return buf
    }
}

// MARK: - Respiration / cohérence cardiaque (Breathwerk)

struct BreathingView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BreathPattern.createdAt) private var custom: [BreathPattern]
    @Query(sort: \BreathSessionLog.date, order: .reverse) private var logs: [BreathSessionLog]

    @AppStorage("breath.selected") private var selectedID = BreathTechnique.coherence.id
    @AppStorage("breath.favorites") private var favoritesRaw = ""
    @AppStorage("breath.minutes") private var totalMinutes = 5
    @AppStorage("breath.rounds") private var rounds = 10
    @AppStorage("breath.useRounds") private var useRounds = false
    @AppStorage("breath.voice") private var voiceOn = false

    @State private var query = ""
    @State private var run: BreathRun?
    @State private var runItem: BreathLibrary.Item?
    @State private var scale: CGFloat = 0.5
    @State private var label = "Prêt"
    @State private var currentPhase: BreathPhase?
    @State private var editing: BreathPattern?
    @State private var creating = false
    @State private var pendingDelete: BreathPattern?
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var favorites: Set<String> { BreathLibrary.decodeFavorites(favoritesRaw) }
    private var library: [BreathLibrary.Item] { BreathLibrary.items(custom: custom) }
    private var selected: BreathLibrary.Item? { library.first { $0.id == selectedID } ?? library.first }

    /// Une seance abandonnee tot n'encombre pas l'historique; une seance finie y va toujours.
    static func shouldLog(completed: Bool, activeSeconds: Int) -> Bool { completed || activeSeconds >= 20 }

    var body: some View {
        ZStack {
            Theme.background
            if run != nil { runningView } else { setupView }
        }
        .navigationTitle("Respiration").navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { _ in advance() }
        // Quitter l'app met en pause: au retour on reprend dans la meme phase.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, run?.isPaused == false { run?.pause(at: Date()) }
        }
        .sheet(isPresented: $creating) { BreathPatternEditor(pattern: nil) }
        .sheet(item: $editing) { BreathPatternEditor(pattern: $0) }
        .confirmationDialog("Supprimer cette technique ?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let p = pendingDelete {
                    var f = favorites; f.remove(p.key); favoritesRaw = BreathLibrary.encodeFavorites(f)
                    if selectedID == p.key { selectedID = BreathTechnique.coherence.id }
                    ctx.delete(p)
                }
                pendingDelete = nil
            }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        } message: { Text("L'historique de ses séances est conservé.") }
    }

    // MARK: Préparation

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 16) {
                libraryCard
                if let item = selected { configCard(item) }
                statsCard
                MindReminderCard(id: "breath", label: "Rappel quotidien", title: "Respiration",
                                 message: "Quelques minutes pour respirer.", route: "breathwerk", defaultHour: 13)
            }
            .padding(Theme.pad)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $query, prompt: "Chercher une technique")
    }

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Techniques", actionTitle: "Créer") { creating = true }
            let items = BreathLibrary.filter(library, query: query, favorites: favorites)
            if items.isEmpty {
                Text("Aucune technique ne correspond à « \(query) ».").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Button { selectedID = item.id; Haptics.soft() } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.id == selected?.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(.mindTint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text(item.summary).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item.id == selected?.id ? .isSelected : [])
                    Button { toggleFavorite(item.id) } label: {
                        Image(systemName: favorites.contains(item.id) ? "star.fill" : "star")
                    }
                    .foregroundStyle(.mindTint)
                    .accessibilityLabel(favorites.contains(item.id) ? "Retirer des favoris" : "Ajouter aux favoris")
                    if item.isCustom, let p = custom.first(where: { $0.key == item.id }) {
                        Menu {
                            Button("Modifier", systemImage: "pencil") { editing = p }
                            Button("Supprimer", systemImage: "trash", role: .destructive) { pendingDelete = p }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .foregroundStyle(.mindTint)
                        .accessibilityLabel("Options de \(item.name)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .card()
    }

    private func toggleFavorite(_ id: String) {
        var f = favorites
        if f.contains(id) { f.remove(id) } else { f.insert(id) }
        favoritesRaw = BreathLibrary.encodeFavorites(f)
        Haptics.tap()
    }

    private func configCard(_ item: BreathLibrary.Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.name).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(BreathLibrary.rhythm(item.phases)).font(.caption).foregroundStyle(Theme.textSecondary)
            if item.rounds > 0 {
                Text("\(item.rounds) rondes prévues par la technique.").font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                Picker("Mode", selection: $useRounds) {
                    Text("Durée").tag(false)
                    Text("Rondes").tag(true)
                }
                .pickerStyle(.segmented)
                if useRounds {
                    Stepper("Rondes : \(rounds)", value: $rounds, in: 1...60)
                } else {
                    Stepper("Durée : \(totalMinutes) min", value: $totalMinutes, in: 1...30)
                }
            }
            Toggle(isOn: $voiceOn) { Label("Consignes à voix haute", systemImage: "speaker.wave.2") }.tint(.mindTint)
            Text("Une vibration marque chaque phase (réglage Sons et vibrations du profil).")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
            PrimaryButton(title: "Commencer", icon: "play.fill", tint: .mindTint) { start(item) }
        }
        .card()
    }

    private var statsCard: some View {
        let done = logs.filter(\.completed)
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now)
        let weekSeconds = logs.filter { week?.contains($0.date) ?? false }.reduce(0) { $0 + $1.activeSeconds }
        let streak = MindStats.streak(dates: logs.map(\.date))
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Progression")
            if logs.isEmpty {
                Text("Tes séances apparaîtront ici : durée, technique et série de jours.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                HStack {
                    stat("\(weekSeconds / 60) min", "cette semaine")
                    stat("\(streak) j", "série")
                    stat("\(done.count)", "terminées")
                }
                ForEach(logs.prefix(8)) { l in
                    HStack {
                        Image(systemName: l.completed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(l.completed ? Theme.success : Theme.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.patternName).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            Text(l.date, format: .dateTime.weekday().day().month().hour().minute())
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(formatHMS(l.activeSeconds)).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            Text(caption).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Séance

    private var runningView: some View {
        VStack(spacing: 24) {
            if let item = runItem { Text(item.name).font(.headline).foregroundStyle(Theme.textSecondary) }
            ZStack {
                Circle().fill(Color.mindTint.opacity(0.15)).frame(width: 260, height: 260)
                Circle().fill(Color.mindTint.opacity(0.5))
                    .frame(width: 240, height: 240)
                    // Reduire les animations: le cercle reste fixe, les consignes restent.
                    .scaleEffect(reduceMotion ? 0.75 : scale)
                VStack(spacing: 6) {
                    Text(label).font(.title2.bold()).foregroundStyle(.white)
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        if let r = run {
                            let rem = r.position(atElapsed: r.elapsed(at: ctx.date)).phaseRemaining
                            Text("\(Int(rem.rounded(.up)))").font(.title3.monospacedDigit()).foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.updatesFrequently)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if let r = run {
                    VStack(spacing: 4) {
                        Text("Ronde \(min(r.totalRounds, r.completedRounds(at: ctx.date) + 1)) sur \(r.totalRounds)")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                        Text("Reste \(formatHMS(Int((r.totalSeconds - r.elapsed(at: ctx.date)).rounded(.up))))")
                            .font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            HStack(spacing: 12) {
                if run?.isPaused == true {
                    PrimaryButton(title: "Reprendre", icon: "play.fill", tint: .mindTint) { resume() }
                } else {
                    PrimaryButton(title: "Pause", icon: "pause.fill", tint: .mindTint) { pause() }
                }
                PrimaryButton(title: "Arrêter", icon: "stop.fill", tint: Theme.bg2) { finish(completed: false) }
            }
        }
        .padding()
        .frame(maxWidth: 520)
    }

    private func start(_ item: BreathLibrary.Item) {
        var r = BreathRun(phases: item.phases, rounds: item.rounds > 0 ? item.rounds : (useRounds ? rounds : 0),
                          minutes: totalMinutes)
        runItem = item
        scale = 0.5
        let events = r.start(at: Date())
        run = r
        handle(events)
    }

    private func pause() {
        run?.pause(at: Date())
        label = "En pause"
        MindSpeech.shared.stop()
    }

    private func resume() {
        run?.resume(at: Date())
        if let p = currentPhase { label = p.kind.label }
    }

    private func advance() {
        guard var r = run, !r.isPaused else { return }
        let events = r.tick(at: Date())
        run = r
        handle(events)
    }

    private func handle(_ events: [BreathRun.Event]) {
        for e in events {
            switch e {
            case .phase(let p, _):
                currentPhase = p
                label = p.kind.label
                if let target = p.kind.targetScale, !reduceMotion {
                    withAnimation(.easeInOut(duration: Double(p.seconds))) { scale = CGFloat(target) }
                }
                cue(p)
            case .finished:
                Haptics.success()
                finish(completed: true)
            }
        }
    }

    /// Repere de phase: vibration propre a chaque type, voix si choisie, sinon
    /// annonce VoiceOver (pour ne pas doubler la voix).
    private func cue(_ p: BreathPhase) {
        switch p.kind {
        case .inhale: Haptics.medium()
        case .topUp: Haptics.tap()
        case .exhale: Haptics.soft()
        case .holdFull, .holdEmpty: Haptics.tap()
        }
        if voiceOn {
            MindSpeech.shared.say(p.kind.label)
        } else if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: "\(p.kind.label), \(p.seconds) secondes")
        }
    }

    private func finish(completed: Bool) {
        guard let r = run, let item = runItem else { run = nil; return }
        let now = Date()
        let active = Int(r.elapsed(at: now).rounded())
        if Self.shouldLog(completed: completed, activeSeconds: active) {
            ctx.insert(BreathSessionLog(patternKey: item.id, patternName: item.name, activeSeconds: active,
                                        rounds: r.completedRounds(at: now), completed: completed))
        }
        // Remise a zero AVANT tout autre tick: la fin ne peut s'ecrire qu'une fois.
        run = nil; runItem = nil; currentPhase = nil
        label = "Prêt"; scale = 0.5
        MindSpeech.shared.stop()
        if completed && voiceOn { MindSpeech.shared.say("Séance terminée") }
    }
}

/// Creer ou modifier une technique: nom, phases (type + secondes), rondes.
struct BreathPatternEditor: View {
    let pattern: BreathPattern?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phases: [BreathPhase] = [.init(kind: .inhale, seconds: 4), .init(kind: .exhale, seconds: 6)]
    @State private var rounds = 0
    @State private var loaded = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !phases.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") { TextField("Ex. Expiration longue", text: $name) }
                Section {
                    ForEach(phases.indices, id: \.self) { i in
                        HStack {
                            Picker("Phase", selection: $phases[i].kind) {
                                ForEach(BreathPhaseKind.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            Spacer()
                            Stepper("\(phases[i].seconds) s", value: $phases[i].seconds, in: 1...30)
                                .fixedSize()
                        }
                    }
                    .onDelete { phases.remove(atOffsets: $0) }
                    .onMove { phases.move(fromOffsets: $0, toOffset: $1) }
                    Button("Ajouter une phase", systemImage: "plus") { phases.append(.init(kind: .exhale, seconds: 4)) }
                } header: { Text("Phases d'un cycle") } footer: {
                    Text("Cycle : \(phases.reduce(0) { $0 + $1.seconds }) s")
                }
                Section {
                    Stepper(rounds == 0 ? "Rondes : au choix" : "Rondes : \(rounds)", value: $rounds, in: 0...60)
                } footer: { Text("Au choix : tu règles la durée ou le nombre de rondes avant chaque séance.") }
            }
            .navigationTitle(pattern == nil ? "Nouvelle technique" : "Modifier").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.disabled(!canSave) }
            }
            .onAppear {
                guard !loaded, let p = pattern else { loaded = true; return }
                name = p.name; phases = p.phases; rounds = p.rounds; loaded = true
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let p = pattern {
            p.name = n; p.phases = phases; p.rounds = rounds
        } else {
            ctx.insert(BreathPattern(name: n, phases: phases, rounds: rounds))
        }
        dismiss()
    }
}

// MARK: - Méditation (Headplace)

/// Dossier des audios importes par l'utilisateur.
enum MindAudioFiles {
    static var directory: URL {
        // Racine propre a LifeOS (jamais le ~/Documents de l'utilisateur sur Mac):
        // sauvegardee et videe avec le reste par FullBackup et DataEraser.
        let dir = AppPaths.documents.appendingPathComponent("MindAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func url(_ fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    enum ImportError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Ce fichier audio n'est pas lisible." }
    }

    /// Copie le fichier choisi dans l'app et lit sa duree. Un fichier illisible est retire.
    static func importFile(from src: URL) throws -> (fileName: String, title: String, duration: Double) {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let ext = src.pathExtension.isEmpty ? "m4a" : src.pathExtension
        let name = "medit-\(UUID().uuidString).\(ext)"
        let dest = url(name)
        try FileManager.default.copyItem(at: src, to: dest)
        do {
            let player = try AVAudioPlayer(contentsOf: dest)
            guard player.duration > 0 else { throw ImportError.unreadable }
            return (name, src.deletingPathExtension().lastPathComponent, player.duration)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw ImportError.unreadable
        }
    }
}

/// Lecteur des audios importes. Il vit hors de l'ecran: la lecture continue
/// telephone verrouille (mode audio en arriere plan) et reprend a la position gardee.
@MainActor
final class MeditationAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MeditationAudioPlayer()
    @Published private(set) var current: MeditationAudio?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published var errorMessage: String?
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var tickCount = 0
    private var startedAt: Double = 0
    private var interrupted = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let opts = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in self?.handleInterruption(typeRaw: type, optionsRaw: opts) }
        }
    }

    var duration: Double { player?.duration ?? current?.durationSeconds ?? 0 }

    func play(_ audio: MeditationAudio) {
        if current?.uid == audio.uid, player != nil { resume(); return }
        stop(log: true)
        let url = MindAudioFiles.url(audio.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Le fichier de « \(audio.title) » est introuvable. Supprime-le et importe-le à nouveau."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            // Reprise: on repart de la position gardee, sauf si elle est a la toute fin.
            let resumeAt = audio.resumePosition < p.duration - 2 ? audio.resumePosition : 0
            p.currentTime = resumeAt
            startedAt = resumeAt
            player = p
            current = audio
            errorMessage = nil
            p.play()
            isPlaying = true
            startTicker()
        } catch {
            errorMessage = "Lecture impossible de « \(audio.title) »."
        }
    }

    func pause() {
        player?.pause(); isPlaying = false
        savePosition()
    }

    func resume() {
        guard let p = player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        p.play(); isPlaying = true; startTicker()
    }

    func seek(by delta: Double) {
        guard let p = player else { return }
        p.currentTime = max(0, min(p.duration - 0.5, p.currentTime + delta))
        position = p.currentTime
        savePosition()
    }

    func seek(to t: Double) {
        guard let p = player else { return }
        p.currentTime = max(0, min(p.duration - 0.5, t)); position = p.currentTime
    }

    /// Arret: garde la position et inscrit l'ecoute si elle a dure au moins une minute.
    func stop(log: Bool) {
        guard let p = player, let audio = current else { return }
        let listened = max(0, p.currentTime - startedAt)
        savePosition()
        p.stop()
        if log, listened >= 60 {
            audio.modelContext?.insert(MeditationLog(kind: "audio", title: audio.title, seconds: Int(listened),
                                                     completed: false, sourceKey: "audio.\(audio.uid)"))
        }
        reset()
    }

    /// Fichier supprime: on coupe sans rien ecrire.
    func forget(uid: String) { if current?.uid == uid { player?.stop(); reset() } }

    private func reset() {
        ticker?.invalidate(); ticker = nil
        player = nil; current = nil; isPlaying = false; position = 0
    }

    private func savePosition() {
        guard let p = player, let audio = current else { return }
        audio.resumePosition = p.currentTime
        position = p.currentTime
    }

    private func startTicker() {
        ticker?.invalidate()
        tickCount = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Minuteur pose sur la boucle principale: on y est deja.
            MainActor.assumeIsolated {
                guard let self, let p = self.player else { return }
                self.position = p.currentTime
                self.tickCount += 1
                // Position gardee toutes les 5 s: un arret brutal ne fait perdre que quelques secondes.
                if self.tickCount % 5 == 0 { self.current?.resumePosition = p.currentTime }
            }
        }
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            if isPlaying { pause(); interrupted = true }
        case .ended:
            guard interrupted else { return }
            interrupted = false
            if AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0).contains(.shouldResume) { resume() }
        @unknown default: break
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.didFinish(success: flag) }
    }

    private func didFinish(success: Bool) {
        guard let audio = current else { return }
        if success {
            audio.resumePosition = 0
            audio.modelContext?.insert(MeditationLog(kind: "audio", title: audio.title,
                                                     seconds: Int(max(0, audio.durationSeconds - startedAt)),
                                                     completed: true, sourceKey: "audio.\(audio.uid)"))
            MindBell.shared.ring()
        }
        reset()
    }
}

struct MeditationView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \MeditationTimerPreset.createdAt) private var presets: [MeditationTimerPreset]
    @Query(sort: \MeditationAudio.importedAt) private var audios: [MeditationAudio]
    @Query(sort: \MeditationLog.date, order: .reverse) private var logs: [MeditationLog]
    @ObservedObject private var audioPlayer = MeditationAudioPlayer.shared

    @State private var minutes = 10
    @State private var engine = CountdownEngine(key: "meditation")
    @AppStorage("meditation.currentRun") private var currentRunRaw = ""
    @State private var bellsRung = 0
    @State private var query = ""
    @State private var maxMinutes: Int?
    @State private var creatingPreset = false
    @State private var editingPreset: MeditationTimerPreset?
    @State private var importing = false
    @State private var importError: String?
    @State private var pendingDeleteAudio: MeditationAudio?
    @State private var pendingDeletePreset: MeditationTimerPreset?
    private let secondTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// L'etat "en cours" vient du moteur, pas d'un @State local.
    /// Avant, `started` repartait a faux en revenant sur l'ecran alors que le moteur
    /// restaure tournait encore: bouton "Méditer" sur un cadran qui defile, et un
    /// appui relancait la seance de zero.
    private var started: Bool { engine.isRunning }

    static let endNotificationID = "medi"
    static let bellPrefix = "medi.bell."

    /// Delai avant la fin de seance, ou nil si rien n'est en cours.
    /// La notification de fin est planifiee A L'AVANCE sur ce delai: l'ancienne
    /// version la posait dans onFinish, qui ne tourne que dans le minuteur de
    /// l'app au premier plan, donc telephone verrouille aucun signal n'arrivait.
    static func endAlertDelay(deadline: Date?, now: Date = Date()) -> TimeInterval? {
        guard let deadline else { return nil }
        let d = deadline.timeIntervalSince(now)
        return d > 0 ? d : nil
    }

    private var storedRun: MeditationLogic.StoredRun? {
        currentRunRaw.data(using: .utf8).flatMap { try? JSONDecoder().decode(MeditationLogic.StoredRun.self, from: $0) }
    }

    private var libraryItems: [MeditationLogic.LibraryItem] {
        presets.map { .init(id: "preset.\($0.uid)", title: $0.name, minutes: $0.minutes, isFavorite: $0.isFavorite, isAudio: false) }
        + audios.map { .init(id: "audio.\($0.uid)", title: $0.title, minutes: Int(($0.durationSeconds / 60).rounded(.up)),
                             isFavorite: $0.isFavorite, isAudio: true) }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    if started { runningCard }
                    else if audioPlayer.current != nil { playerCard }
                    else { quickCard }
                    if let err = audioPlayer.errorMessage ?? importError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                    if !started { recommendationCard }
                    if !started { libraryCard }
                    historyCard
                    MindReminderCard(id: "meditation", label: "Rappel quotidien", title: "Méditation",
                                     message: "Un moment pour méditer.", route: "headplace", defaultHour: 8)
                    Text("Méditations guidées, histoires et musiques : pas de catalogue dans LifeOS. Importe tes propres audios.")
                        .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .padding(Theme.pad)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Méditation").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Chercher dans mes séances")
        .onAppear { reconcile() }
        .onChange(of: scenePhase) { _, p in if p == .active { reconcile() } }
        .onReceive(secondTick) { _ in ringIntervalBellIfDue() }
        .sheet(isPresented: $creatingPreset) { MeditationPresetEditor(preset: nil) }
        .sheet(item: $editingPreset) { MeditationPresetEditor(preset: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            importAudio(result)
        }
        .confirmationDialog("Supprimer cet audio ?",
                            isPresented: Binding(get: { pendingDeleteAudio != nil }, set: { if !$0 { pendingDeleteAudio = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let a = pendingDeleteAudio {
                    audioPlayer.forget(uid: a.uid)
                    try? FileManager.default.removeItem(at: MindAudioFiles.url(a.fileName))
                    ctx.delete(a)
                }
                pendingDeleteAudio = nil
            }
            Button("Annuler", role: .cancel) { pendingDeleteAudio = nil }
        } message: { Text("Le fichier est retiré de LifeOS. L'historique est conservé.") }
        .confirmationDialog("Supprimer ce minuteur ?",
                            isPresented: Binding(get: { pendingDeletePreset != nil }, set: { if !$0 { pendingDeletePreset = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let p = pendingDeletePreset { ctx.delete(p) }
                pendingDeletePreset = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletePreset = nil }
        }
    }

    // MARK: cartes

    private var quickCard: some View {
        VStack(spacing: 16) {
            Picker("Durée", selection: $minutes) {
                ForEach([3, 5, 10, 15, 20], id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            TimerDial(engine: engine, tint: .mindTint, caption: "\(minutes) min")
            PrimaryButton(title: "Méditer", icon: "play.fill", tint: .mindTint) {
                startTimer(title: "Séance libre \(minutes) min", sourceKey: "quick.\(minutes)", minutes: minutes,
                           interval: 0, startBell: true, endBell: true)
            }
        }
        .card()
    }

    private var runningCard: some View {
        VStack(spacing: 16) {
            if let run = storedRun { Text(run.title).font(.headline).foregroundStyle(Theme.textSecondary) }
            TimerDial(engine: engine, tint: .mindTint, caption: "Respire et observe")
            if let run = storedRun, run.intervalMinutes > 0 {
                Text("Cloche toutes les \(run.intervalMinutes) min").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            PrimaryButton(title: "Terminer", icon: "stop.fill", tint: Theme.bg2) { stopTimer() }
        }
        .card()
    }

    private var playerCard: some View {
        VStack(spacing: 12) {
            if let a = audioPlayer.current {
                Text(a.title).font(.headline).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                Slider(value: Binding(get: { audioPlayer.position }, set: { audioPlayer.seek(to: $0) }),
                       in: 0...max(1, audioPlayer.duration)).tint(.mindTint)
                    .accessibilityLabel("Position de lecture")
                HStack {
                    Text(formatHMS(Int(audioPlayer.position))).font(.caption.monospacedDigit())
                    Spacer()
                    Text(formatHMS(Int(audioPlayer.duration))).font(.caption.monospacedDigit())
                }
                .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 28) {
                    Button { audioPlayer.seek(by: -15) } label: { Image(systemName: "gobackward.15").font(.title2) }
                        .accessibilityLabel("Reculer de 15 secondes")
                    Button { audioPlayer.isPlaying ? audioPlayer.pause() : audioPlayer.resume() } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 52))
                    }
                    .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Lecture")
                    Button { audioPlayer.seek(by: 15) } label: { Image(systemName: "goforward.15").font(.title2) }
                        .accessibilityLabel("Avancer de 15 secondes")
                }
                .foregroundStyle(.mindTint)
                Button("Arrêter la lecture") { audioPlayer.stop(log: true) }.font(.subheadline)
            }
        }
        .card()
    }

    private var recommendationCard: some View {
        let available = Set(libraryItems.map(\.id) + [3, 5, 10, 15, 20].map { "quick.\($0)" })
        let key = MeditationLogic.recommend(logs: logs.map { ($0.sourceKey, $0.date) }, available: available, now: .now)
        return Group {
            if let key {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Pour maintenant", subtitle: "D'après tes séances habituelles à cette heure")
                    HStack {
                        Text(title(for: key)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button("Lancer") { launch(key) }.buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.mindTint)
                    }
                }
                .card()
            }
        }
    }

    private var libraryCard: some View {
        let items = MeditationLogic.filter(libraryItems, query: query, maxMinutes: maxMinutes)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Mes séances")
            HStack(spacing: 8) {
                Button("Nouveau minuteur", systemImage: "timer") { creatingPreset = true }
                    .buttonStyle(LifeOSGlassButtonStyle()).tint(.mindTint)
                Button("Importer un audio", systemImage: "square.and.arrow.down") { importing = true }
                    .buttonStyle(LifeOSGlassButtonStyle()).tint(.mindTint)
            }
            .font(.subheadline)
            Picker("Durée", selection: $maxMinutes) {
                Text("Toutes").tag(Int?.none)
                Text("≤ 5 min").tag(Int?.some(5))
                Text("≤ 10 min").tag(Int?.some(10))
                Text("≤ 20 min").tag(Int?.some(20))
            }
            .pickerStyle(.segmented)
            if libraryItems.isEmpty {
                Text("Crée un minuteur avec ses cloches, ou importe un audio depuis Fichiers (une méditation que tu possèdes, un enregistrement).")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else if items.isEmpty {
                Text("Aucune séance ne correspond.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.isAudio ? "waveform" : "timer").foregroundStyle(.mindTint).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        Text(subtitle(for: item)).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button { toggleFavorite(item.id) } label: { Image(systemName: item.isFavorite ? "star.fill" : "star") }
                        .foregroundStyle(.mindTint)
                        .accessibilityLabel(item.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
                    Menu {
                        Button("Lancer", systemImage: "play.fill") { launch(item.id) }
                        if let p = preset(item.id) { Button("Modifier", systemImage: "pencil") { editingPreset = p } }
                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                            if let p = preset(item.id) { pendingDeletePreset = p }
                            if let a = audio(item.id) { pendingDeleteAudio = a }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .foregroundStyle(.mindTint)
                    .accessibilityLabel("Options de \(item.title)")
                }
                .contentShape(Rectangle())
                .onTapGesture { launch(item.id) }
                .padding(.vertical, 4)
            }
        }
        .card()
    }

    private var historyCard: some View {
        let counted = logs.filter { $0.completed || $0.seconds >= 60 }
        let total = counted.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Historique")
            if counted.isEmpty {
                Text("Tes séances terminées apparaîtront ici, avec ta série de jours.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                HStack {
                    statBox("\(MindStats.streak(dates: counted.map(\.date))) j", "série")
                    statBox("\(total / 60) min", "au total")
                    statBox("\(counted.count)", "séances")
                }
                ForEach(counted.prefix(8)) { l in
                    HStack {
                        Image(systemName: l.completed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(l.completed ? Theme.success : Theme.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.title).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            Text(l.date, format: .dateTime.weekday().day().month().hour().minute())
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(formatHMS(l.seconds)).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }

    private func statBox(_ v: String, _ c: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            Text(c).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: actions

    private func preset(_ id: String) -> MeditationTimerPreset? { presets.first { "preset.\($0.uid)" == id } }
    private func audio(_ id: String) -> MeditationAudio? { audios.first { "audio.\($0.uid)" == id } }

    private func title(for key: String) -> String {
        if let p = preset(key) { return p.name }
        if let a = audio(key) { return a.title }
        if key.hasPrefix("quick."), let m = Int(key.dropFirst(6)) { return "Séance libre \(m) min" }
        return key
    }

    private func subtitle(for item: MeditationLogic.LibraryItem) -> String {
        if let p = preset(item.id) {
            var s = "\(p.minutes) min"
            if p.intervalMinutes > 0 { s += " · cloche toutes les \(p.intervalMinutes) min" }
            return s
        }
        if let a = audio(item.id) {
            let resume = a.resumePosition > 5 ? " · reprise à \(formatHMS(Int(a.resumePosition)))" : ""
            return formatHMS(Int(a.durationSeconds)) + resume
        }
        return ""
    }

    private func toggleFavorite(_ id: String) {
        if let p = preset(id) { p.isFavorite.toggle() }
        if let a = audio(id) { a.isFavorite.toggle() }
        Haptics.tap()
    }

    private func launch(_ key: String) {
        if let p = preset(key) {
            audioPlayer.stop(log: true)
            startTimer(title: p.name, sourceKey: key, minutes: p.minutes, interval: p.intervalMinutes,
                       startBell: p.startBell, endBell: p.endBell)
        } else if let a = audio(key) {
            guard !started else { return }
            audioPlayer.play(a)
        } else if key.hasPrefix("quick."), let m = Int(key.dropFirst(6)) {
            startTimer(title: "Séance libre \(m) min", sourceKey: key, minutes: m, interval: 0, startBell: true, endBell: true)
        }
    }

    private func startTimer(title: String, sourceKey: String, minutes: Int, interval: Int, startBell: Bool, endBell: Bool) {
        let seconds = minutes * 60
        engine.start(seconds: seconds)
        guard let deadline = engine.deadline else { return }
        let run = MeditationLogic.StoredRun(title: title, sourceKey: sourceKey, totalSeconds: seconds,
                                            deadline: deadline, intervalMinutes: interval, endBell: endBell)
        if let d = try? JSONEncoder().encode(run) { currentRunRaw = String(data: d, encoding: .utf8) ?? "" }
        engine.onFinish = { finishRun(completed: true, ringBell: true) }
        bellsRung = 0
        if let delay = Self.endAlertDelay(deadline: deadline) {
            NotificationManager.shared.scheduleAfter(id: Self.endNotificationID, title: "Séance terminée", body: "Reviens en douceur.", seconds: delay)
        }
        // Cloches intermediaires aussi en notification: elles sonnent telephone verrouille.
        for (i, offset) in MeditationLogic.intervalOffsets(totalSeconds: seconds, intervalMinutes: interval).prefix(30).enumerated() {
            NotificationManager.shared.scheduleAfter(id: "\(Self.bellPrefix)\(i)", title: "Cloche",
                                                     body: "\(offset / 60) min écoulées", seconds: TimeInterval(offset))
        }
        if startBell { MindBell.shared.ring() }
    }

    private func stopTimer() {
        let total = storedRun?.totalSeconds ?? 0
        let elapsed = max(0, total - engine.remaining)
        engine.stop()
        // Arret avant la fin: la notification ne doit plus sonner.
        NotificationManager.shared.cancel(id: Self.endNotificationID)
        NotificationManager.shared.cancelWithPrefix(Self.bellPrefix)
        finishRun(completed: false, ringBell: false, elapsed: elapsed)
    }

    /// Inscrit la seance stockee une seule fois (on l'efface en premier), puis sonne.
    private func finishRun(completed: Bool, ringBell: Bool, elapsed: Int? = nil) {
        guard let run = storedRun else { return }
        currentRunRaw = ""
        let seconds = completed ? run.totalSeconds : (elapsed ?? 0)
        if completed || seconds >= 60 {
            ctx.insert(MeditationLog(kind: "minuteur", title: run.title, seconds: seconds,
                                     completed: completed, sourceKey: run.sourceKey))
        }
        if completed && ringBell && run.endBell && scenePhase == .active { MindBell.shared.ring() }
    }

    /// Au retour: rattrape une seance finie app fermee ou en arriere plan.
    private func reconcile() {
        engine.onFinish = { finishRun(completed: true, ringBell: true) }
        engine.refresh()
        if MeditationLogic.isFinished(storedRun, engineRunning: engine.isRunning, now: Date()) {
            finishRun(completed: true, ringBell: false)
        } else if !engine.isRunning, storedRun != nil {
            // Moteur arrete sans echeance passee (etat incoherent): on oublie la seance.
            currentRunRaw = ""
        }
        if let run = storedRun {
            // Les cloches deja passees ont sonne en notification: on ne les rejoue pas.
            let elapsed = run.totalSeconds - engine.remaining
            bellsRung = MeditationLogic.intervalOffsets(totalSeconds: run.totalSeconds, intervalMinutes: run.intervalMinutes)
                .filter { $0 <= elapsed }.count
        }
    }

    private func ringIntervalBellIfDue() {
        guard started, let run = storedRun, run.intervalMinutes > 0 else { return }
        let elapsed = run.totalSeconds - engine.remaining
        let due = MeditationLogic.intervalOffsets(totalSeconds: run.totalSeconds, intervalMinutes: run.intervalMinutes)
            .filter { $0 <= elapsed }.count
        if due > bellsRung { bellsRung = due; MindBell.shared.ring() }
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .failure(let e): importError = e.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let f = try MindAudioFiles.importFile(from: url)
                ctx.insert(MeditationAudio(title: f.title, fileName: f.fileName, durationSeconds: f.duration))
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

/// Minuteur personnel: duree, cloche de debut, cloches intermediaires, cloche de fin.
struct MeditationPresetEditor: View {
    let preset: MeditationTimerPreset?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minutes = 10
    @State private var interval = 0
    @State private var startBell = true
    @State private var endBell = true
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") { TextField("Ex. Assise du matin", text: $name) }
                Section("Durée") { Stepper("\(minutes) min", value: $minutes, in: 1...120) }
                Section {
                    Toggle("Cloche de début", isOn: $startBell)
                    Stepper(interval == 0 ? "Cloches intermédiaires : aucune" : "Cloche toutes les \(interval) min",
                            value: $interval, in: 0...max(0, minutes - 1))
                    Toggle("Cloche de fin", isOn: $endBell)
                } header: { Text("Cloches") } footer: {
                    Text("Téléphone verrouillé, les cloches arrivent en notification.")
                }
            }
            .navigationTitle(preset == nil ? "Nouveau minuteur" : "Modifier").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded, let p = preset else { loaded = true; return }
                name = p.name; minutes = p.minutes; interval = p.intervalMinutes
                startBell = p.startBell; endBell = p.endBell; loaded = true
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let iv = min(interval, max(0, minutes - 1))
        if let p = preset {
            p.name = n; p.minutes = minutes; p.intervalMinutes = iv; p.startBell = startBell; p.endBell = endBell
        } else {
            ctx.insert(MeditationTimerPreset(name: n, minutes: minutes, intervalMinutes: iv, startBell: startBell, endBell: endBell))
        }
        dismiss()
    }
}

// MARK: - Humeur & gratitude (Daylia)

/// Brouillon d'une entree, partage par l'ajout et la modification.
struct MoodDraft: Equatable {
    var date = Date()
    var score = 3
    var moodUID = ""
    var activityUIDs: Set<String> = []
    var note = ""
    var gratitude = ""
    var photoData: Data?
    var existingPhoto = ""
    var removePhoto = false
}

enum MoodStyle {
    static let faces = ["😞", "🙁", "😐", "🙂", "😄"]
    static func face(_ score: Int) -> String { faces[max(0, min(4, score - 1))] }
    static func color(_ avg: Double) -> Color {
        // Rouge (1) vers vert (5).
        let t = max(0, min(1, (avg - 1) / 4))
        return Color(hue: 0.0 + 0.33 * t, saturation: 0.65, brightness: 0.85)
    }
}

/// Formulaire d'entree: niveau, humeur nommee, activites, photo, date, note, gratitude.
struct MoodEntryForm: View {
    @Binding var draft: MoodDraft
    let activities: [MoodActivity]
    let customMoods: [MoodCustomMood]
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        draft.score = i
                        if let m = customMoods.first(where: { $0.uid == draft.moodUID }), m.score != i { draft.moodUID = "" }
                        Haptics.tap()
                    } label: {
                        Text(MoodStyle.face(i)).font(.largeTitle).opacity(draft.score == i ? 1 : 0.4)
                            .scaleEffect(draft.score == i ? 1.2 : 1)
                    }
                    .accessibilityLabel("Niveau \(i) sur 5")
                    .accessibilityAddTraits(draft.score == i ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            if !customMoods.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(customMoods) { m in
                        chip("\(m.emoji) \(m.name)", selected: draft.moodUID == m.uid) {
                            if draft.moodUID == m.uid { draft.moodUID = "" } else { draft.moodUID = m.uid; draft.score = m.score }
                        }
                    }
                }
            }
            let visible = activities.filter { !$0.isArchived || draft.activityUIDs.contains($0.uid) }
            if !visible.isEmpty {
                Text("Activités").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                FlowLayout(spacing: 6) {
                    ForEach(visible) { a in
                        chip("\(a.emoji) \(a.name)", selected: draft.activityUIDs.contains(a.uid)) {
                            if draft.activityUIDs.contains(a.uid) { draft.activityUIDs.remove(a.uid) } else { draft.activityUIDs.insert(a.uid) }
                        }
                    }
                }
            }
            DatePicker("Date", selection: $draft.date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline)
            TextField("Une note sur ta journée…", text: $draft.note, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
            TextField("Gratitude : 1 chose positive", text: $draft.gratitude, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(hasPhoto ? "Changer la photo" : "Ajouter une photo", systemImage: "photo")
                }
                if hasPhoto {
                    Spacer()
                    Button("Retirer", role: .destructive) { draft.photoData = nil; draft.removePhoto = true }
                }
            }
            .font(.subheadline)
            if let data = draft.photoData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 10))
            } else if !draft.removePhoto, let img = ImageStore.load(draft.existingPhoto.isEmpty ? nil : draft.existingPhoto) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // Recompressee en JPEG: une photo HEIC de 4 Mo ne doit pas gonfler la base.
                    let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.75) ?? data
                    await MainActor.run { draft.photoData = jpeg; draft.removePhoto = false }
                }
            }
        }
    }

    private var hasPhoto: Bool { draft.photoData != nil || (!draft.existingPhoto.isEmpty && !draft.removePhoto) }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.tap() }) {
            Text(text).font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(Color.mindTint) : AnyShapeStyle(Theme.bg2), in: Capsule())
                .foregroundStyle(selected ? .white : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lecture et ecriture des entrees avec leur complement. Toute la logique de lien
/// (date unique, photo, suppression) passe par ici, pour l'ajout comme pour la modification.
enum MoodStore {
    static func extra(for entry: MoodEntry, in extras: [MoodEntryExtra]) -> MoodEntryExtra? {
        extras.first { MoodAnalytics.sameInstant($0.entryDate, entry.date) }
    }

    @discardableResult
    static func insert(_ d: MoodDraft, existingDates: [Date], ctx: ModelContext) -> MoodEntry {
        let date = MoodAnalytics.uniqueDate(d.date, existing: existingDates)
        let e = MoodEntry(date: date, score: d.score, note: d.note, gratitude: d.gratitude)
        ctx.insert(e)
        let photo = d.photoData.flatMap { ImageStore.save($0, prefix: "mood") } ?? ""
        if !d.moodUID.isEmpty || !d.activityUIDs.isEmpty || !photo.isEmpty {
            ctx.insert(MoodEntryExtra(entryDate: date, moodUID: d.moodUID, activityUIDs: d.activityUIDs.sorted(), photoFileName: photo))
        }
        return e
    }

    static func update(_ e: MoodEntry, with d: MoodDraft, extras: [MoodEntryExtra], otherDates: [Date], ctx: ModelContext) {
        let ex = extra(for: e, in: extras)
        let newDate = MoodAnalytics.sameInstant(d.date, e.date) ? e.date : MoodAnalytics.uniqueDate(d.date, existing: otherDates)
        e.date = newDate; e.score = d.score; e.note = d.note; e.gratitude = d.gratitude
        var photo = ex?.photoFileName ?? ""
        if d.removePhoto || d.photoData != nil {
            if !photo.isEmpty { ImageStore.delete(photo) }
            photo = ""
        }
        if let data = d.photoData { photo = ImageStore.save(data, prefix: "mood") ?? "" }
        if let ex {
            ex.entryDate = newDate; ex.moodUID = d.moodUID; ex.activityUIDs = d.activityUIDs.sorted(); ex.photoFileName = photo
        } else if !d.moodUID.isEmpty || !d.activityUIDs.isEmpty || !photo.isEmpty {
            ctx.insert(MoodEntryExtra(entryDate: newDate, moodUID: d.moodUID, activityUIDs: d.activityUIDs.sorted(), photoFileName: photo))
        }
    }

    static func delete(_ e: MoodEntry, extras: [MoodEntryExtra], ctx: ModelContext) {
        if let ex = extra(for: e, in: extras) {
            if !ex.photoFileName.isEmpty { ImageStore.delete(ex.photoFileName) }
            ctx.delete(ex)
        }
        ctx.delete(e)
    }

    static func draft(for e: MoodEntry, extras: [MoodEntryExtra]) -> MoodDraft {
        let ex = extra(for: e, in: extras)
        return MoodDraft(date: e.date, score: e.score, moodUID: ex?.moodUID ?? "",
                         activityUIDs: Set(ex?.activityUIDs ?? []), note: e.note, gratitude: e.gratitude,
                         photoData: nil, existingPhoto: ex?.photoFileName ?? "")
    }
}

struct MoodJournalView: View {
    enum Mode: String, CaseIterable, Identifiable { case list = "Liste", month = "Mois", year = "Année"; var id: String { rawValue } }

    @Environment(\.modelContext) private var ctx
    @Query(sort: \MoodEntry.date, order: .reverse) private var entries: [MoodEntry]
    @Query private var extras: [MoodEntryExtra]
    @Query(sort: \MoodActivity.createdAt) private var activities: [MoodActivity]
    @Query(sort: \MoodCustomMood.createdAt) private var customMoods: [MoodCustomMood]
    @AppStorage("daylia.goalDays") private var goalDays = 0

    @State private var draft = MoodDraft()
    @State private var pendingDelete: MoodEntry?
    @State private var editing: MoodEntry?
    @State private var mode: Mode = .list
    @State private var query = ""
    @State private var activityFilter: String?
    @State private var scoreFilter: Int?
    @State private var dayFilter: String?
    @State private var monthAnchor = Date()
    @State private var yearAnchor = Calendar.current.component(.year, from: .now)
    @State private var showManage = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var rows: [(entry: MoodEntry, row: MoodAnalytics.Row)] {
        entries.map { e in
            let ex = MoodStore.extra(for: e, in: extras)
            let mood = customMoods.first { $0.uid == ex?.moodUID }
            return (e, MoodAnalytics.Row(date: e.date, score: e.score, note: e.note, gratitude: e.gratitude,
                                         moodName: mood.map { "\($0.emoji) \($0.name)" } ?? "",
                                         activities: ex?.activityUIDs ?? []))
        }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    formCard
                    if entries.isEmpty {
                        emptyState
                    } else {
                        Picker("Vue", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented)
                        switch mode {
                        case .list: listCard
                        case .month: monthCard
                        case .year: yearCard
                        }
                        associationsCard
                        goalCard
                        exportCard
                    }
                    MindReminderCard(id: "daylia", label: "Rappel quotidien", title: "Humeur",
                                     message: "Comment s'est passée ta journée ?", route: "daylia", defaultHour: 21)
                }
                .padding(Theme.pad)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Humeur & gratitude").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showManage = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Humeurs et activités")
            }
        }
        .sheet(isPresented: $showManage) { MoodManageSheet() }
        .sheet(item: $editing) { e in
            MoodEntryEditor(entry: e, extras: extras, activities: activities, customMoods: customMoods,
                            otherDates: entries.filter { $0 !== e }.map(\.date))
        }
        // Un seul appui sur la corbeille effacait l'entree, sans retour possible.
        .confirmationDialog("Supprimer cette entrée ?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let e = pendingDelete { MoodStore.delete(e, extras: extras, ctx: ctx) }
                pendingDelete = nil
            }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Cette action est définitive.")
        }
    }

    private var formCard: some View {
        VStack(spacing: 14) {
            Text("Comment tu te sens ?").font(.headline).foregroundStyle(Theme.textPrimary)
            MoodEntryForm(draft: $draft, activities: activities, customMoods: customMoods)
            PrimaryButton(title: "Enregistrer", icon: "checkmark", tint: .mindTint) {
                MoodStore.insert(draft, existingDates: entries.map(\.date), ctx: ctx)
                draft = MoodDraft()
                Haptics.success()
            }
        }
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 32)).foregroundStyle(.mindTint)
            Text("Suis ton humeur chaque jour").font(.headline).foregroundStyle(Theme.textPrimary)
            // On ne promet que ce que l'ecran calcule vraiment.
            Text("Tes entrées apparaîtront ici en liste, en mois et en année. Avec assez d'entrées, l'écran compare ton humeur avec et sans chaque activité.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.mindTint.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    // MARK: liste + filtres

    private var listCard: some View {
        let all = rows
        let byDay = dayFilter.map { key in all.filter { MindDay.key($0.row.date) == key } } ?? all
        let kept = Set(MoodAnalytics.filter(byDay.map(\.row), query: query, activityUID: activityFilter, score: scoreFilter).map(\.date))
        let shown = byDay.filter { kept.contains($0.row.date) }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Historique", subtitle: "Humeur moyenne : \(avgText(shown.map(\.row)))")
            TextField("Chercher dans les notes", text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Menu {
                    Button("Toutes les activités") { activityFilter = nil }
                    ForEach(activities) { a in Button("\(a.emoji) \(a.name)") { activityFilter = a.uid } }
                } label: {
                    Label(activities.first { $0.uid == activityFilter }?.name ?? "Activité", systemImage: "line.3.horizontal.decrease.circle")
                }
                Menu {
                    Button("Tous les niveaux") { scoreFilter = nil }
                    ForEach(1...5, id: \.self) { s in Button("\(MoodStyle.face(s)) \(s)/5") { scoreFilter = s } }
                } label: {
                    Label(scoreFilter.map { "\(MoodStyle.face($0)) \($0)/5" } ?? "Niveau", systemImage: "face.smiling")
                }
                Spacer()
                if dayFilter != nil || activityFilter != nil || scoreFilter != nil || !query.isEmpty {
                    Button("Effacer") { dayFilter = nil; activityFilter = nil; scoreFilter = nil; query = "" }
                }
            }
            .font(.subheadline).tint(.mindTint)
            if let d = dayFilter { Text("Jour : \(d)").font(.caption).foregroundStyle(Theme.textSecondary) }
            if shown.isEmpty {
                Text("Aucune entrée ne correspond.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(shown.prefix(60), id: \.row.date) { item in
                entryRow(item.entry, item.row)
            }
            if shown.count > 60 {
                Text("\(shown.count - 60) entrées plus anciennes : affine les filtres.").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private func entryRow(_ e: MoodEntry, _ r: MoodAnalytics.Row) -> some View {
        let ex = MoodStore.extra(for: e, in: extras)
        let names = r.activities.compactMap { uid in activities.first { $0.uid == uid }.map { "\($0.emoji) \($0.name)" } }
        return HStack(alignment: .top) {
            Text(MoodStyle.face(e.score)).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.date, format: .dateTime.weekday().day().month().hour().minute()).font(.caption).foregroundStyle(Theme.textSecondary)
                if !r.moodName.isEmpty { Text(r.moodName).font(.caption.weight(.semibold)).foregroundStyle(.mindTint) }
                if !e.note.isEmpty { Text(e.note).font(.subheadline).foregroundStyle(Theme.textPrimary) }
                if !e.gratitude.isEmpty { Label(e.gratitude, systemImage: "infinity").font(.caption).foregroundStyle(.mindTint) }
                if !names.isEmpty { Text(names.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.textSecondary) }
                if let p = ex?.photoFileName, !p.isEmpty, let img = ImageStore.load(p) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer()
            Menu {
                Button("Modifier", systemImage: "pencil") { editing = e }
                Button("Supprimer", systemImage: "trash", role: .destructive) { pendingDelete = e }
            } label: { Image(systemName: "ellipsis.circle") }
            .foregroundStyle(.mindTint)
            .accessibilityLabel("Options de l'entrée")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { editing = e }
    }

    private func avgText(_ rs: [MoodAnalytics.Row]) -> String {
        guard let a = MoodAnalytics.average(rs) else { return "—" }
        return String(format: "%.1f/5", a).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: mois / année

    private var monthCard: some View {
        let cal = Calendar.current
        let avgs = MoodAnalytics.dailyAverages(rows.map(\.row))
        let interval = cal.dateInterval(of: .month, for: monthAnchor)
        let first = interval?.start ?? monthAnchor
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        // Lundi en premier.
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 10) {
            HStack {
                Button { monthAnchor = cal.date(byAdding: .month, value: -1, to: monthAnchor) ?? monthAnchor } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Mois précédent")
                Spacer()
                Text(first, format: .dateTime.month(.wide).year()).font(.headline)
                Spacer()
                Button { monthAnchor = cal.date(byAdding: .month, value: 1, to: monthAnchor) ?? monthAnchor } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Mois suivant")
            }
            .tint(.mindTint)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) { i in
                    Text(["L", "M", "M", "J", "V", "S", "D"][i]).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                ForEach(0..<lead, id: \.self) { i in Color.clear.frame(height: 36).id("lead\(i)") }
                ForEach(1...days, id: \.self) { d in
                    let date = cal.date(byAdding: .day, value: d - 1, to: first) ?? first
                    let key = MindDay.key(date)
                    let avg = avgs[key]
                    Button {
                        guard avg != nil else { return }
                        dayFilter = key; mode = .list
                    } label: {
                        Text("\(d)").font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(avg.map { MoodStyle.color($0) } ?? Theme.bg2, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(avg == nil ? Theme.textSecondary : .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(avg.map { "\(d), humeur moyenne \(String(format: "%.1f", $0))" } ?? "\(d), aucune entrée")
                }
            }
            Text("Touche un jour pour voir ses entrées.").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private var yearCard: some View {
        let cal = Calendar.current
        let avgs = MoodAnalytics.dailyAverages(rows.map(\.row))
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 31)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { yearAnchor -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Année précédente")
                Spacer()
                Text(String(yearAnchor)).font(.headline)
                Spacer()
                Button { yearAnchor += 1 } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Année suivante")
            }
            .tint(.mindTint)
            ForEach(1...12, id: \.self) { m in
                let first = cal.date(from: DateComponents(year: yearAnchor, month: m, day: 1)) ?? .now
                let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
                HStack(spacing: 6) {
                    Text(first, format: .dateTime.month(.narrow)).font(.caption2).foregroundStyle(Theme.textSecondary).frame(width: 12)
                    LazyVGrid(columns: cols, spacing: 2) {
                        ForEach(1...31, id: \.self) { d in
                            let key = String(format: "%04d-%02d-%02d", yearAnchor, m, d)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(d > days ? Color.clear : (avgs[key].map { MoodStyle.color($0) } ?? Theme.bg2))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(monthAccessibility(year: yearAnchor, month: m, avgs: avgs))
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { s in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2).fill(MoodStyle.color(Double(s))).frame(width: 10, height: 10)
                        Text("\(s)").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .card()
    }

    private func monthAccessibility(year: Int, month: Int, avgs: [String: Double]) -> String {
        let prefix = String(format: "%04d-%02d-", year, month)
        let vals = avgs.filter { $0.key.hasPrefix(prefix) }.map(\.value)
        guard !vals.isEmpty else { return "Mois \(month) : aucune entrée" }
        let avg = vals.reduce(0, +) / Double(vals.count)
        return "Mois \(month) : \(vals.count) jours notés, moyenne \(String(format: "%.1f", avg))"
    }

    // MARK: associations, objectif, export

    private var associationsCard: some View {
        let list = MoodAnalytics.associations(rows.map(\.row))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Activités et humeur")
            if list.isEmpty {
                Text("Il faut au moins 3 entrées avec et 3 sans une activité pour comparer. Ajoute des activités à tes entrées.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(list.prefix(6), id: \.activityUID) { a in
                let name = activities.first { $0.uid == a.activityUID }.map { "\($0.emoji) \($0.name)" } ?? "Activité supprimée"
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Avec : \(fmt(a.averageWith)) sur \(a.withCount) entrées · sans : \(fmt(a.averageWithout)) sur \(a.withoutCount)")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            if !list.isEmpty {
                Text("Ce sont des associations observées dans tes entrées, pas des causes.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }

    private var goalCard: some View {
        let done = MindStats.daysThisWeek(dates: entries.map(\.date))
        return VStack(alignment: .leading, spacing: 8) {
            Stepper(goalDays == 0 ? "Objectif : aucun" : "Objectif : \(goalDays) jours notés par semaine", value: $goalDays, in: 0...7)
                .font(.subheadline)
            if goalDays > 0 {
                ProgressView(value: Double(min(done, goalDays)), total: Double(goalDays)).tint(.mindTint)
                Text("\(done) sur \(goalDays) cette semaine").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Export")
            if let url = exportURL {
                ShareLink(item: url) { Label("Partager le fichier CSV", systemImage: "square.and.arrow.up") }
            } else {
                Button("Préparer l'export CSV", systemImage: "tablecells") { exportCSV() }
            }
            if let exportError { Text(exportError).font(.caption).foregroundStyle(Theme.warning) }
            Text("Toutes tes entrées : date, niveau, humeur, activités, note et gratitude.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .font(.subheadline).tint(.mindTint)
        .card()
    }

    private func exportCSV() {
        let names = Dictionary(uniqueKeysWithValues: activities.map { ($0.uid, $0.name) })
        let text = MoodAnalytics.csv(rows.map(\.row), activityNames: names)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("humeurs-\(MindDay.key(.now)).csv")
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            exportURL = url; exportError = nil
        } catch {
            exportError = "Export impossible : \(error.localizedDescription)"
        }
    }
}

struct MoodEntryEditor: View {
    let entry: MoodEntry
    let extras: [MoodEntryExtra]
    let activities: [MoodActivity]
    let customMoods: [MoodCustomMood]
    let otherDates: [Date]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MoodDraft()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                MoodEntryForm(draft: $draft, activities: activities, customMoods: customMoods).padding()
            }
            .background(Theme.background)
            .navigationTitle("Modifier l'entrée").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        MoodStore.update(entry, with: draft, extras: extras, otherDates: otherDates, ctx: ctx)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                draft = MoodStore.draft(for: entry, extras: extras); loaded = true
            }
        }
    }
}

/// Humeurs nommees et activites de l'utilisateur.
struct MoodManageSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MoodActivity.createdAt) private var activities: [MoodActivity]
    @Query(sort: \MoodCustomMood.createdAt) private var moods: [MoodCustomMood]
    @Query private var extras: [MoodEntryExtra]
    @State private var newActivity = ""
    @State private var newActivityEmoji = ""
    @State private var newMood = ""
    @State private var newMoodEmoji = ""
    @State private var newMoodScore = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(activities) { a in
                        HStack {
                            TextField("Emoji", text: Bindable(a).emoji).frame(width: 44)
                            TextField("Nom", text: Bindable(a).name)
                            Spacer()
                            if used(a.uid) {
                                Button(a.isArchived ? "Réactiver" : "Archiver") { a.isArchived.toggle() }.font(.caption)
                            } else {
                                Button(role: .destructive) { ctx.delete(a) } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Supprimer \(a.name)")
                            }
                        }
                        .opacity(a.isArchived ? 0.5 : 1)
                    }
                    HStack {
                        TextField("🙂", text: $newActivityEmoji).frame(width: 44)
                        TextField("Nouvelle activité", text: $newActivity)
                        Button("Ajouter") {
                            let n = newActivity.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            ctx.insert(MoodActivity(name: n, emoji: String(newActivityEmoji.prefix(2))))
                            newActivity = ""; newActivityEmoji = ""
                        }
                        .disabled(newActivity.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: { Text("Activités") } footer: {
                    Text("Une activité déjà utilisée s'archive : elle reste dans l'historique et les comparaisons.")
                }
                Section {
                    ForEach(moods) { m in
                        HStack {
                            TextField("Emoji", text: Bindable(m).emoji).frame(width: 44)
                            TextField("Nom", text: Bindable(m).name)
                            Picker("Niveau", selection: Bindable(m).score) {
                                ForEach(1...5, id: \.self) { Text("\(MoodStyle.face($0)) \($0)").tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                    }
                    .onDelete { idx in idx.map { moods[$0] }.forEach(ctx.delete) }
                    HStack {
                        TextField("😌", text: $newMoodEmoji).frame(width: 44)
                        TextField("Nouvelle humeur", text: $newMood)
                        Picker("Niveau", selection: $newMoodScore) {
                            ForEach(1...5, id: \.self) { Text("\(MoodStyle.face($0)) \($0)").tag($0) }
                        }
                        .pickerStyle(.menu).labelsHidden()
                        Button("Ajouter") {
                            let n = newMood.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            ctx.insert(MoodCustomMood(name: n, emoji: String(newMoodEmoji.prefix(2)), score: newMoodScore))
                            newMood = ""; newMoodEmoji = ""
                        }
                        .disabled(newMood.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: { Text("Humeurs personnalisées") } footer: {
                    Text("Chaque humeur est rattachée à un niveau de 1 à 5, utilisé pour les moyennes.")
                }
            }
            .navigationTitle("Humeurs et activités").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func used(_ uid: String) -> Bool { extras.contains { $0.activityUIDs.contains(uid) } }
}

// MARK: - Détox écran

struct ScreenDetoxView: View {
    @AppStorage(AppStorageKeys.screenGoal) private var goalHours = 3
    @AppStorage(AppStorageKeys.screenToday) private var todayMinutes = 0
    /// Jour auquel `todayMinutes` se rapporte, en nombre de jours depuis 1970.
    ///
    /// Sans ca le compteur "aujourd'hui" n'etait JAMAIS remis a zero: il
    /// cumulait depuis l'installation, donc l'anneau etait rouge a vie et
    /// l'objectif quotidien ne voulait plus rien dire.
    @AppStorage("screenTodayDay") private var storedDay = 0

    private var todayIndex: Int {
        Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970 / 86_400)
    }

    private func resetIfNewDay() {
        guard storedDay != todayIndex else { return }
        storedDay = todayIndex
        todayMinutes = 0
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    ScreenBlockCard()
                    VStack(spacing: 12) {
                        Text("Suivi manuel").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        Text("iOS ne laisse pas une app lire ton temps d'écran : note-le toi-même depuis Réglages > Temps d'écran.")
                            .font(.caption).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                        ZStack {
                            ProgressRing(progress: Double(todayMinutes)/Double(max(1,goalHours*60)), lineWidth: 14, tint: todayMinutes > goalHours*60 ? Theme.danger : .mindTint)
                            VStack {
                                Text("\(todayMinutes/60)h\(String(format: "%02d", todayMinutes%60))").font(.title.bold()).foregroundStyle(Theme.textPrimary)
                                Text("/ \(goalHours)h objectif").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }.frame(width: 200, height: 200)
                        HStack {
                            Button("-15") { todayMinutes = max(0, todayMinutes-15) }.buttonStyle(LifeOSGlassButtonStyle()).tint(.mindTint)
                            Button("+15 min") { todayMinutes += 15 }.buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.mindTint)
                            Button("Reset") { todayMinutes = 0 }.buttonStyle(LifeOSGlassButtonStyle()).tint(.gray)
                        }
                        Stepper("Objectif : \(goalHours)h / jour", value: $goalHours, in: 1...12)
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Détox écran").navigationBarTitleDisplayMode(.inline)
        .onAppear { resetIfNewDay() }
    }
}

// MARK: - Briefing du matin (Fabuleux)

/// Lit les enregistrements partages et construit LE briefing du jour.
/// Point d'entree unique: Fabuleux et le briefing du reveil appellent la meme fonction.
@MainActor
enum DayBriefingStore {
    static func build(todos: [TodoItem], events: [SocialEvent], habits: [Habit],
                      steps: [RoutineStep], checks: [RoutineCheck], period: RoutinePeriod, now: Date = Date(),
                      defaults: UserDefaults = .standard) -> DayBriefing {
        let cal = Calendar.current
        let today = MindDay.key(now)
        let periodSteps = steps.filter { $0.period == period.rawValue }.map(\.uid)
        let doneToday = Set(checks.filter { $0.day == today }.map(\.stepUID))
        let sleepTS = defaults.double(forKey: "lastSleepCheckDate")
        return DayBriefingBuilder.make(
            now: now,
            tasks: todos.map { .init(title: $0.title, done: $0.done, due: $0.due, recurringDays: $0.recurringDays, priority: $0.priority) },
            events: events.map { .init(title: $0.title, date: $0.date, location: $0.location) },
            habits: habits.map { h in .init(activeToday: h.isActive(on: now), archived: h.isArchived,
                                            doneToday: h.completions.contains { cal.isDate($0.date, inSameDayAs: now) }) },
            sleepCheckDate: sleepTS > 0 ? Date(timeIntervalSince1970: sleepTS) : nil,
            sleepHours: defaults.double(forKey: AppStorageKeys.lastSleepHours),
            sleepQuality: defaults.integer(forKey: AppStorageKeys.lastSleepQuality),
            routineDone: periodSteps.filter { doneToday.contains($0) }.count,
            routineTotal: periodSteps.count)
    }

    /// Meme briefing, lu directement dans la base (pour une vue qui n'a pas les requetes).
    static func fetch(_ ctx: ModelContext, now: Date = Date()) -> DayBriefing {
        let period: RoutinePeriod = Calendar.current.component(.hour, from: now) < 15 ? .morning : .evening
        return build(todos: (try? ctx.fetch(FetchDescriptor<TodoItem>())) ?? [],
                     events: (try? ctx.fetch(FetchDescriptor<SocialEvent>())) ?? [],
                     habits: (try? ctx.fetch(FetchDescriptor<Habit>())) ?? [],
                     steps: (try? ctx.fetch(FetchDescriptor<RoutineStep>())) ?? [],
                     checks: (try? ctx.fetch(FetchDescriptor<RoutineCheck>())) ?? [],
                     period: period, now: now)
    }
}

/// Carte "Ta journée", reutilisable telle quelle par le briefing du reveil.
struct DayBriefingFactsCard: View {
    let briefing: DayBriefing
    var showAgenda = true
    var showHabits = true
    var showSleep = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tes priorités du jour")
            if briefing.tasks.isEmpty {
                Text("Aucune tâche planifiée aujourd'hui. Profites-en ou ajoute un objectif.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(briefing.tasks.prefix(5).enumerated()), id: \.offset) { _, t in
                    Label {
                        Text(t.title + (t.overdue ? " (en retard)" : "")).foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: t.overdue ? "exclamationmark.circle" : "circle")
                            .foregroundStyle(t.overdue ? Theme.warning : Theme.textSecondary)
                    }
                    .font(.subheadline)
                }
            }
            if showAgenda {
                Divider()
                Text("Agenda").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                if briefing.events.isEmpty {
                    Text("Rien à l'agenda aujourd'hui.").font(.footnote).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(Array(briefing.events.enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .firstTextBaseline) {
                            Text(e.date, format: .dateTime.hour().minute()).font(.subheadline.monospacedDigit()).foregroundStyle(.mindTint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.title).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                if !e.location.isEmpty { Text(e.location).font(.caption).foregroundStyle(Theme.textSecondary) }
                            }
                        }
                    }
                }
            }
            if showHabits && briefing.habitsDue > 0 {
                Divider()
                Label("Habitudes : \(briefing.habitsDone) sur \(briefing.habitsDue)", systemImage: "checkmark.seal")
                    .font(.subheadline).foregroundStyle(Theme.textPrimary)
            }
            if showSleep {
                Divider()
                if let h = briefing.sleepHours {
                    Label("Nuit notée : \(String(format: "%.1f", h).replacingOccurrences(of: ".", with: ",")) h"
                          + (briefing.sleepQuality.map { ", qualité \($0)/5" } ?? ""), systemImage: "moon.stars")
                        .font(.subheadline).foregroundStyle(Theme.textPrimary)
                } else {
                    Label("Nuit pas encore notée aujourd'hui.", systemImage: "moon.stars")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct MorningBriefingView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var todos: [TodoItem]
    @Query private var events: [SocialEvent]
    @Query private var habits: [Habit]
    @Query(sort: \RoutineStep.order) private var steps: [RoutineStep]
    @Query private var checks: [RoutineCheck]
    @Query(sort: \DailyReflection.date, order: .reverse) private var reflections: [DailyReflection]
    @ObservedObject private var alarm = AlarmManager.shared

    @AppStorage("fabuleux.showQuote") private var showQuote = true
    @AppStorage("fabuleux.showAgenda") private var showAgenda = true
    @AppStorage("fabuleux.showHabits") private var showHabits = true
    @AppStorage("fabuleux.showSleep") private var showSleep = true
    @AppStorage("fabuleux.autoRead") private var autoRead = false
    @AppStorage("fabuleux.lastAutoRead") private var lastAutoReadDay = ""

    @State private var period: RoutinePeriod = Calendar.current.component(.hour, from: .now) < 15 ? .morning : .evening
    @State private var editingRoutine = false
    @State private var newStep = ""
    @State private var reflectionText = ""
    @State private var reflectionSaved = false
    @State private var showPrefs = false

    private let quotes = [
        "Discipline is choosing between what you want now and what you want most.",
        "Tu n'as pas besoin de motivation, tu as besoin de routine.",
        "1% meilleur chaque jour = 37× en un an.",
        "Le succès, c'est la somme de petits efforts répétés jour après jour.",
        "Fais aujourd'hui ce que les autres ne veulent pas, vis demain comme les autres ne peuvent pas."
    ]
    private var quote: String { quotes[Calendar.current.component(.day, from: .now) % quotes.count] }
    private var todayKey: String { MindDay.key(.now) }

    /// Une tache compte aujourd'hui si elle est due aujourd'hui, en retard, ou
    /// recurrente ce jour de la semaine. Avant, seules les taches datees du jour
    /// sortaient: les recurrentes (sans date) et les retards etaient invisibles.
    /// Une tache sans date ni recurrence n'est pas "planifiee": elle reste dehors.
    static func isPriorityToday(done: Bool, due: Date?, recurringDays: Set<Int>,
                                now: Date, calendar: Calendar = .current) -> Bool {
        DayBriefingBuilder.isPriorityToday(done: done, due: due, recurringDays: recurringDays, now: now, calendar: calendar)
    }

    private var briefing: DayBriefing {
        DayBriefingStore.build(todos: todos, events: events, habits: habits, steps: steps, checks: checks, period: period)
    }

    private var periodSteps: [RoutineStep] { steps.filter { $0.period == period.rawValue } }
    private var checkTuples: [(stepUID: String, day: String)] { checks.map { ($0.stepUID, $0.day) } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    DayBriefingFactsCard(briefing: briefing, showAgenda: showAgenda, showHabits: showHabits, showSleep: showSleep)
                    routineCard
                    reflectionCard
                    Text("Parcours et programmes coachés : pas de contenu dans LifeOS pour l'instant. Ta routine, c'est toi qui la construis.")
                        .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .padding(Theme.pad)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Briefing du matin").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showPrefs = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Préférences du briefing")
            }
        }
        .sheet(isPresented: $showPrefs) { prefsSheet }
        .onAppear {
            reflectionText = reflections.first { $0.day == todayKey }?.text ?? ""
            if autoRead, lastAutoReadDay != todayKey {
                lastAutoReadDay = todayKey
                alarm.speakText(DayBriefingBuilder.spokenText(briefing))
            }
        }
        .onDisappear { if alarm.isSpeaking { alarm.stopSpeaking() } }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sun.horizon.fill").font(.title).foregroundStyle(.mindTint)
                Spacer()
                Button {
                    if alarm.isSpeaking { alarm.stopSpeaking() } else { alarm.speakText(DayBriefingBuilder.spokenText(briefing)) }
                } label: {
                    Label(alarm.isSpeaking ? "Arrêter" : "Écouter", systemImage: alarm.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(LifeOSGlassButtonStyle()).tint(.mindTint)
            }
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            if showQuote { Text("« \(quote) »").font(.subheadline).italic().foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: routine

    private var routineCard: some View {
        let uids = periodSteps.map(\.uid)
        let done = Set(checks.filter { $0.day == todayKey }.map(\.stepUID))
        let streak = RoutineLogic.streak(stepUIDs: uids, checks: checkTuples)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Routine").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(editingRoutine ? "Terminé" : "Modifier") { editingRoutine.toggle() }.font(.subheadline).tint(.mindTint)
            }
            Picker("Moment", selection: $period) { ForEach(RoutinePeriod.allCases) { Text($0.label).tag($0) } }
                .pickerStyle(.segmented)
            if periodSteps.isEmpty && !editingRoutine {
                Text("Ta routine du \(period.rawValue) est vide. Ajoute tes propres étapes avec Modifier.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                if period == .morning {
                    Button("Partir des 3 étapes de base") { seedMorning() }.font(.subheadline).tint(.mindTint)
                }
            }
            if editingRoutine { routineEditor } else {
                ForEach(periodSteps) { s in
                    Button { toggle(s) } label: {
                        HStack {
                            Image(systemName: done.contains(s.uid) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done.contains(s.uid) ? Theme.success : Theme.textSecondary)
                            Text(s.title).foregroundStyle(Theme.textPrimary)
                            if let h = habit(s.habitUID) {
                                Spacer()
                                Label(h.name, systemImage: "link").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(done.contains(s.uid) ? .isSelected : [])
                }
                if !periodSteps.isEmpty {
                    Text("\(uids.filter { done.contains($0) }.count) sur \(uids.count) aujourd'hui · série \(streak) j")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    historyStrip(uids)
                }
            }
        }
        .card()
    }

    /// 14 derniers jours: plein = routine complete, demi = commencee.
    private func historyStrip(_ uids: [String]) -> some View {
        let cal = Calendar.current
        return HStack(spacing: 4) {
            ForEach((0..<14).reversed(), id: \.self) { back in
                let day = MindDay.key(cal.date(byAdding: .day, value: -back, to: .now) ?? .now)
                let doneSet = Set(checks.filter { $0.day == day }.map(\.stepUID))
                let n = uids.filter { doneSet.contains($0) }.count
                Circle()
                    .fill(n == uids.count && n > 0 ? Color.mindTint : (n > 0 ? Color.mindTint.opacity(0.4) : Theme.bg2))
                    .frame(maxWidth: 14, maxHeight: 14)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Historique sur 14 jours")
    }

    private var routineEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(periodSteps.enumerated()), id: \.element.uid) { i, s in
                HStack(spacing: 8) {
                    TextField("Étape", text: Bindable(s).title).textFieldStyle(.roundedBorder)
                    Menu {
                        Button("Aucune habitude") { s.habitUID = "" }
                        ForEach(habits.filter { !$0.isArchived }) { h in Button(h.name) { s.habitUID = h.uid } }
                    } label: { Image(systemName: s.habitUID.isEmpty ? "link.badge.plus" : "link") }
                    .accessibilityLabel("Empiler une habitude")
                    Button { move(s, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(i == 0)
                        .accessibilityLabel("Monter")
                    Button { move(s, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(i == periodSteps.count - 1)
                        .accessibilityLabel("Descendre")
                    Button(role: .destructive) { deleteStep(s) } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Supprimer l'étape")
                }
                .tint(.mindTint)
            }
            HStack {
                TextField("Nouvelle étape", text: $newStep).textFieldStyle(.roundedBorder).onSubmit(addStep)
                Button("Ajouter", action: addStep).disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Empiler une habitude : cocher l'étape coche aussi l'habitude liée.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    private func habit(_ uid: String) -> Habit? { uid.isEmpty ? nil : habits.first { $0.uid == uid } }

    private func toggle(_ s: RoutineStep) {
        if let existing = checks.first(where: { $0.stepUID == s.uid && $0.day == todayKey }) {
            ctx.delete(existing)
            if let h = habit(s.habitUID) { HabitSync.apply(HabitOp(habitID: h.uid, action: .uncomplete, source: "routine"), to: h, ctx: ctx) }
        } else {
            ctx.insert(RoutineCheck(stepUID: s.uid, day: todayKey))
            if let h = habit(s.habitUID) { HabitSync.apply(HabitOp(habitID: h.uid, action: .complete, source: "routine"), to: h, ctx: ctx) }
            Haptics.tap()
        }
    }

    private func addStep() {
        let t = newStep.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        ctx.insert(RoutineStep(title: t, period: period, order: (periodSteps.map(\.order).max() ?? -1) + 1))
        newStep = ""
    }

    private func seedMorning() {
        let base = ["Verre d'eau + lumière du jour", "3 respirations de cohérence", "Définis ta tâche n°1"]
        for (i, t) in base.enumerated() { ctx.insert(RoutineStep(title: t, period: .morning, order: i)) }
    }

    private func move(_ s: RoutineStep, by delta: Int) {
        var list = periodSteps
        guard let i = list.firstIndex(where: { $0.uid == s.uid }), list.indices.contains(i + delta) else { return }
        list.swapAt(i, i + delta)
        for (n, step) in list.enumerated() { step.order = n }
    }

    private func deleteStep(_ s: RoutineStep) {
        checks.filter { $0.stepUID == s.uid }.forEach(ctx.delete)
        ctx.delete(s)
    }

    // MARK: réflexion

    private var reflectionCard: some View {
        let prompt = RoutineLogic.prompt(for: .now)
        let past = reflections.filter { $0.day != todayKey }.prefix(5)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Réflexion")
            Text(prompt).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            TextField("Ta réponse…", text: $reflectionText, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(3...8)
                .onChange(of: reflectionText) { _, _ in reflectionSaved = false }
            HStack {
                Button("Enregistrer", systemImage: "checkmark") { saveReflection(prompt) }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.mindTint)
                    .disabled(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if reflectionSaved { Text("Enregistré").font(.caption).foregroundStyle(Theme.success) }
            }
            if !past.isEmpty {
                Divider()
                ForEach(Array(past), id: \.day) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.date, format: .dateTime.weekday().day().month()).font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(r.prompt).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        Text(r.text).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
        .card()
    }

    private func saveReflection(_ prompt: String) {
        let text = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let r = reflections.first(where: { $0.day == todayKey }) {
            r.text = text; r.prompt = prompt; r.date = .now
        } else {
            ctx.insert(DailyReflection(day: todayKey, prompt: prompt, text: text))
        }
        reflectionSaved = true
        Haptics.success()
    }

    private var prefsSheet: some View {
        NavigationStack {
            Form {
                Section("Afficher") {
                    Toggle("Citation du jour", isOn: $showQuote)
                    Toggle("Agenda", isOn: $showAgenda)
                    Toggle("Habitudes", isOn: $showHabits)
                    Toggle("Nuit", isOn: $showSleep)
                }
                Section {
                    Toggle("Lire le briefing à l'ouverture", isOn: $autoRead)
                } footer: { Text("Une fois par jour, à la première ouverture.") }
            }
            .navigationTitle("Préférences").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showPrefs = false } } }
        }
    }
}
