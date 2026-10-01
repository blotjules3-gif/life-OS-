import SwiftUI
import SwiftData

// MARK: - Seance du jour : le programme, la charge conseillee, et le journal

/// Seance prevue par le programme. Demarrer cree une `TrainingSession` et FIGE la
/// charge conseillee de chaque exercice : logger une serie ne la change plus en cours
/// de route. Les series vont dans le MEME journal que Hevvy, rattachees a la seance.
/// Seule une seance TERMINEE sert de base a la prochaine progression. Une seance en
/// cours survit a la fermeture de l'app et se reprend ici.
struct GymSessionView: View {
    /// Jour de programme a demarrer (nil pour reprendre une seance par son id).
    var day: GymDay?
    /// Seance a reprendre, quel que soit le jour (commencee la veille, jour renomme...).
    var sessionID: UUID? = nil
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]
    @Query(sort: \TrainingSession.start, order: .reverse) private var sessions: [TrainingSession]
    @AppStorage(AppStorageKeys.userBench1RM) private var bench1RM: Double = 0
    @AppStorage(AppStorageKeys.userSquat1RM) private var squat1RM: Double = 0
    @AppStorage(AppStorageKeys.userDeadlift1RM) private var deadlift1RM: Double = 0
    @AppStorage(AppStorageKeys.gymMinIncrement) private var minIncrement: Double = 0
    @AppStorage(AppStorageKeys.gymRestSeconds) private var restSeconds = 90
    @State private var error: String?
    @State private var confirmCancel = false
    @State private var record: String?

    /// Seance en cours : par son id si on reprend, sinon celle rattachee a CE jour
    /// (par identifiant de jour, jamais par titre).
    private var active: TrainingSession? {
        if let sessionID {
            return sessions.first { $0.id == sessionID && $0.state == GymSessionService.State.active.rawValue }
        }
        guard let day else { return nil }
        return GymSessionService.activeSession(for: day, in: sessions)
    }
    /// Exercices : la liste FIGEE de la seance en cours ; sinon celle du programme.
    private var exercises: [String] {
        if let active { return GymSessionService.frozenExercises(of: active) }
        return (day?.focus ?? "").split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var title: String { active?.title ?? day?.title ?? "Séance" }
    private var logged: [StrengthProgression.LoggedSet] { sets.map(\.logged) }
    private var doneIDs: Set<UUID> { GymSessionService.doneIDs(sessions) }

    var body: some View {
        List {
            if exercises.isEmpty {
                Text("Aucun exercice dans cette séance. Ajoute-les dans le programme.").foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning)
            }
            if let session = active {
                recoverySection(session)
                if let end = session.restEnd, end > .now { restSection(end, session) }
                if let record { Label(record, systemImage: "trophy.fill").font(.subheadline.weight(.semibold)) }
                let frozen = GymSessionService.prescriptions(of: session)
                ForEach(exercises, id: \.self) { label in
                    ExerciseBlock(label: label,
                                  superset: GymSessionService.supersetPartner(of: label, in: session),
                                  prescription: frozen[GymExercises.baseName(label)],
                                  usesDefaultTarget: StrengthProgression.target(from: label) == nil,
                                  done: sessionSets(session, label),
                                  onLog: { w, r, rpe, kind in log(label, w, r, rpe, kind, session) },
                                  onDelete: { remove($0) })
                }
                Section {
                    Button { finish(session) } label: { Label("Terminer la séance", systemImage: "checkmark.seal.fill") }
                    Button(role: .destructive) { confirmCancel = true } label: { Label("Annuler la séance", systemImage: "xmark.circle") }
                } footer: {
                    Text("Commencée à \(session.start.formatted(date: .omitted, time: .shortened)). Seule une séance terminée sert à calculer les prochaines charges.")
                }
            } else if !exercises.isEmpty {
                Section {
                    Button { start() } label: { Label("Commencer la séance", systemImage: "play.circle.fill") }
                } footer: {
                    Text("Les charges conseillées sont calculées au démarrage, à partir de tes séances terminées, et ne bougent plus pendant la séance.")
                }
            }
        }
        .navigationTitle(title.isEmpty ? "Séance" : title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Annuler la séance ?", isPresented: $confirmCancel, titleVisibility: .visible) {
            if let s = active {
                Button("Annuler et garder les séries dans l'historique") { cancel(s, deleteSets: false) }
                Button("Annuler et effacer ses séries", role: .destructive) { cancel(s, deleteSets: true) }
            }
        } message: {
            Text("Une séance annulée ne sert jamais de base de progression.")
        }
    }

    /// Groupes travailles il y a moins de 48 h, seance en cours exclue (une seance
    /// plus tot aujourd'hui compte).
    @ViewBuilder private func recoverySection(_ session: TrainingSession) -> some View {
        let groups = Array(Set(exercises.compactMap { GymExercises.group(of: $0) })).sorted()
        let tired = groups.compactMap { g -> (String, Int)? in
            guard let h = StrengthProgression.hoursSince(group: g, in: logged, excludingSession: session.id), h < 48 else { return nil }
            return (g, Int(h))
        }
        if !tired.isEmpty {
            Section {
                ForEach(tired, id: \.0) { g, h in
                    Label("\(g) travaillés il y a \(h) h : récupération incomplète, reste léger.", systemImage: "bed.double.fill")
                        .font(.footnote)
                }
            }
        }
    }

    private func restSection(_ end: Date, _ session: TrainingSession) -> some View {
        Section {
            HStack {
                Label { Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit() } icon: { Image(systemName: "timer") }
                Spacer()
                Button("Passer") { skipRest(session) }.buttonStyle(.borderless)
            }
        } header: { Text("Repos") } footer: {
            Text("Le repos continue si tu quittes l'écran ou l'app ; une notification sonne à la fin.")
        }
    }

    private func sessionSets(_ session: TrainingSession, _ label: String) -> [WorkoutSet] {
        let key = StrengthProgression.normalized(label)
        return sets.filter { $0.sessionID == session.id && StrengthProgression.normalized($0.exercise) == key }
            .sorted { $0.date < $1.date }
    }

    private func profile1RM(_ label: String) -> Double? {
        let n = StrengthProgression.normalized(label)
        if n.hasPrefix("developpe couche") { return bench1RM > 0 ? bench1RM : nil }
        if n.hasPrefix("squat") { return squat1RM > 0 ? squat1RM : nil }
        if n.hasPrefix("souleve de terre") && !n.contains("roumain") { return deadlift1RM > 0 ? deadlift1RM : nil }
        return nil
    }

    private func start() {
        guard let day else { return }
        do {
            try GymSessionService.start(day: day, title: day.title, exercises: exercises, history: logged, doneSessions: doneIDs,
                                        profile1RM: profile1RM, minIncrement: minIncrement, in: ctx)
            error = nil; Haptics.tap()
        } catch let e { error = e.localizedDescription; Haptics.warning() }
    }

    private static let restNotificationID = "gym.rest"

    private func scheduleRestNotification(_ end: Date?) {
        NotificationManager.shared.cancel(id: Self.restNotificationID)
        if let end, end > .now {
            NotificationManager.shared.schedule(id: Self.restNotificationID, title: "Repos terminé",
                                                body: "Série suivante : \(title)", at: end)
        }
    }

    private func skipRest(_ s: TrainingSession) {
        do { try GymSessionService.skipRest(s, in: ctx); scheduleRestNotification(nil) }
        catch let e { error = e.localizedDescription }
    }

    /// Rend true seulement si la serie est vraiment enregistree : la saisie n'est
    /// videe qu'a ce moment-la.
    private func log(_ label: String, _ weight: String, _ reps: Int, _ rpe: Double, _ kind: WorkoutSetKind,
                     _ session: TrainingSession) -> Bool {
        let history = StrengthProgression.completed(logged, doneSessions: doneIDs)
        do {
            let set = try GymSessionService.log(exercise: label, weightText: weight, reps: reps, rpe: rpe, kind: kind,
                                                session: session,
                                                restSeconds: GymSessionService.restSeconds(after: label, in: session, default: restSeconds),
                                                in: ctx)
            error = nil
            record = StrengthProgression.isPersonalRecord(set.logged, history: history)
                ? "Record sur \(set.exercise) : \(StrengthProgression.fmt(set.weightKg)) kg × \(set.reps)" : nil
            scheduleRestNotification(session.restEnd)
            Haptics.success()
            return true
        } catch let e {
            error = e.localizedDescription; Haptics.warning()
            return false
        }
    }

    private func remove(_ set: WorkoutSet) {
        do { try GymSessionService.delete(set, in: ctx); error = nil } catch let e { error = e.localizedDescription }
    }

    private func finish(_ s: TrainingSession) {
        do { try GymSessionService.finish(s, in: ctx); error = nil; scheduleRestNotification(nil); Haptics.success() }
        catch let e { error = e.localizedDescription; Haptics.warning() }
    }

    private func cancel(_ s: TrainingSession, deleteSets: Bool) {
        do { try GymSessionService.cancel(s, deleteSets: deleteSets, sets: sets, in: ctx); error = nil; scheduleRestNotification(nil) }
        catch let e { error = e.localizedDescription; Haptics.warning() }
    }
}

private struct ExerciseBlock: View {
    let label: String
    /// Exercice enchaine avec celui-ci (superset), s'il y en a un.
    var superset: String? = nil
    let prescription: StrengthProgression.Prescription?
    let usesDefaultTarget: Bool
    let done: [WorkoutSet]
    let onLog: (String, Int, Double, WorkoutSetKind) -> Bool
    let onDelete: (WorkoutSet) -> Void

    @State private var weight = ""
    @State private var reps = 0
    @State private var rpe = 8.0
    @State private var kind: WorkoutSetKind = .work

    private var canLog: Bool { GymSessionService.parseWeight(weight) != nil && reps > 0 }

    var body: some View {
        Section {
            if let p = prescription {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.weight.map { "\(p.sets) × \(p.reps) à \(StrengthProgression.fmt($0)) kg" } ?? "\(p.sets) × \(p.reps)")
                        .font(.headline)
                    Text(p.reason).font(.caption).foregroundStyle(.secondary)
                    if usesDefaultTarget {
                        Text("Pas de cible dans le programme : cible par défaut 3 × 8 à 12.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(Array(done.enumerated()), id: \.element.id) { i, s in
                HStack {
                    Text("\(i + 1). \((WorkoutSetKind(rawValue: s.kind) ?? .work).label)")
                    Spacer()
                    Text("\(StrengthProgression.fmt(s.weightKg)) kg × \(s.reps) · effort \(Int(s.rpe))").foregroundStyle(.secondary)
                }
                .swipeActions { Button(role: .destructive) { onDelete(s) } label: { Label("Supprimer", systemImage: "trash") } }
            }
            if prescription != nil {
                Picker("Type", selection: $kind) {
                    ForEach(WorkoutSetKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    TextField("kg", text: $weight).keyboardType(.decimalPad).frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Charge en kilos")
                    Stepper("\(reps) reps", value: $reps, in: 0...50).fixedSize()
                }
                if !weight.isEmpty && GymSessionService.parseWeight(weight) == nil {
                    Text("Charge entre 0 et 1000 kg.").font(.caption).foregroundStyle(Theme.warning)
                }
                Picker("Effort ressenti", selection: $rpe) {
                    ForEach([6.0, 7, 8, 9, 10], id: \.self) { Text("\(Int($0))/10").tag($0) }
                }
                .pickerStyle(.segmented)
                Button {
                    // La saisie reste en place si l'enregistrement echoue.
                    if onLog(weight, reps, rpe, kind), kind == .warmup { kind = .work }
                } label: { Label("Valider la série", systemImage: "checkmark.circle.fill") }
                .disabled(!canLog)
            }
        } header: {
            if let superset {
                Text("\(GymExercises.baseName(label)) · superset avec \(superset)")
            } else {
                Text(GymExercises.baseName(label))
            }
        }
        .onAppear {
            if weight.isEmpty, let w = done.last?.weightKg ?? prescription?.weight { weight = StrengthProgression.fmt(w) }
            if reps == 0 { reps = done.last?.reps ?? prescription?.reps ?? 0 }
        }
    }
}

// MARK: - Volume de la semaine

/// Series difficiles par groupe sur 7 jours, avec le repere 10 a 20.
struct GymWeeklyVolumeView: View {
    let sets: [WorkoutSet]
    var body: some View {
        let vol = StrengthProgression.weeklyHardSets(sets.map(\.logged))  // series de travail seulement
        let groups = GymExercises.catalog.keys.filter { $0 != "Cardio" }.sorted()
        ForEach(groups, id: \.self) { g in
            let n = vol[g, default: 0]
            HStack {
                Text(g)
                Spacer()
                Text("\(n) série\(n > 1 ? "s" : "")")
                    .foregroundStyle(n == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                Image(systemName: n >= 10 && n <= 20 ? "checkmark.circle.fill" : (n > 20 ? "exclamationmark.circle" : "circle"))
                    .foregroundStyle(n >= 10 && n <= 20 ? Theme.success : (n > 20 ? Theme.warning : Color.secondary))
                    .accessibilityLabel(n >= 10 && n <= 20 ? "dans la cible" : (n > 20 ? "au-dessus de la cible" : "sous la cible"))
            }
        }
    }
}

#if DEBUG
/// `-shotGymSession` : remplit la seance du jour (modele "Dos + Biceps") et, avec
/// `-shotGymStart`, la demarre et logue une serie, pour REGARDER l'ecran sans taper.
/// Absent des builds Release.
struct GymSessionShot: View {
    @Environment(\.modelContext) private var ctx
    @Query private var days: [GymDay]
    @State private var day: GymDay?

    var body: some View {
        NavigationStack {
            if let day { GymSessionView(day: day) } else { ProgressView() }
        }
        .task {
            let w = Calendar.current.component(.weekday, from: .now)
            let d = days.first { $0.weekday == w } ?? { let n = GymDay(weekday: w); ctx.insert(n); return n }()
            d.isRest = false; d.title = "Dos + Biceps"
            d.focus = GymExercises.focus(for: "Dos + Biceps", goal: "Prise de muscle")
            try? ctx.save()
            if DebugLaunchFlags.has("-shotGymStart"),
               let s = try? GymSessionService.start(day: d, title: d.title, exercises: d.focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) },
                                                    history: [], doneSessions: [], in: ctx) {
                try? GymSessionService.log(exercise: "Tractions pronation", weightText: "0", reps: 8, rpe: 8, kind: .work, session: s, in: ctx)
            }
            day = d
        }
    }
}
#endif
