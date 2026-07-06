import SwiftUI
import SwiftData
import Charts
import UserNotifications

extension ShapeStyle where Self == Color { static var fitTint: Color { AppCategory.fitness.tint } }

// MARK: - Hub Fitness

struct FitnessHubView: View {
    @State private var showTabata = false
    @State private var showFitnessProfile = false
    @AppStorage("fitnessCoachIntroShown") private var coachIntroShown = false
    @AppStorage("userWeightKg") private var userWeightKg: Double = 0
    @AppStorage("userHeightCm") private var userHeightCm: Double = 0
    @AppStorage("userStrengthLevel") private var userStrengthLevel: String = ""
    @AppStorage("userBench1RM") private var userBench1RM: Double = 0
    @AppStorage("userSquat1RM") private var userSquat1RM: Double = 0
    @AppStorage("userDeadlift1RM") private var userDeadlift1RM: Double = 0
    @AppStorage("userWeeklyFrequency") private var userWeeklyFrequency: Int = 3

    private var profileFields: [Bool] {
        [
            userWeightKg > 0,
            userHeightCm > 0,
            !userStrengthLevel.isEmpty,
            userBench1RM > 0,
            userSquat1RM > 0,
            userDeadlift1RM > 0,
        ]
    }
    private var filledCount: Int { profileFields.filter { $0 }.count }
    private var totalFields: Int { profileFields.count }
    private var profileProgress: Double {
        totalFields > 0 ? Double(filledCount) / Double(totalFields) : 0
    }
    private var profileIsIncomplete: Bool {
        // On considère "incomplet" tant qu'on n'a ni poids ni niveau (les 2 minimums pour calibrer).
        userWeightKg == 0 || userStrengthLevel.isEmpty
    }

    var body: some View {
        HubScaffold(category: .fitness) {
            if profileIsIncomplete {
                coachIntroBanner
            }
            Button { openCoachForSessionRequest() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.fitTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Génère ma séance du jour").font(.body).foregroundStyle(.primary)
                        Text("Le coach te pose 6 questions et construit ta séance").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { showFitnessProfile = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.fitTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mon profil sportif").font(.body).foregroundStyle(.primary)
                        Text("Poids, taille, niveau, 1RM — le coach s'en sert").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ToolRow(icon: "figure.strengthtraining.traditional", title: "Séance guidée",
                    subtitle: "Ta séance du jour, série par série + repos", tint: .fitTint) { GuidedWorkoutView() }
            ToolRow(icon: "figure.walk", title: "Compteur de pas",
                    subtitle: "Aujourd'hui + 7 jours (Santé)", tint: .fitTint) { StepsView() }
            ToolRow(icon: "dumbbell.fill", title: "Muscu & progression",
                    subtitle: "Charges, volume, 1RM, courbe", tint: .fitTint) { StrengthView() }
            Button { showTabata = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "timer")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.fitTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HIIT / Tabata").font(.body).foregroundStyle(.primary)
                        Text("Minuteur sportif plein écran").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ToolRow(icon: "figure.cooldown", title: "Mobilité & stretching",
                    subtitle: "Routines guidées", tint: .fitTint) { MobilityRoutineView() }
            ToolRow(icon: "flame.fill", title: "Streaks & habitudes",
                    subtitle: "Régularité d'entraînement", tint: .fitTint) { StreaksView() }
        }
        .fullScreenCover(isPresented: $showTabata) { TabataView() }
        .sheet(isPresented: $showFitnessProfile) { FitnessProfileSheet() }
        .onAppear {
            // Première ouverture de Muscu + profil vide → auto-lance le coach + programme rappel J+1.
            guard !coachIntroShown, profileIsIncomplete else { return }
            coachIntroShown = true
            scheduleCoachIntroFollowup()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                openCoachForIntro()
            }
        }
        .onChange(of: profileIsIncomplete) { _, incomplete in
            // Dès que le profil est complet, annule le rappel J+1.
            if !incomplete { cancelCoachIntroFollowup() }
        }
    }

    private func scheduleCoachIntroFollowup() {
        let content = UNMutableNotificationContent()
        content.title = "Ta séance t'attend"
        content.body = "2 min pour répondre au coach et il te calibre une séance parfaite."
        content.sound = .default
        content.userInfo = ["deeplink": "lifeos://fitness"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 24 * 60 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: "fitnessCoachIntroFollowup", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelCoachIntroFollowup() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["fitnessCoachIntroFollowup"])
    }

    private var coachIntroBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.fitTint, in: Circle())
                Text("Profil sportif à compléter")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(filledCount)/\(totalFields)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.fitTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.fitTint.opacity(0.15), in: Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 5)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.fitTint.opacity(0.7), Color.fitTint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(profileProgress)), height: 5)
                        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: profileProgress)
                }
            }
            .frame(height: 5)

            Text(filledCount == 0
                 ? "Pour que le coach calibre tes séances, choisis ton mode."
                 : "Encore \(totalFields - filledCount) infos pour un plan sur mesure.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { openCoachForIntro() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Le coach me guide")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.fitTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { showFitnessProfile = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11, weight: .bold))
                        Text("Je remplis moi-même")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.fitTint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.fitTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.fitTint.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.fitTint.opacity(0.25), lineWidth: 1)
        )
        .padding(.bottom, 4)
    }

    private func openCoachForIntro() {
        NotificationCenter.default.post(
            name: .lifeOSOpenAIChat,
            object: nil,
            userInfo: ["prefill": "Je viens d'ouvrir la catégorie Muscu et je veux progresser. Pose-moi les questions nécessaires (objectif, niveau, équipement, fréquence hebdo, blessures, records bench/squat/deadlift, poids et taille) et explique-moi le pourquoi de chaque question. Une fois que j'ai répondu, propose-moi une première séance calibrée."]
        )
    }

    private func openCoachForSessionRequest() {
        let hour = Calendar.current.component(.hour, from: .now)
        let timeHint: String
        switch hour {
        case 5..<11:  timeHint = "ce matin"
        case 11..<14: timeHint = "ce midi"
        case 14..<18: timeHint = "cet après-midi"
        default:      timeHint = "ce soir"
        }
        NotificationCenter.default.post(
            name: .lifeOSOpenAIChat,
            object: nil,
            userInfo: ["prefill": "Génère-moi ma séance pour \(timeHint). Pose-moi les questions nécessaires (objectif, équipement, temps dispo, blessures) avant de proposer, puis explique tes choix."]
        )
    }
}

// MARK: - Pas

struct StepsView: View {
    @State private var today = 0
    @State private var loading = true
    @AppStorage("stepGoal") private var goal = 10000

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 20) {
                    if loading { ProgressView().tint(.fitTint).padding(.top, 40) }
                    else {
                        ZStack {
                            ProgressRing(progress: Double(today)/Double(max(1,goal)), lineWidth: 16, tint: .fitTint)
                            VStack {
                                Text("\(today)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                                Text("/ \(goal) pas").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }.frame(width: 230, height: 230)
                        HStack(spacing: 12) {
                            StatTile(value: String(format: "%.1f", Double(today)*0.0007), label: "km approx.", icon: "map")
                            StatTile(value: "\(Int(Double(today)*0.04))", label: "kcal approx.", icon: "flame.fill", tint: .orange)
                        }
                        Stepper("Objectif : \(goal) pas", value: $goal, in: 3000...25000, step: 1000).card()
                    }
                    if today == 0 && !loading {
                        IntegrationNotice(text: "Aucun pas remonté. Active la capability HealthKit dans Xcode et autorise l'accès aux pas. Sur simulateur, les données de pas sont souvent vides — teste sur un vrai iPhone.")
                    }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Compteur de pas").navigationBarTitleDisplayMode(.inline)
        .task {
            _ = await HealthService.shared.requestAuthorization()
            today = await HealthService.shared.cachedStepsToday()
            loading = false
        }
    }
}

// MARK: - Muscu & progression

struct StrengthView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]
    @State private var showAdd = false
    @State private var selectedExercise: String?

    private var exercises: [String] { Array(Set(sets.map { $0.exercise })).sorted() }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    if let ex = selectedExercise ?? exercises.first, !exercises.isEmpty {
                        ProgressChartCard(exercise: ex, sets: sets.filter { $0.exercise == ex })
                        if exercises.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(exercises, id: \.self) { e in
                                        Button { selectedExercise = e } label: {
                                            Text(e).font(.caption.bold())
                                                .padding(.horizontal, 12).padding(.vertical, 7)
                                                .background((e == (selectedExercise ?? exercises.first)) ? AnyShapeStyle(Color.fitTint) : Theme.cardFill, in: Capsule())
                                                .foregroundStyle((e == (selectedExercise ?? exercises.first)) ? .white : Theme.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                        // Suggestion de progression adaptative
                        if let last = sets.filter({ $0.exercise == ex }).first {
                            HStack {
                                Image(systemName: "wand.and.stars").foregroundStyle(.fitTint)
                                Text("Prochaine séance : vise \(String(format: "%.1f", last.weightKg + suggestIncrement(last)))kg × \(last.reps) si tu as fini tes reps facilement.")
                                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                            }.card(padding: 12)
                        }
                    }

                    if sets.isEmpty {
                        EmptyState(icon: "dumbbell", title: "Aucune série", message: "Logge ta première série pour suivre ta progression.")
                    } else {
                        VStack(spacing: 8) {
                            SectionHeader(title: "Dernières séries")
                            ForEach(sets.prefix(15)) { s in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(s.exercise).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text(s.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(String(format: "%.1f", s.weightKg))kg × \(s.reps)").font(.subheadline.bold()).foregroundStyle(.fitTint)
                                    Button(role: .destructive) { ctx.delete(s) } label: { Image(systemName: "trash").font(.caption) }.foregroundStyle(.red.opacity(0.7))
                                }.card(padding: 12)
                            }
                        }
                    }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Muscu & progression").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { WorkoutEditor(knownExercises: exercises) }
    }
    private func suggestIncrement(_ s: WorkoutSet) -> Double { s.weightKg < 40 ? 2.5 : 5 }
}

struct ProgressChartCard: View {
    let exercise: String
    let sets: [WorkoutSet]
    var body: some View {
        let data = sets.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: exercise, subtitle: "Charge max estimée (1RM Epley)")
            Chart(data) { s in
                LineMark(x: .value("Date", s.date), y: .value("1RM", s.estimated1RM))
                    .foregroundStyle(Color.fitTint)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", s.date), y: .value("1RM", s.estimated1RM))
                    .foregroundStyle(Color.fitTint)
            }
            .frame(height: 180)
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.stroke); AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
            .chartXAxis { AxisMarks { _ in AxisValueLabel(format: .dateTime.day().month()).foregroundStyle(Theme.textSecondary) } }
        }.card()
    }
}

struct WorkoutEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let knownExercises: [String]
    @State private var exercise = ""; @State private var weight = ""; @State private var reps = ""; @State private var rpe = 8.0
    var body: some View {
        NavigationStack {
            Form {
                Section("Exercice") {
                    TextField("Ex: Développé couché", text: $exercise)
                    if !knownExercises.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(knownExercises, id: \.self) { e in
                                Button(e) { exercise = e }.buttonStyle(.bordered).tint(.fitTint).font(.caption)
                            } }
                        }
                    }
                }
                Section("Série") {
                    HStack { Text("Charge (kg)"); Spacer(); TextField("0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Répétitions"); Spacer(); TextField("0", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    VStack(alignment: .leading) { Text("RPE : \(Int(rpe))"); Slider(value: $rpe, in: 5...10, step: 1).tint(.fitTint) }
                }
            }
            .navigationTitle("Logger une série").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(WorkoutSet(exercise: exercise, weightKg: Double(weight) ?? 0, reps: Int(reps) ?? 0, rpe: rpe)); dismiss()
                }.disabled(exercise.isEmpty) }
            }
        }
    }
}

// MARK: - HIIT / Tabata

struct HIITView: View {
    @State private var work = 20
    @State private var rest = 10
    @State private var rounds = 8
    @State private var engine = CountdownEngine()
    @State private var phase = "Prêt"
    @State private var currentRound = 0
    @State private var inWork = true
    @State private var running = false

    var body: some View {
        ZStack {
            (inWork && running ? Color.fitTint.opacity(0.18) : Theme.bg).ignoresSafeArea()
            VStack(spacing: 24) {
                if !running {
                    VStack(spacing: 14) {
                        stepperRow("Effort", $work, 5...120, "s")
                        stepperRow("Récup", $rest, 5...120, "s")
                        stepperRow("Rounds", $rounds, 1...30, "")
                    }.card()
                }
                ZStack {
                    ProgressRing(progress: engine.progress, lineWidth: 16, tint: inWork ? .fitTint : .blue)
                    VStack(spacing: 4) {
                        Text(phase.uppercased()).font(.caption.bold()).foregroundStyle(inWork ? .fitTint : .blue)
                        Text(formatHMS(engine.remaining)).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                        if running { Text("Round \(currentRound)/\(rounds)").font(.caption).foregroundStyle(Theme.textSecondary) }
                    }
                }.frame(width: 240, height: 240)

                if !running {
                    PrimaryButton(title: "Démarrer", icon: "play.fill", tint: .fitTint) { startWorkout() }
                } else {
                    PrimaryButton(title: "Stop", icon: "stop.fill", tint: Theme.bg2) { stopWorkout() }
                }
            }.padding()
        }
        .navigationTitle("HIIT / Tabata").navigationBarTitleDisplayMode(.inline)
    }
    private func stepperRow(_ label: String, _ v: Binding<Int>, _ range: ClosedRange<Int>, _ unit: String) -> some View {
        Stepper("\(label) : \(v.wrappedValue)\(unit)", value: v, in: range, step: unit == "s" ? 5 : 1)
    }
    private func startWorkout() {
        running = true; currentRound = 1; inWork = true; phase = "Effort"
        engine.onFinish = nextPhase
        engine.start(seconds: work)
        Haptics.tap()
    }
    private func nextPhase() {
        Haptics.success()
        if inWork {
            inWork = false; phase = "Récup"; engine.onFinish = nextPhase; engine.start(seconds: rest)
        } else {
            if currentRound >= rounds { phase = "Terminé 🔥"; running = false; return }
            currentRound += 1; inWork = true; phase = "Effort"; engine.onFinish = nextPhase; engine.start(seconds: work)
        }
    }
    private func stopWorkout() { engine.stop(); running = false; phase = "Prêt" }
}

// MARK: - Mobilité

struct MobilityRoutineView: View {
    struct Stretch: Identifiable { let id = UUID(); let name: String; let seconds: Int; let icon: String }
    private let routines: [(String, [Stretch])] = [
        ("Réveil matinal (5 min)", [
            Stretch(name: "Chat-vache", seconds: 45, icon: "figure.flexibility"),
            Stretch(name: "Étirement ischio debout", seconds: 40, icon: "figure.cooldown"),
            Stretch(name: "Rotation des épaules", seconds: 30, icon: "figure.arms.open"),
            Stretch(name: "Fente avec rotation", seconds: 45, icon: "figure.strengthtraining.functional")
        ]),
        ("Anti-position assise (6 min)", [
            Stretch(name: "Ouverture de hanches", seconds: 60, icon: "figure.flexibility"),
            Stretch(name: "Étirement fléchisseurs", seconds: 45, icon: "figure.cooldown"),
            Stretch(name: "Étirement pectoraux", seconds: 40, icon: "figure.arms.open"),
            Stretch(name: "Twist colonne", seconds: 45, icon: "figure.core.training")
        ]),
        ("Post-muscu (5 min)", [
            Stretch(name: "Étirement quadriceps", seconds: 40, icon: "figure.cooldown"),
            Stretch(name: "Étirement dos", seconds: 45, icon: "figure.flexibility"),
            Stretch(name: "Étirement triceps", seconds: 30, icon: "figure.arms.open")
        ])
    ]
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(routines, id: \.0) { routine in
                        NavigationLink { GuidedStretchView(title: routine.0, stretches: routine.1) } label: {
                            HStack {
                                Image(systemName: "figure.cooldown").font(.title2).foregroundStyle(.fitTint)
                                    .frame(width: 44, height: 44).background(Color.fitTint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading) {
                                    Text(routine.0).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    Text("\(routine.1.count) exercices").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary).font(.caption.bold())
                            }.card()
                        }.buttonStyle(.plain)
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Mobilité").navigationBarTitleDisplayMode(.inline)
    }
}

struct GuidedStretchView: View {
    let title: String
    let stretches: [MobilityRoutineView.Stretch]
    @State private var index = 0
    @State private var engine = CountdownEngine()
    @State private var started = false
    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 24) {
                let s = stretches[min(index, stretches.count-1)]
                Image(systemName: s.icon).font(.system(size: 70)).foregroundStyle(.fitTint)
                Text(s.name).font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                Text("Exercice \(index+1)/\(stretches.count)").font(.caption).foregroundStyle(Theme.textSecondary)
                TimerDial(engine: engine, tint: .fitTint, caption: "\(s.seconds)s")
                if !started {
                    PrimaryButton(title: "Commencer", icon: "play.fill", tint: .fitTint) { begin() }
                } else {
                    PrimaryButton(title: index < stretches.count-1 ? "Passer" : "Terminer", icon: "forward.fill", tint: Theme.bg2) { next() }
                }
            }.padding()
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    private func begin() { started = true; engine.onFinish = next; engine.start(seconds: stretches[index].seconds) }
    private func next() {
        if index < stretches.count - 1 { index += 1; engine.onFinish = next; engine.start(seconds: stretches[index].seconds) }
        else { engine.stop(); started = false }
    }
}

// MARK: - Streaks & habitudes

struct StreaksView: View {
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]

    private var trainingDays: Set<Date> {
        Set(sets.map { Calendar.current.startOfDay(for: $0.date) })
    }
    private var streak: Int {
        var count = 0
        var day = Calendar.current.startOfDay(for: .now)
        // tolère de ne pas s'être entraîné aujourd'hui
        if !trainingDays.contains(day) { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        while trainingDays.contains(day) { count += 1; day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        return count
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill").font(.system(size: 50)).foregroundStyle(.orange)
                        Text("\(streak)").font(.system(size: 56, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                        Text("jours de série").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }.frame(maxWidth: .infinity).card()

                    HStack(spacing: 12) {
                        StatTile(value: "\(trainingDays.count)", label: "jours actifs", icon: "calendar")
                        StatTile(value: "\(sets.count)", label: "séries totales", icon: "list.number")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Habitudes")
                        habitProgressRow("7 jours d'affilée", min(streak, 7), 7)
                        habitProgressRow("30 séances ce mois", monthlySessions, 30)
                        habitProgressRow("100 séries au total", min(sets.count, 100), 100)
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Streaks & habitudes").navigationBarTitleDisplayMode(.inline)
    }
    private var monthlySessions: Int {
        let comps = Calendar.current.dateComponents([.year, .month], from: .now)
        return trainingDays.filter { Calendar.current.dateComponents([.year,.month], from: $0) == comps }.count
    }
    private func habitProgressRow(_ name: String, _ value: Int, _ goal: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(name).font(.subheadline).foregroundStyle(Theme.textPrimary); Spacer(); Text("\(value)/\(goal)").font(.caption.bold()).foregroundStyle(value >= goal ? .green : Theme.textSecondary) }
            ProgressView(value: Double(min(value, goal)), total: Double(goal)).tint(value >= goal ? .green : .fitTint)
        }
    }
}
