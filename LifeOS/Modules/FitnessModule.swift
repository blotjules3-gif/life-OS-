import SwiftUI
import UIKit
import SwiftData
import Charts
import UserNotifications

extension ShapeStyle where Self == Color { static var fitTint: Color { AppCategory.fitness.tint } }

// MARK: - Hub Fitness


// MARK: - Pas

struct StepsView: View {
    @State private var today = 0
    @State private var loading = true
    @AppStorage(AppStorageKeys.stepGoal) private var goal = 10000

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
                                Text("\(today)").font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                Text("/ \(goal) pas").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }.frame(width: 230, height: 230)
                        HStack(spacing: 12) {
                            StatTile(value: String(format: "%.1f", Double(today)*0.0007), label: "km approx.", icon: "map")
                            StatTile(value: "\(Int(Double(today)*0.04))", label: "kcal approx.", icon: "flame.fill", tint: Theme.warning)
                        }
                        Stepper("Objectif : \(goal) pas", value: $goal, in: 3000...25000, step: 1000).card()
                    }
                    if today == 0 && !loading {
                        // Ancien texte: "Active la capability HealthKit dans
                        // Xcode". C'est une consigne de DEVELOPPEUR affichee a
                        // l'utilisateur, et elle ne menait a aucune action.
                        VStack(spacing: 12) {
                            EmptyState(icon: "figure.walk",
                                       title: "Aucun pas pour l'instant",
                                       message: "LifeOS lit tes pas dans Apple Santé. Si tu as refusé l'accès, tu peux l'autoriser dans Réglages.")
                            Button {
                                Task {
                                    _ = await HealthService.shared.requestAuthorization()
                                    today = await HealthService.shared.stepsToday()
                                }
                            } label: {
                                Label("Autoriser Apple Santé", systemImage: "heart.fill")
                            }
                            .buttonStyle(LifeOSGlassButtonStyle(prominent: true))

                            // iOS ne redemande jamais une permission refusee:
                            // sans ce lien l'utilisateur est bloque pour de bon.
                            Button("Ouvrir les Réglages") {
                                if let u = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(u)
                                }
                            }
                            .font(.footnote)
                        }
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
    @Query private var sessions: [TrainingSession]
    @State private var showAdd = false
    @State private var editing: WorkoutSet?
    @State private var selectedExercise: String?
    @State private var deleteError: String?

    private var exercises: [String] { Array(Set(sets.map { $0.exercise })).sorted() }
    /// Meilleur 1RM estime par exercice, series de travail des seances terminees.
    private var records: [(String, StrengthProgression.LoggedSet)] {
        let done = StrengthProgression.completed(sets.map(\.logged), doneSessions: GymSessionService.doneIDs(sessions))
            .filter { $0.kind == .work && $0.reps > 0 && $0.weight > 0 }
        let best = Dictionary(grouping: done, by: \.exercise).compactMapValues { list in
            list.max { StrengthProgression.e1RM($0.weight, $0.reps) < StrengthProgression.e1RM($1.weight, $1.reps) }
        }
        return best.sorted { $0.key < $1.key }
    }

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
                                                .background((e == (selectedExercise ?? exercises.first)) ? AnyShapeStyle(Color.fitTint) : AnyShapeStyle(Color.clear), in: Capsule()).raisedSurface(Capsule())
                                                .foregroundStyle((e == (selectedExercise ?? exercises.first)) ? .white : Theme.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                        // Suggestion de progression adaptative
                        if let last = sets.filter({ $0.exercise == ex }).first {
                            // Meme moteur que la seance du programme : la cible est la derniere
                            // serie (reps faites), la decision vient de l'historique complet.
                            let p = StrengthProgression.next(
                                exercise: ex,
                                target: .init(sets: 3, repLow: max(1, last.reps - 2), repHigh: max(1, last.reps)),
                                history: StrengthProgression.completed(sets.map(\.logged),
                                                                       doneSessions: GymSessionService.doneIDs(sessions)))
                            HStack(alignment: .top) {
                                Image(systemName: "wand.and.stars").foregroundStyle(.fitTint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Prochaine séance : \(p.weight.map { StrengthProgression.fmt($0) + " kg" } ?? "même charge") × \(p.reps)")
                                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    Text(p.reason).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 12)
                        }
                    }

                    if !records.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Records", subtitle: "Meilleur 1RM estimé, séances terminées")
                            ForEach(records, id: \.0) { name, r in
                                HStack {
                                    Image(systemName: "trophy.fill").foregroundStyle(.fitTint)
                                    Text(name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(StrengthProgression.fmt(r.weight)) kg × \(r.reps) · 1RM \(Int(StrengthProgression.e1RM(r.weight, r.reps))) kg")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }.card()
                    }

                    if let deleteError {
                        Label(deleteError, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning)
                    }
                    if sets.isEmpty {
                        EmptyState(icon: "dumbbell", title: "Aucune série", message: "Logge ta première série pour suivre ta progression.")
                    } else {
                        VStack(spacing: 8) {
                            SectionHeader(title: "Dernières séries", subtitle: "Touche une série pour la corriger")
                            ForEach(sets.prefix(15)) { s in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(s.exercise).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text("\(s.date.formatted(.dateTime.day().month().hour().minute())) · \((WorkoutSetKind(rawValue: s.kind) ?? .work).label)")
                                            .font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(String(format: "%.1f", s.weightKg))kg × \(s.reps)").font(.subheadline.bold()).foregroundStyle(.fitTint)
                                    Button(role: .destructive) {
                                        do { try GymSessionService.delete(s, in: ctx); deleteError = nil }
                                        catch { deleteError = error.localizedDescription }
                                    } label: { Image(systemName: "trash").font(.caption) }
                                        .foregroundStyle(Theme.danger.opacity(0.7))
                                        .accessibilityLabel("Supprimer la série")
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editing = s }
                                .card(padding: 12)
                            }
                        }
                    }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Muscu & progression").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { WorkoutEditor(knownExercises: exercises) }
        .sheet(item: $editing) { s in WorkoutEditor(knownExercises: exercises, editing: s) }
    }
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
    /// Serie a corriger ; nil = nouvelle serie.
    var editing: WorkoutSet? = nil
    @State private var exercise = ""; @State private var weight = ""; @State private var reps = ""; @State private var rpe = 8.0
    @State private var kind: WorkoutSetKind = .work
    @State private var error: String?
    @State private var loaded = false

    private var valid: Bool {
        !exercise.trimmingCharacters(in: .whitespaces).isEmpty
            && GymSessionService.parseWeight(weight) != nil && (Int(reps) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercice") {
                    TextField("Ex: Développé couché", text: $exercise)
                    if !knownExercises.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(knownExercises, id: \.self) { e in
                                Button(e) { exercise = e }.buttonStyle(LifeOSGlassButtonStyle()).tint(.fitTint).font(.caption)
                            } }
                        }
                    }
                }
                Section("Série") {
                    Picker("Type", selection: $kind) { ForEach(WorkoutSetKind.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
                    HStack { Text("Charge (kg)"); Spacer(); TextField("0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Répétitions"); Spacer(); TextField("0", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    VStack(alignment: .leading) { Text("RPE : \(Int(rpe))"); Slider(value: $rpe, in: 5...10, step: 1).tint(.fitTint) }
                }
                if let error { Text(error).foregroundStyle(Theme.warning).font(.footnote) }
            }
            .navigationTitle(editing == nil ? "Logger une série" : "Corriger la série").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Ajouter" : "Enregistrer") { save() }.disabled(!valid)
                }
            }
            .onAppear {
                guard !loaded, let e = editing else { return }
                loaded = true
                exercise = e.exercise; weight = StrengthProgression.fmt(e.weightKg); reps = String(e.reps); rpe = e.rpe
                kind = WorkoutSetKind(rawValue: e.kind) ?? .work
            }
        }
    }

    /// Ne ferme la feuille qu'apres un enregistrement reussi ; sinon l'erreur s'affiche
    /// et la saisie reste.
    private func save() {
        guard let w = GymSessionService.parseWeight(weight), let r = Int(reps), r > 0 else { return }
        let name = exercise.trimmingCharacters(in: .whitespaces)
        if let e = editing {
            let old = (e.exercise, e.weightKg, e.reps, e.rpe, e.kind)
            e.exercise = name; e.weightKg = w; e.reps = r; e.rpe = rpe; e.kind = kind.rawValue
            do { try ctx.save(); dismiss() } catch {
                (e.exercise, e.weightKg, e.reps, e.rpe, e.kind) = old
                self.error = "Correction non enregistrée : \(error.localizedDescription)"
            }
        } else {
            let s = WorkoutSet(exercise: name, weightKg: w, reps: r, rpe: rpe, kind: kind.rawValue)
            ctx.insert(s)
            do { try ctx.save(); dismiss() } catch {
                ctx.delete(s)
                self.error = "Série non enregistrée : \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - HIIT / Tabata

struct HIITView: View {
    @State private var work = 20
    @State private var rest = 10
    @State private var rounds = 8
    @State private var engine = CountdownEngine(key: "workout")
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
                    ProgressRing(progress: engine.progress, lineWidth: 16, tint: inWork ? .fitTint : Theme.finance)
                    VStack(spacing: 4) {
                        Text(phase.uppercased()).font(.caption.bold()).foregroundStyle(inWork ? .fitTint : Theme.finance)
                        Text(formatHMS(engine.remaining)).font(.system(size: 46, weight: .bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
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
            if currentRound >= rounds { phase = "Terminé"; running = false; return }
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
                                    .frame(width: 44, height: 44).background(Color.fitTint.opacity(0.23), in: RoundedRectangle(cornerRadius: 10))
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
                        Image(systemName: "flame.fill").font(.system(size: 50)).foregroundStyle(Theme.warning)
                        Text("\(streak)").font(.system(size: 56, weight: .bold)).foregroundStyle(Theme.textPrimary)
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
            HStack { Text(name).font(.subheadline).foregroundStyle(Theme.textPrimary); Spacer(); Text("\(value)/\(goal)").font(.caption.bold()).foregroundStyle(value >= goal ? Theme.success : Theme.textSecondary) }
            ProgressView(value: Double(min(value, goal)), total: Double(goal)).tint(value >= goal ? Theme.success : .fitTint)
        }
    }
}
