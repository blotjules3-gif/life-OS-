import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var mindTint: Color { AppCategory.mind.tint } }

// MARK: - Hub Mental

struct MindHubView: View {
    var body: some View {
        HubScaffold(category: .mind) {
            ToolRow(icon: "wind", title: "Respiration & cohérence",
                    subtitle: "Box breathing, 365…", tint: .mindTint) { BreathingView() }
            ToolRow(icon: "leaf.fill", title: "Méditation",
                    subtitle: "Minuteur silencieux guidé", tint: .mindTint) { MeditationView() }
            ToolRow(icon: "face.smiling.inverse", title: "Humeur & gratitude",
                    subtitle: "Journal quotidien", tint: .mindTint) { MoodJournalView() }
            ToolRow(icon: "hourglass", title: "Détox écran",
                    subtitle: "Usage & objectifs", tint: .mindTint) { ScreenDetoxView() }
            ToolRow(icon: "sun.horizon.fill", title: "Briefing du matin",
                    subtitle: "Motivation + ta journée", tint: .mindTint) { MorningBriefingView() }
        }
    }
}

// MARK: - Respiration / cohérence cardiaque

struct BreathingView: View {
    enum Pattern: String, CaseIterable, Identifiable {
        case box = "Box 4-4-4-4"
        case coherence = "Cohérence 5-5"
        case relax = "Relax 4-7-8"
        var id: String { rawValue }
        /// (inspire, rétention, expire, rétention) en secondes
        var phases: [(String, Int)] {
            switch self {
            case .box: return [("Inspire", 4), ("Retiens", 4), ("Expire", 4), ("Retiens", 4)]
            case .coherence: return [("Inspire", 5), ("Expire", 5)]
            case .relax: return [("Inspire", 4), ("Retiens", 7), ("Expire", 8)]
            }
        }
    }
    @State private var pattern: Pattern = .coherence
    @State private var running = false
    @State private var phaseIndex = 0
    @State private var scale: CGFloat = 0.5
    @State private var label = "Prêt"
    @State private var totalMinutes = 5
    @State private var endDate: Date?
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var phaseEnd: Date?

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 28) {
                if !running {
                    Picker("Technique", selection: $pattern) {
                        ForEach(Pattern.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).tint(.mindTint)
                    Stepper("Durée : \(totalMinutes) min", value: $totalMinutes, in: 1...20).card()
                }
                ZStack {
                    Circle().fill(Color.mindTint.opacity(0.15)).frame(width: 260, height: 260)
                    Circle().fill(Color.mindTint.opacity(0.5))
                        .frame(width: 240, height: 240)
                        .scaleEffect(scale)
                        .animation(.easeInOut(duration: Double(currentPhaseDuration)), value: scale)
                    Text(label).font(.title2.bold()).foregroundStyle(.white)
                }
                if running, let end = endDate {
                    Text("Reste \(formatHMS(Int(end.timeIntervalSinceNow)))").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if !running {
                    PrimaryButton(title: "Commencer", icon: "play.fill", tint: .mindTint) { start() }
                } else {
                    PrimaryButton(title: "Arrêter", icon: "stop.fill", tint: Theme.bg2) { stop() }
                }
            }.padding()
        }
        .navigationTitle("Respiration").navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { _ in advanceIfNeeded() }
    }
    private var currentPhaseDuration: Int { pattern.phases[phaseIndex % pattern.phases.count].1 }
    private func start() {
        running = true; phaseIndex = 0; endDate = Date().addingTimeInterval(Double(totalMinutes*60))
        applyPhase()
    }
    private func stop() { running = false; label = "Prêt"; scale = 0.5; endDate = nil; phaseEnd = nil }
    private func applyPhase() {
        let p = pattern.phases[phaseIndex % pattern.phases.count]
        label = p.0
        scale = p.0 == "Expire" ? 0.5 : (p.0 == "Inspire" ? 1.0 : scale)
        phaseEnd = Date().addingTimeInterval(Double(p.1))
        Haptics.tap()
    }
    private func advanceIfNeeded() {
        guard running else { return }
        if let end = endDate, Date() >= end { Haptics.success(); stop(); return }
        if let pe = phaseEnd, Date() >= pe { phaseIndex += 1; applyPhase() }
    }
}

// MARK: - Méditation

struct MeditationView: View {
    @State private var minutes = 10
    @State private var engine = CountdownEngine()
    @State private var started = false
    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 26) {
                if !started {
                    Picker("Durée", selection: $minutes) {
                        ForEach([3,5,10,15,20], id: \.self) { Text("\($0) min").tag($0) }
                    }.pickerStyle(.segmented)
                }
                TimerDial(engine: engine, tint: .mindTint, caption: started ? "Respire et observe" : "\(minutes) min")
                if !started {
                    PrimaryButton(title: "Méditer", icon: "play.fill", tint: .mindTint) {
                        started = true
                        engine.onFinish = { NotificationManager.shared.scheduleAfter(id: "medi", title: "Séance terminée 🧘", body: "Reviens en douceur.", seconds: 1); started = false }
                        engine.start(seconds: minutes*60)
                    }
                } else {
                    PrimaryButton(title: "Terminer", icon: "stop.fill", tint: Theme.bg2) { engine.stop(); started = false }
                }
            }.padding()
        }
        .navigationTitle("Méditation").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Humeur & gratitude

struct MoodJournalView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MoodEntry.date, order: .reverse) private var entries: [MoodEntry]
    @State private var score = 3
    @State private var note = ""
    @State private var gratitude = ""

    private let faces = ["😞","🙁","😐","🙂","😄"]

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 14) {
                        Text("Comment tu te sens ?").font(.headline).foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { i in
                                Button { score = i; Haptics.tap() } label: {
                                    Text(faces[i-1]).font(.system(size: 34)).opacity(score == i ? 1 : 0.4)
                                        .scaleEffect(score == i ? 1.2 : 1)
                                }
                            }
                        }
                        TextField("Une note sur ta journée…", text: $note, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
                        TextField("Gratitude : 1 chose positive ✨", text: $gratitude, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
                        PrimaryButton(title: "Enregistrer", icon: "checkmark", tint: .mindTint) {
                            ctx.insert(MoodEntry(score: score, note: note, gratitude: gratitude))
                            note = ""; gratitude = ""; score = 3
                        }
                    }.card()

                    if entries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 32))
                                .foregroundStyle(.mindTint)
                            Text("Suis ton humeur chaque jour")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Text("En quelques semaines, tu verras des tendances : pic de moral le vendredi, baisse le lundi, lien avec tes habitudes ou ton sommeil.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(Color.mindTint.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Historique", subtitle: "Humeur moyenne : \(avgMood)")
                            ForEach(entries.prefix(20)) { e in
                                HStack(alignment: .top) {
                                    Text(faces[max(0,min(4,e.score-1))]).font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.date, format: .dateTime.weekday().day().month().hour().minute()).font(.caption).foregroundStyle(Theme.textSecondary)
                                        if !e.note.isEmpty { Text(e.note).font(.subheadline).foregroundStyle(Theme.textPrimary) }
                                        if !e.gratitude.isEmpty { Label(e.gratitude, systemImage: "sparkles").font(.caption).foregroundStyle(.mindTint) }
                                    }
                                    Spacer()
                                    Button(role: .destructive) { ctx.delete(e) } label: { Image(systemName: "trash").font(.caption) }.foregroundStyle(.red.opacity(0.6))
                                }.padding(.vertical, 4)
                            }
                        }.card()
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Humeur & gratitude").navigationBarTitleDisplayMode(.inline)
    }
    private var avgMood: String {
        guard !entries.isEmpty else { return "—" }
        let a = Double(entries.reduce(0) { $0 + $1.score }) / Double(entries.count)
        return String(format: "%.1f/5", a)
    }
}

// MARK: - Détox écran

struct ScreenDetoxView: View {
    @AppStorage("screenGoal") private var goalHours = 3
    @AppStorage("screenToday") private var todayMinutes = 0
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    IntegrationNotice(text: "Le temps d'écran système d'iOS (Screen Time) n'est pas lisible par une app tierce pour des raisons de confidentialité Apple. Deux options réelles : (1) la saisie manuelle ci-dessous, ou (2) une extension « Screen Time API » (DeviceActivity) qui demande une autorisation spéciale et permet de poser des limites/bloqueurs façon Forest.")
                    VStack(spacing: 12) {
                        ZStack {
                            ProgressRing(progress: Double(todayMinutes)/Double(max(1,goalHours*60)), lineWidth: 14, tint: todayMinutes > goalHours*60 ? .red : .mindTint)
                            VStack {
                                Text("\(todayMinutes/60)h\(String(format: "%02d", todayMinutes%60))").font(.title.bold()).foregroundStyle(Theme.textPrimary)
                                Text("/ \(goalHours)h objectif").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }.frame(width: 200, height: 200)
                        HStack {
                            Button("-15") { todayMinutes = max(0, todayMinutes-15) }.buttonStyle(.bordered).tint(.mindTint)
                            Button("+15 min") { todayMinutes += 15 }.buttonStyle(.borderedProminent).tint(.mindTint)
                            Button("Reset") { todayMinutes = 0 }.buttonStyle(.bordered).tint(.gray)
                        }
                        Stepper("Objectif : \(goalHours)h / jour", value: $goalHours, in: 1...12)
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Détox écran").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Briefing du matin

struct MorningBriefingView: View {
    @Query private var todos: [TodoItem]
    @Query private var events: [SocialEvent]
    private let quotes = [
        "Discipline is choosing between what you want now and what you want most.",
        "Tu n'as pas besoin de motivation, tu as besoin de routine.",
        "1% meilleur chaque jour = 37× en un an.",
        "Le succès, c'est la somme de petits efforts répétés jour après jour.",
        "Fais aujourd'hui ce que les autres ne veulent pas, vis demain comme les autres ne peuvent pas."
    ]
    private var quote: String { quotes[Calendar.current.component(.day, from: .now) % quotes.count] }
    private var todayTodos: [TodoItem] { todos.filter { !$0.done && ($0.due.map { Calendar.current.isDateInToday($0) } ?? false) } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "sun.horizon.fill").font(.title).foregroundStyle(.mindTint)
                        Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                        Text("« \(quote) »").font(.subheadline).italic().foregroundStyle(Theme.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Tes priorités du jour")
                        if todayTodos.isEmpty { Text("Aucune tâche planifiée aujourd'hui. Profites-en ou ajoute un objectif.").font(.footnote).foregroundStyle(Theme.textSecondary) }
                        else { ForEach(todayTodos.prefix(5)) { t in Label(t.title, systemImage: "circle").foregroundStyle(Theme.textPrimary).font(.subheadline) } }
                    }.card()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Rituel de démarrage")
                        Label("Verre d'eau + lumière du jour", systemImage: "sun.max").font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Label("3 respirations de cohérence", systemImage: "wind").font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Label("Définis ta tâche n°1", systemImage: "target").font(.subheadline).foregroundStyle(Theme.textPrimary)
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Briefing du matin").navigationBarTitleDisplayMode(.inline)
    }
}
