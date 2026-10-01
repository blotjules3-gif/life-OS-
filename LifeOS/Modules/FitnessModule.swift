import SwiftUI
import UIKit
import SwiftData
import Charts
import UserNotifications
import AudioToolbox
import UniformTypeIdentifiers

extension ShapeStyle where Self == Color { static var fitTint: Color { AppCategory.fitness.tint } }

// MARK: - Outils partagés du module Sport

/// Notifications locales du module : on ne redemande jamais une permission
/// refusée (iOS ne le fait pas), on renvoie vers Réglages.
enum FitnessNotify {
    static func ensureAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return await NotificationManager.shared.requestAuthorization()
        default: return false
        }
    }
}

/// Ligne "permission refusée" avec la seule sortie possible : Réglages.
struct FitnessPermissionDenied: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "bell.slash.fill").font(.footnote).foregroundStyle(Theme.warning)
            Button("Ouvrir les Réglages") {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }.font(.footnote.bold())
        }
    }
}

/// Largeur de lecture confortable sur iPad et Mac, pleine largeur sur iPhone.
private extension View {
    func readableWidth() -> some View { frame(maxWidth: 760).frame(maxWidth: .infinity) }
}

// MARK: - Pas

struct StepsView: View {
    @State private var today = 0
    /// 90 derniers jours lus dans Santé (aujourd'hui compris), du plus ancien au plus récent.
    @State private var history: [(day: Date, steps: Int)] = []
    @State private var loading = true
    @State private var window = 7
    @State private var notifyDenied = false
    @AppStorage(AppStorageKeys.stepGoal) private var goal = 10000
    @AppStorage("steps.goalNotify") private var goalNotify = false
    @AppStorage("steps.goalNotifiedDay") private var goalNotifiedDay = ""
    @AppStorage("steps.recordSteps") private var recordSteps = 0
    @AppStorage("steps.recordDay") private var recordDay = 0.0

    private var shown: [(day: Date, steps: Int)] { Array(history.suffix(window)) }
    private var record: StepStats.BestDay? {
        recordSteps > 0 ? StepStats.BestDay(day: Date(timeIntervalSince1970: recordDay), steps: recordSteps) : nil
    }

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
                        goalNoticeCard
                        if history.count > 1 { historyCard }
                        if let record { recordCard(record) }
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
                                    await load(fresh: true)
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
                .readableWidth()
            }
        }
        .navigationTitle("Compteur de pas").navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(fresh: true) }
        .task {
            _ = await HealthService.shared.requestAuthorization()
            await load(fresh: false)
            loading = false
        }
        .onChange(of: goal) { _, _ in Task { await notifyGoalIfNeeded() } }
    }

    private var historyCard: some View {
        let s = StepStats.summary(shown, goal: goal)
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Période", selection: $window) {
                Text("7 j").tag(7); Text("30 j").tag(30); Text("90 j").tag(90)
            }.pickerStyle(.segmented)
            SectionHeader(title: "\(window) derniers jours",
                          subtitle: "Moyenne \(s.average) pas · objectif atteint \(s.goalHits)/\(s.days)")
            Chart(shown, id: \.day) { d in
                BarMark(x: .value("Jour", d.day, unit: .day), y: .value("Pas", d.steps))
                    .foregroundStyle(d.steps >= goal ? Color.fitTint : Color.fitTint.opacity(0.4))
                RuleMark(y: .value("Objectif", goal)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(height: 170)
            .chartXAxis {
                if window == 7 {
                    AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                } else {
                    AxisMarks(values: .stride(by: window == 30 ? .weekOfYear : .month)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
            }
            if let best = s.best {
                Text("Meilleur jour de la période : \(best.steps) pas le \(best.day.formatted(.dateTime.day().month()))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Text("Un jour sans données Santé compte pour 0.").font(.caption2).foregroundStyle(Theme.textSecondary)
        }.card()
    }

    private func recordCard(_ r: StepStats.BestDay) -> some View {
        HStack {
            Image(systemName: "trophy.fill").foregroundStyle(.fitTint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Record : \(r.steps) pas").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("Le \(r.day.formatted(.dateTime.day().month().year())) · plus haut jour vu par LifeOS dans Santé")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }.card()
    }

    private var goalNoticeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Me prévenir quand l'objectif est atteint", isOn: $goalNotify).tint(.fitTint)
            // Dit clairement: c'est l'app qui constate, pas un declencheur Sante
            // en arriere-plan. Promettre l'inverse serait faux.
            Text("Une notification par jour au plus, envoyée quand LifeOS voit l'objectif atteint (à l'ouverture de cet écran ou en tirant pour rafraîchir). Ce n'est pas un suivi en arrière-plan.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            if notifyDenied {
                FitnessPermissionDenied(message: "Notifications refusées : LifeOS ne peut pas te prévenir.")
            }
        }
        .card()
        .onChange(of: goalNotify) { _, on in
            guard on else { return }
            Task {
                if await FitnessNotify.ensureAuthorized() {
                    notifyDenied = false
                    await notifyGoalIfNeeded()
                } else {
                    goalNotify = false; notifyDenied = true
                }
            }
        }
    }

    private func load(fresh: Bool) async {
        today = fresh ? await HealthService.shared.stepsToday() : await HealthService.shared.cachedStepsToday()
        history = await HealthService.shared.stepsByDay(days: 90)
        if let r = StepStats.record(current: record, seen: history) {
            recordSteps = r.steps; recordDay = r.day.timeIntervalSince1970
        }
        await notifyGoalIfNeeded()
    }

    private func notifyGoalIfNeeded() async {
        guard goalNotify, StepStats.shouldNotifyGoal(steps: today, goal: goal, lastNotifiedDay: goalNotifiedDay, now: .now) else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { notifyDenied = true; return }
        let c = UNMutableNotificationContent()
        c.title = "Objectif de pas atteint"
        c.body = "\(today) pas aujourd'hui pour un objectif de \(goal). Bravo !"
        c.sound = .default
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lifeos.steps.goal", content: c, trigger: nil))
            goalNotifiedDay = StepStats.dayKey(.now)
        } catch {
            AppLog.general.error("notification d'objectif de pas refusée: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Muscu & progression

/// Fichier CSV partagé par ShareLink : écrit dans le dossier temporaire au moment du partage.
struct SetsCSVFile: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LifeOS-series.csv")
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

struct StrengthView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]
    @Query private var sessions: [TrainingSession]
    @Query(sort: \CustomExercise.name) private var customs: [CustomExercise]
    @State private var showAdd = false
    @State private var editing: WorkoutSet?
    @State private var selectedExercise: String?
    @State private var deleteError: String?

    private var exercises: [String] { Array(Set(sets.map { $0.exercise })).sorted() }
    private var suggestions: [String] { ExerciseLibrary.suggestions(custom: customs.map(\.name), logged: exercises) }
    private var customGroups: [(name: String, group: String)] { customs.map { ($0.name, $0.muscleGroup) } }
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
                    toolsRow
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
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                        if let g = ExerciseLibrary.group(of: name, custom: customGroups) {
                                            Text(g).font(.caption2).foregroundStyle(Theme.textSecondary)
                                        }
                                    }
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
                        exportCard
                    }
                }
                .padding(Theme.pad)
                .readableWidth()
            }
        }
        .navigationTitle("Muscu & progression").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { WorkoutEditor(knownExercises: suggestions) }
        .sheet(item: $editing) { s in WorkoutEditor(knownExercises: suggestions, editing: s) }
    }

    /// Accès aux deux écrans de Hevvy qui ne sont pas des séries.
    private var toolsRow: some View {
        HStack(spacing: 10) {
            NavigationLink { ExerciseLibraryView() } label: {
                Label("Exercices", systemImage: "books.vertical.fill").font(.footnote.bold()).frame(maxWidth: .infinity)
            }.buttonStyle(LifeOSGlassButtonStyle())
            NavigationLink { BodyMeasurementsView() } label: {
                Label("Mensurations", systemImage: "ruler.fill").font(.footnote.bold()).frame(maxWidth: .infinity)
            }.buttonStyle(LifeOSGlassButtonStyle())
        }
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Export", subtitle: "\(sets.count) séries · CSV lisible par Numbers, Excel, Sheets")
            ShareLink(item: SetsCSVFile(text: SetsCSV.make(sets)),
                      preview: SharePreview("Séries LifeOS (CSV)", image: Image(systemName: "tablecells"))) {
                Label("Exporter mes séries", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
        }.card()
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
    @Query(sort: \CustomExercise.name) private var customs: [CustomExercise]
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
    private var chosenInfo: String? {
        let k = ExerciseLibrary.key(exercise)
        guard !k.isEmpty else { return nil }
        if let c = customs.first(where: { ExerciseLibrary.key($0.name) == k }) {
            return "\(c.muscleGroup) · \((ExerciseEquipment(rawValue: c.equipment) ?? .other).label)"
        }
        return GymExercises.group(of: exercise)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ex: Développé couché", text: $exercise)
                    if !knownExercises.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(knownExercises, id: \.self) { e in
                                Button(e) { exercise = e }.buttonStyle(LifeOSGlassButtonStyle()).tint(.fitTint).font(.caption)
                            } }
                        }
                    }
                } header: { Text("Exercice") } footer: {
                    if let chosenInfo { Text(chosenInfo) }
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
            e.exercise = GymExercises.baseName(name); e.weightKg = w; e.reps = r; e.rpe = rpe; e.kind = kind.rawValue
            do { try ctx.save(); dismiss() } catch {
                (e.exercise, e.weightKg, e.reps, e.rpe, e.kind) = old
                self.error = "Correction non enregistrée : \(error.localizedDescription)"
            }
        } else {
            do {
                try GymSessionService.logStandalone(exercise: name, weightText: weight, reps: r, rpe: rpe, kind: kind, in: ctx)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Bibliothèque d'exercices (Hevvy)

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CustomExercise.name) private var customs: [CustomExercise]
    @Query private var sets: [WorkoutSet]
    @State private var search = ""
    @State private var group = "Tous"
    @State private var creating = false
    @State private var editing: CustomExercise?
    @State private var pendingDelete: CustomExercise?
    @State private var error: String?

    private func matches(_ name: String, _ g: String) -> Bool {
        (group == "Tous" || group == g)
            && (search.isEmpty || ExerciseLibrary.key(name).contains(ExerciseLibrary.key(search)))
    }

    var body: some View {
        List {
            Section {
                Picker("Groupe musculaire", selection: $group) {
                    Text("Tous").tag("Tous")
                    ForEach(ExerciseLibrary.muscleGroups, id: \.self) { Text($0).tag($0) }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
            }
            Section {
                let mine = customs.filter { matches($0.name, $0.muscleGroup) }
                if mine.isEmpty {
                    Text(customs.isEmpty ? "Aucun exercice perso. Touche + pour en créer un." : "Aucun exercice perso pour ce filtre.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(mine) { c in
                    Button { editing = c } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).foregroundStyle(Theme.textPrimary)
                            Text("\(c.muscleGroup) · \((ExerciseEquipment(rawValue: c.equipment) ?? .other).label) · \(loggedCount(c.name)) séries")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .swipeActions { Button("Supprimer", role: .destructive) { pendingDelete = c } }
                    .contextMenu {
                        Button("Modifier") { editing = c }
                        Button("Supprimer", role: .destructive) { pendingDelete = c }
                    }
                }
            } header: { Text("Mes exercices") }
            ForEach(ExerciseLibrary.muscleGroups.filter { GymExercises.catalog[$0] != nil }, id: \.self) { g in
                let list = (GymExercises.catalog[g] ?? []).filter { matches($0, g) }
                if !list.isEmpty {
                    Section(g) {
                        ForEach(list, id: \.self) { n in Text(n).foregroundStyle(Theme.textPrimary) }
                    }
                }
            }
            Section {
                // Dependance de contenu, dite telle quelle: aucune video n'est inventee.
                Text("Démonstrations en vidéo : pas encore disponibles dans LifeOS.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .searchable(text: $search, prompt: "Rechercher un exercice")
        .navigationTitle("Exercices").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("Créer un exercice") } }
        .sheet(isPresented: $creating) { CustomExerciseEditor() }
        .sheet(item: $editing) { CustomExerciseEditor(editing: $0) }
        .confirmationDialog("Supprimer cet exercice ?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { c in
            Button("Supprimer", role: .destructive) { delete(c) }
            Button("Annuler", role: .cancel) {}
        } message: { c in
            Text("Les \(loggedCount(c.name)) séries déjà loggées restent dans ton historique.")
        }
    }

    private func loggedCount(_ name: String) -> Int {
        let k = ExerciseLibrary.key(name)
        return sets.filter { ExerciseLibrary.key($0.exercise) == k }.count
    }

    private func delete(_ c: CustomExercise) {
        ctx.delete(c)
        do { try ctx.save(); error = nil } catch {
            ctx.rollback()
            self.error = "Suppression impossible : \(error.localizedDescription)"
        }
    }
}

struct CustomExerciseEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var customs: [CustomExercise]
    @Query private var sets: [WorkoutSet]
    var editing: CustomExercise? = nil
    @State private var name = ""
    @State private var group = ExerciseLibrary.muscleGroups.first ?? "Autre"
    @State private var equipment: ExerciseEquipment = .barbell
    @State private var error: String?
    @State private var loaded = false

    /// Un nom du catalogue existant est aussi un doublon.
    private var existingNames: [String] {
        customs.filter { $0.id != editing?.id }.map(\.name) + GymExercises.catalog.values.flatMap { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") { TextField("Ex: Développé Larsen", text: $name) }
                Section("Détails") {
                    Picker("Groupe musculaire", selection: $group) {
                        ForEach(ExerciseLibrary.muscleGroups, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Matériel", selection: $equipment) {
                        ForEach(ExerciseEquipment.allCases) { Text($0.label).tag($0) }
                    }
                }
                if let editing, ExerciseLibrary.key(editing.name) != ExerciseLibrary.key(name), !name.isEmpty {
                    Text("Les séries déjà loggées sous « \(editing.name) » prendront le nouveau nom.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
            }
            .navigationTitle(editing == nil ? "Nouvel exercice" : "Modifier l'exercice").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = editing {
                    name = e.name; group = e.muscleGroup; equipment = ExerciseEquipment(rawValue: e.equipment) ?? .other
                }
            }
        }
    }

    private func save() {
        if let msg = ExerciseLibrary.validate(name: name, existing: existingNames, original: editing?.name) { error = msg; return }
        let n = name.trimmingCharacters(in: .whitespaces)
        if let e = editing {
            let old = e.name
            e.name = n; e.muscleGroup = group; e.equipment = equipment.rawValue
            ExerciseRename.apply(from: old, to: n, sets: sets)
        } else {
            ctx.insert(CustomExercise(name: n, muscleGroup: group, equipment: equipment))
        }
        do { try ctx.save(); dismiss() } catch {
            ctx.rollback()
            self.error = "Exercice non enregistré : \(error.localizedDescription)"
        }
    }
}

// MARK: - Mensurations (Hevvy)

struct BodyMeasurementsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var entries: [BodyMeasurement]
    @State private var kind: MeasurementKind = .weight
    @AppStorage("measure.massUnit") private var massUnitRaw = MeasureUnit.kg.rawValue
    @AppStorage("measure.lengthUnit") private var lengthUnitRaw = MeasureUnit.cm.rawValue
    @State private var adding = false
    @State private var editing: BodyMeasurement?
    @State private var error: String?

    private var displayUnit: MeasureUnit {
        switch kind.units.first?.family {
        case .mass: return MeasureUnit(rawValue: massUnitRaw) ?? .kg
        case .length: return MeasureUnit(rawValue: lengthUnitRaw) ?? .cm
        default: return .percent
        }
    }
    private var unitBinding: Binding<MeasureUnit> {
        Binding(get: { displayUnit }, set: { u in
            if u.family == .mass { massUnitRaw = u.rawValue } else if u.family == .length { lengthUnitRaw = u.rawValue }
        })
    }
    private var points: [BodyMeasureLogic.Point] { BodyMeasureLogic.series(entries, kind: kind, in: displayUnit) }
    private var rows: [BodyMeasurement] { entries.filter { $0.kind == kind.rawValue } }

    private func fmt(_ v: Double) -> String { String(format: v.rounded() == v ? "%.0f" : "%.1f", v) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Mesure", selection: $kind) {
                            ForEach(MeasurementKind.allCases) { Text($0.label).tag($0) }
                        }
                        if kind.units.count > 1 {
                            Picker("Unité", selection: unitBinding) {
                                ForEach(kind.units) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                    }.card()

                    if let last = points.last {
                        HStack(spacing: 12) {
                            StatTile(value: "\(fmt(last.value)) \(displayUnit.label)", label: "dernière mesure", icon: "ruler")
                            if let ch = BodyMeasureLogic.change(points) {
                                StatTile(value: "\(ch >= 0 ? "+" : "")\(fmt(ch)) \(displayUnit.label)", label: "depuis la 1re mesure",
                                         icon: ch >= 0 ? "arrow.up.right" : "arrow.down.right", tint: .fitTint)
                            }
                        }
                    }
                    if points.count >= 2 {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: kind.label, subtitle: "Évolution en \(displayUnit.label)")
                            Chart(points, id: \.date) { p in
                                LineMark(x: .value("Date", p.date), y: .value(kind.label, p.value)).foregroundStyle(Color.fitTint)
                                PointMark(x: .value("Date", p.date), y: .value(kind.label, p.value)).foregroundStyle(Color.fitTint)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 180)
                        }.card()
                    }
                    if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning) }
                    if rows.isEmpty {
                        EmptyState(icon: "ruler", title: "Aucune mesure", message: "Ajoute ta première mesure de \(kind.label.lowercased()) pour suivre son évolution.",
                                   actionTitle: "Ajouter", action: { adding = true })
                    } else {
                        VStack(spacing: 8) {
                            SectionHeader(title: "Historique", subtitle: "Touche une mesure pour la corriger")
                            ForEach(rows) { e in
                                HStack {
                                    Text(e.date.formatted(.dateTime.day().month().year())).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    let u = MeasureUnit(rawValue: e.unit) ?? displayUnit
                                    Text("\(fmt(FitnessUnits.convert(e.value, from: u, to: displayUnit) ?? e.value)) \(displayUnit.label)")
                                        .font(.subheadline.bold()).foregroundStyle(.fitTint)
                                    Button(role: .destructive) { delete(e) } label: { Image(systemName: "trash").font(.caption) }
                                        .foregroundStyle(Theme.danger.opacity(0.7)).accessibilityLabel("Supprimer la mesure")
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editing = e }
                                .card(padding: 12)
                            }
                        }
                    }
                }
                .padding(Theme.pad)
                .readableWidth()
            }
        }
        .navigationTitle("Mensurations").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter une mesure") } }
        .sheet(isPresented: $adding) { MeasurementEditor(kind: kind, unit: displayUnit) }
        .sheet(item: $editing) { e in
            MeasurementEditor(kind: MeasurementKind(rawValue: e.kind) ?? kind, unit: MeasureUnit(rawValue: e.unit) ?? displayUnit, editing: e)
        }
    }

    private func delete(_ e: BodyMeasurement) {
        ctx.delete(e)
        do { try ctx.save(); error = nil } catch {
            ctx.rollback()
            self.error = "Suppression impossible : \(error.localizedDescription)"
        }
    }
}

struct MeasurementEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State var kind: MeasurementKind
    @State var unit: MeasureUnit
    var editing: BodyMeasurement? = nil
    @State private var valueText = ""
    @State private var date = Date()
    @State private var error: String?
    @State private var healthNote: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mesure", selection: $kind) { ForEach(MeasurementKind.allCases) { Text($0.label).tag($0) } }
                        .onChange(of: kind) { _, k in if !k.units.contains(unit) { unit = k.units[0] } }
                    HStack {
                        TextField("Valeur", text: $valueText).keyboardType(.decimalPad)
                        if kind.units.count > 1 {
                            Picker("Unité", selection: $unit) { ForEach(kind.units) { Text($0.label).tag($0) } }
                                .pickerStyle(.segmented).frame(maxWidth: 140)
                        } else { Text(unit.label).foregroundStyle(Theme.textSecondary) }
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                if kind == .weight {
                    Section {
                        Button("Reprendre le dernier poids d'Apple Santé") { Task { await importWeight() } }
                        if let healthNote { Text(healthNote).font(.caption).foregroundStyle(Theme.textSecondary) }
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
            }
            .navigationTitle(editing == nil ? "Nouvelle mesure" : "Corriger la mesure").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = editing { valueText = SetsCSV.number(e.value).replacingOccurrences(of: ".", with: ","); date = e.date }
            }
        }
    }

    private func importWeight() async {
        _ = await HealthService.shared.requestAuthorization()
        guard let m = await HealthService.shared.latestBodyMass() else {
            healthNote = "Aucun poids trouvé dans Apple Santé (ou accès refusé dans Réglages)."
            return
        }
        let v = FitnessUnits.convert(m.kg, from: .kg, to: unit) ?? m.kg
        valueText = String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
        date = min(m.date, .now)
        healthNote = "Poids du \(m.date.formatted(.dateTime.day().month().year())) repris de Santé."
    }

    private func save() {
        guard let v = BodyMeasureLogic.parse(valueText, kind: kind) else { error = "Valeur invalide."; return }
        if let e = editing {
            let old = (e.kind, e.value, e.unit, e.date)
            e.kind = kind.rawValue; e.value = v; e.unit = unit.rawValue; e.date = date
            do { try ctx.save(); dismiss() } catch {
                (e.kind, e.value, e.unit, e.date) = old
                self.error = "Correction non enregistrée : \(error.localizedDescription)"
            }
        } else {
            let m = BodyMeasurement(date: date, kind: kind, value: v, unit: unit)
            ctx.insert(m)
            do { try ctx.save(); dismiss() } catch {
                ctx.delete(m)
                self.error = "Mesure non enregistrée : \(error.localizedDescription)"
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

/// Une routine prête à suivre : intégrée ou créée par l'utilisateur.
struct MobilityPlan: Identifiable, Hashable {
    let id: String
    let title: String
    let stretches: [MobilityRoutineView.Stretch]
}

struct MobilityRoutineView: View {
    struct Stretch: Identifiable, Hashable { var id = UUID(); let name: String; let seconds: Int; let icon: String }
    /// Identifiants stables : la reprise après relancement retrouve la routine par eux.
    static let builtIn: [MobilityPlan] = [
        MobilityPlan(id: "builtin-reveil", title: "Réveil matinal (5 min)", stretches: [
            Stretch(name: "Chat-vache", seconds: 45, icon: "figure.flexibility"),
            Stretch(name: "Étirement ischio debout", seconds: 40, icon: "figure.cooldown"),
            Stretch(name: "Rotation des épaules", seconds: 30, icon: "figure.arms.open"),
            Stretch(name: "Fente avec rotation", seconds: 45, icon: "figure.strengthtraining.functional")
        ]),
        MobilityPlan(id: "builtin-assise", title: "Anti-position assise (6 min)", stretches: [
            Stretch(name: "Ouverture de hanches", seconds: 60, icon: "figure.flexibility"),
            Stretch(name: "Étirement fléchisseurs", seconds: 45, icon: "figure.cooldown"),
            Stretch(name: "Étirement pectoraux", seconds: 40, icon: "figure.arms.open"),
            Stretch(name: "Twist colonne", seconds: 45, icon: "figure.core.training")
        ]),
        MobilityPlan(id: "builtin-postmuscu", title: "Post-muscu (5 min)", stretches: [
            Stretch(name: "Étirement quadriceps", seconds: 40, icon: "figure.cooldown"),
            Stretch(name: "Étirement dos", seconds: 45, icon: "figure.flexibility"),
            Stretch(name: "Étirement triceps", seconds: 30, icon: "figure.arms.open")
        ])
    ]

    static func plan(_ r: MobilityRoutine) -> MobilityPlan {
        MobilityPlan(id: "custom-\(r.id.uuidString)", title: r.name,
                     stretches: r.steps.map { Stretch(id: $0.id, name: $0.name, seconds: $0.seconds, icon: "figure.flexibility") })
    }

    @Environment(\.modelContext) private var ctx
    @Query(sort: \MobilityRoutine.createdAt) private var routines: [MobilityRoutine]
    @Query(sort: \MobilitySession.date, order: .reverse) private var history: [MobilitySession]
    @AppStorage("mobility.sound") private var soundOn = true
    @State private var creating = false
    @State private var editing: MobilityRoutine?
    @State private var pendingDelete: MobilityRoutine?
    @State private var error: String?
    @State private var inProgress: MobilityProgress?

    private var allPlans: [MobilityPlan] { Self.builtIn + routines.map(Self.plan) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if let p = inProgress, let plan = allPlans.first(where: { $0.id == p.routineID }) {
                        NavigationLink { GuidedStretchView(plan: plan) } label: {
                            Label("Reprendre « \(plan.title) » · exercice \(p.index + 1)/\(plan.stretches.count)", systemImage: "play.circle.fill")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(LifeOSGlassButtonStyle(prominent: true))
                    }
                    ForEach(Self.builtIn) { routineRow($0, custom: nil) }

                    SectionHeader(title: "Mes routines", actionTitle: "Créer", action: { creating = true })
                    if routines.isEmpty {
                        Text("Crée ta propre routine : tes exercices, dans ton ordre, avec tes durées.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(routines) { r in routineRow(Self.plan(r), custom: r) }
                    if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning) }

                    Toggle("Son entre les exercices", isOn: $soundOn).tint(.fitTint).card()
                    historyCard
                    Text("Démonstrations en vidéo : pas encore disponibles dans LifeOS.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.pad)
                .readableWidth()
            }
        }
        .navigationTitle("Mobilité").navigationBarTitleDisplayMode(.inline)
        .onAppear { inProgress = MobilityResume.load() }
        .sheet(isPresented: $creating) { MobilityRoutineEditor() }
        .sheet(item: $editing) { MobilityRoutineEditor(editing: $0) }
        .confirmationDialog("Supprimer cette routine ?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { r in
            Button("Supprimer", role: .destructive) { delete(r) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in Text("Les séances déjà faites restent dans l'historique.") }
    }

    private func routineRow(_ plan: MobilityPlan, custom: MobilityRoutine?) -> some View {
        HStack {
            NavigationLink { GuidedStretchView(plan: plan) } label: {
                HStack {
                    Image(systemName: "figure.cooldown").font(.title2).foregroundStyle(.fitTint)
                        .frame(width: 44, height: 44).background(Color.fitTint.opacity(0.23), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading) {
                        Text(plan.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(plan.stretches.count) exercices · \(formatHMS(plan.stretches.reduce(0) { $0 + $1.seconds }))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary).font(.caption.bold())
                }
            }.buttonStyle(.plain)
            if let custom {
                Menu {
                    Button("Modifier") { editing = custom }
                    Button("Supprimer", role: .destructive) { pendingDelete = custom }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.textSecondary) }
                    .accessibilityLabel("Options de la routine")
            }
        }.card()
    }

    private var historyCard: some View {
        let cal = Calendar.current
        let month = history.filter { cal.isDate($0.date, equalTo: .now, toGranularity: .month) }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Historique", subtitle: "\(month.count) séance\(month.count > 1 ? "s" : "") ce mois · \(formatHMS(month.reduce(0) { $0 + $1.durationSeconds }))")
            if history.isEmpty {
                Text("Aucune séance terminée pour l'instant.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(history.prefix(10)) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.routineName).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Text("\(s.date.formatted(.dateTime.day().month().hour().minute())) · \(s.exercisesDone)/\(s.exercisesTotal) exercices")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text(formatHMS(s.durationSeconds)).font(.caption.bold()).foregroundStyle(.fitTint)
                    Button(role: .destructive) { deleteSession(s) } label: { Image(systemName: "trash").font(.caption) }
                        .foregroundStyle(Theme.danger.opacity(0.7)).accessibilityLabel("Supprimer la séance")
                }
            }
        }.card()
    }

    private func delete(_ r: MobilityRoutine) {
        if inProgress?.routineID == "custom-\(r.id.uuidString)" { MobilityResume.clear(); inProgress = nil }
        ctx.delete(r)
        do { try ctx.save(); error = nil } catch { ctx.rollback(); self.error = "Suppression impossible : \(error.localizedDescription)" }
    }

    private func deleteSession(_ s: MobilitySession) {
        ctx.delete(s)
        do { try ctx.save(); error = nil } catch { ctx.rollback(); self.error = "Suppression impossible : \(error.localizedDescription)" }
    }
}

struct MobilityRoutineEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    var editing: MobilityRoutine? = nil
    @State private var name = ""
    @State private var steps: [MobilityStepSpec] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") { TextField("Ex: Hanches du soir", text: $name) }
                Section {
                    ForEach($steps) { $s in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Nom de l'exercice", text: $s.name)
                            Stepper("Durée : \(formatHMS(s.seconds))", value: $s.seconds, in: MobilityRoutineRules.secondsRange, step: 5)
                        }
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps = MobilityRoutineRules.moved(steps, from: $0, to: $1) }
                    Button { steps.append(MobilityStepSpec(name: "", seconds: 30)) } label: { Label("Ajouter un exercice", systemImage: "plus") }
                } header: { Text("Exercices, dans l'ordre") } footer: {
                    Text("Total : \(formatHMS(MobilityRoutineRules.totalSeconds(steps))). Glisse pour supprimer, Modifier pour réordonner.")
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
            }
            .navigationTitle(editing == nil ? "Nouvelle routine" : "Modifier la routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
                ToolbarItem(placement: .bottomBar) { EditButton() }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = editing { name = e.name; steps = e.steps } else { steps = [MobilityStepSpec(name: "", seconds: 30)] }
            }
        }
    }

    private func save() {
        let clean = steps.map { MobilityStepSpec(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespaces), seconds: $0.seconds) }
        if let msg = MobilityRoutineRules.validate(name: name, steps: clean) { error = msg; return }
        let n = name.trimmingCharacters(in: .whitespaces)
        if let e = editing {
            let old = (e.name, e.stepsData)
            e.name = n; e.steps = clean
            do { try ctx.save(); dismiss() } catch {
                (e.name, e.stepsData) = old
                self.error = "Routine non enregistrée : \(error.localizedDescription)"
            }
        } else {
            let r = MobilityRoutine(name: n, steps: clean)
            ctx.insert(r)
            do { try ctx.save(); dismiss() } catch {
                ctx.delete(r)
                self.error = "Routine non enregistrée : \(error.localizedDescription)"
            }
        }
    }
}

struct GuidedStretchView: View {
    let plan: MobilityPlan
    private var stretches: [MobilityRoutineView.Stretch] { plan.stretches }
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @Query private var sessions: [MobilitySession]
    @AppStorage("mobility.sound") private var soundOn = true
    @State private var engine = CountdownEngine(key: "mobility")
    @State private var progress: MobilityProgress?
    @State private var summary: String?
    @State private var error: String?
    @State private var confirmStop = false
    @State private var restored = false

    private var index: Int { min(progress?.index ?? 0, max(0, stretches.count - 1)) }
    private var started: Bool { progress != nil }
    private var waiting: Bool { progress?.waiting ?? false }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 22) {
                if stretches.isEmpty {
                    EmptyState(icon: "figure.cooldown", title: "Routine vide", message: "Ajoute des exercices à cette routine.")
                } else {
                    let s = stretches[index]
                    Image(systemName: s.icon).font(.system(size: 70)).foregroundStyle(.fitTint)
                    Text(s.name).font(.title2.bold()).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                    Text("Exercice \(index+1)/\(stretches.count)").font(.caption).foregroundStyle(Theme.textSecondary)
                    if started && !waiting {
                        TimerDial(engine: engine, tint: .fitTint, caption: engine.isRunning ? "\(s.seconds)s" : "En pause")
                    } else {
                        // Avant le depart, on montre la duree prevue: le moteur peut
                        // encore porter le minuteur d'une autre routine.
                        ZStack {
                            ProgressRing(progress: 0, lineWidth: 14, tint: .fitTint)
                            Text(formatHMS(s.seconds)).font(.system(size: 46, weight: .bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                        }.frame(width: 240, height: 240)
                    }
                    if let summary {
                        Label(summary, systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.success)
                            .multilineTextAlignment(.center)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning) }
                    if !started {
                        PrimaryButton(title: summary == nil ? "Commencer" : "Recommencer", icon: "play.fill", tint: .fitTint) { begin() }
                    } else {
                        HStack(spacing: 12) {
                            PrimaryButton(title: waiting ? "Reprendre" : (engine.isRunning ? "Pause" : "Reprendre"),
                                          icon: (engine.isRunning && !waiting) ? "pause.fill" : "play.fill", tint: .fitTint) { togglePause() }
                            PrimaryButton(title: index < stretches.count-1 ? "Passer" : "Terminer", icon: "forward.fill", tint: Theme.bg2) { skip() }
                        }
                        Button("Arrêter la séance") { confirmStop = true }.font(.footnote)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 560)
        }
        .navigationTitle(plan.title).navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: restore)
        .onChange(of: scenePhase) { _, p in if p == .active { engine.refresh() } }
        .confirmationDialog("Arrêter la séance ?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Enregistrer ce qui est fait") { finish() }
            Button("Abandonner sans enregistrer", role: .destructive) { abandon() }
            Button("Continuer", role: .cancel) {}
        }
    }

    // MARK: Déroulé

    private func restore() {
        guard !restored else { return }
        restored = true
        let saved = MobilityResume.load()
        switch MobilityResume.resolve(saved: saved, routineID: plan.id, stepCount: stretches.count,
                                      engineRunning: engine.isRunning, engineRemaining: engine.remaining) {
        case .none: break
        case .running(let i):
            progress = saved; progress?.index = i
            engine.onFinish = timerFinished
            engine.refresh()
        case .paused(let i):
            progress = saved; progress?.index = i
            engine.onFinish = timerFinished
        case .ready(let i):
            progress = saved; progress?.index = i
        case .expiredThenReady(let i):
            // L'exercice precedent s'est fini app fermee: il est fait.
            progress = saved
            progress?.doneSeconds += stretches[i - 1].seconds
            progress?.doneCount += 1
            progress?.index = i; progress?.waiting = true
            persist()
        case .finished:
            progress = saved
            progress?.doneSeconds += stretches[stretches.count - 1].seconds
            progress?.doneCount += 1
            finish()
        }
    }

    private func begin() {
        guard !stretches.isEmpty else { return }
        summary = nil; error = nil
        engine.stop()
        progress = MobilityProgress(routineID: plan.id, runID: UUID(), index: 0, startedAt: .now)
        startCurrent()
    }

    private func startCurrent() {
        progress?.waiting = false
        persist()
        engine.onFinish = timerFinished
        engine.start(seconds: stretches[index].seconds)
    }

    private func togglePause() {
        if waiting { startCurrent(); return }
        if engine.isRunning { engine.pause() } else {
            engine.onFinish = timerFinished
            engine.resume()
        }
    }

    private func timerFinished() {
        progress?.doneSeconds += stretches[index].seconds
        progress?.doneCount += 1
        advance()
    }

    private func skip() {
        Haptics.tap()
        if !waiting { progress?.doneSeconds += max(0, engine.total - engine.remaining) }
        advance()
    }

    private func advance() {
        // Le son systeme suit le bouton silencieux: rien ne sonne en mode silence.
        if soundOn { AudioServicesPlaySystemSound(1057) }
        if index < stretches.count - 1 {
            progress?.index = index + 1
            startCurrent()
        } else {
            finish()
        }
    }

    private func persist() { if let progress { MobilityResume.save(progress) } }

    private func abandon() {
        engine.stop(); MobilityResume.clear(); progress = nil
    }

    /// Enregistre la séance une fois par tentative (runID), si du temps a été fait.
    private func finish() {
        engine.stop()
        MobilityResume.clear()
        guard let p = progress else { return }
        progress = nil
        guard p.doneSeconds > 0 else { summary = "Rien à enregistrer : aucun exercice commencé."; return }
        guard FitnessHistory.shouldRecord(p.runID, existing: sessions.map(\.runID)) else { return }
        let s = MobilitySession(runID: p.runID, date: .now, routineName: plan.title, durationSeconds: p.doneSeconds,
                                exercisesDone: p.doneCount, exercisesTotal: stretches.count)
        ctx.insert(s)
        do {
            try ctx.save()
            summary = "Séance enregistrée : \(formatHMS(p.doneSeconds)), \(p.doneCount)/\(stretches.count) exercices."
        } catch {
            ctx.delete(s)
            self.error = "Séance non enregistrée : \(error.localizedDescription)"
        }
    }
}

// MARK: - Streaks & habitudes

struct StreaksView: View {
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]
    @Query(sort: \TabataSessionLog.date, order: .reverse) private var tabata: [TabataSessionLog]
    @Query(sort: \MobilitySession.date, order: .reverse) private var mobility: [MobilitySession]
    @AppStorage("streakz.weeklyTarget") private var weeklyTarget = 3
    @AppStorage("streakz.reminderOn") private var reminderOn = false
    @AppStorage("streakz.reminderMinutes") private var reminderMinutes = 18 * 60
    @State private var reminderDenied = false
    @State private var reminderError: String?

    private let cal = StreakEngine.frenchCalendar
    private var activity: [Date: StreakEngine.DayActivity] {
        StreakEngine.activity(strength: sets.map(\.date), tabata: tabata.map(\.date), mobility: mobility.map(\.date), calendar: cal)
    }

    var body: some View {
        let act = activity
        let days = Set(act.keys)
        let weekly = StreakEngine.weeklyStreak(days, target: weeklyTarget, today: .now, calendar: cal)
        let thisWeek = StreakEngine.activeDaysPerWeek(days, calendar: cal)[StreakEngine.weekStart(.now, calendar: cal)] ?? 0
        return ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill").font(.system(size: 50)).foregroundStyle(Theme.warning)
                        Text("\(weekly)").font(.system(size: 56, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        Text(weekly > 1 ? "semaines de série" : "semaine de série").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        Text("Cette semaine : \(min(thisWeek, 7))/\(weeklyTarget) jours actifs")
                            .font(.footnote.weight(.semibold)).foregroundStyle(thisWeek >= weeklyTarget ? Theme.success : Theme.textSecondary)
                        ProgressView(value: Double(min(thisWeek, weeklyTarget)), total: Double(max(1, weeklyTarget)))
                            .tint(thisWeek >= weeklyTarget ? Theme.success : .fitTint).frame(maxWidth: 260)
                    }.frame(maxWidth: .infinity).card()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        StatTile(value: "\(StreakEngine.dayStreak(days, today: .now, calendar: cal))", label: "jours d'affilée", icon: "calendar")
                        StatTile(value: "\(StreakEngine.bestDayStreak(days, calendar: cal))", label: "meilleure série (jours)", icon: "trophy.fill", tint: .fitTint)
                        StatTile(value: "\(StreakEngine.bestWeeklyStreak(days, target: weeklyTarget, calendar: cal))", label: "meilleure série (semaines)", icon: "rosette", tint: .fitTint)
                        StatTile(value: "\(days.count)", label: "jours actifs", icon: "checkmark.circle")
                    }

                    heatmapCard(act)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Ce qui compte", subtitle: "Un jour est actif dès une activité")
                        countRow("dumbbell.fill", "Séries de muscu", sets.count)
                        countRow("timer", "Séances Tabata", tabata.count)
                        countRow("figure.cooldown", "Séances de mobilité", mobility.count)
                    }.card()

                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("Objectif : \(weeklyTarget) jour\(weeklyTarget > 1 ? "s" : "") actif\(weeklyTarget > 1 ? "s" : "") par semaine",
                                value: $weeklyTarget, in: 1...7)
                        Text("Les jours de repos ne cassent pas ta série tant que l'objectif de la semaine est tenu. La semaine en cours ne compte qu'une fois l'objectif atteint.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }.card()

                    reminderCard
                }
                .padding(Theme.pad)
                .readableWidth()
            }
        }
        .navigationTitle("Streaks & habitudes").navigationBarTitleDisplayMode(.inline)
        .task { if reminderOn { await scheduleReminder() } }
    }

    private func countRow(_ icon: String, _ label: String, _ n: Int) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.fitTint).frame(width: 24)
            Text(label).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(n)").font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
        }
    }

    private func heatmapCard(_ act: [Date: StreakEngine.DayActivity]) -> some View {
        let grid = StreakEngine.heatmap(act, weeks: 18, today: .now, calendar: cal)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Calendrier", subtitle: "18 dernières semaines · lundi en haut")
            HStack(spacing: 3) {
                ForEach(grid.indices, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(grid[w]) { c in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color(c))
                                .aspectRatio(1, contentMode: .fit)
                                .accessibilityLabel("\(c.date.formatted(.dateTime.day().month())) : \(c.types) activité\(c.types > 1 ? "s" : "")")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Text("Moins").font(.caption2).foregroundStyle(Theme.textSecondary)
                ForEach(0..<4) { n in
                    RoundedRectangle(cornerRadius: 3).fill(color(StreakEngine.HeatCell(date: .now, types: n, isFuture: false))).frame(width: 12, height: 12)
                }
                Text("3 types (muscu, Tabata, mobilité)").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }.card()
    }

    private func color(_ c: StreakEngine.HeatCell) -> Color {
        if c.isFuture { return .clear }
        switch c.types {
        case 0: return Theme.textSecondary.opacity(0.15)
        case 1: return Color.fitTint.opacity(0.45)
        case 2: return Color.fitTint.opacity(0.75)
        default: return Color.fitTint
        }
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Rappel quotidien", isOn: $reminderOn).tint(.fitTint)
            if reminderOn {
                DatePicker("Heure", selection: Binding(
                    get: { cal.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now },
                    set: { d in
                        let c = cal.dateComponents([.hour, .minute], from: d)
                        reminderMinutes = (c.hour ?? 18) * 60 + (c.minute ?? 0)
                    }), displayedComponents: .hourAndMinute)
            }
            if reminderDenied { FitnessPermissionDenied(message: "Notifications refusées : le rappel ne peut pas sonner.") }
            if let reminderError { Text(reminderError).font(.footnote).foregroundStyle(Theme.warning) }
        }
        .card()
        .onChange(of: reminderOn) { _, _ in Task { await scheduleReminder() } }
        .onChange(of: reminderMinutes) { _, _ in Task { await scheduleReminder() } }
        .onChange(of: weeklyTarget) { _, _ in if reminderOn { Task { await scheduleReminder() } } }
    }

    private func scheduleReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [StreakReminder.id])
        guard reminderOn else { return }
        guard await FitnessNotify.ensureAuthorized() else { reminderOn = false; reminderDenied = true; return }
        reminderDenied = false
        let c = UNMutableNotificationContent()
        c.title = "Streakz"
        c.body = "Objectif : \(weeklyTarget) jour\(weeklyTarget > 1 ? "s" : "") actif\(weeklyTarget > 1 ? "s" : "") cette semaine. Muscu, Tabata ou mobilité, tout compte."
        c.sound = .default
        c.userInfo = ["route": "streakz"]
        let trigger = UNCalendarNotificationTrigger(dateMatching: StreakReminder.components(minutes: reminderMinutes), repeats: true)
        do {
            try await center.add(UNNotificationRequest(identifier: StreakReminder.id, content: c, trigger: trigger))
            reminderError = nil
        } catch {
            reminderError = "Rappel non programmé : \(error.localizedDescription)"
        }
    }
}
