import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Hub Sommeil

struct SleepHubView: View {
    var body: some View {
        HubScaffold(category: .sleep) {
            ToolRow(icon: "chart.bar.xaxis", title: "Suivi du sommeil",
                    subtitle: "Durée, dette, régularité · 7 nuits", tint: .sleepTint) { SleepDashboardView() }
            ToolRow(icon: "bed.double.fill", title: "Heure de coucher optimale",
                    subtitle: "Cycles de 90 min · réveil léger", tint: .sleepTint) { BedtimeCalculatorView() }
            ToolRow(icon: "powersleep", title: "Power nap",
                    subtitle: "Sieste calibrée 20 ou 90 min", tint: .sleepTint) { PowerNapView() }
            ToolRow(icon: "moon.zzz.fill", title: "Coucher progressif",
                    subtitle: "Rappel + lumière bleue + mode nuit", tint: .sleepTint) { WindDownView() }
            ToolRow(icon: "cloud.moon.fill", title: "Journal de rêves",
                    subtitle: "Note vocale + texte + humeur", tint: .sleepTint) { DreamJournalView() }
            ToolRow(icon: "heart.text.square.fill", title: "Score de récupération",
                    subtitle: "HRV + FC repos (Apple Santé)", tint: .sleepTint) { RecoveryScoreView() }
        }
    }
}

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
                                .datePickerStyle(.wheel)
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
    @State private var engine = CountdownEngine()
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
                            engine.onFinish = { NotificationManager.shared.scheduleAfter(id: "nap", title: "Réveil", body: "Ta sieste est terminée, debout en douceur !", seconds: 1) }
                            engine.start(seconds: minutes * 60)
                            started = true
                        }
                    } else {
                        PrimaryButton(title: engine.isRunning ? "Pause" : "Reprendre",
                                      icon: engine.isRunning ? "pause.fill" : "play.fill", tint: .sleepTint) {
                            engine.isRunning ? engine.pause() : engine.resume()
                        }
                        PrimaryButton(title: "Stop", icon: "stop.fill", tint: Theme.bg2) {
                            engine.stop(); started = false
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Power nap").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Coucher progressif

struct WindDownView: View {
    @AppStorage("windDownHour") private var hour = 22
    @AppStorage("windDownMinute") private var minute = 30
    @AppStorage("windDownEnabled") private var enabled = false
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
            Button { showAdd = true } label: { Image(systemName: "plus") }
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
                Text(String(repeating: "•", count: dream.mood)).foregroundStyle(.sleepTint)
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
                Button(role: .destructive) { ctx.delete(dream) } label: { Image(systemName: "trash") }
                    .foregroundStyle(.red.opacity(0.8))
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Rêve") {
                    TextField("Titre", text: $title)
                    TextField("Décris ton rêve…", text: $text, axis: .vertical).lineLimit(4...8)
                }
                Section("Note vocale") {
                    Button {
                        recorder.isRecording ? recorder.stop() : recorder.start()
                    } label: {
                        Label(recorder.isRecording ? "Arrêter l'enregistrement" : "Enregistrer ma voix",
                              systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .foregroundStyle(recorder.isRecording ? .red : .sleepTint)
                    }
                    if recorder.filename != nil { Text("Note vocale enregistrée").font(.caption).foregroundStyle(.green) }
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
                        ctx.insert(DreamEntry(title: title, text: text, mood: mood, audioFilename: recorder.filename))
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Enregistreur audio minimal pour le journal de rêves.
@Observable
final class AudioRecorder {
    static var docsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var recorder: AVAudioRecorder?
    var isRecording = false
    var filename: String?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
        let name = "dream-\(Int(Date().timeIntervalSince1970)).m4a"
        let url = Self.docsURL.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        isRecording = true
        filename = name
    }
    func stop() { recorder?.stop(); isRecording = false }
    func cancel() {
        recorder?.stop(); recorder?.deleteRecording(); isRecording = false; filename = nil
    }
}

// MARK: - Score de récupération

struct RecoveryScoreView: View {
    @State private var hrv: Double?
    @State private var rhr: Double?
    @State private var loading = true

    private var score: Int? {
        guard let hrv, let rhr else { return nil }
        // Heuristique simple : HRV élevée + FC repos basse => meilleure récup.
        let hrvScore = min(100, max(0, (hrv / 80.0) * 100))
        let rhrScore = min(100, max(0, (1 - (rhr - 40) / 50) * 100))
        return Int((hrvScore * 0.6 + rhrScore * 0.4).rounded())
    }

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
                                Text("\(score)").font(.system(size: 54, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                                Text("Récupération").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(width: 220, height: 220).padding(.top, 10)
                        Text(advice(score)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        HStack(spacing: 12) {
                            StatTile(value: hrv.map { "\(Int($0)) ms" } ?? "—", label: "HRV (SDNN)", icon: "waveform.path.ecg")
                            StatTile(value: rhr.map { "\(Int($0))" } ?? "—", label: "FC repos", icon: "heart.fill", tint: .red)
                        }
                    } else {
                        EmptyState(icon: "heart.slash", title: "Pas de données santé",
                                   message: "Active la capability HealthKit dans Xcode et autorise l'accès à la HRV et la FC au repos (mesurées par une Apple Watch).")
                    }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Score de récupération").navigationBarTitleDisplayMode(.inline)
        .task {
            _ = await HealthService.shared.requestAuthorization()
            hrv = await HealthService.shared.hrv()
            rhr = await HealthService.shared.restingHeartRate()
            loading = false
        }
    }
    private func scoreColor(_ s: Int) -> Color { s >= 66 ? .green : (s >= 40 ? .yellow : .red) }
    private func advice(_ s: Int) -> String {
        s >= 66 ? "Bien récupéré. Tu peux pousser fort aujourd'hui"
        : s >= 40 ? "Récup moyenne. Entraînement modéré conseillé."
        : "Faible récup. Privilégie repos, mobilité et sommeil."
    }
}
