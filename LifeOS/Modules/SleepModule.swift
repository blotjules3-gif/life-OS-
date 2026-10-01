import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Hub Sommeil


extension ShapeStyle where Self == Color { static var sleepTint: Color { AppCategory.sleep.tint } }

// MARK: - Calcul heure de coucher / réveil

struct BedtimeCalculatorView: View {
    @State private var mode = 0            // 0 = je connais mon réveil, 1 = je me couche maintenant
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    private let fallAsleep = 15            // minutes pour s'endormir

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $mode) {
                        Text("Je veux me réveiller à…").tag(0)
                        Text("Je me couche maintenant").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if mode == 0 {
                        VStack(spacing: 12) {
                            DatePicker("Heure de réveil", selection: $wake, displayedComponents: .hourAndMinute)
                                .adaptiveWheelDatePicker()
                                .labelsHidden()
                            Text("Couche-toi à l'une de ces heures pour te réveiller en fin de cycle :")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                            ForEach([6, 5, 4], id: \.self) { cycles in
                                bedtimeRow(cycles: cycles)
                            }
                        }
                        .card()
                    } else {
                        VStack(spacing: 12) {
                            Text("Si tu t'endors maintenant, vise un réveil à :")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                            ForEach([6, 5, 4], id: \.self) { cycles in
                                wakeRow(cycles: cycles)
                            }
                        }
                        .card()
                    }

                    IntegrationNotice(text: "Le réveil « intelligent » façon Sleep Cycle (sonner pendant ton sommeil léger) nécessite l'analyse du sommeil via Apple Watch / micro la nuit. Ici on calcule la fenêtre idéale par cycles de 90 min, ce qui couvre 90% du bénéfice sans capteur.")
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Heure de coucher").navigationBarTitleDisplayMode(.inline)
    }

    private func bedtimeRow(cycles: Int) -> some View {
        let minutes = cycles * 90 + fallAsleep
        let bed = Calendar.current.date(byAdding: .minute, value: -minutes, to: wake) ?? wake
        return cycleRow(time: bed, cycles: cycles)
    }
    private func wakeRow(cycles: Int) -> some View {
        let minutes = cycles * 90 + fallAsleep
        let w = Calendar.current.date(byAdding: .minute, value: minutes, to: .now) ?? .now
        return cycleRow(time: w, cycles: cycles)
    }
    private func cycleRow(time: Date, cycles: Int) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(time, style: .time).font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                Text("\(cycles) cycles · \(Double(cycles) * 1.5, specifier: "%.1f")h de sommeil")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if cycles == 5 {
                Text("Recommandé").font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.sleepTint.opacity(0.2), in: Capsule())
                    .foregroundStyle(Color.sleepTint)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Power nap

struct PowerNapView: View {
    @State private var engine = CountdownEngine(key: "nap")
    @State private var minutes = 20
    @State private var started = false

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 28) {
                if !started {
                    Picker("Durée", selection: $minutes) {
                        Text("Power nap · 20 min").tag(20)
                        Text("Cycle complet · 90 min").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    Text(minutes == 20
                         ? "20 min : recharge sans inertie de sommeil. Idéal en après-midi."
                         : "90 min : un cycle complet, réveil naturel. Évite le coup de barre.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                TimerDial(engine: engine, tint: .sleepTint,
                          caption: started ? "Sieste en cours" : "\(minutes) min")

                HStack(spacing: 14) {
                    if !started {
                        PrimaryButton(title: "Démarrer la sieste", icon: "play.fill", tint: .sleepTint) {
                            engine.start(seconds: minutes * 60)
                            // Le reveil est programme MAINTENANT, pour l'heure de fin.
                            //
                            // Avant, il etait programme dans `onFinish`, c'est a dire au
                            // moment ou le compte a rebours arrivait a zero. Or ce rappel
                            // ne s'execute que si l'app tourne encore. Telephone
                            // verrouille ou app fermee, personne n'etait reveille. Une
                            // app suspendue ne peut pas organiser son propre reveil a
                            // l'instant voulu : la notification doit exister avant.
                            NotificationManager.shared.scheduleAfter(
                                id: "nap", title: "Réveil",
                                body: "Ta sieste est terminée, debout en douceur !",
                                seconds: TimeInterval(minutes * 60))
                            started = true
                        }
                    } else {
                        PrimaryButton(title: engine.isRunning ? "Pause" : "Reprendre",
                                      icon: engine.isRunning ? "pause.fill" : "play.fill", tint: .sleepTint) {
                            if engine.isRunning {
                                engine.pause()
                                // En pause, l'heure de fin n'a plus de sens.
                                NotificationManager.shared.cancel(id: "nap")
                            } else {
                                engine.resume()
                                // resume() ne fait rien si la sieste est deja finie:
                                // reprogrammer quand meme posait un faux "Réveil" 1 s plus tard.
                                if engine.isRunning {
                                    NotificationManager.shared.scheduleAfter(
                                        id: "nap", title: "Réveil",
                                        body: "Ta sieste est terminée, debout en douceur !",
                                        seconds: TimeInterval(max(1, engine.remaining)))
                                } else {
                                    started = false
                                }
                            }
                        }
                        PrimaryButton(title: "Stop", icon: "stop.fill", tint: Theme.bg2) {
                            engine.stop(); started = false
                            NotificationManager.shared.cancel(id: "nap")
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Power nap").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // L'ecran doit REPRENDRE la session persistee. Sans ca, revenir sur l'ecran
            // pendant une sieste en cours affichait "Demarrer la sieste" alors que le
            // compte a rebours tournait toujours, et le bouton en relancait une seconde.
            started = engine.isRunning || engine.remaining > 0
            // Fin de sieste ecran ouvert: revenir a l'etat de depart au lieu de
            // laisser un bouton "Reprendre" sur une sieste terminee.
            engine.onFinish = { started = false }
            engine.refresh()
        }
    }
}

// MARK: - Coucher progressif

struct WindDownView: View {
    @AppStorage(AppStorageKeys.windDownHour) private var hour = 22
    @AppStorage(AppStorageKeys.windDownMinute) private var minute = 30
    @AppStorage(AppStorageKeys.windDownEnabled) private var enabled = false
    @State private var time = Date()

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Rappel de coucher progressif", isOn: $enabled)
                            .tint(.sleepTint)
                            .onChange(of: enabled) { _, on in on ? schedule() : NotificationManager.shared.cancel(id: "winddown") }
                        DatePicker("Heure du rappel", selection: $time, displayedComponents: .hourAndMinute)
                            .onChange(of: time) { _, _ in if enabled { schedule() } }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Checklist du soir")
                        checklistRow("moon.fill", "Active Night Shift / mode nuit", "Réglages › Affichage › Night Shift — réduit la lumière bleue.")
                        checklistRow("iphone.slash", "Pose les écrans 45 min avant", "La lumière bleue retarde la mélatonine.")
                        checklistRow("lightbulb.fill", "Baisse les lumières", "Lumière chaude < 100 lux le soir.")
                        checklistRow("thermometer.snowflake", "Chambre à 18-19°C", "Le froid facilite l'endormissement.")
                    }
                    .card()
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Coucher progressif").navigationBarTitleDisplayMode(.inline)
        .onAppear { time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now }
    }

    private func schedule() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        hour = c.hour ?? 22; minute = c.minute ?? 30
        NotificationManager.shared.scheduleDaily(id: "winddown", title: "Heure de décompresser",
            body: "Baisse les lumières, mode nuit ON, écrans en pause. Au lit dans 45 min.", hour: hour, minute: minute)
    }
    private func checklistRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.sleepTint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(sub).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Journal de rêves (texte + voix)

struct DreamJournalView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \DreamEntry.date, order: .reverse) private var dreams: [DreamEntry]
    @State private var showAdd = false

    var body: some View {
        ZStack {
            Theme.background
            if dreams.isEmpty {
                EmptyState(icon: "cloud.moon", title: "Aucun rêve noté",
                           message: "Au réveil, capture ton rêve à la voix avant qu'il s'efface.")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(dreams) { d in DreamCard(dream: d) }
                    }
                    .padding(Theme.pad)
                }
            }
        }
        .navigationTitle("Journal de rêves").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter")
        } }
        .sheet(isPresented: $showAdd) { DreamEditor() }
    }
}

struct DreamCard: View {
    @Environment(\.modelContext) private var ctx
    let dream: DreamEntry
    @State private var player: AVAudioPlayer?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dream.title.isEmpty ? "Rêve" : dream.title)
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(repeating: "•", count: max(0, dream.mood))).foregroundStyle(.sleepTint)
            }
            Text(dream.date, style: .date).font(.caption).foregroundStyle(Theme.textSecondary)
            if !dream.text.isEmpty {
                Text(dream.text).font(.subheadline).foregroundStyle(Theme.textPrimary.opacity(0.9))
            }
            HStack {
                if dream.audioFilename != nil {
                    Button { play() } label: { Label("Écouter", systemImage: "play.circle.fill") }
                        .foregroundStyle(.sleepTint)
                }
                Spacer()
                Button(role: .destructive) {
                    // Le .m4a restait dans Documents pour toujours.
                    AudioRecorder.removeFile(named: dream.audioFilename)
                    ctx.delete(dream)
                } label: { Image(systemName: "trash") }
                    .foregroundStyle(Theme.danger.opacity(0.8))
            }
        }
        .card()
    }
    private func play() {
        guard let name = dream.audioFilename else { return }
        let url = AudioRecorder.docsURL.appendingPathComponent(name)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

struct DreamEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var mood = 3
    @State private var recorder = AudioRecorder()
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Rêve") {
                    TextField("Titre", text: $title)
                    TextField("Décris ton rêve…", text: $text, axis: .vertical).lineLimit(4...8)
                }
                Section("Note vocale") {
                    Button {
                        if recorder.isRecording { recorder.stop() } else { Task { await recorder.start() } }
                    } label: {
                        Label(recorder.isRecording ? "Arrêter l'enregistrement" : "Enregistrer ma voix",
                              systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .foregroundStyle(recorder.isRecording ? Theme.danger : .sleepTint)
                    }
                    if let error = recorder.errorMessage {
                        Text(error).font(.caption).foregroundStyle(Theme.danger)
                    } else if recorder.filename != nil && !recorder.isRecording {
                        Text("Note vocale enregistrée").font(.caption).foregroundStyle(Theme.success)
                    }
                }
                Section("Ressenti") {
                    Stepper("Intensité : \(mood)/5", value: $mood, in: 1...5)
                }
            }
            .navigationTitle("Nouveau rêve").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { recorder.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if recorder.isRecording { recorder.stop() }
                        saved = true
                        ctx.insert(DreamEntry(title: title, text: text, mood: mood, audioFilename: recorder.filename))
                        dismiss()
                    }
                }
            }
            // Fermeture par glissement: sans ca, la note vocale restait sur
            // le disque sans aucun reve pour la pointer.
            .onDisappear { if !saved { recorder.cancel() } }
        }
    }
}

/// Enregistreur audio minimal pour le journal de rêves.
@MainActor
@Observable
final class AudioRecorder {
    static var docsURL: URL { AppPaths.documents }
    private var recorder: AVAudioRecorder?
    var isRecording = false
    var filename: String?
    /// Message montre a la place d'un faux "Note vocale enregistrée".
    var errorMessage: String?

    /// Avant: permission jamais demandee, erreurs avalees par try?, et l'ecran
    /// disait "enregistrée" pour un fichier qui n'existait pas.
    func start() async {
        errorMessage = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Micro refusé. Autorise LifeOS dans Réglages › Confidentialité › Micro."
            return
        }
        // Un second enregistrement remplace le premier: l'ancien fichier
        // restait orphelin sur le disque.
        discardCurrent()
        let name = "dream-\(Int(Date().timeIntervalSince1970)).m4a"
        let url = Self.docsURL.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            let r = try AVAudioRecorder(url: url, settings: settings)
            guard r.record() else {
                errorMessage = "L'enregistrement n'a pas pu démarrer."
                Self.removeFile(named: name)
                return
            }
            recorder = r
            isRecording = true
            filename = name
        } catch {
            errorMessage = "L'enregistrement n'a pas pu démarrer : \(error.localizedDescription)"
            Self.removeFile(named: name)
        }
    }
    func stop() { recorder?.stop(); isRecording = false }
    func cancel() { discardCurrent() }

    private func discardCurrent() {
        recorder?.stop()
        recorder = nil
        Self.removeFile(named: filename)
        isRecording = false
        filename = nil
    }

    /// Efface une note vocale du disque. Sans nom ou fichier absent: rien.
    nonisolated static func removeFile(named name: String?, in dir: URL = AppPaths.documents) {
        guard let name, !name.isEmpty else { return }
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Score de récupération

/// Score de recuperation, pur et testable.
enum RecoveryScore {
    /// Au-dela, la mesure n'est plus celle de ce matin: pas de score "du jour".
    static let maxAge: TimeInterval = 36 * 3600

    static func isFresh(_ date: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(date) <= maxAge
    }

    /// Heuristique simple : HRV élevée + FC repos basse => meilleure récup.
    /// Avant: la DERNIERE mesure, meme vieille de plusieurs mois, faisait le
    /// score du jour. Une mesure perimee ne donne plus de score.
    static func score(hrv: (value: Double, date: Date)?, rhr: (value: Double, date: Date)?,
                      now: Date = .now) -> Int? {
        guard let hrv, let rhr, isFresh(hrv.date, now: now), isFresh(rhr.date, now: now) else { return nil }
        let hrvScore = min(100, max(0, (hrv.value / 80.0) * 100))
        let rhrScore = min(100, max(0, (1 - (rhr.value - 40) / 50) * 100))
        return Int((hrvScore * 0.6 + rhrScore * 0.4).rounded())
    }
}

struct RecoveryScoreView: View {
    @State private var hrv: (value: Double, date: Date)?
    @State private var rhr: (value: Double, date: Date)?
    @State private var loading = true

    private var score: Int? { RecoveryScore.score(hrv: hrv, rhr: rhr) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    if loading {
                        ProgressView().tint(.sleepTint).padding(.top, 40)
                    } else if let score {
                        ZStack {
                            ProgressRing(progress: Double(score) / 100, lineWidth: 16, tint: scoreColor(score))
                            VStack {
                                Text("\(score)").font(.system(size: 54, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                Text("Récupération").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 220, height: 220).padding(.top, 10)
                        Text(advice(score)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        tiles
                    } else if hrv != nil || rhr != nil {
                        // Des mesures existent mais pas assez recentes (ou une
                        // seule des deux): on les montre datees, sans score.
                        EmptyState(icon: "clock.arrow.circlepath", title: "Pas de mesure récente",
                                   message: "Le score demande la VFC et la FC au repos des dernières 36 h. Porte ton Apple Watch la nuit pour l'obtenir.")
                        tiles
                    } else {
                        EmptyState(icon: "heart.slash", title: "Pas de données santé",
                                   message: "Autorise LifeOS à lire la VFC et la FC au repos dans l'app Santé (Partage › Apps › LifeOS). Ces mesures viennent d'une Apple Watch.")
                    }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Score de récupération").navigationBarTitleDisplayMode(.inline)
        .task {
            _ = await HealthService.shared.requestAuthorization()
            hrv = await HealthService.shared.hrvSample()
            rhr = await HealthService.shared.restingHeartRateSample()
            loading = false
        }
    }

    private var tiles: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                StatTile(value: hrv.map { "\(Int($0.value)) ms" } ?? "—", label: "HRV (SDNN)", icon: "waveform.path.ecg")
                StatTile(value: rhr.map { "\(Int($0.value))" } ?? "—", label: "FC repos", icon: "heart.fill", tint: Theme.danger)
            }
            // Chaque valeur avec sa date: une mesure ancienne ne passe plus
            // pour celle du jour.
            Text(measuredLine)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var measuredLine: String {
        func d(_ date: Date) -> String { date.formatted(.relative(presentation: .named)) }
        var parts: [String] = []
        if let hrv { parts.append("VFC mesurée \(d(hrv.date))") }
        if let rhr { parts.append("FC repos \(d(rhr.date))") }
        return parts.joined(separator: " · ")
    }
    private func scoreColor(_ s: Int) -> Color { s >= 66 ? Theme.success : (s >= 40 ? Theme.learning : Theme.danger) }
    private func advice(_ s: Int) -> String {
        s >= 66 ? "Bien récupéré. Tu peux pousser fort aujourd'hui"
        : s >= 40 ? "Récup moyenne. Entraînement modéré conseillé."
        : "Faible récup. Privilégie repos, mobilité et sommeil."
    }
}
