import SwiftUI
import SwiftData

// Lundi → Dimanche (la convention Calendar met Dimanche = 1).
let gymWeekOrder = [2, 3, 4, 5, 6, 7, 1]
func gymWeekdayName(_ w: Int) -> String {
    ["", "Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"][w]
}

// MARK: - Programme de sport

struct GymProgramView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var days: [GymDay]
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]
    @Query private var sessions: [TrainingSession]
    @Query(sort: \GymProgramPlan.createdAt) private var plans: [GymProgramPlan]
    @AppStorage(FitbotSettings.equipmentKey) private var equipmentRaw = ""
    @AppStorage(FitbotSettings.excludedKey) private var excludedRaw = ""
    @AppStorage(AppStorageKeys.gymMinIncrement) private var minIncrement: Double = 0
    @AppStorage(AppStorageKeys.gymRestSeconds) private var restSeconds = 90

    @AppStorage(AppStorageKeys.gymReminderOn)     private var on = true
    @AppStorage(AppStorageKeys.gymReminderHour)   private var hour = 7
    @AppStorage(AppStorageKeys.gymReminderMinute) private var minute = 0
    @AppStorage(AppStorageKeys.gymConfirm)        private var confirm = true

    @State private var editing: GymDay?
    @State private var generating = false
    @State private var confirmUndo = false
    @State private var programError: String?

    private var equipment: Set<FitbotEquipment> { FitbotEquipment.parse(equipmentRaw) }
    private var excluded: Set<String> { FitbotSettings.parseExcluded(excludedRaw) }
    private var activePlan: GymProgramPlan? { FitbotProgramService.activePlan(plans) }

    private func day(_ w: Int) -> GymDay? { days.first { $0.weekday == w } }

    var body: some View {
        Form {
            Section {
                Toggle("Rappel chaque jour d'entraînement", isOn: $on)
                    .onChange(of: on) { _, _ in reschedule() }
                if on {
                    DatePicker("Heure", selection: timeBinding, displayedComponents: .hourAndMinute)
                    Toggle("Vérif « bien été ? » +1h30", isOn: $confirm)
                        .onChange(of: confirm) { _, _ in reschedule() }
                }
            } header: {
                Text("Rappel salle")
            } footer: {
                Text("Chaque jour d'entraînement, une notif motivante avec la séance du jour. Les jours de repos, rien.")
            }

            // Une seance ouverte se reprend par son identifiant, quel que soit le jour
            // (commencee hier, jour renomme ou devenu repos entre-temps).
            if let open = GymSessionService.anyActive(sessions) {
                Section("Séance en cours") {
                    NavigationLink {
                        GymSessionView(day: nil, sessionID: open.id)
                    } label: {
                        Label("Reprendre : \(open.title) (commencée \(open.start.formatted(.relative(presentation: .named))))",
                              systemImage: "arrow.clockwise.circle.fill")
                    }
                }
            } else if let today = day(Calendar.current.component(.weekday, from: .now)) {
                Section("Aujourd'hui") {
                    if today.isRest || today.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(today.isRest ? "Repos. La récupération fait aussi progresser." : "Pas de séance définie aujourd'hui.")
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            GymSessionView(day: today)
                        } label: {
                            Label("Commencer : \(today.title)", systemImage: "play.circle.fill")
                        }
                    }
                }
            }

            programSection
            historySection
            equipmentSection

            Section {
                GymWeeklyVolumeView(sets: sets)
            } header: {
                Text("Volume sur 7 jours")
            } footer: {
                Text("Séries avec un effort d'au moins 7/10, par muscle. Repère courant pour progresser : 10 à 20 par semaine.")
            }

            Section {
                Picker("Plus petit pas de charge", selection: $minIncrement) {
                    Text("Automatique").tag(0.0)
                    ForEach([1.0, 1.25, 2, 2.5, 5], id: \.self) { Text("\(StrengthProgression.fmt($0)) kg").tag($0) }
                }
                Picker("Repos entre les séries", selection: $restSeconds) {
                    ForEach([60, 90, 120, 180, 240], id: \.self) { Text("\($0 / 60) min\($0 % 60 == 0 ? "" : " 30")").tag($0) }
                }
            } header: {
                Text("Réglages de séance")
            } footer: {
                Text("Automatique : 5 kg sur les gros exercices de jambes, 2 kg aux haltères, 2,5 kg ailleurs. Choisis tes plus petits disques si ta salle en a d'autres.")
            }

            Section("Ma semaine") {
                ForEach(gymWeekOrder, id: \.self) { w in
                    let d = day(w)
                    Button { editing = d } label: {
                        HStack(spacing: 12) {
                            Text(gymWeekdayName(w)).foregroundStyle(.primary)
                            Spacer()
                            if let d, !d.isRest, !FitbotSupersets.decode(d.supersetsJSON).isEmpty {
                                Image(systemName: "link").font(.caption).foregroundStyle(.fitTint)
                                    .accessibilityLabel("avec superset")
                            }
                            Text(label(for: d))
                                .font(.subheadline)
                                .foregroundStyle(color(for: d))
                                .lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Programme de sport").navigationBarTitleDisplayMode(.inline)
        .task {
            seedIfNeeded()
            _ = try? GymSessionService.migrateExerciseNames(in: ctx)
            _ = await NotificationManager.shared.requestAuthorization()
        }
        .sheet(item: $editing) { d in
            GymDayEditor(day: d) { reschedule() }
        }
        .sheet(isPresented: $generating) {
            FitbotGeneratorSheet(days: days) { reschedule() }
        }
        .confirmationDialog("Revenir à la semaine d'avant ?", isPresented: $confirmUndo, titleVisibility: .visible) {
            Button("Revenir à la semaine d'avant", role: .destructive) { undoProgram() }
        } message: {
            Text("Ta semaine redevient celle d'avant le programme, retouches faites depuis comprises. Tes séances passées ne changent pas.")
        }
    }

    // MARK: Programme, historique, matériel

    @ViewBuilder private var programSection: some View {
        Section {
            if let plan = activePlan {
                let goal = FitbotGoal(rawValue: plan.goal)?.label ?? plan.goal
                let split = FitbotSplit(rawValue: plan.split)?.label ?? plan.split
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(goal) · \(split)").font(.headline)
                    Text("\(plan.daysPerWeek) séances par semaine · \(plan.sessionMinutes) min · depuis le \(plan.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { generating = true } label: {
                Label(activePlan == nil ? "Générer mon programme" : "Générer un nouveau programme",
                      systemImage: "wand.and.stars")
            }
            if let plan = FitbotProgramService.latestUndoable(plans) {
                Button(role: .destructive) { confirmUndo = true } label: {
                    Label("Revenir à la semaine d'avant le \(plan.createdAt.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "arrow.uturn.backward")
                }
            }
            if let programError {
                Label(programError, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning)
            }
        } header: {
            Text("Programme")
        } footer: {
            Text("Selon ton objectif, tes jours, la durée et ton matériel. Tu vois la semaine avant de remplacer la tienne, et tu peux revenir en arrière.")
        }
    }

    @ViewBuilder private var historySection: some View {
        let doneStarts = sessions.filter { $0.state == GymSessionService.State.done.rawValue }.map(\.start)
        Section {
            if let plan = activePlan {
                let rows = FitbotHistory.weeks(planStart: plan.createdAt, planEnd: nil, planned: plan.daysPerWeek,
                                               doneSessionStarts: doneStarts)
                ForEach(rows.suffix(8).reversed(), id: \.index) { r in
                    HStack {
                        Text("Semaine \(r.index)")
                        Text(r.start.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(r.done) / \(r.planned) séances")
                            .foregroundStyle(r.done >= r.planned ? Theme.success : Color.secondary)
                    }
                }
                ForEach(FitbotProgramService.previousPlans(plans), id: \.persistentModelID) { p in
                    let rows = FitbotHistory.weeks(planStart: p.createdAt, planEnd: FitbotProgramService.end(of: p, in: plans),
                                                   planned: p.daysPerWeek, doneSessionStarts: doneStarts)
                    HStack {
                        Text("Avant : \(FitbotGoal(rawValue: p.goal)?.label ?? p.goal), \(rows.count) sem.")
                            .font(.subheadline)
                        Spacer()
                        Text("\(rows.map(\.done).reduce(0, +)) / \(rows.map(\.planned).reduce(0, +))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } else {
                let planned = days.filter { !$0.isRest && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.count
                let weekStart = FitbotHistory.mondayCalendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
                let rows = FitbotHistory.weeks(planStart: weekStart, planEnd: nil, planned: planned, doneSessionStarts: doneStarts)
                HStack {
                    Text("Cette semaine")
                    Spacer()
                    Text("\(rows.last?.done ?? 0) / \(planned) séances").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Historique du programme")
        } footer: {
            Text("Séances terminées contre séances prévues, semaine par semaine depuis le début du programme.")
        }
    }

    @ViewBuilder private var equipmentSection: some View {
        Section {
            ForEach(FitbotEquipment.allCases) { e in
                Toggle(isOn: Binding(
                    get: { equipment.contains(e) },
                    set: { on in
                        var set = equipment
                        if on { set.insert(e) } else { set.remove(e) }
                        // Jamais vide : sans rien, on revient a la salle complète.
                        equipmentRaw = FitbotEquipment.serialize(set.isEmpty ? [.gym] : set)
                    })) {
                    Label(e.label, systemImage: e.icon)
                }
                .tint(.fitTint)
            }
            if !excluded.isEmpty {
                DisclosureGroup("Exercices exclus (\(excluded.count))") {
                    ForEach(excluded.sorted(), id: \.self) { name in
                        HStack {
                            Text(name).font(.subheadline)
                            Spacer()
                            Button("Réautoriser") {
                                var set = excluded; set.remove(name)
                                excludedRaw = FitbotSettings.serializeExcluded(set)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        } header: {
            Text("Mon matériel")
        } footer: {
            Text("Les ajouts, remplacements et programmes ne proposent que des exercices faisables avec ce matériel, jamais un exercice exclu. Le catalogue n'a pas encore d'exercice aux élastiques : avec eux, seuls les exercices au poids du corps sont proposés.")
        }
    }

    private func undoProgram() {
        guard let plan = FitbotProgramService.latestUndoable(plans) else { return }
        do {
            try FitbotProgramService.undo(plan, days: days, in: ctx)
            programError = nil; reschedule(); Haptics.success()
        } catch let e { programError = e.localizedDescription; Haptics.warning() }
    }

    private func label(for d: GymDay?) -> String {
        guard let d else { return "—" }
        if d.isRest { return "Repos" }
        return d.title.trimmingCharacters(in: .whitespaces).isEmpty ? "À définir" : d.title
    }
    private func color(for d: GymDay?) -> Color {
        guard let d, !d.isRest, !d.title.trimmingCharacters(in: .whitespaces).isEmpty else { return .secondary }
        return .fitTint
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents(); c.hour = hour; c.minute = minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { v in
                let c = Calendar.current.dateComponents([.hour, .minute], from: v)
                hour = c.hour ?? 7; minute = c.minute ?? 0
                reschedule()
            }
        )
    }

    private func seedIfNeeded() {
        guard days.isEmpty else { return }
        for w in 1...7 { ctx.insert(GymDay(weekday: w)) }
    }

    private func reschedule() {
        for w in 1...7 {
            NotificationManager.shared.cancel(id: "gym.day.\(w)")
            NotificationManager.shared.cancel(id: "gym.day.\(w).confirm")
            NotificationManager.shared.cancel(id: "gym.day.\(w).protein")
        }
        guard on else { return }
        // Heure d'entraînement (par défaut 18h) pour caler la collation post-séance.
        let trainHour = UserDefaults.standard.integer(forKey: "sportHour")
        let trainStart = (trainHour > 0 ? trainHour : 18) * 60
        for w in 1...7 {
            guard let d = day(w), !d.isRest,
                  !d.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let extra = d.focus.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "\n\(d.focus)"
            NotificationManager.shared.scheduleWeekly(
                id: "gym.day.\(w)",
                title: "SALLE DE SPORT",
                body: "Allez, lève-toi! Aujourd'hui : \(d.title)" + extra,
                weekday: w, hour: hour, minute: minute)

            // Post-séance (~10 min après une séance d'~1 h) : protéines + créatine.
            var pw = w
            var pwTotal = trainStart + 70
            if pwTotal >= 1440 { pwTotal -= 1440; pw = w % 7 + 1 }
            NotificationManager.shared.scheduleWeekly(
                id: "gym.day.\(w).protein",
                title: "Fin de séance",
                body: "Dans la foulée : ~30 g de protéines + ta créatine pour bien récupérer.",
                weekday: pw, hour: pwTotal / 60, minute: pwTotal % 60)
            if confirm {
                var cw = w
                var total = hour * 60 + minute + 90
                if total >= 1440 { total -= 1440; cw = w % 7 + 1 }   // dépasse minuit → jour suivant
                NotificationManager.shared.scheduleWeekly(
                    id: "gym.day.\(w).confirm",
                    title: "Séance faite ?",
                    body: "Tu as bien été à la salle (\(d.title)) ?",
                    weekday: cw, hour: total / 60, minute: total % 60,
                    categoryId: "LIFEOS_CONFIRM",
                    userInfo: ["confirmKey": "gym", "confirmLabel": "ta séance"])
            }
        }
    }
}

// MARK: - Éditeur d'un jour

struct GymDayEditor: View {
    @Bindable var day: GymDay
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FitbotSettings.equipmentKey) private var equipmentRaw = ""
    @AppStorage(FitbotSettings.excludedKey) private var excludedRaw = ""
    @State private var showAI = false

    private var equipment: Set<FitbotEquipment> { FitbotEquipment.parse(equipmentRaw) }
    private var excluded: Set<String> { FitbotSettings.parseExcluded(excludedRaw) }
    private var exercises: [String] {
        day.focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var pairs: [[String]] { FitbotSupersets.decode(day.supersetsJSON) }

    /// Ecrit la liste ET nettoie les supersets : une paire dont un exercice est parti,
    /// ou qui n'est plus voisine, disparait.
    private func write(_ list: [String], pairs newPairs: [[String]]? = nil) {
        day.focus = list.joined(separator: " · ")
        day.supersetsJSON = FitbotSupersets.encode(FitbotSupersets.prune(newPairs ?? pairs, exercises: list))
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Jour de repos", isOn: $day.isRest).tint(.fitTint)
                if !day.isRest {
                    Section("Séance") {
                        TextField("Nom (ex: Dos + Biceps)", text: $day.title)
                    }
                    Section {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { i, ex in
                            exerciseRow(i, ex)
                        }
                        addMenu
                    } header: {
                        Text("Exercices")
                    } footer: {
                        Text("↻ propose un exercice du même groupe musculaire, faisable avec ton matériel (\(FitbotEquipment.summary(equipment))). Glisse pour supprimer, exclure ou faire un superset avec l'exercice suivant.")
                    }
                }
            }
            .navigationTitle(gymWeekdayName(day.weekday)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !day.isRest {
                        Button { showAI = true } label: { Image(systemName: "infinity") }.tint(.fitTint).accessibilityLabel("Ton coach")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { onDone(); dismiss() }
                }
            }
            .sheet(isPresented: $showAI) {
                ToolAISheet(title: "Modifier la séance",
                            placeholder: "Ex : le développé couché, la machine n'est pas dispo, remplace-le") { request in
                    applyAI(request)
                }
            }
        }
    }

    private func exerciseRow(_ i: Int, _ ex: String) -> some View {
        let partner = FitbotSupersets.partner(of: ex, in: pairs)
        let alts = GymExercises.alternatives(for: ex, avoiding: exercises, equipment: equipment, excluded: excluded)
        return HStack(spacing: 10) {
            Image(systemName: "\(min(i + 1, 50)).circle.fill").foregroundStyle(.fitTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex).font(.subheadline)
                if let partner {
                    Label("Superset avec \(partner)", systemImage: "link").font(.caption2).foregroundStyle(.fitTint)
                }
                if !GymExercises.isAllowed(ex, with: equipment) {
                    Label("Demande du matériel que tu n'as pas", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            Menu {
                if alts.isEmpty {
                    Text("Aucun remplaçant avec ton matériel")
                } else {
                    ForEach(alts, id: \.self) { alt in
                        Button(GymExercises.baseName(alt)) { replace(at: i, with: alt) }
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.fitTint)
            }
            .accessibilityLabel("Remplacer \(GymExercises.baseName(ex))")
        }
        .swipeActions {
            Button(role: .destructive) { remove(at: i) } label: { Label("Suppr", systemImage: "trash") }
            if GymExercises.group(of: ex) != nil {
                Button { exclude(at: i) } label: { Label("Exclure", systemImage: "nosign") }.tint(.orange)
            }
        }
        .swipeActions(edge: .leading) {
            if partner != nil {
                Button { write(exercises, pairs: FitbotSupersets.unpair(ex, pairs: pairs)) } label: {
                    Label("Dissocier", systemImage: "link.badge.plus")
                }
            } else if i + 1 < exercises.count {
                Button { write(exercises, pairs: FitbotSupersets.pair(at: i, exercises: exercises, pairs: pairs)); Haptics.tap() } label: {
                    Label("Superset", systemImage: "link")
                }.tint(.fitTint)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(GymExercises.catalog.keys.sorted(), id: \.self) { group in
                let present = Set(exercises.map { GymExercises.baseName($0) })
                let options = GymExercises.choices(group: group, equipment: equipment, excluded: excluded)
                    .filter { !present.contains($0) }
                Menu(group) {
                    if options.isEmpty {
                        Text("Aucun exercice avec ton matériel")
                    } else {
                        ForEach(options, id: \.self) { name in
                            Button(name) { add(name, group: group) }
                        }
                    }
                }
            }
        } label: {
            Label("Ajouter un exercice", systemImage: "plus.circle.fill").foregroundStyle(.fitTint)
        }
    }

    private func replace(at i: Int, with alt: String) {
        var list = exercises
        guard list.indices.contains(i) else { return }
        let renamed = FitbotSupersets.rename(list[i], to: alt, pairs: pairs)
        list[i] = alt; write(list, pairs: renamed); Haptics.tap()
    }
    private func remove(at i: Int) {
        var list = exercises; guard list.indices.contains(i) else { return }
        list.remove(at: i); write(list); Haptics.tap()
    }
    /// Retire l'exercice ET l'exclut : ni les ajouts, ni les remplacements, ni les
    /// programmes generes ne le reproposent.
    private func exclude(at i: Int) {
        let list = exercises; guard list.indices.contains(i) else { return }
        var set = excluded; set.insert(GymExercises.baseName(list[i]))
        excludedRaw = FitbotSettings.serializeExcluded(set)
        remove(at: i)
    }
    private func add(_ name: String, group: String) {
        // Meme cible que les autres exercices du jour, sinon cible par defaut a la seance.
        let suffix = exercises.lazy.map(GymExercises.repsSuffix).first { !$0.isEmpty } ?? ""
        var list = exercises
        list.append(group == "Cardio" ? name : name + suffix)
        write(list); Haptics.tap()
    }

    /// Édition en langage naturel : repère un exercice cité et le remplace.
    private func applyAI(_ request: String) -> String {
        let text = request.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let list = exercises
        for (i, ex) in list.enumerated() {
            let base = GymExercises.baseName(ex).lowercased().folding(options: .diacriticInsensitive, locale: .current)
            // mot-clé principal de l'exercice (premier mot significatif)
            let key = base.split(separator: " ").first.map(String.init) ?? base
            if text.contains(base) || (key.count > 3 && text.contains(key)) {
                if let alt = GymExercises.alternative(for: ex, avoiding: list, equipment: equipment, excluded: excluded) {
                    replace(at: i, with: alt); Haptics.success()
                    return "Remplacé par : \(GymExercises.baseName(alt))"
                }
                return "Aucun autre exercice du même groupe n'est faisable avec ton matériel."
            }
        }
        return "Dis-moi quel exercice remplacer (ex : « remplace le squat »), ou touche ↻ à côté de l'exercice."
    }
}

// MARK: - Générateur de programme

/// Choix de l'objectif, des jours, de la durée et du matériel, APERCU de la semaine
/// obtenue a cote de l'actuelle, puis remplacement (annulable depuis le programme).
struct FitbotGeneratorSheet: View {
    let days: [GymDay]
    var onApplied: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FitbotSettings.equipmentKey) private var equipmentRaw = ""
    @AppStorage(FitbotSettings.excludedKey) private var excludedRaw = ""
    @AppStorage(AppStorageKeys.gymRestSeconds) private var restSeconds = 90
    @AppStorage("fitbot.lastGoal") private var goalRaw = FitbotGoal.hypertrophie.rawValue
    @AppStorage("fitbot.lastDays") private var daysPerWeek = 3
    @AppStorage("fitbot.lastMinutes") private var minutes = 60
    @State private var setRest = true
    @State private var error: String?

    private var goal: FitbotGoal { FitbotGoal(rawValue: goalRaw) ?? .hypertrophie }
    private var equipment: Set<FitbotEquipment> { FitbotEquipment.parse(equipmentRaw) }
    private var week: FitbotGenerator.Week {
        FitbotGenerator.generate(goal: goal, daysPerWeek: daysPerWeek, sessionMinutes: minutes,
                                 equipment: equipment, excluded: FitbotSettings.parseExcluded(excludedRaw))
    }
    private var current: [Int: GymDaySnapshot] {
        Dictionary(FitbotProgramService.snapshot(days).map { ($0.weekday, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Objectif", selection: $goalRaw) {
                        ForEach(FitbotGoal.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Stepper("\(daysPerWeek) séances par semaine", value: $daysPerWeek, in: FitbotGenerator.allowedDays)
                    Picker("Durée d'une séance", selection: $minutes) {
                        ForEach(FitbotGenerator.sessionLengths, id: \.self) { Text("\($0) min").tag($0) }
                    }
                } header: {
                    Text("Ton programme")
                }

                Section {
                    ForEach(FitbotEquipment.allCases) { e in
                        Toggle(isOn: Binding(
                            get: { equipment.contains(e) },
                            set: { on in
                                var set = equipment
                                if on { set.insert(e) } else { set.remove(e) }
                                equipmentRaw = FitbotEquipment.serialize(set.isEmpty ? [.gym] : set)
                            })) { Label(e.label, systemImage: e.icon) }
                            .tint(.fitTint)
                    }
                } header: {
                    Text("Matériel disponible")
                }

                let w = week
                Section {
                    LabeledContent("Découpage", value: w.split.label)
                    LabeledContent("Par exercice", value: goal.guidance)
                    Toggle("Régler le repos entre séries sur \(goal.restSeconds < 60 ? "\(goal.restSeconds) s" : "\(goal.restSeconds / 60) min\(goal.restSeconds % 60 == 0 ? "" : " 30")")", isOn: $setRest)
                        .tint(.fitTint)
                    if !w.uncoveredGroups.isEmpty {
                        Label("Aucun exercice du catalogue pour \(w.uncoveredGroups.joined(separator: ", ")) avec ce matériel : ces muscles ne sont pas travaillés.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Theme.warning)
                    }
                } header: {
                    Text("Ce que ça donne")
                } footer: {
                    Text("\(w.daysPerWeek) séances : \(w.split.label.lowercased()). Séries, répétitions et repos sont des repères généraux d'entraînement, pas un avis médical. Les charges viennent ensuite de tes séances terminées.")
                }

                Section {
                    ForEach(w.days, id: \.weekday) { d in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(gymWeekdayName(d.weekday)).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(d.isRest ? "Repos" : d.title)
                                    .font(.subheadline).foregroundStyle(d.isRest ? Color.secondary : Color.fitTint)
                            }
                            if !d.isRest {
                                Text(d.exercises.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let old = current[d.weekday], old != d {
                                Text("Avant : \(old.isRest ? "Repos" : (old.title.isEmpty ? "À définir" : old.title))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("Aperçu de la semaine")
                }

                Section {
                    Button { apply(w) } label: {
                        Label("Remplacer ma semaine", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(!w.isUsable)
                    if !w.isUsable {
                        Text("Une séance resterait vide avec ce matériel. Ajoute du matériel ou réautorise des exercices exclus.")
                            .font(.footnote).foregroundStyle(Theme.warning)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning)
                    }
                } footer: {
                    Text("Tu pourras revenir à ta semaine actuelle depuis le programme. Tes séances passées et leurs charges ne changent pas.")
                }
            }
            .navigationTitle("Générer un programme").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
    }

    private func apply(_ w: FitbotGenerator.Week) {
        do {
            try FitbotProgramService.apply(w, days: days, in: ctx)
            if setRest { restSeconds = w.goal.restSeconds }
            error = nil; Haptics.success(); onApplied(); dismiss()
        } catch let e { error = e.localizedDescription; Haptics.warning() }
    }
}

// MARK: - Appliquer / annuler un programme

/// Ecrit une semaine generee dans les jours de programme EXISTANTS (meme identifiant :
/// une seance en cours reste rattachee a son jour), garde la semaine d'avant pour
/// l'annulation, et remonte toute erreur d'enregistrement en remettant tout en place.
enum FitbotProgramService {
    typealias Saver = (ModelContext) throws -> Void
    static let defaultSaver: Saver = { try $0.save() }

    enum ProgramError: LocalizedError, Equatable {
        case unusable, nothingToUndo, saveFailed(String)
        var errorDescription: String? {
            switch self {
            case .unusable: return "Une séance serait vide avec ce matériel : rien n'a été remplacé."
            case .nothingToUndo: return "Pas de semaine précédente à remettre."
            case .saveFailed(let why): return "Non enregistré (\(why)). Ta semaine est inchangée."
            }
        }
    }

    /// Un instantane par jour, lundi → dimanche. Un jour absent = jour vide.
    static func snapshot(_ days: [GymDay]) -> [GymDaySnapshot] {
        gymWeekOrder.map { w in
            guard let d = days.first(where: { $0.weekday == w }) else {
                return GymDaySnapshot(weekday: w, title: "", focus: "", isRest: false)
            }
            return GymDaySnapshot(weekday: w, title: d.title, focus: d.focus, isRest: d.isRest, supersetsJSON: d.supersetsJSON)
        }
    }

    /// Ecrit les instantanes dans les jours existants ; cree ceux qui manquent et les rend.
    @discardableResult
    static func write(_ snaps: [GymDaySnapshot], into days: [GymDay], in ctx: ModelContext) -> [GymDay] {
        var created: [GymDay] = []
        for s in snaps {
            let d = days.first { $0.weekday == s.weekday } ?? created.first { $0.weekday == s.weekday } ?? {
                let n = GymDay(weekday: s.weekday); ctx.insert(n); created.append(n); return n
            }()
            d.title = s.title; d.focus = s.focus; d.isRest = s.isRest; d.supersetsJSON = s.supersetsJSON
        }
        return created
    }

    static func activePlan(_ plans: [GymProgramPlan]) -> GymProgramPlan? {
        plans.filter { $0.undoneAt == nil }.max { $0.createdAt < $1.createdAt }
    }

    /// Seul le DERNIER programme s'annule : la semaine qu'il garde est celle qu'il a
    /// remplacee, plus ancienne serait perimee.
    static func latestUndoable(_ plans: [GymProgramPlan]) -> GymProgramPlan? {
        guard let p = activePlan(plans), !p.previousWeekJSON.isEmpty else { return nil }
        return p
    }

    /// Programmes d'avant (non annules), le plus recent d'abord.
    static func previousPlans(_ plans: [GymProgramPlan]) -> [GymProgramPlan] {
        let kept = plans.filter { $0.undoneAt == nil }.sorted { $0.createdAt > $1.createdAt }
        return Array(kept.dropFirst())
    }

    /// Fin d'un programme : le debut du programme suivant (non annule), sinon nil.
    static func end(of plan: GymProgramPlan, in plans: [GymProgramPlan]) -> Date? {
        plans.filter { $0.undoneAt == nil && $0.createdAt > plan.createdAt }.map(\.createdAt).min()
    }

    @discardableResult
    static func apply(_ week: FitbotGenerator.Week, days: [GymDay], in ctx: ModelContext, now: Date = .now,
                      save: Saver = defaultSaver) throws -> GymProgramPlan {
        guard week.isUsable else { throw ProgramError.unusable }
        let previous = snapshot(days)
        let plan = GymProgramPlan(createdAt: now, goal: week.goal.rawValue, daysPerWeek: week.daysPerWeek,
                                  sessionMinutes: week.sessionMinutes,
                                  equipment: FitbotEquipment.serialize(week.equipment),
                                  split: week.split.rawValue, previousWeekJSON: encode(previous))
        let created = write(week.days, into: days, in: ctx)
        ctx.insert(plan)
        do { try save(ctx) } catch {
            // Retour cible : les jours reprennent leurs valeurs, rien de neuf ne reste.
            write(previous, into: days, in: ctx)
            for d in created { ctx.delete(d) }
            ctx.delete(plan)
            throw ProgramError.saveFailed(error.localizedDescription)
        }
        return plan
    }

    static func undo(_ plan: GymProgramPlan, days: [GymDay], in ctx: ModelContext, now: Date = .now,
                     save: Saver = defaultSaver) throws {
        guard plan.undoneAt == nil, let previous = decode(plan.previousWeekJSON) else { throw ProgramError.nothingToUndo }
        let current = snapshot(days)
        let created = write(previous, into: days, in: ctx)
        plan.undoneAt = now
        do { try save(ctx) } catch {
            write(current, into: days, in: ctx)
            for d in created { ctx.delete(d) }
            plan.undoneAt = nil
            throw ProgramError.saveFailed(error.localizedDescription)
        }
    }

    static func encode(_ snaps: [GymDaySnapshot]) -> String {
        (try? String(data: JSONEncoder().encode(snaps), encoding: .utf8)) ?? ""
    }
    static func decode(_ json: String) -> [GymDaySnapshot]? {
        guard !json.isEmpty, let d = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([GymDaySnapshot].self, from: d)
    }
}
