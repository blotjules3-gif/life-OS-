import SwiftUI
import SwiftData
import EventKit
import WidgetKit
import UserNotifications
import UniformTypeIdentifiers
import CoreText

extension ShapeStyle where Self == Color { static var prodTint: Color { AppCategory.productivity.tint } }

// MARK: - Regles pures (testees dans AuditFixesProductivityTests)

enum ProductivityRules {

    /// Ordre des taches : priorite la plus haute d'abord, puis l'echeance la plus
    /// PROCHE, les taches sans date en dernier. Avant, le tuple entier etait trie a
    /// l'envers : a priorite egale l'echeance la plus lointaine passait devant.
    static func todoPrecedes(priorityA: Int, dueA: Date?, priorityB: Int, dueB: Date?) -> Bool {
        if priorityA != priorityB { return priorityA > priorityB }
        switch (dueA, dueB) {
        case let (a?, b?): return a < b
        case (.some, nil): return true
        default: return false
        }
    }

    static func todoPrecedes(_ a: TodoItem, _ b: TodoItem) -> Bool {
        todoPrecedes(priorityA: a.priority, dueA: a.due, priorityB: b.priority, dueB: b.due)
    }

    /// Une date pile a minuit = « ce jour-la, sans heure ». C'est ainsi qu'une tache
    /// recurrente sans heure garde sa prochaine occurrence.
    static func isDateOnly(_ d: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute, .second], from: d)
        return c.hour == 0 && c.minute == 0 && c.second == 0
    }

    /// En retard ? Une date sans heure ne l'est qu'a partir du lendemain.
    static func isLate(_ due: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        isDateOnly(due, calendar: calendar) ? due < calendar.startOfDay(for: now) : due < now
    }

    /// Prochaine occurrence STRICTEMENT apres `after` parmi les jours de semaine
    /// (1=Dim … 7=Sam), a l'heure de `timeOf` (minuit si pas d'heure).
    static func nextOccurrence(after: Date, weekdays: Set<Int>, timeOf: Date?,
                               calendar: Calendar = .current) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let hm = timeOf.map { calendar.dateComponents([.hour, .minute], from: $0) }
        let base = calendar.startOfDay(for: after)
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: base),
                  weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            return calendar.date(bySettingHour: hm?.hour ?? 0, minute: hm?.minute ?? 0, second: 0, of: day)
        }
        return nil
    }

    /// Cocher une tache. Une tache recurrente n'a qu'un booleen `done` : la cocher
    /// la cachait pour toujours. Elle reste donc ouverte et son echeance passe a la
    /// prochaine occurrence (jours de semaine ou chaque mois). Une ancienne tache
    /// recurrente deja cochee se rouvre.
    static func toggleDone(_ t: TodoItem, now: Date = .now) {
        let rule = TaskRecurrence.of(t)
        guard rule != .none else {
            t.done.toggle()
            t.completedAt = t.done ? now : nil
            return
        }
        if t.done { t.done = false; t.completedAt = nil; return }
        // Depart : la plus tardive entre aujourd'hui et l'echeance (une tache cochee
        // en avance ne revient pas le jour meme de son echeance).
        let from = max(now, t.due ?? now)
        if let next = rule.next(after: from, timeOf: t.due) {
            t.due = next
            t.blockStart = nil; t.blockEnd = nil; t.blockLocked = false
            t.checklistRaw = Checklist.reset(t.checklistRaw)
            t.completedAt = now
        } else {
            t.done = true
            t.completedAt = now
        }
    }

    /// Serie d'une habitude, en ne comptant QUE ses jours actifs. Avant, chaque jour
    /// calendaire comptait : une habitude du lundi au vendredi retombait a 1 chaque
    /// lundi. Aujourd'hui non coche ne casse pas la serie (la journee n'est pas finie).
    static func habitStreak(completions: [Date], activeDays: Set<Int>, now: Date = .now,
                            calendar: Calendar = .current) -> Int {
        let active = activeDays.isEmpty ? Set(1...7) : activeDays
        let doneDays = Set(completions.map { calendar.startOfDay(for: $0) })
        guard !doneDays.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: now)
        var day = today
        var streak = 0
        // Borne : dix ans de jours suffisent, et la boucle ne peut pas tourner a vide.
        for _ in 0..<3660 {
            let isActive = active.contains(calendar.component(.weekday, from: day))
            if isActive {
                if doneDays.contains(day) { streak += 1 }
                else if day != today { break }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Serie d'une habitude reelle: jours sautes ou en pause neutres, et serie en
    /// semaines pour « x fois par semaine » (HabitRules.streak). Meme valeur partout:
    /// frise, fiche, coach.
    static func habitStreak(_ h: Habit, now: Date = .now) -> Int {
        HabitRules.streak(h, now: now)
    }

    /// Moyenne ARRONDIE des vraies series. L'ancienne valeur etait le nombre total de
    /// completions divise par le nombre d'habitudes, affichee par le coach comme une
    /// serie en jours.
    static func averageStreak(_ streaks: [Int]) -> Int {
        guard !streaks.isEmpty else { return 0 }
        return Int((Double(streaks.reduce(0, +)) / Double(streaks.count)).rounded())
    }

    /// Ecrit la serie moyenne lue par le coach (UserContextBuilder, AIAssistantView).
    static func publishAverageStreak(_ habits: [Habit], now: Date = .now) {
        guard let defaults = LifeOSGroup.defaults else { return }
        let live = habits.filter { !$0.isPending && !$0.isArchived }
        defaults.set(averageStreak(live.map { habitStreak($0, now: now) }), forKey: "habits_avg_streak")
    }

    /// Signature d'un ajout au calendrier : meme titre et meme echeance = meme evenement.
    static func calendarSignature(title: String, due: Date?) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines))|\(due.map { String(Int($0.timeIntervalSince1970)) } ?? "sans-date")"
    }

    enum CalendarDecision: Equatable { case add, alreadyAdded, addAgainAfterChange }

    static func calendarDecision(stored: String?, current: String) -> CalendarDecision {
        guard let stored else { return .add }
        return stored == current ? .alreadyAdded : .addAgainAfterChange
    }

    /// Jour (aaaa-mm-jj) d'un compteur quotidien.
    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Rappels d'habitude

/// L'editeur titrait « HORAIRE DU RAPPEL » sans rien programmer. Un rappel hebdo par
/// jour actif, identifie par l'uid stable de l'habitude (jamais son nom).
enum HabitReminders {
    static let prefix = "habit.reminder."

    @MainActor
    static func schedule(_ h: Habit) {
        let uid = h.uid
        guard !uid.isEmpty else { return }
        // En pause: aucun rappel (la reprise les repose, HabitTrackerView.task).
        let silent = h.isPending || h.isArchived || HabitRules.isPaused(h.pausedUntil, on: .now)
        let reqs: [UNNotificationRequest] = silent ? [] : h.activeDays.sorted().map { (wd: Int) -> UNNotificationRequest in
            let content = UNMutableNotificationContent()
            content.title = "Rappel habitude"
            content.body = "C'est l'heure de ton habitude : \(h.name)."
            content.sound = .default
            content.categoryIdentifier = "LIFEOS_HABIT"
            content.userInfo = ["habitID": uid, "habitName": h.name]
            var comps = DateComponents()
            comps.weekday = wd; comps.hour = h.scheduledHour; comps.minute = h.scheduledMinute
            return UNNotificationRequest(identifier: "\(prefix)\(uid).\(wd)", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        }
        Task {
            if !reqs.isEmpty { _ = await NotificationManager.shared.requestAuthorization() }
            await NotificationManager.shared.replacePending(prefix: "\(prefix)\(uid).", with: reqs)
        }
    }

    static func cancel(uid: String) {
        guard !uid.isEmpty else { return }
        NotificationManager.shared.cancelWithPrefix("\(prefix)\(uid).")
    }

    /// Retire les rappels d'habitudes supprimees, archivees ou en attente ailleurs
    /// dans l'app (objectif archive, etc.), sinon ils sonneraient pour rien.
    static func prune(keeping validUIDs: Set<String>) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let stale = reqs.map(\.identifier).filter { id in
                guard id.hasPrefix(prefix) else { return false }
                let rest = id.dropFirst(prefix.count)
                guard let dot = rest.lastIndex(of: ".") else { return true }
                return !validUIDs.contains(String(rest[..<dot]))
            }
            if !stale.isEmpty { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale) }
        }
    }
}

// MARK: - Rappels de tache

/// Un rappel par tache, identifie par son uid stable. Avant, l'editeur Todoo n'en
/// programmait aucun et cocher ne l'annulait pas.
enum TaskReminders {
    static let prefix = "todo.reminder."

    @MainActor
    static func schedule(_ t: TodoItem) {
        TodoIDs.ensure(t)
        let id = prefix + t.uid
        guard !t.done, let fire = TaskReminderRules.fireDate(due: t.due, minutesBefore: t.reminderMinutes) else {
            NotificationManager.shared.cancel(id: id)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Rappel de tâche"
        content.body = t.project.isEmpty ? t.title : "\(t.title) · \(t.project)"
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let req = UNNotificationRequest(identifier: id, content: content,
                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
            await NotificationManager.shared.replacePending(prefix: id, with: [req])
        }
    }

    static func cancel(_ t: TodoItem) {
        guard !t.uid.isEmpty else { return }
        NotificationManager.shared.cancel(id: prefix + t.uid)
    }
}

/// Notifications refusees: on le dit a l'endroit ou l'on promet un rappel, avec
/// une sortie vers les Reglages.
struct NotificationDeniedNotice: View {
    @State private var denied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if denied {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                    Text("Notifications refusées : le rappel ne sonnera pas.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Réglages") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                    }
                    .font(.caption.bold())
                }
                .foregroundStyle(Theme.danger)
            }
        }
        .task { denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied }
    }
}

// MARK: - Hub Productivité


// MARK: - To-do

struct TodoView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TodoItem.due) private var todos: [TodoItem]
    /// Vue choisie, gardee entre deux ouvertures.
    @AppStorage("todo.list") private var listRaw = TodoList.today.rawValue
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var priorityFilter: Int?
    @State private var capture = ""
    @State private var showAdd = false
    @State private var addProject = ""
    @State private var editing: TodoItem?
    @State private var calendarAlert: String?
    @State private var undoTask: TodoItem?
    @State private var undoSnap: TodoSnapshot?
    @State private var undoLabel = ""
    @State private var undoToken = 0
    @State private var renaming: String?
    @State private var renameText = ""

    private var list: TodoList { TodoList(rawValue: listRaw) ?? .today }

    private func passes(_ t: TodoItem) -> Bool {
        TodoFilter.matches(t, search: search, tag: tagFilter, priority: priorityFilter)
    }

    /// Recherche: globale (ouvertes puis terminees). Sinon la vue choisie.
    private var visible: [TodoItem] {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            return TodoFilter.tasks(todos, in: .all).filter(passes) + TodoFilter.tasks(todos, in: .done).filter(passes)
        }
        return TodoFilter.tasks(todos, in: list).filter(passes)
    }

    private func count(_ l: TodoList) -> Int {
        (l == .projects || l == .done) ? 0 : TodoFilter.tasks(todos, in: l).count
    }

    private var parsed: ParsedTask? {
        capture.trimmingCharacters(in: .whitespaces).isEmpty ? nil : TaskCapture.parse(capture)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background
            VStack(spacing: 0) {
                listPicker
                captureBar
                activeFilters
                content
            }
            if undoTask != nil { undoToast }
        }
        .navigationTitle("Todoo").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Rechercher une tâche")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { addProject = ""; showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter")
            }
        }
        .sheet(isPresented: $showAdd) {
            TodoEditor(initialDue: list == .today ? Calendar.current.startOfDay(for: .now) : nil, initialProject: addProject)
        }
        .sheet(item: $editing) { TodoEditor(task: $0) }
        .alert("Calendrier", isPresented: .init(get: { calendarAlert != nil }, set: { if !$0 { calendarAlert = nil } })) {
            Button("OK") { calendarAlert = nil }
        } message: { Text(calendarAlert ?? "") }
        .alert("Renommer le projet", isPresented: .init(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nom du projet", text: $renameText)
            Button("Renommer") {
                if let from = renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    TodoProjects.rename(from, to: renameText, in: todos)
                    save()
                }
                renaming = nil
            }
            Button("Annuler", role: .cancel) { renaming = nil }
        } message: { Text("Toutes les tâches du projet suivent. Un nom déjà utilisé fusionne les deux projets.") }
        .onAppear { TodoIDs.ensure(ctx) }
    }

    // MARK: Barres

    private var listPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TodoList.allCases) { l in
                    let sel = list == l && search.isEmpty
                    Button { listRaw = l.rawValue; Haptics.tap() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: l.icon)
                            Text(l.label)
                            if count(l) > 0 { Text("\(count(l))").monospacedDigit().opacity(0.6) }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(sel ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05), in: Capsule())
                        .foregroundStyle(sel ? Color.accentColor : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private var captureBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                TextField("Ajouter : demain 18h #maison !2", text: $capture)
                    .submitLabel(.done)
                    .onSubmit(addCaptured)
                if let p = parsed {
                    Button("Ajouter", action: addCaptured)
                        .font(.footnote.bold())
                        .disabled(p.title.isEmpty)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .raisedSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), .nested)
            if let p = parsed { CapturePreview(parsed: p) }
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
    }

    @ViewBuilder private var activeFilters: some View {
        if tagFilter != nil || priorityFilter != nil {
            HStack(spacing: 8) {
                if let tagFilter {
                    filterChip("@\(tagFilter)") { self.tagFilter = nil }
                }
                if let priorityFilter {
                    filterChip(Self.priorityName(priorityFilter)) { self.priorityFilter = nil }
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
        }
    }

    private func filterChip(_ label: String, clear: @escaping () -> Void) -> some View {
        Button(action: clear) {
            HStack(spacing: 4) { Text(label); Image(systemName: "xmark.circle.fill") }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var filterMenu: some View {
        Menu {
            Section("Étiquette") {
                let tags = TodoProjects.allTags(todos)
                if tags.isEmpty { Text("Aucune étiquette") }
                ForEach(tags, id: \.self) { t in
                    Button { tagFilter = t } label: { Label("@\(t)", systemImage: tagFilter == t ? "checkmark" : "tag") }
                }
            }
            Section("Priorité") {
                ForEach([2, 1, 0], id: \.self) { p in
                    Button { priorityFilter = p } label: { Label(Self.priorityName(p), systemImage: priorityFilter == p ? "checkmark" : "flag") }
                }
            }
            if tagFilter != nil || priorityFilter != nil {
                Button("Retirer les filtres", role: .destructive) { tagFilter = nil; priorityFilter = nil }
            }
        } label: {
            Image(systemName: (tagFilter != nil || priorityFilter != nil) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filtrer")
    }

    static func priorityName(_ p: Int) -> String { p >= 2 ? "Urgente" : (p == 1 ? "Importante" : "Normale") }

    // MARK: Contenu

    @ViewBuilder private var content: some View {
        if !search.isEmpty || (list != .upcoming && list != .projects) {
            if visible.isEmpty { emptyState; Spacer() } else {
                List { ForEach(visible) { row($0) } }.scrollContentBackground(.hidden)
            }
        } else if list == .upcoming {
            let groups = TodoFilter.groupedByDay(visible)
            if groups.isEmpty { emptyState; Spacer() } else {
                List {
                    ForEach(groups) { g in
                        Section { ForEach(g.tasks) { row($0) } } header: {
                            Text(g.day, format: .dateTime.weekday(.wide).day().month(.wide))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        } else {
            projectsList
        }
    }

    private var emptyState: some View {
        let msg: String
        switch list {
        case .inbox: msg = "Les tâches sans projet arrivent ici. Tape une tâche ci-dessus."
        case .today: msg = "Rien de prévu aujourd'hui. Les tâches en retard s'affichent aussi ici."
        case .upcoming: msg = "Aucune tâche datée après aujourd'hui."
        case .done: msg = "Les tâches terminées s'affichent ici."
        default: msg = "Ajoute une tâche avec le champ ci-dessus ou le +."
        }
        return EmptyState(icon: "checklist", title: search.isEmpty ? "Rien ici" : "Aucun résultat", message: search.isEmpty ? msg : "Aucune tâche ne contient ces mots.")
    }

    private var projectsList: some View {
        List {
            let inbox = visible.filter(TodoFilter.isInbox)
            if !inbox.isEmpty {
                Section("Boîte de réception") { ForEach(inbox) { row($0) } }
            }
            ForEach(TodoProjects.projects(todos), id: \.self) { p in
                let tasks = visible.filter { TextFold.fold($0.project) == TextFold.fold(p) }
                Section {
                    if tasks.isEmpty {
                        Text("Aucune tâche ouverte").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(TodoProjects.sections(of: p, in: tasks), id: \.self) { sec in
                        if !sec.isEmpty {
                            Text(sec.uppercased()).font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(tasks.filter { TextFold.fold($0.section.trimmingCharacters(in: .whitespaces)) == TextFold.fold(sec) }) { row($0) }
                    }
                } header: {
                    HStack {
                        Text(p)
                        Spacer()
                        Menu {
                            Button { addProject = p; showAdd = true } label: { Label("Ajouter une tâche", systemImage: "plus") }
                            Button { renaming = p; renameText = p } label: { Label("Renommer", systemImage: "pencil") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Options du projet \(p)")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ t: TodoItem) -> some View {
        TodoRow(task: t, onToggle: { toggle(t) }, onOpen: { editing = t })
            .listRowBackground(Theme.card)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { delete(t) } label: { Label("Supprimer", systemImage: "trash") }
            }
            .swipeActions(edge: .leading) {
                if !t.done {
                    Button { postpone(t) } label: { Label("Demain", systemImage: "arrow.turn.up.right") }.tint(Theme.warning)
                }
            }
            .contextMenu {
                Button { editing = t } label: { Label("Modifier", systemImage: "pencil") }
                Menu("Déplacer vers") {
                    Button("Boîte de réception") { move(t, to: "") }
                    ForEach(TodoProjects.projects(todos), id: \.self) { p in Button(p) { move(t, to: p) } }
                }
                Menu("Priorité") {
                    ForEach([2, 1, 0], id: \.self) { p in Button(Self.priorityName(p)) { t.priority = p; save() } }
                }
                Button { addToCalendar(t) } label: { Label("Ajouter au calendrier", systemImage: "calendar.badge.plus") }
                Button(role: .destructive) { delete(t) } label: { Label("Supprimer", systemImage: "trash") }
            }
    }

    private var undoToast: some View {
        HStack(spacing: 12) {
            Text(undoLabel).font(.footnote.weight(.semibold)).lineLimit(2)
            Spacer()
            Button("Annuler") {
                if let t = undoTask, let s = undoSnap {
                    s.restore(t)
                    save()
                    TaskReminders.schedule(t)
                }
                undoTask = nil
            }
            .font(.footnote.bold())
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .raisedSurface(Capsule())
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Actions

    private func addCaptured() {
        guard let p = parsed else { return }
        guard !p.title.isEmpty else { Haptics.warning(); return }
        let t = TodoItem(title: p.title, due: p.due ?? (list == .today ? Calendar.current.startOfDay(for: .now) : nil),
                         priority: p.priority ?? 0, project: p.project ?? "")
        t.tagsRaw = TagList.serialize(p.tags)
        p.recurrence.apply(to: t)
        TodoIDs.ensure(t)
        ctx.insert(t)
        save()
        capture = ""
        Haptics.medium()
    }

    private func toggle(_ t: TodoItem) {
        let snap = TodoSnapshot(t)
        withAnimation { ProductivityRules.toggleDone(t) }
        save()
        if t.done { TaskReminders.cancel(t) } else { TaskReminders.schedule(t) }
        Haptics.tap()
        if t.done {
            undoLabel = "Tâche terminée"
        } else if !snap.done, let d = t.due {
            undoLabel = "Prochaine fois : \(d.formatted(.dateTime.weekday(.abbreviated).day().month()))"
        } else {
            undoLabel = "Tâche rouverte"
        }
        withAnimation { undoTask = t }
        undoSnap = snap
        undoToken += 1
        let token = undoToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if undoToken == token { withAnimation { undoTask = nil } } }
    }

    private func postpone(_ t: TodoItem) {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        if let d = t.due, !ProductivityRules.isDateOnly(d) {
            let hm = cal.dateComponents([.hour, .minute], from: d)
            t.due = cal.date(bySettingHour: hm.hour ?? 9, minute: hm.minute ?? 0, second: 0, of: tomorrow)
        } else {
            t.due = tomorrow
        }
        t.blockStart = nil; t.blockEnd = nil; t.blockLocked = false
        save()
        TaskReminders.schedule(t)
    }

    private func move(_ t: TodoItem, to project: String) {
        t.project = project
        t.section = ""
        save()
    }

    private func delete(_ t: TodoItem) {
        TaskReminders.cancel(t)
        ctx.delete(t)
        save()
    }

    private func save() {
        do { try ctx.save() }
        catch { AppLog.data.error("tache non enregistree: \(error.localizedDescription, privacy: .public)") }
    }

    /// Ajouts deja faits : [identifiant de la tache: signature titre|echeance].
    /// L'app n'a que l'acces calendrier en ECRITURE (Info.plist) : elle ne peut ni
    /// relire ni modifier un evenement. Sans cette trace, chaque appui creait un
    /// doublon. Garde locale, une entree par tache.
    private static let calendarLinksKey = "todo.calendarLinks"

    private func todoKey(_ todo: TodoItem) -> String? {
        guard let data = try? JSONEncoder().encode(todo.persistentModelID) else { return nil }
        return data.base64EncodedString()
    }

    private func addToCalendar(_ todo: TodoItem) {
        let signature = ProductivityRules.calendarSignature(title: todo.title, due: todo.due)
        let key = todoKey(todo)
        let links = UserDefaults.standard.dictionary(forKey: Self.calendarLinksKey) as? [String: String] ?? [:]
        let decision = ProductivityRules.calendarDecision(stored: key.flatMap { links[$0] }, current: signature)
        if decision == .alreadyAdded {
            calendarAlert = "Cette tâche est déjà dans ton calendrier."
            return
        }
        let store = EKEventStore()
        let requestAccess = {
            let event = EKEvent(eventStore: store)
            event.title = todo.title
            event.notes = todo.project.isEmpty ? nil : todo.project
            let start = todo.due ?? Date().addingTimeInterval(3600)
            event.startDate = start
            event.endDate   = start.addingTimeInterval(TimeInterval(DayPlanner.durationOf(todo) * 60))
            event.calendar  = store.defaultCalendarForNewEvents
            do {
                try store.save(event, span: .thisEvent)
                if let key {
                    var saved = UserDefaults.standard.dictionary(forKey: Self.calendarLinksKey) as? [String: String] ?? [:]
                    saved[key] = signature
                    UserDefaults.standard.set(saved, forKey: Self.calendarLinksKey)
                }
                let when = "Ajouté au calendrier pour \(start.formatted(.dateTime.day().month().hour().minute()))."
                calendarAlert = decision == .addAgainAfterChange
                    ? when + " L'ancien événement de cette tâche reste dans ton calendrier : supprime-le à la main."
                    : when
            } catch {
                calendarAlert = "Impossible d'accéder au calendrier. Vérifie les autorisations dans Réglages."
            }
        }
        store.requestWriteOnlyAccessToEvents { granted, _ in
            DispatchQueue.main.async { if granted { requestAccess() } else { calendarAlert = "Accès calendrier refusé. Autorise-le dans Réglages > LifeOS > Calendriers." } }
        }
    }
}

/// Ce que la saisie rapide a compris, avant d'ajouter.
struct CapturePreview: View {
    let parsed: ParsedTask

    var body: some View {
        let chips = items
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if chips.isEmpty {
                    Text("Astuce : demain 18h, lundi, le 12 octobre, #projet, @étiquette, !1 urgente, !2 importante, tous les lundis")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                ForEach(chips, id: \.self) { c in
                    Text(c).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var items: [String] {
        var out: [String] = []
        if let d = parsed.due {
            out.append(parsed.hasTime ? d.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
                                      : d.formatted(.dateTime.weekday(.abbreviated).day().month()))
        }
        if parsed.recurrence != .none { out.append(parsed.recurrence.label) }
        if let p = parsed.project { out.append("#\(p)") }
        out += parsed.tags.map { "@\($0)" }
        if let p = parsed.priority { out.append(TodoView.priorityName(p)) }
        return out
    }
}

struct TodoRow: View {
    let task: TodoItem
    var onToggle: () -> Void
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(task.done ? Theme.success : priorityColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Rouvrir" : "Terminer")
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).strikethrough(task.done)
                    .foregroundStyle(task.done ? Theme.textSecondary : Theme.textPrimary)
                if !task.notes.isEmpty {
                    Text(task.notes).font(.caption).lineLimit(1).foregroundStyle(Theme.textSecondary)
                }
                meta
                let tags = TagList.parse(task.tagsRaw)
                if !tags.isEmpty {
                    Text(tags.map { "@\($0)" }.joined(separator: " "))
                        .font(.caption2).foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private var priorityColor: Color { task.priority >= 2 ? Theme.danger : task.priority == 1 ? Theme.warning : Theme.textSecondary }

    private var meta: some View {
        HStack(spacing: 6) {
            if !task.project.isEmpty {
                Text(task.section.isEmpty ? task.project : "\(task.project) · \(task.section)")
                    .font(.caption2).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .raisedSurface(Capsule(), .nested).foregroundStyle(Theme.textSecondary)
            }
            if let d = task.due {
                // Une date sans heure (occurrence d'une tache recurrente)
                // ne s'affiche pas « 00:00 » et n'est en retard qu'au lendemain.
                let dateOnly = ProductivityRules.isDateOnly(d)
                if ProductivityRules.isLate(d) && !task.done {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.badge.exclamationmark")
                        if dateOnly { Text(d, format: .dateTime.day().month()) }
                        else { Text(d, format: .dateTime.day().month().hour().minute()) }
                        Text("En retard")
                    }
                    .font(.caption2.bold()).foregroundStyle(Theme.danger)
                } else {
                    Group {
                        if dateOnly { Text(d, format: .dateTime.weekday(.abbreviated).day().month()) }
                        else { Text(d, format: .dateTime.weekday(.abbreviated).day().month().hour().minute()) }
                    }
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            if TaskRecurrence.of(task) != .none {
                Image(systemName: "repeat").font(.caption2).foregroundStyle(Color.accentColor)
            }
            if task.reminderMinutes >= 0 && task.due != nil {
                Image(systemName: "bell").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            let cl = Checklist.progress(task.checklistRaw)
            if cl.total > 0 {
                Label("\(cl.done)/\(cl.total)", systemImage: "checklist").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            if task.estimateMinutes > 0 {
                Text("\(task.estimateMinutes) min").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .lineLimit(1)
    }
}

struct TodoEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var allTodos: [TodoItem]
    let task: TodoItem?

    @State private var title = ""
    @State private var notes = ""
    @State private var project: String
    @State private var section = ""
    @State private var tagsText = ""
    @State private var priority = 0
    @State private var hasDue: Bool
    @State private var hasTime: Bool
    @State private var due: Date
    /// 0 jamais, 1 tous les jours, 2 en semaine, 3 certains jours, 4 tous les mois
    @State private var recurrenceKind = 0
    @State private var selectedDays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var reminder = -1
    @State private var estimate = 0
    @State private var checklist: [ChecklistItem] = []
    @State private var newItem = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    init(initialDue: Date? = nil, task: TodoItem? = nil, initialProject: String = "") {
        self.task = task
        _project = State(initialValue: initialProject)
        if let initialDue {
            _hasDue = State(initialValue: true)
            _hasTime = State(initialValue: !ProductivityRules.isDateOnly(initialDue))
            _due = State(initialValue: initialDue)
        } else {
            _hasDue = State(initialValue: false)
            _hasTime = State(initialValue: true)
            _due = State(initialValue: Date())
        }
    }

    private let dayOptions: [(day: Int, label: String)] = [
        (2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")
    ]
    private let estimates = [0, 15, 30, 45, 60, 90, 120, 180, 240]

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var recurrence: TaskRecurrence {
        switch recurrenceKind {
        case 1: return .daily
        case 2: return .weekdays
        case 3: return selectedDays.isEmpty ? .none : TaskRecurrence.of(daysRaw: selectedDays.map(String.init).joined(separator: ","), rule: "")
        case 4: return .monthly
        default: return .none
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    detailsCard
                    projectCard
                    priorityCard
                    dueCard
                    recurrenceCard
                    reminderCard
                    checklistCard
                    if task != nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Supprimer cette tâche", systemImage: "trash")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(Theme.danger)
                                .padding(.vertical, 14)
                        }
                        .padding(4)
                        .liquidGlassCard(cornerRadius: Theme.radius)
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .onAppear(perform: load)
        .confirmationDialog("Supprimer cette tâche ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let task {
                    TaskReminders.cancel(task)
                    ctx.delete(task)
                    do { try ctx.save() } catch { AppLog.data.error("suppression tache: \(error.localizedDescription, privacy: .public)") }
                }
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Annuler") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(LifeOSPressStyle(scale: 0.95))
            Spacer()
            Text(task == nil ? "Nouvelle tâche" : "Modifier la tâche")
                .font(AppFont.heading(size: 17, weight: .bold))
            Spacer()
            Button(action: save) {
                Text(task == nil ? "Ajouter" : "Enregistrer")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color.primary, in: Capsule())
            }
            .buttonStyle(LifeOSPressStyle(scale: 0.95))
            .disabled(trimmedTitle.isEmpty)
            .opacity(trimmedTitle.isEmpty ? 0.35 : 1.0)
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
    }

    private func card<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).tracking(0.6)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: Theme.radius)
    }

    private func field(_ placeholder: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        TextField(placeholder, text: text, axis: axis)
            .font(.system(size: 15))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), .nested)
    }

    private var detailsCard: some View {
        card("DÉTAILS DE LA TÂCHE") {
            field("Que dois-tu accomplir ?", text: $title)
            field("Notes", text: $notes, axis: .vertical)
            Picker("Durée estimée", selection: $estimate) {
                ForEach(estimates, id: \.self) { m in Text(m == 0 ? "Non estimée (1 h)" : "\(m) min").tag(m) }
            }
        }
    }

    private var projectCard: some View {
        card("PROJET, SECTION, ÉTIQUETTES") {
            HStack {
                field("Projet (vide = boîte de réception)", text: $project)
                let projects = TodoProjects.projects(allTodos)
                if !projects.isEmpty {
                    Menu {
                        Button("Boîte de réception") { project = "" }
                        ForEach(projects, id: \.self) { p in Button(p) { project = p } }
                    } label: { Image(systemName: "chevron.down.circle").font(.title3) }
                    .accessibilityLabel("Choisir un projet")
                }
            }
            HStack {
                field("Section (ex : À acheter)", text: $section)
                let sections = TodoProjects.sections(of: project, in: allTodos).filter { !$0.isEmpty }
                if !sections.isEmpty {
                    Menu {
                        Button("Sans section") { section = "" }
                        ForEach(sections, id: \.self) { s in Button(s) { section = s } }
                    } label: { Image(systemName: "chevron.down.circle").font(.title3) }
                    .accessibilityLabel("Choisir une section")
                }
            }
            field("Étiquettes, séparées par des virgules", text: $tagsText)
            let known = TodoProjects.allTags(allTodos)
            if !known.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(known, id: \.self) { tag in
                            let on = TagList.contains(tagsText, tag)
                            Button {
                                var list = TagList.parse(tagsText)
                                if on { list.removeAll { TextFold.fold($0) == TextFold.fold(tag) } } else { list.append(tag) }
                                tagsText = list.joined(separator: ", ")
                            } label: {
                                Text("@\(tag)").font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(on ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05), in: Capsule())
                                    .foregroundStyle(on ? Color.accentColor : Theme.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var priorityCard: some View {
        card("PRIORITÉ") {
            HStack(spacing: 10) {
                priorityPill("Normale", tag: 0, color: .secondary)
                priorityPill("Importante", tag: 1, color: Theme.warning)
                priorityPill("Urgente", tag: 2, color: Theme.danger)
            }
        }
    }

    private var dueCard: some View {
        card("ÉCHÉANCE") {
            Toggle(isOn: $hasDue.animation(.spring(response: 0.25))) {
                Label("Fixer une date", systemImage: "calendar.badge.clock").font(.system(size: 15, weight: .medium))
            }
            if hasDue {
                DatePicker("Date", selection: $due, displayedComponents: .date)
                Toggle("Heure précise", isOn: $hasTime.animation())
                if hasTime {
                    DatePicker("Heure", selection: $due, displayedComponents: .hourAndMinute)
                }
            }
        }
    }

    private var recurrenceCard: some View {
        card("RÉPÉTITION") {
            Picker("Répéter", selection: $recurrenceKind) {
                Text("Jamais").tag(0)
                Text("Tous les jours").tag(1)
                Text("En semaine").tag(2)
                Text("Certains jours").tag(3)
                Text("Tous les mois").tag(4)
            }
            if recurrenceKind == 3 {
                HStack(spacing: 8) {
                    ForEach(dayOptions, id: \.day) { opt in
                        let isSel = selectedDays.contains(opt.day)
                        Button {
                            if isSel { selectedDays.remove(opt.day) } else { selectedDays.insert(opt.day) }
                            Haptics.tap()
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(isSel ? Color.accentColor : Color.primary.opacity(0.06), in: Circle())
                                .foregroundStyle(isSel ? Theme.onAccent : Theme.textPrimary)
                        }
                        .buttonStyle(LifeOSPressStyle(scale: 0.94))
                        .accessibilityLabel(opt.label)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if recurrenceKind == 4 {
                Text("Revient chaque mois le même jour que l'échéance (le dernier jour quand le mois est plus court).")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var reminderCard: some View {
        card("RAPPEL") {
            Picker("Rappel", selection: $reminder) {
                ForEach(TaskReminderRules.options, id: \.minutes) { Text($0.label).tag($0.minutes) }
            }
            if reminder >= 0 {
                if !hasDue && recurrenceKind == 0 {
                    Text("Le rappel a besoin d'une échéance.").font(.caption).foregroundStyle(Theme.warning)
                } else if hasDue && !hasTime {
                    Text("Sans heure, le rappel part à 9 h ce jour-là.").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                NotificationDeniedNotice()
            }
        }
    }

    private var checklistCard: some View {
        card("SOUS-TÂCHES") {
            ForEach($checklist) { $item in
                HStack(spacing: 10) {
                    Button { item.done.toggle() } label: {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.done ? Theme.success : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    TextField("Sous-tâche", text: $item.title)
                        .strikethrough(item.done)
                    Button { checklist.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retirer")
                }
            }
            HStack {
                TextField("Ajouter une sous-tâche", text: $newItem).onSubmit(addItem)
                Button(action: addItem) { Image(systemName: "plus.circle.fill") }
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        checklist.append(ChecklistItem(title: t, done: false))
        newItem = ""
    }

    private func priorityPill(_ label: String, tag: Int, color: Color) -> some View {
        let isSel = priority == tag
        return Button {
            priority = tag
            Haptics.tap()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isSel ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSel ? color.opacity(0.16) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSel ? color : Theme.stroke, lineWidth: isSel ? 1.5 : 0.6))
                .foregroundStyle(isSel ? color : Color.primary)
        }
        .buttonStyle(LifeOSPressStyle(scale: 0.95))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let t = task else { return }
        title = t.title; notes = t.notes; project = t.project; section = t.section
        tagsText = TagList.parse(t.tagsRaw).joined(separator: ", ")
        priority = t.priority
        if let d = t.due { hasDue = true; due = d; hasTime = !ProductivityRules.isDateOnly(d) } else { hasDue = false }
        switch TaskRecurrence.of(t) {
        case .none: recurrenceKind = 0
        case .daily: recurrenceKind = 1
        case .weekdays: recurrenceKind = 2
        case .weekly(let d): recurrenceKind = 3; selectedDays = d
        case .monthly: recurrenceKind = 4
        }
        reminder = t.reminderMinutes
        estimate = t.estimateMinutes
        checklist = Checklist.parse(t.checklistRaw)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        let cal = Calendar.current
        let t = task ?? TodoItem()
        t.title = trimmedTitle
        t.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        t.project = project.trimmingCharacters(in: .whitespaces)
        t.section = section.trimmingCharacters(in: .whitespaces)
        t.tagsRaw = TagList.serialize(TagList.parse(tagsText))
        t.priority = priority
        var d: Date? = hasDue ? (hasTime ? due : cal.startOfDay(for: due)) : nil
        let rule = recurrence
        if rule != .none, d == nil {
            // Une tache recurrente sans date commence a sa premiere occurrence.
            let today = cal.startOfDay(for: .now)
            d = (0..<62).lazy.compactMap { cal.date(byAdding: .day, value: $0, to: today) }
                .first { rule == .monthly || rule.matches($0, anchor: nil) }
        }
        let dueChanged = t.due != d
        t.due = d
        rule.apply(to: t)
        t.reminderMinutes = reminder
        if t.estimateMinutes != estimate, t.blockStart != nil, !t.blockLocked {
            // Duree changee: l'ancien creneau ne correspond plus, le planning le refera.
            t.blockStart = nil; t.blockEnd = nil
        }
        t.estimateMinutes = estimate
        if dueChanged && t.blockLocked == false { t.blockStart = nil; t.blockEnd = nil }
        t.checklistRaw = Checklist.serialize(checklist)
        TodoIDs.ensure(t)
        if task == nil { ctx.insert(t) }
        do { try ctx.save() } catch { AppLog.data.error("tache non enregistree: \(error.localizedDescription, privacy: .public)") }
        TaskReminders.schedule(t)
        Haptics.medium()
        dismiss()
    }
}

// MARK: - Lecture du calendrier (plages occupees)

/// L'app n'a aujourd'hui que l'acces calendrier en ecriture (Info.plist). La
/// lecture des plages occupees ne marche que si l'acces complet est accorde, et ne
/// peut etre demandee que si la cle NSCalendarsFullAccessUsageDescription existe:
/// sans elle, iOS arreterait l'app a la demande.
enum CalendarBusy {
    enum Access: Equatable { case authorized, canAsk, denied, notInThisVersion }

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
    }

    static var readKeyPresent: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    static func access() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .denied, .restricted: return .denied
        default: return readKeyPresent ? .canAsk : .notInThisVersion
        }
    }

    static func requestRead() async -> Bool {
        guard readKeyPresent else { return false }
        return (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    static func events(from: Date, to: Date) -> [Event] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = EKEventStore()
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: pred)
            .filter { !$0.isAllDay && $0.availability != .free }
            .map { Event(id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                         title: $0.title ?? "Occupé", start: max($0.startDate, from), end: min($0.endDate, to)) }
            .filter { $0.end > $0.start }
    }
}

// MARK: - Time-blocking auto

struct TimeBlockView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query private var todos: [TodoItem]
    @AppStorage(AppStorageKeys.dayStart) private var dayStart = 9
    @AppStorage(AppStorageKeys.dayEnd) private var dayEnd = 18
    @AppStorage("timeblock.buffer") private var buffer = 0
    @AppStorage("timeblock.lunch") private var lunch = true
    @State private var dayOffset = 0
    @State private var keepExisting = true
    @State private var preview: PlanOutcome?
    @State private var overflow: [PlanOverflow] = []
    @State private var events: [CalendarBusy.Event] = []
    @State private var access: CalendarBusy.Access = .notInThisVersion
    @State private var message: String?
    @State private var showFixed = false
    @State private var editing: TodoItem?

    private let cal = Calendar.current
    private var day: Date { cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: .now)) ?? .now }
    private func at(_ h: Int) -> Date { cal.date(bySettingHour: min(max(h, 0), 23), minute: 0, second: 0, of: day) ?? day }
    private var window: PlanSlot { PlanSlot(start: at(dayStart), end: at(dayEnd)) }
    private var wholeDay: PlanSlot { PlanSlot(start: day, end: cal.date(byAdding: .day, value: 1, to: day) ?? day) }
    private func isOnDay(_ d: Date?) -> Bool { d.map { cal.isDate($0, inSameDayAs: day) } ?? false }
    private func slot(_ t: TodoItem) -> PlanSlot? {
        guard let s = t.blockStart, let e = t.blockEnd, e > s else { return nil }
        return PlanSlot(start: s, end: e)
    }

    private var lunchSlot: PlanSlot? {
        guard lunch, dayStart < 14, dayEnd > 13 else { return nil }
        return PlanSlot(start: at(13), end: at(14))
    }
    private var lockedOnDay: [TodoItem] { todos.filter { !$0.done && $0.blockLocked && isOnDay($0.blockStart) && slot($0) != nil } }
    /// Ce qui ne bouge jamais: calendrier, blocs verrouilles, pause.
    private var busy: [PlanSlot] {
        events.map { PlanSlot(start: $0.start, end: $0.end) } + lockedOnDay.compactMap(slot) + (lunchSlot.map { [$0] } ?? [])
    }
    /// Taches a placer: ouvertes, non verrouillees, prevues ce jour (recurrence comprise).
    private var candidates: [TodoItem] {
        todos.filter { !$0.done && !$0.blockLocked && $0.applies(to: day) }.sorted(by: ProductivityRules.todoPrecedes)
    }
    private var scheduled: [TodoItem] {
        todos.filter { !$0.done && isOnDay($0.blockStart) && slot($0) != nil }
            .sorted { ($0.blockStart ?? .distantPast) < ($1.blockStart ?? .distantPast) }
    }
    private var unplaced: [TodoItem] { candidates.filter { !isOnDay($0.blockStart) } }

    /// Fenetre affichee: la journee de travail, elargie aux blocs poses en dehors.
    private var display: PlanSlot {
        var s = window.start, e = window.end
        for t in scheduled { if let b = slot(t) { s = min(s, b.start); e = max(e, b.end) } }
        for ev in events { s = min(s, ev.start); e = max(e, ev.end) }
        let sh = cal.component(.hour, from: s)
        let start = cal.date(bySettingHour: sh, minute: 0, second: 0, of: day) ?? s
        return PlanSlot(start: start, end: max(e, start.addingTimeInterval(3600)))
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    settingsCard
                    Picker("Jour", selection: $dayOffset) {
                        Text("Aujourd'hui").tag(0)
                        Text("Demain").tag(1)
                    }
                    .pickerStyle(.segmented)
                    calendarNotice
                    HStack(spacing: 10) {
                        PrimaryButton(title: "Proposer un planning", icon: "wand.and.stars", tint: .prodTint) { propose() }
                        Button { showFixed = true } label: {
                            Image(systemName: "lock.rectangle.stack").font(.title3)
                                .frame(width: 52, height: 52)
                                .glassControl(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ajouter un bloc fixe")
                    }
                    Toggle("Garder les blocs déjà posés quand ils restent valables", isOn: $keepExisting)
                        .font(.footnote)
                    if let preview { previewCard(preview) }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    timelineCard
                    overflowCard
                }
                .padding(Theme.pad)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Structurd").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFixed) { FixedBlockEditor(day: day, defaultHour: max(dayStart, min(dayEnd - 1, cal.component(.hour, from: .now) + 1))) }
        .sheet(item: $editing) { TodoEditor(task: $0) }
        .onAppear { TodoIDs.ensure(ctx); reloadCalendar() }
        .onChange(of: dayOffset) { _, _ in preview = nil; overflow = []; message = nil; reloadCalendar() }
        .onChange(of: scenePhase) { _, p in if p == .active { reloadCalendar() } }
    }

    // MARK: Cartes

    private var settingsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Stepper("Début \(dayStart)h", value: $dayStart, in: 5...12)
                Divider().frame(height: 24)
                Stepper("Fin \(dayEnd)h", value: $dayEnd, in: 13...23)
            }
            Picker("Marge entre les blocs", selection: $buffer) {
                Text("Aucune").tag(0); Text("5 min").tag(5); Text("10 min").tag(10); Text("15 min").tag(15)
            }
            Toggle("Pause déjeuner de 13 h à 14 h", isOn: $lunch)
        }
        .font(.footnote).card()
    }

    @ViewBuilder private var calendarNotice: some View {
        switch access {
        case .authorized:
            Label(events.isEmpty ? "Calendrier lu : aucun rendez-vous ce jour." : "Calendrier lu : \(events.count) rendez-vous évités.",
                  systemImage: "calendar").font(.footnote).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .canAsk:
            Button {
                Task { _ = await CalendarBusy.requestRead(); reloadCalendar() }
            } label: {
                Label("Lire mon calendrier pour éviter mes rendez-vous", systemImage: "calendar.badge.plus")
                    .font(.footnote.weight(.semibold))
            }
        case .denied:
            HStack {
                Text("Accès au calendrier refusé : tes rendez-vous ne sont pas pris en compte.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Réglages") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                    .font(.footnote.bold())
            }
        case .notInThisVersion:
            IntegrationNotice(text: "La lecture de ton calendrier n'est pas encore activée dans cette version. Ajoute tes rendez-vous comme blocs fixes (cadenas) : le planning ne les touche jamais.")
        }
    }

    private func task(_ key: String) -> TodoItem? { todos.first { $0.uid == key } }

    private func previewCard(_ p: PlanOutcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APERÇU, RIEN N'EST ENCORE ÉCRIT").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
            let placed = p.placed.sorted { $0.value.start < $1.value.start }
            if placed.isEmpty && p.overflow.isEmpty {
                Text("Aucune tâche à placer ce jour. Ajoute des tâches dans Todoo.").font(.footnote)
            }
            ForEach(placed, id: \.key) { key, s in
                HStack {
                    Text("\(s.start.formatted(date: .omitted, time: .shortened)) à \(s.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.monospacedDigit().bold()).foregroundStyle(.prodTint)
                    Text(task(key)?.title ?? "Tâche").font(.subheadline).lineLimit(1)
                    Spacer()
                    Text("\(s.minutes) min").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            if !p.overflow.isEmpty {
                Divider()
                Text("Sans créneau").font(.caption.bold()).foregroundStyle(Theme.warning)
                ForEach(p.overflow, id: \.key) { o in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task(o.key)?.title ?? "Tâche").font(.subheadline)
                        Text(o.reason).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            HStack {
                Button("Annuler") { preview = nil }
                Spacer()
                Button("Appliquer") { apply() }.bold().disabled(placed.isEmpty && p.overflow.isEmpty)
            }
            .font(.subheadline)
        }
        .card()
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TA JOURNÉE").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                Spacer()
                if scheduled.contains(where: { !$0.blockLocked }) {
                    Button("Effacer les blocs non verrouillés", role: .destructive) { clearBlocks() }.font(.caption)
                }
            }
            if scheduled.isEmpty && events.isEmpty {
                EmptyState(icon: "calendar.badge.clock", title: "Journée vide",
                           message: "Propose un planning : tes tâches sont placées selon leur durée estimée, sans chevaucher tes rendez-vous ni tes blocs fixes.")
            } else {
                Text("Maintiens un bloc puis glisse-le pour le déplacer : il devient verrouillé.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                DayTimeline(display: display, wholeDay: wholeDay, tasks: scheduled, events: events, lunch: lunchSlot,
                            onMove: move, onToggleLock: toggleLock, onUnschedule: unschedule, onOpen: { editing = $0 })
            }
        }
        .card()
    }

    @ViewBuilder private var overflowCard: some View {
        if !unplaced.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("À PLACER (\(unplaced.count))").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                ForEach(unplaced) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.subheadline)
                            if let reason = overflow.first(where: { $0.key == t.uid })?.reason {
                                Text(reason).font(.caption2).foregroundStyle(Theme.warning)
                            }
                        }
                        Spacer()
                        Text("\(DayPlanner.durationOf(t)) min").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = t }
                }
            }
            .card()
        }
    }

    // MARK: Actions

    private func reloadCalendar() {
        access = CalendarBusy.access()
        events = CalendarBusy.events(from: wholeDay.start, to: wholeDay.end)
    }

    private func propose() {
        TodoIDs.ensure(ctx)
        reloadCalendar()
        let items = candidates.map { t in
            PlanItem(key: t.uid, minutes: DayPlanner.durationOf(t), existing: isOnDay(t.blockStart) ? slot(t) : nil)
        }
        let earliest = dayOffset == 0 ? Date() : window.start
        withAnimation { preview = DayPlanner.plan(items: items, busy: busy, window: window, earliest: earliest,
                                                  bufferMinutes: buffer, keepExisting: keepExisting) }
        message = nil
    }

    private func apply() {
        guard let p = preview else { return }
        for t in candidates {
            if let s = p.placed[t.uid] { t.blockStart = s.start; t.blockEnd = s.end }
            else if isOnDay(t.blockStart) { t.blockStart = nil; t.blockEnd = nil }
        }
        overflow = p.overflow
        save()
        let n = p.placed.count
        message = p.overflow.isEmpty
            ? "\(n) tâche\(n > 1 ? "s" : "") planifiée\(n > 1 ? "s" : "")."
            : "\(n) tâche\(n > 1 ? "s" : "") planifiée\(n > 1 ? "s" : ""), \(p.overflow.count) sans créneau (liste À placer)."
        withAnimation { preview = nil }
    }

    private func move(_ t: TodoItem, to s: PlanSlot) {
        t.blockStart = s.start; t.blockEnd = s.end
        // Pose a la main = verrouille: le planning ne l'ecrasera plus.
        t.blockLocked = true
        save()
        message = "« \(t.title) » déplacé à \(s.start.formatted(date: .omitted, time: .shortened)) et verrouillé."
        Haptics.tap()
    }

    private func toggleLock(_ t: TodoItem) { t.blockLocked.toggle(); save() }

    private func unschedule(_ t: TodoItem) {
        t.blockStart = nil; t.blockEnd = nil; t.blockLocked = false
        save()
    }

    /// Vide les creneaux non verrouilles du jour, sans toucher aux taches elles-memes.
    private func clearBlocks() {
        for t in scheduled where !t.blockLocked { t.blockStart = nil; t.blockEnd = nil }
        save()
        message = nil
    }

    private func save() {
        do { try ctx.save() }
        catch { AppLog.data.error("creneaux non sauvegardes: \(error.localizedDescription, privacy: .public)") }
    }
}

/// Frise d'une journee: rendez-vous du calendrier (gris, fixes), pause, et blocs
/// de taches deplacables (appui long puis glisser, ou menu pour le clavier/Mac).
struct DayTimeline: View {
    let display: PlanSlot
    let wholeDay: PlanSlot
    let tasks: [TodoItem]
    let events: [CalendarBusy.Event]
    let lunch: PlanSlot?
    var onMove: (TodoItem, PlanSlot) -> Void
    var onToggleLock: (TodoItem) -> Void
    var onUnschedule: (TodoItem) -> Void
    var onOpen: (TodoItem) -> Void

    @State private var dragKey: String?
    @State private var dragY: CGFloat = 0
    private let ptPerMin: CGFloat = 1.1
    private let gutter: CGFloat = 50

    private func y(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(display.start) / 60) * ptPerMin }
    private func h(_ s: PlanSlot) -> CGFloat { max(CGFloat(s.minutes) * ptPerMin, 24) }

    private var hours: [Date] {
        var out: [Date] = [], d = display.start
        while d <= display.end { out.append(d); d = d.addingTimeInterval(3600) }
        return out
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { hr in
                HStack(spacing: 6) {
                    Text(hr, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        .frame(width: gutter - 6, alignment: .trailing)
                    Rectangle().fill(Theme.stroke).frame(height: 0.5)
                }
                .offset(y: y(hr) - 6)
            }
            if let lunch {
                block(title: "Pause déjeuner", subtitle: nil, color: Theme.success.opacity(0.18), slot: lunch, icon: "fork.knife")
            }
            ForEach(events) { ev in
                block(title: ev.title, subtitle: "Calendrier", color: Color.gray.opacity(0.22),
                      slot: PlanSlot(start: ev.start, end: ev.end), icon: "calendar")
            }
            ForEach(tasks) { t in taskBlock(t) }
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(display.minutes) * ptPerMin + 12, alignment: .topLeading)
    }

    private func block(title: String, subtitle: String?, color: Color, slot: PlanSlot, icon: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.caption2)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                if let subtitle, h(slot) > 34 { Text(subtitle).font(.caption2).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: h(slot), maxHeight: h(slot), alignment: .topLeading)
        .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.leading, gutter)
        .offset(y: y(slot.start))
        .allowsHitTesting(false)
    }

    private func taskBlock(_ t: TodoItem) -> some View {
        let s = PlanSlot(start: t.blockStart ?? display.start, end: t.blockEnd ?? display.start)
        let dragging = dragKey == t.uid
        let tint: Color = t.priority >= 2 ? Theme.danger : (t.priority == 1 ? Theme.warning : .prodTint)
        let gesture = LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag) = value {
                    if dragKey != t.uid { dragKey = t.uid; Haptics.tap() }
                    dragY = drag?.translation.height ?? 0
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value, abs(drag.translation.height) > 2 {
                    onMove(t, DayPlanner.moved(s, byMinutes: Double(drag.translation.height / ptPerMin), within: wholeDay))
                }
                dragKey = nil; dragY = 0
            }
        return HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(t.title).font(.caption.weight(.semibold)).lineLimit(1)
                if h(s) > 34 {
                    Text("\(s.start.formatted(date: .omitted, time: .shortened)) · \(s.minutes) min")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if t.blockLocked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.textSecondary) }
        }
        .padding(.leading, 8).padding(.trailing, 32).padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: h(s), maxHeight: h(s), alignment: .topLeading)
        .background(tint.opacity(dragging ? 0.30 : 0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tint.opacity(dragging ? 0.8 : 0.3), lineWidth: 1))
        .padding(.leading, gutter)
        .offset(y: y(s.start) + (dragging ? dragY : 0))
        .zIndex(dragging ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { onOpen(t) }
        .gesture(gesture)
        // Menu par bouton (pas de menu contextuel: il entrerait en conflit avec
        // l'appui long qui lance le glisser). Sert aussi au clavier et a VoiceOver.
        .overlay(alignment: .topTrailing) {
            Menu {
                Button { onMove(t, DayPlanner.moved(s, byMinutes: -15, within: wholeDay)) } label: { Label("Avancer de 15 min", systemImage: "arrow.up") }
                Button { onMove(t, DayPlanner.moved(s, byMinutes: 15, within: wholeDay)) } label: { Label("Reculer de 15 min", systemImage: "arrow.down") }
                Button { onToggleLock(t) } label: {
                    Label(t.blockLocked ? "Déverrouiller" : "Verrouiller", systemImage: t.blockLocked ? "lock.open" : "lock")
                }
                Button { onOpen(t) } label: { Label("Modifier la tâche", systemImage: "pencil") }
                Button(role: .destructive) { onUnschedule(t) } label: { Label("Retirer du planning", systemImage: "calendar.badge.minus") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.caption).foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 24)
            }
            .accessibilityLabel("Options du bloc \(t.title)")
            .offset(y: y(s.start) + (dragging ? dragY : 0))
        }
        .accessibilityHint("Maintiens puis glisse pour déplacer, ou utilise le bouton d'options")
    }
}

/// Rendez-vous ou bloc pose a la main: verrouille d'office, jamais deplace par le planning.
struct FixedBlockEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let day: Date
    let defaultHour: Int
    @State private var title = ""
    @State private var start = Date()
    @State private var minutes = 60
    @State private var ready = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre (ex : Réunion d'équipe)", text: $title)
                DatePicker("Début", selection: $start, displayedComponents: .hourAndMinute)
                Picker("Durée", selection: $minutes) {
                    ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { Text("\($0) min").tag($0) }
                }
                Text("Ce bloc est verrouillé : le planning automatique ne le déplace jamais et place tes tâches autour.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .navigationTitle("Bloc fixe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !ready else { return }
                ready = true
                start = Calendar.current.date(bySettingHour: defaultHour, minute: 0, second: 0, of: day) ?? day
            }
        }
    }

    private func save() {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: start)
        let s = cal.date(bySettingHour: hm.hour ?? 9, minute: hm.minute ?? 0, second: 0, of: day) ?? start
        let t = TodoItem(title: title.trimmingCharacters(in: .whitespaces), due: s, project: "")
        t.blockStart = s
        t.blockEnd = s.addingTimeInterval(TimeInterval(minutes * 60))
        t.blockLocked = true
        t.estimateMinutes = minutes
        TodoIDs.ensure(t)
        ctx.insert(t)
        do { try ctx.save() } catch { AppLog.data.error("bloc fixe non enregistre: \(error.localizedDescription, privacy: .public)") }
        dismiss()
    }
}

// MARK: - Habit tracker

struct HabitTrackerView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Habit.scheduledHour) private var allHabits: [Habit]
    @State private var showAdd = false
    @State private var editingHabit: Habit?
    @AppStorage(AppStorageKeys.habitModulesRaw) private var habitModulesRaw = ""

    private var pendingHabits: [Habit] { allHabits.filter { $0.isPending && !$0.isArchived } }
    private var activeHabits: [Habit] { allHabits.filter { !$0.isPending && !$0.isArchived } }

    @State private var pendingDeleteHabit: Habit?
    @State private var undoWorkItem: DispatchWorkItem?

    private func softDelete(_ habit: Habit) {
        undoWorkItem?.cancel()
        habit.isArchived = true
        pendingDeleteHabit = habit
        let work = DispatchWorkItem {
            if let h = pendingDeleteHabit, h.isArchived {
                ctx.delete(h)
                do { try ctx.save() } catch { AppLog.data.error("delayed delete habit save failed: \(error.localizedDescription, privacy: .public)") }
            }
            pendingDeleteHabit = nil
        }
        undoWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func undoDelete() {
        undoWorkItem?.cancel()
        pendingDeleteHabit?.isArchived = false
        pendingDeleteHabit = nil
    }

    @State private var showPending = false

    var body: some View {
        HabitTrackerTimelineView()
            // Les habitudes proposees n'etaient affichees nulle part alors qu'une
            // notification hebdo annonce « N habitudes proposées t'attendent ».
            .safeAreaInset(edge: .top) {
                if !pendingHabits.isEmpty {
                    Button { showPending = true } label: {
                        Label("\(pendingHabits.count) habitude\(pendingHabits.count > 1 ? "s" : "") proposée\(pendingHabits.count > 1 ? "s" : "") à activer",
                              systemImage: "sparkles")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.warning.opacity(0.10), in: Capsule())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
            }
            .sheet(isPresented: $showPending) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 10) {
                            if pendingHabits.isEmpty {
                                EmptyState(icon: "checkmark.circle", title: "Tout est trié", message: "Plus aucune habitude proposée en attente.")
                            }
                            ForEach(pendingHabits) { PendingHabitRow(habit: $0) }
                        }
                        .padding(Theme.pad)
                    }
                    .navigationTitle("Habitudes proposées").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showPending = false } } }
                }
            }
            .navigationTitle("Habitly")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { HabitOverviewView() } label: { Image(systemName: "chart.bar.xaxis") }
                        .accessibilityLabel("Mes habitudes et statistiques")
                }
            }
            .task {
                resumeEndedPauses()
                let modules = habitModulesRaw.split(separator: ",").map(String.init)
                if !modules.isEmpty && allHabits.isEmpty {
                    HabitDefaults.insertPendingHabits(for: modules, into: ctx)
                }
                NotificationManager.shared.schedulePendingHabitNotification(pendingCount: pendingHabits.count)
                syncHabitsToWidget()
            }
            .onChange(of: pendingHabits.count) { _, new in
                NotificationManager.shared.schedulePendingHabitNotification(pendingCount: new)
            }
            .onChange(of: allHabits.count) { _, _ in syncHabitsToWidget() }
    }

    /// Une pause finie: l'habitude revient et ses rappels sont reposes.
    private func resumeEndedPauses() {
        for h in allHabits where h.pausedUntil != nil && !HabitRules.isPaused(h.pausedUntil, on: .now) {
            h.pausedUntil = nil
            HabitReminders.schedule(h)
        }
        try? ctx.save()
    }

    private func syncHabitsToWidget() {
        // Un seul ecrivain de l'instantane des habitudes: HabitSync.
        HabitSync.ensureIDs(ctx)
        HabitSync.publish(ctx)
        // Vraie serie moyenne (jours actifs), plus un total de completions.
        ProductivityRules.publishAverageStreak(activeHabits)
        // Rappels d'habitudes supprimees ou archivees ailleurs: on les retire.
        HabitReminders.prune(keeping: Set(activeHabits.map(\.uid).filter { !$0.isEmpty }))

        WidgetCenter.shared.reloadTimelines(ofKind: "HabitsWidget")
    }
}

struct PendingHabitRow: View {
    @Environment(\.modelContext) private var ctx
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: habit.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: UInt(habit.colorHex)))
                .frame(width: 36, height: 36)
                .background(Color(hex: UInt(habit.colorHex)).opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(habit.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.25)) {
                    habit.isPending = false
                    do { try ctx.save() } catch { AppLog.data.error("activateHabit failed: \(error.localizedDescription, privacy: .public)") }
                }
                Haptics.tap()
            } label: {
                Text("Activer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(hex: UInt(habit.colorHex)), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                ctx.delete(habit)
                do { try ctx.save() } catch { AppLog.data.error("deleteHabit failed: \(error.localizedDescription, privacy: .public)") }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Theme.warning.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.warning.opacity(0.2), lineWidth: 1)
        )
    }
}

struct HabitRow: View {
    @Environment(\.modelContext) private var ctx
    let habit: Habit
    var onEdit: () -> Void
    var onDelete: () -> Void = {}

    private var doneToday: Bool {
        habit.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: .now) }
    }
    // Serie sur les jours ACTIFS seulement (voir ProductivityRules.habitStreak).
    private var streak: Int { ProductivityRules.habitStreak(habit) }
    private var timeLabel: String { String(format: "%02d:%02d", habit.scheduledHour, habit.scheduledMinute) }

    var body: some View {
        HStack(spacing: 14) {
            Button { toggleToday() } label: {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(doneToday ? Color(hex: UInt(habit.colorHex)) : Color.secondary.opacity(0.35))
                    .animation(.spring(duration: 0.2), value: doneToday)
            }
            .buttonStyle(.plain)

            Image(systemName: habit.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: UInt(habit.colorHex)))
                .frame(width: 36, height: 36)
                .background(Color(hex: UInt(habit.colorHex)).opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(AppFont.sans(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(timeLabel)
                    .font(AppFont.body(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if streak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.caption2).foregroundStyle(Theme.warning)
                    Text("\(streak)")
                        .font(AppFont.body(size: 12, weight: .bold))
                        .foregroundStyle(Theme.warning)
                }
            }

            Button { onEdit() } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .contextMenu {
            Button { duplicate() } label: { Label("Dupliquer", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func duplicate() {
        let copy = Habit(
            name: habit.name + " (copie)",
            icon: habit.icon,
            colorHex: habit.colorHex,
            isPending: false,
            moduleTag: habit.moduleTag,
            scheduledHour: habit.scheduledHour,
            scheduledMinute: habit.scheduledMinute
        )
        ctx.insert(copy)
        do { try ctx.save() } catch { AppLog.data.error("duplicate habit save failed: \(error.localizedDescription, privacy: .public)") }
        Haptics.tap()
    }

    private func toggleToday() {
        if let c = habit.completions.first(where: { Calendar.current.isDate($0.date, inSameDayAs: .now) }) {
            habit.completions.removeAll { $0 === c }
            ctx.delete(c)
        } else {
            habit.completions.append(HabitCompletion())
        }
        Haptics.tap()
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitsWidget")
    }
}

struct HabitEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    var editingHabit: Habit? = nil
    var initialHour: Int? = nil

    @State private var name = ""
    @State private var icon = "drop.fill"
    @State private var color = 0x47CC5C
    @State private var scheduledHour = 9
    @State private var scheduledMinute = 0
    @State private var selectedDays: Set<Int> = Set(1...7)
    /// 0 jours precis, 1 « x fois par semaine »
    @State private var freqMode = 0
    @State private var weeklyTarget = 3
    @State private var targetKind = 0
    @State private var targetValue: Double = 8
    @State private var targetUnit = ""

    private let colors = [0x47CC5C, 0x2185FF, 0xFF2E33, 0xFFB83D, 0xA852F5, 0x24C7CC, 0xFF338C, 0x29BDC7]
    private let minutes = [0, 15, 30, 45]
    private let dayOptions: [(day: Int, label: String)] = [
        (2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header Liquid Glass
            HStack {
                Button("Annuler") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(LifeOSPressStyle(scale: 0.95))

                Spacer()

                Text(editingHabit == nil ? "Nouvelle habitude" : "Modifier l'habitude")
                    .font(AppFont.heading(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    save()
                } label: {
                    Text(editingHabit == nil ? "Créer" : "Enregistrer")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(LifeOSPressStyle(scale: 0.95))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Section 1: Nom
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NOM DE L'HABITUDE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        TextField("Ex: Méditation du matin, Salle de sport...", text: $name)
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .raisedSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), .nested)
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 2: Jours actifs
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FRÉQUENCE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        Picker("Fréquence", selection: $freqMode) {
                            Text("Jours précis").tag(0)
                            Text("Fois par semaine").tag(1)
                        }
                        .pickerStyle(.segmented)

                        if freqMode == 1 {
                            Stepper("\(weeklyTarget) fois par semaine, le jour de ton choix", value: $weeklyTarget, in: 1...7)
                                .font(.system(size: 15, weight: .medium))
                        } else {
                        HStack(spacing: 8) {
                            ForEach(dayOptions, id: \.day) { opt in
                                let isSel = selectedDays.contains(opt.day)
                                Button {
                                    if isSel {
                                        if selectedDays.count > 1 { selectedDays.remove(opt.day) }
                                    } else {
                                        selectedDays.insert(opt.day)
                                    }
                                    Haptics.tap()
                                } label: {
                                    Text(opt.label)
                                        .font(.system(size: 14, weight: .bold))
                                        .frame(width: 38, height: 38)
                                        .background(isSel ? Color.accentColor : Color.primary.opacity(0.06), in: Circle())
                                        .foregroundStyle(isSel ? Theme.onAccent : Theme.textPrimary)
                                }
                                .buttonStyle(LifeOSPressStyle(scale: 0.94))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)

                        HStack(spacing: 8) {
                            presetDayButton("Tous les jours", isSelected: selectedDays.count == 7) {
                                selectedDays = Set(1...7)
                            }
                            presetDayButton("Semaine", isSelected: selectedDays == [2, 3, 4, 5, 6]) {
                                selectedDays = [2, 3, 4, 5, 6]
                            }
                            presetDayButton("Week-end", isSelected: selectedDays == [7, 1]) {
                                selectedDays = [7, 1]
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Objectif: simple, quantite (8 verres) ou duree (20 min)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OBJECTIF DU JOUR")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                        Picker("Objectif", selection: $targetKind) {
                            Text("Fait / pas fait").tag(0)
                            Text("Quantité").tag(1)
                            Text("Durée").tag(2)
                        }
                        .pickerStyle(.segmented)
                        if targetKind == 1 {
                            Stepper("\(Int(targetValue)) \(targetUnit.isEmpty ? "fois" : targetUnit)", value: $targetValue, in: 1...200)
                            TextField("Unité (ex : verres, pages, pompes)", text: $targetUnit)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), .nested)
                        } else if targetKind == 2 {
                            Stepper("\(Int(targetValue)) min", value: $targetValue, in: 5...300, step: 5)
                        }
                        if targetKind > 0 {
                            Text("Chaque appui sur le rond de la frise ajoute \(targetKind == 2 ? "5 min" : "1"). L'habitude est cochée quand l'objectif est atteint.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 3: Horaire
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HORAIRE DU RAPPEL")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        HStack {
                            Label("Heure quotidienne", systemImage: "clock.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.primary)
                            Spacer()
                            DatePicker("", selection: Binding(
                                get: {
                                    var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                                    c.hour = scheduledHour
                                    c.minute = scheduledMinute
                                    return Calendar.current.date(from: c) ?? .now
                                },
                                set: { newDate in
                                    let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                    scheduledHour = c.hour ?? 9
                                    scheduledMinute = c.minute ?? 0
                                }
                            ), displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        }
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 4: Icône
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ICÔNE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        SmartIconPicker(selectedIcon: $icon, queryText: name, accentColor: Color(hex: UInt(color)))
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 5: Couleur
                    VStack(alignment: .leading, spacing: 12) {
                        Text("COULEUR")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        HStack(spacing: 12) {
                            ForEach(colors, id: \.self) { c in
                                let isSel = color == c
                                Button {
                                    color = c
                                    Haptics.tap()
                                } label: {
                                    Circle()
                                        .fill(Color(hex: UInt(c)))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: isSel ? 3 : 0)
                                        )
                                        .shadow(color: Color(hex: UInt(c)).opacity(isSel ? 0.45 : 0.15), radius: isSel ? 5 : 2, y: isSel ? 2 : 1)
                                        .scaleEffect(isSel ? 1.15 : 1.0)
                                        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSel)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 6: Supprimer (si modification)
                    if editingHabit != nil {
                        Button(role: .destructive) {
                            if let h = editingHabit {
                                HabitReminders.cancel(uid: h.uid)
                                ctx.delete(h)
                                do { try ctx.save() } catch { AppLog.data.error("delete habit failed: \(error.localizedDescription, privacy: .public)") }
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "trash")
                                Text("Supprimer cette habitude")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundStyle(Theme.danger)
                            .padding(.vertical, 14)
                        }
                        .padding(4)
                        .liquidGlassCard(cornerRadius: Theme.radius)
                    }
                }
                .padding(20)
            }
        }
        .background(Color.white.ignoresSafeArea())
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .onAppear {
            if let h = editingHabit {
                name = h.name; icon = h.icon; color = h.colorHex
                scheduledHour = h.scheduledHour; scheduledMinute = h.scheduledMinute
                selectedDays = h.activeDays
                freqMode = h.weeklyTarget > 0 ? 1 : 0
                weeklyTarget = h.weeklyTarget > 0 ? h.weeklyTarget : 3
                targetKind = h.targetKind
                targetValue = h.targetValue > 0 ? h.targetValue : (h.targetKind == 2 ? 20 : 8)
                targetUnit = h.targetUnit
            } else if let initialHour {
                scheduledHour = initialHour
            }
        }
    }

    private func presetDayButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
            Haptics.tap()
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04), in: Capsule())
        .overlay(Capsule().stroke(isSelected ? Color.accentColor : Theme.stroke, lineWidth: isSelected ? 1.5 : 0.6))
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .buttonStyle(LifeOSPressStyle(scale: 0.95))
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // « x fois par semaine »: l'habitude est proposee chaque jour jusqu'a ce que
        // l'objectif de la semaine soit atteint.
        let daysRaw = freqMode == 1 ? "1,2,3,4,5,6,7" : selectedDays.sorted().map(String.init).joined(separator: ",")
        let saved: Habit
        if let h = editingHabit {
            h.name = trimmed; h.icon = icon; h.colorHex = color
            h.scheduledHour = scheduledHour; h.scheduledMinute = scheduledMinute
            h.activeDaysRaw = daysRaw
            saved = h
        } else {
            saved = Habit(name: trimmed, icon: icon, colorHex: color, scheduledHour: scheduledHour, scheduledMinute: scheduledMinute, activeDaysRaw: daysRaw)
            ctx.insert(saved)
        }
        saved.weeklyTarget = freqMode == 1 ? weeklyTarget : 0
        saved.targetKind = targetKind
        saved.targetValue = targetKind == 0 ? 0 : targetValue
        saved.targetUnit = targetKind == 1 ? targetUnit.trimmingCharacters(in: .whitespaces) : ""
        do {
            try ctx.save()
        } catch {
            AppLog.data.error("save habit failed: \(error.localizedDescription, privacy: .public)")
        }
        // Le rappel promis par « HORAIRE DU RAPPEL » existe enfin. Une ancienne fiche
        // sans uid en recoit un d'abord: le rappel est identifie par lui.
        if saved.uid.isEmpty { HabitSync.ensureIDs(ctx) }
        HabitReminders.schedule(saved)
        WidgetCenter.shared.reloadAllTimelines()
        Haptics.medium()
        dismiss()
    }
}

// MARK: - Habitly : vue d'ensemble, fiche, statistiques

enum HabitLabels {
    static func frequency(_ h: Habit) -> String {
        if h.weeklyTarget > 0 { return "\(h.weeklyTarget) fois par semaine" }
        let d = h.activeDays
        if d.count == 7 { return "Tous les jours" }
        if d == TaskRecurrence.workweek { return "En semaine" }
        if d == [7, 1] { return "Le week-end" }
        return TaskRecurrence.weekly(d).label
    }

    static func target(_ h: Habit) -> String? {
        guard HabitRules.hasTarget(h) else { return nil }
        let v = h.targetValue.formatted(.number.precision(.fractionLength(0...1)))
        let unit = HabitRules.unitLabel(h)
        return unit.isEmpty ? "Objectif : \(v)" : "Objectif : \(v) \(unit)"
    }

    static func today(_ h: Habit, now: Date = .now) -> String {
        let cal = Calendar.current
        if h.completions.contains(where: { cal.isDate($0.date, inSameDayAs: now) }) { return "Fait aujourd'hui" }
        if HabitRules.isPaused(h.pausedUntil, on: now), let u = h.pausedUntil {
            return "En pause jusqu'au \(u.formatted(.dateTime.day().month()))"
        }
        if HabitRules.skipped(h.skippedDaysRaw).contains(ProductivityRules.dayKey(now)) { return "Sautée aujourd'hui" }
        if h.weeklyTarget > 0 {
            let n = HabitRules.doneCount(inWeekOf: now, completions: HabitRules.completionDates(h))
            return n >= h.weeklyTarget ? "Objectif de la semaine atteint" : "\(n)/\(h.weeklyTarget) cette semaine"
        }
        if HabitRules.hasTarget(h) {
            let p = HabitRules.progress(h, now: now)
            return "\(p.formatted(.number.precision(.fractionLength(0...1))))/\(h.targetValue.formatted(.number.precision(.fractionLength(0...1)))) \(HabitRules.unitLabel(h))"
        }
        return HabitRules.isDueToday(h, now: now) ? "À faire" : "Pas prévue aujourd'hui"
    }
}

@MainActor
enum HabitStore {
    /// Apres chaque changement: sauvegarde, instantane des widgets (seul ecrivain:
    /// HabitSync), serie moyenne du coach.
    static func commit(_ ctx: ModelContext) {
        do { try ctx.save() } catch { AppLog.data.error("habitude non enregistree: \(error.localizedDescription, privacy: .public)") }
        HabitSync.publish(ctx)
        let all = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        ProductivityRules.publishAverageStreak(all)
    }
}

struct HabitOverviewView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Habit.scheduledHour) private var allHabits: [Habit]
    @State private var showNew = false
    private var habits: [Habit] { allHabits.filter { !$0.isPending && !$0.isArchived } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                LazyVStack(spacing: 10) {
                    if habits.isEmpty {
                        EmptyState(icon: "square.grid.3x3", title: "Aucune habitude",
                                   message: "Crée ta première habitude : un objectif simple, une quantité ou une durée.",
                                   actionTitle: "Nouvelle habitude") { showNew = true }
                    }
                    ForEach(habits) { h in
                        NavigationLink { HabitDetailView(habit: h) } label: { row(h) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(Theme.pad)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Mes habitudes").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nouvelle habitude") } }
        .sheet(isPresented: $showNew) { HabitEditor() }
    }

    private func row(_ h: Habit) -> some View {
        let color = Color(hex: UInt(h.colorHex))
        let streak = HabitRules.streak(h)
        let rate = HabitRules.completionRate(completions: HabitRules.completionDates(h), activeDays: h.activeDays,
                                             weeklyTarget: h.weeklyTarget, skipped: HabitRules.skipped(h.skippedDaysRaw), since: h.createdAt)
        return HStack(spacing: 12) {
            Image(systemName: h.icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(h.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("\(HabitLabels.frequency(h)) · \(HabitLabels.today(h))").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if streak > 0 {
                    Label("\(streak)", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(Theme.warning)
                }
                if let rate { Text("\(Int((rate * 100).rounded())) %").font(.caption2).foregroundStyle(Theme.textSecondary) }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

struct HabitDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var showEdit = false
    @State private var showPause = false
    @State private var pauseUntil = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var futureTapNotice = false

    private var gone: Bool { habit.isDeleted || habit.modelContext == nil }

    var body: some View {
        ZStack {
            Theme.background
            if gone {
                EmptyState(icon: "trash", title: "Habitude supprimée")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        todayCard
                        statsGrid
                        HabitMonthGrid(habit: habit, month: $month, onTap: tapDay, onSkip: skipDay)
                            .card()
                        Text("Touche un jour passé pour le cocher ou le décocher. Appui long : sauter ce jour (la série n'est pas cassée).")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        actionsCard
                    }
                    .padding(Theme.pad)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(gone ? "" : habit.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !gone {
                ToolbarItem(placement: .topBarTrailing) { Button("Modifier") { showEdit = true } }
            }
        }
        .sheet(isPresented: $showEdit, onDismiss: { if gone { dismiss() } }) { HabitEditor(editingHabit: habit) }
        .sheet(isPresented: $showPause) { pauseSheet }
        .alert("Jour à venir", isPresented: $futureTapNotice) { Button("OK") {} } message: {
            Text("On ne peut pas cocher un jour qui n'est pas encore arrivé. Tu peux le sauter avec un appui long.")
        }
    }

    private var color: Color { Color(hex: UInt(habit.colorHex)) }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: habit.icon)
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(HabitLabels.frequency(habit)).font(.subheadline.weight(.semibold))
                if let t = HabitLabels.target(habit) { Text(t).font(.caption).foregroundStyle(Theme.textSecondary) }
                Text(HabitLabels.today(habit)).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .card()
    }

    private var doneToday: Bool { habit.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: .now) } }

    @ViewBuilder private var todayCard: some View {
        if HabitRules.hasTarget(habit) {
            let p = HabitRules.progress(habit)
            VStack(spacing: 10) {
                Text("AUJOURD'HUI").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 18) {
                    Button { change(-HabitRules.step(habit)) } label: { Image(systemName: "minus.circle.fill").font(.system(size: 34)) }
                        .buttonStyle(.plain).disabled(p <= 0).accessibilityLabel("Retirer")
                    VStack(spacing: 2) {
                        Text(p.formatted(.number.precision(.fractionLength(0...1))))
                            .font(.system(size: 34, weight: .black)).monospacedDigit()
                        Text("sur \(habit.targetValue.formatted(.number.precision(.fractionLength(0...1)))) \(HabitRules.unitLabel(habit))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(minWidth: 110)
                    Button { change(HabitRules.step(habit)) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 34)) }
                        .buttonStyle(.plain).accessibilityLabel("Ajouter")
                }
                .foregroundStyle(color)
                ProgressView(value: min(p / max(habit.targetValue, 1), 1)).tint(color)
            }
            .card()
        } else {
            Button {
                HabitRules.setDone(habit, on: .now, done: !doneToday, ctx: ctx)
                HabitStore.commit(ctx); Haptics.tap()
            } label: {
                Label(doneToday ? "Fait aujourd'hui" : "Cocher aujourd'hui", systemImage: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(doneToday ? color : Theme.textPrimary)
                    .glassControl(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            }
            .buttonStyle(LifeOSPressStyle())
        }
    }

    private var statsGrid: some View {
        let dates = HabitRules.completionDates(habit)
        let skipped = HabitRules.skipped(habit.skippedDaysRaw)
        let unit = habit.weeklyTarget > 0 ? "sem." : "j"
        let streak = HabitRules.streak(habit)
        let best = HabitRules.bestStreak(completions: dates, activeDays: habit.activeDays, weeklyTarget: habit.weeklyTarget,
                                         skipped: skipped, since: habit.createdAt)
        let rate = HabitRules.completionRate(completions: dates, activeDays: habit.activeDays, weeklyTarget: habit.weeklyTarget,
                                             skipped: skipped, since: habit.createdAt)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            statTile("Série actuelle", "\(streak) \(unit)", "flame.fill")
            statTile("Meilleure série", "\(max(best, streak)) \(unit)", "trophy.fill")
            statTile("Réussite 30 jours", rate.map { "\(Int(($0 * 100).rounded())) %" } ?? "Pas encore", "chart.bar.fill")
            statTile("Total", "\(Set(dates.map { Calendar.current.startOfDay(for: $0) }).count) jours", "checkmark.seal.fill")
        }
    }

    private func statTile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title3.weight(.black)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var actionsCard: some View {
        let paused = HabitRules.isPaused(habit.pausedUntil, on: .now)
        let skippedToday = HabitRules.skipped(habit.skippedDaysRaw).contains(ProductivityRules.dayKey(.now))
        return VStack(spacing: 0) {
            Button { skipDay(.now) } label: {
                Label(skippedToday ? "Ne plus sauter aujourd'hui" : "Sauter aujourd'hui", systemImage: "forward.end")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            }
            Divider()
            if paused {
                Button { resume() } label: {
                    Label("Reprendre maintenant", systemImage: "play.circle")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }
            } else {
                Button { showPause = true } label: {
                    Label("Mettre en pause…", systemImage: "pause.circle")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }
            }
        }
        .buttonStyle(.plain)
        .card()
    }

    private var pauseSheet: some View {
        NavigationStack {
            Form {
                DatePicker("En pause jusqu'au", selection: $pauseUntil, in: Date()..., displayedComponents: .date)
                Text("Pendant la pause, l'habitude disparaît de ta journée, ses rappels se taisent et ta série est gelée.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .navigationTitle("Pause").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { showPause = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mettre en pause") {
                        habit.skippedDaysRaw = HabitRules.pausing(habit.skippedDaysRaw, from: .now, through: pauseUntil)
                        habit.pausedUntil = Calendar.current.startOfDay(for: pauseUntil)
                        HabitStore.commit(ctx)
                        HabitReminders.schedule(habit)
                        showPause = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func change(_ amount: Double) {
        HabitRules.addProgress(habit, amount: amount, ctx: ctx)
        HabitStore.commit(ctx)
        Haptics.tap()
    }

    private func tapDay(_ day: Date) {
        let cal = Calendar.current
        guard cal.startOfDay(for: day) <= cal.startOfDay(for: .now) else { futureTapNotice = true; return }
        let done = habit.completions.contains { cal.isDate($0.date, inSameDayAs: day) }
        HabitRules.setDone(habit, on: day, done: !done, ctx: ctx)
        HabitStore.commit(ctx)
        Haptics.tap()
    }

    private func skipDay(_ day: Date) {
        habit.skippedDaysRaw = HabitRules.toggledSkip(habit.skippedDaysRaw, day: day)
        HabitStore.commit(ctx)
        Haptics.tap()
    }

    private func resume() {
        habit.skippedDaysRaw = HabitRules.resuming(habit.skippedDaysRaw, from: .now)
        habit.pausedUntil = nil
        HabitStore.commit(ctx)
        HabitReminders.schedule(habit)
    }
}

/// Calendrier du mois: fait (plein), saute (barre), manque (contour), a venir.
struct HabitMonthGrid: View {
    let habit: Habit
    @Binding var month: Date
    var onTap: (Date) -> Void
    var onSkip: (Date) -> Void

    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    private var days: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let lead = (cal.component(.weekday, from: interval.start) + 5) % 7
        return Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        let color = Color(hex: UInt(habit.colorHex))
        let doneDays = Set(habit.completions.map { cal.startOfDay(for: $0.date) })
        let skipped = HabitRules.skipped(habit.skippedDaysRaw)
        let today = cal.startOfDay(for: .now)
        let created = cal.startOfDay(for: habit.createdAt)
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Mois précédent")
                Spacer()
                Text(month, format: .dateTime.month(.wide).year()).font(.subheadline.weight(.bold))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Mois suivant")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(["L", "M", "M", "J", "V", "S", "D"].enumerated()), id: \.offset) { _, l in
                    Text(l).font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    if let d {
                        let key = ProductivityRules.dayKey(d)
                        let isDone = doneDays.contains(d)
                        let isSkipped = skipped.contains(key)
                        let due = habit.weeklyTarget == 0 && habit.activeDays.contains(cal.component(.weekday, from: d))
                        let missed = !isDone && !isSkipped && due && d < today && d >= created
                        ZStack {
                            Circle().fill(isDone ? color : Color.clear)
                            if missed { Circle().stroke(Theme.danger.opacity(0.5), lineWidth: 1.2) }
                            if isSkipped { Image(systemName: "minus").font(.caption2.bold()).foregroundStyle(Theme.textSecondary) }
                            else {
                                Text("\(cal.component(.day, from: d))")
                                    .font(.caption.weight(d == today ? .black : .regular))
                                    .foregroundStyle(isDone ? Color.white : (d > today ? Theme.textSecondary.opacity(0.5) : Theme.textPrimary))
                            }
                        }
                        .frame(height: 34)
                        .overlay(d == today ? Circle().stroke(color, lineWidth: 1.5) : nil)
                        .contentShape(Rectangle())
                        .onTapGesture { onTap(d) }
                        .onLongPressGesture { onSkip(d) }
                        .accessibilityLabel(d.formatted(.dateTime.day().month(.wide)) + (isDone ? ", fait" : isSkipped ? ", sauté" : ""))
                        .accessibilityAction(named: "Sauter ce jour") { onSkip(d) }
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
    }

    private func shift(_ n: Int) {
        if let m = cal.date(byAdding: .month, value: n, to: month) { month = m }
    }
}

// MARK: - Focus / Pomodoro

struct FocusTimerView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FocusSession.start, order: .reverse) private var history: [FocusSession]
    @State private var engine = CountdownEngine(key: "focus")
    // Phase, cycle et fin de phase PERSISTES: le moteur survit a une relance, l'ecran
    // doit retrouver ou il en etait (avant, tout etait en @State et se perdait).
    @AppStorage("focus.isFocus") private var isFocus = true
    @AppStorage("focus.phase") private var phaseRaw = FocusPhase.focus.rawValue
    @AppStorage("focus.cycleDone") private var cycleDone = 0
    /// Debut de la phase en cours (cle unique de la session enregistree).
    @AppStorage("focus.phaseStart") private var phaseStart: Double = 0
    /// Fin absolue de la phase en cours (0 = rien ne tourne).
    @AppStorage("focus.phaseEnd") private var phaseEnd: Double = 0
    @AppStorage("focus.tag") private var tag = ""
    /// Sortie de l'app pendant une concentration: heure, et ecran verrouille ou non.
    @AppStorage("focus.leftAt") private var leftAt: Double = 0
    @AppStorage("focus.lockedAway") private var lockedAway = false
    @AppStorage(AppStorageKeys.focusLen) private var focusLen = 25
    @AppStorage(AppStorageKeys.breakLen) private var breakLen = 5
    @AppStorage("focus.longBreakLen") private var longBreakLen = 15
    @AppStorage("focus.cycleLength") private var cycleLength = 4
    @AppStorage("focus.autoStartFocus") private var autoStartFocus = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var notice: String?
    @State private var lastBroken = false
    @State private var confirmStop = false
    @State private var newTag = ""
    @State private var askTag = false

    static let endNotificationID = "focus.phase.end"

    private var phase: FocusPhase { FocusPhase(rawValue: phaseRaw) ?? .focus }
    private var config: FocusConfig { FocusConfig(focus: focusLen, shortBreak: breakLen, longBreak: longBreakLen, cycleLength: cycleLength) }
    /// En cours = qui tourne OU en pause avec du temps restant.
    private var running: Bool { engine.isRunning || engine.remaining > 0 }
    private var today: [FocusSession] { history.filter { Calendar.current.isDateInToday($0.start) } }
    private var knownTags: [String] {
        TagList.parse(history.map(\.tag).joined(separator: ",")).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 20) {
                    Text(running ? phase.label : "PRÊT À TE CONCENTRER")
                        .font(.caption.bold())
                        .foregroundStyle(phase == .focus ? .prodTint : Theme.success)
                    FocusTree(stage: treeStage, dead: lastBroken && !running, size: 150)
                        .accessibilityLabel(lastBroken && !running ? "Arbre mort" : "Arbre, stade \(treeStage + 1) sur 5")
                    TimerDial(engine: engine, tint: phase == .focus ? Color.accentColor : Theme.success,
                              caption: phase == .focus ? "Session \(cycleDone + 1) sur \(cycleLength)" : "Pause")
                    if let notice {
                        Text(notice).font(.footnote).foregroundStyle(lastBroken ? Theme.danger : Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    tagPicker
                    controls
                    todayForest
                    if !running { settingsCard }
                    Text("Règle : quitter l'app plus de 10 secondes pendant la concentration fait échouer la session. Verrouiller l'écran est toléré si ton iPhone a un code.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    NavigationLink { FocusStatsView() } label: {
                        Label("Historique et statistiques", systemImage: "chart.bar.xaxis")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .glassControl(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    IntegrationNotice(text: "Le blocage des autres apps façon Forest demande l'autorisation Temps d'écran d'Apple (FamilyControls), pas encore accordée à LifeOS. La règle de sortie ci-dessus s'applique déjà.")
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Forêt").navigationBarTitleDisplayMode(.inline)
        .onAppear { reattach() }
        .onChange(of: scenePhase) { _, p in
            if p == .background { wentAway() }
            if p == .active { reattach() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            // L'ecran se verrouille (iPhone avec code): ce n'est pas une sortie.
            if engine.isRunning && phase == .focus { lockedAway = true }
        }
        .confirmationDialog("Abandonner la session ?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { abandon() }
        } message: { Text("La session comptera comme échouée et l'arbre ne survivra pas.") }
        .alert("Nouveau tag", isPresented: $askTag) {
            TextField("Ex : Révisions, Projet X", text: $newTag)
            Button("Choisir") { let t = newTag.trimmingCharacters(in: .whitespaces); if !t.isEmpty { tag = t }; newTag = "" }
            Button("Annuler", role: .cancel) { newTag = "" }
        }
    }

    private var treeStage: Int {
        if !running { return lastBroken ? 4 : 0 }
        return phase == .focus ? FocusRules.growthStage(progress: engine.progress) : 4
    }

    private var tagPicker: some View {
        Menu {
            Button { tag = "" } label: { Label("Sans tag", systemImage: tag.isEmpty ? "checkmark" : "tag.slash") }
            ForEach(knownTags, id: \.self) { t in
                Button { tag = t } label: { Label(t, systemImage: tag == t ? "checkmark" : "tag") }
            }
            Button { askTag = true } label: { Label("Nouveau tag…", systemImage: "plus") }
        } label: {
            Label(tag.isEmpty ? "Sans tag" : tag, systemImage: "tag")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .disabled(running && phase == .focus)
    }

    @ViewBuilder private var controls: some View {
        if !running {
            PrimaryButton(title: "Démarrer le focus", icon: "play.fill", tint: .prodTint) { startFocus() }
        } else {
            HStack {
                PrimaryButton(title: engine.isRunning ? "Pause" : "Reprendre", icon: engine.isRunning ? "pause.fill" : "play.fill", tint: .prodTint) {
                    if engine.isRunning {
                        engine.pause(); phaseEnd = 0
                        NotificationManager.shared.cancel(id: Self.endNotificationID)
                    } else {
                        engine.resume(); phaseEnd = engine.deadline?.timeIntervalSince1970 ?? 0
                        scheduleEndNotification()
                    }
                }
                PrimaryButton(title: phase == .focus ? "Abandonner" : "Passer", icon: "stop.fill", tint: Theme.bg2) {
                    if phase == .focus { confirmStop = true } else { stopAll() }
                }
            }
        }
    }

    @ViewBuilder private var todayForest: some View {
        if !today.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                let done = today.filter(\.isCompleted)
                Text("TA FORÊT DU JOUR · \(done.count) arbre\(done.count > 1 ? "s" : "") · \(done.reduce(0) { $0 + $1.focusedSeconds } / 60) min")
                    .font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(today.reversed()) { s in
                            FocusTree(stage: s.isCompleted ? 4 : 2, dead: !s.isCompleted, size: 40)
                                .accessibilityLabel(s.isCompleted ? "Session réussie" : "Session échouée")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 8) {
            Stepper("Concentration \(focusLen) min", value: $focusLen, in: 5...90, step: 5)
            Stepper("Pause courte \(breakLen) min", value: $breakLen, in: 1...30)
            Stepper("Pause longue \(longBreakLen) min", value: $longBreakLen, in: 5...60, step: 5)
            Stepper("Pause longue toutes les \(cycleLength) sessions", value: $cycleLength, in: 2...8)
            Toggle("Relancer la concentration après la pause", isOn: $autoStartFocus)
        }
        .font(.footnote).card()
    }

    // MARK: Cycle

    /// Rebranche l'ecran sur une phase lancee avant (relance, retour au premier plan)
    /// et applique la regle de sortie.
    private func reattach() {
        engine.onFinish = finishPhase
        if leftAt > 0, phase == .focus, phaseEnd > 0 {
            let outcome = FocusRules.awayOutcome(leftAt: Date(timeIntervalSince1970: leftAt), returnedAt: .now,
                                                 phaseEnd: Date(timeIntervalSince1970: phaseEnd), deviceLocked: lockedAway)
            let left = leftAt
            leftAt = 0; lockedAway = false
            if outcome == .broken {
                let focused = max(0, Int(left - phaseStart))
                engine.stop()
                NotificationManager.shared.cancel(id: Self.endNotificationID)
                record(.interrupted, seconds: focused, end: Date(timeIntervalSince1970: left))
                resetToIdle()
                lastBroken = true
                notice = "Session interrompue : tu as quitté l'app plus de 10 secondes. L'arbre n'a pas survécu."
                Haptics.warning()
                return
            }
        }
        leftAt = 0; lockedAway = false
        if engine.isRunning {
            engine.refresh()
        } else if phaseEnd > 0, engine.remaining == 0, Date(timeIntervalSince1970: phaseEnd) <= .now {
            // La phase s'est terminee app fermee (ecran verrouille): une concentration
            // terminee compte; on n'enchaine pas une pause deja passee.
            if phase == .focus {
                record(.completed, seconds: focusSeconds(), end: Date(timeIntervalSince1970: phaseEnd))
                let next = FocusRules.phaseAfter(.focus, focusDoneInCycle: cycleDone, config: config)
                cycleDone = next.focusDoneInCycle
                notice = "Session terminée pendant ton absence : un arbre de plus."
            }
            resetToIdle()
        }
    }

    private func wentAway() {
        guard engine.isRunning, phase == .focus else { return }
        leftAt = Date().timeIntervalSince1970
        lockedAway = false
    }

    /// Une concentration menee a son terme vaut sa duree prevue (les pauses du
    /// minuteur ne comptent pas comme concentration).
    private func focusSeconds() -> Int { focusLen * 60 }

    private func startPhase(_ p: FocusPhase, minutes: Int) {
        phaseRaw = p.rawValue
        isFocus = p == .focus
        engine.onFinish = finishPhase
        engine.start(seconds: max(1, minutes) * 60)
        phaseStart = Date().timeIntervalSince1970
        phaseEnd = engine.deadline?.timeIntervalSince1970 ?? 0
        scheduleEndNotification()
    }

    private func startFocus() {
        lastBroken = false
        notice = nil
        startPhase(.focus, minutes: focusLen)
    }

    private func finishPhase() {
        NotificationManager.shared.cancel(id: Self.endNotificationID)
        let next = FocusRules.phaseAfter(phase, focusDoneInCycle: cycleDone, config: config)
        if phase == .focus {
            record(.completed, seconds: focusSeconds(), end: .now)
            notice = next.phase == .longBreak ? "Cycle terminé : pause longue bien méritée." : "Session réussie : ton arbre a fini de pousser."
        }
        cycleDone = next.focusDoneInCycle
        if next.phase == .focus && !autoStartFocus {
            resetToIdle()
        } else {
            startPhase(next.phase, minutes: next.minutes)
        }
    }

    private func abandon() {
        let focused = max(0, engine.total - engine.remaining)
        engine.stop()
        NotificationManager.shared.cancel(id: Self.endNotificationID)
        record(.abandoned, seconds: min(focused, focusLen * 60), end: .now)
        resetToIdle()
        lastBroken = true
        notice = "Session abandonnée."
    }

    private func stopAll() {
        engine.stop()
        NotificationManager.shared.cancel(id: Self.endNotificationID)
        resetToIdle()
    }

    private func resetToIdle() {
        phaseRaw = FocusPhase.focus.rawValue
        isFocus = true
        phaseEnd = 0
        phaseStart = 0
    }

    /// Une phase = une ligne, meme apres relance (cle = debut de phase).
    private func record(_ outcome: FocusRules.Outcome, seconds: Int, end: Date) {
        guard phaseStart > 0 else { return }
        let start = Date(timeIntervalSince1970: phaseStart)
        let key = FocusRules.phaseKey(start: start)
        guard FocusRules.shouldRecord(key: key, existing: Set(history.map(\.phaseKey))) else { return }
        ctx.insert(FocusSession(phaseKey: key, start: start, end: end, plannedMinutes: focusLen,
                                focusedSeconds: seconds, tag: tag, outcome: outcome.rawValue))
        do { try ctx.save() } catch { AppLog.data.error("session focus non enregistree: \(error.localizedDescription, privacy: .public)") }
        phaseStart = 0
    }

    private func scheduleEndNotification() {
        guard let end = engine.deadline else { return }
        let body = phase == .focus ? "Session terminée : ton arbre a fini de pousser." : "La pause est finie, on s'y remet ?"
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
            NotificationManager.shared.schedule(id: Self.endNotificationID, title: "Forêt", body: body, at: end)
        }
    }
}

/// Arbre dessine en SwiftUI, sans image: graine, pousse, plant, arbuste, arbre.
struct FocusTree: View {
    var stage: Int
    var dead = false
    var size: CGFloat = 150

    var body: some View {
        let leaf = dead ? Color(red: 0.55, green: 0.47, blue: 0.38) : Color(red: 0.24, green: 0.62, blue: 0.34)
        let leaf2 = dead ? Color(red: 0.47, green: 0.40, blue: 0.33) : Color(red: 0.18, green: 0.52, blue: 0.29)
        let trunk = dead ? Color.gray : Color(red: 0.45, green: 0.31, blue: 0.20)
        let s = min(max(stage, 0), 4)
        let trunkH: [CGFloat] = [0, 0.16, 0.26, 0.34, 0.40]
        let crown: [CGFloat] = [0, 0.14, 0.26, 0.38, 0.52]
        ZStack(alignment: .bottom) {
            Ellipse().fill(Color.brown.opacity(0.22)).frame(width: size * 0.7, height: size * 0.1)
            if s == 0 {
                Ellipse().fill(trunk).frame(width: size * 0.09, height: size * 0.07).offset(y: -size * 0.04)
            } else {
                Capsule().fill(trunk)
                    .frame(width: size * (0.03 + 0.01 * CGFloat(s)), height: size * trunkH[s])
                    .offset(y: -size * 0.04)
                ZStack {
                    if s >= 3 {
                        Circle().fill(leaf2).frame(width: size * crown[s] * 0.7).offset(x: -size * crown[s] * 0.32, y: size * 0.04)
                        Circle().fill(leaf2).frame(width: size * crown[s] * 0.7).offset(x: size * crown[s] * 0.32, y: size * 0.04)
                    }
                    if s == 1 {
                        Ellipse().fill(leaf).frame(width: size * 0.12, height: size * 0.06).rotationEffect(.degrees(-30)).offset(x: -size * 0.05)
                        Ellipse().fill(leaf).frame(width: size * 0.12, height: size * 0.06).rotationEffect(.degrees(30)).offset(x: size * 0.05)
                    } else {
                        Circle().fill(leaf).frame(width: size * crown[s])
                    }
                    if s == 4 {
                        Circle().fill(leaf).frame(width: size * 0.3).offset(y: -size * 0.16)
                    }
                }
                .offset(y: -size * (0.04 + trunkH[s] - 0.02))
            }
        }
        .frame(width: size, height: size, alignment: .bottom)
        .animation(.spring(duration: 0.5), value: s)
    }
}

struct FocusStatsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FocusSession.start, order: .reverse) private var history: [FocusSession]
    @State private var range = 7

    private var inRange: [FocusSession] {
        guard range > 0, let from = Calendar.current.date(byAdding: .day, value: -(range - 1), to: Calendar.current.startOfDay(for: .now)) else { return history }
        return history.filter { $0.start >= from }
    }

    var body: some View {
        let stats = FocusRules.stats(inRange)
        let done = inRange.filter(\.isCompleted)
        let failed = inRange.count - done.count
        return ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Période", selection: $range) {
                        Text("7 jours").tag(7); Text("30 jours").tag(30); Text("Tout").tag(0)
                    }
                    .pickerStyle(.segmented)
                    if history.isEmpty {
                        EmptyState(icon: "leaf", title: "Pas encore d'arbre", message: "Termine une session de concentration pour planter ton premier arbre.")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                            tile("\(done.reduce(0) { $0 + $1.focusedSeconds } / 60) min", "Concentration réussie")
                            tile("\(done.count)", "Arbres plantés")
                            tile("\(failed)", "Sessions échouées")
                            tile(inRange.isEmpty ? "Pas encore" : "\(Int((Double(done.count) / Double(inRange.count) * 100).rounded())) %", "Taux de réussite")
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PAR TAG").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                            ForEach(stats, id: \.tag) { s in
                                HStack {
                                    Text(s.tag).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(s.minutes) min · \(s.completed) réussie\(s.completed > 1 ? "s" : "") · \(Int((s.successRate * 100).rounded())) %")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .card()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HISTORIQUE").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                            ForEach(inRange) { s in
                                HStack(spacing: 10) {
                                    FocusTree(stage: s.isCompleted ? 4 : 2, dead: !s.isCompleted, size: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.start, format: .dateTime.weekday(.abbreviated).day().month().hour().minute()).font(.subheadline)
                                        Text("\(s.tag.isEmpty ? FocusRules.noTag : s.tag) · \(s.focusedSeconds / 60) min · \(label(s.outcome))")
                                            .font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) { ctx.delete(s); try? ctx.save() } label: { Image(systemName: "trash").font(.caption) }
                                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                                        .accessibilityLabel("Supprimer cette session")
                                }
                            }
                        }
                        .card()
                    }
                }
                .padding(Theme.pad)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Statistiques").navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ outcome: String) -> String {
        switch outcome {
        case FocusRules.Outcome.completed.rawValue: return "réussie"
        case FocusRules.Outcome.interrupted.rawValue: return "sortie de l'app"
        default: return "abandonnée"
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.weight(.black)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Notes

struct NotesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.created, order: .reverse) private var notes: [Note]
    @State private var search = ""
    @State private var showAdd = false
    @State private var folder = ""
    @State private var tag: String?
    @State private var pendingDelete: Note?

    private var folders: [String] { NoteFolders.folders(notes.map(\.folder)) }
    private var tags: [String] {
        TagList.parse(notes.map(\.tags).joined(separator: ",")).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filtered: [Note] {
        notes.filter { n in
            NoteFolders.contains(n.folder, folder: folder)
                && (tag.map { TagList.contains(n.tags, $0) } ?? true)
                && NoteSearch.matches(title: n.title, body: n.body, tags: n.tags, folder: n.folder, query: search)
        }
        .sorted { ($0.modified ?? $0.created) > ($1.modified ?? $1.created) }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    filterBar
                    if filtered.isEmpty {
                        EmptyState(icon: "note.text", title: search.isEmpty ? "Aucune note" : "Aucun résultat",
                                   message: search.isEmpty ? "Capture une idée, un lien, une réflexion. Le texte accepte le Markdown et les liens [[Titre]]." : "Aucune note ne contient ces mots.")
                    } else {
                        ForEach(filtered) { n in
                            NavigationLink { NoteEditor(note: n) } label: { card(n) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { pendingDelete = n } label: { Label("Supprimer", systemImage: "trash") }
                                }
                        }
                    }
                }
                .padding(Theme.pad)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .searchable(text: $search, prompt: "Rechercher dans tes notes")
        .navigationTitle("Notio").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) {
            NavigationStack { NoteEditor(note: nil, initialFolder: folder) }
        }
        .confirmationDialog("Supprimer cette note ?", isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let n = pendingDelete { ctx.delete(n); try? ctx.save() }
                pendingDelete = nil
            }
        } message: { Text("La note et son historique de versions seront supprimés.") }
    }

    @ViewBuilder private var filterBar: some View {
        if !folders.isEmpty || !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !folders.isEmpty {
                        Menu {
                            Button { folder = "" } label: { Label("Toutes les notes", systemImage: folder.isEmpty ? "checkmark" : "tray.full") }
                            ForEach(folders, id: \.self) { f in
                                Button { folder = f } label: { Label(f, systemImage: folder == f ? "checkmark" : "folder") }
                            }
                        } label: {
                            chip(folder.isEmpty ? "Tous les dossiers" : folder, icon: "folder", on: !folder.isEmpty)
                        }
                    }
                    ForEach(tags, id: \.self) { t in
                        Button { tag = (tag == t) ? nil : t } label: { chip("#\(t)", icon: nil, on: tag == t) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func chip(_ label: String, icon: String?, on: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(on ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05), in: Capsule())
        .foregroundStyle(on ? Color.accentColor : Theme.textPrimary)
    }

    private func card(_ n: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !n.folder.isEmpty {
                Label(n.folder, systemImage: "folder").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Text(n.title.isEmpty ? "Sans titre" : n.title).font(.headline).foregroundStyle(Theme.textPrimary)
            if let snip = search.isEmpty ? nil : NoteSearch.snippet(n.body, query: search) {
                Text(snip).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2)
            } else if !n.body.isEmpty {
                Text(NotesView.preview(n.body)).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            HStack {
                let t = TagList.parse(n.tags)
                if !t.isEmpty {
                    Text(t.map { "#\($0)" }.joined(separator: " ")).font(.caption2).foregroundStyle(.prodTint).lineLimit(1)
                }
                Spacer()
                Text(n.modified ?? n.created, format: .dateTime.day().month().hour().minute())
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    /// Apercu sans la syntaxe Markdown.
    static func preview(_ body: String) -> String {
        Markdown.blocks(body).prefix(4).map { b -> String in
            switch b {
            case .heading(_, let t), .bullet(let t, _), .numbered(_, let t), .quote(let t), .paragraph(let t): return Markdown.plain(t)
            case .task(let d, let t, _): return (d ? "☑︎ " : "☐ ") + Markdown.plain(t)
            case .rule: return ""
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

struct NoteEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var allNotes: [Note]
    let note: Note?
    var initialFolder: String = ""
    @State private var title = ""
    @State private var body_ = ""
    @State private var tags = ""
    @State private var folder = ""
    @State private var mode = 0     // 0 ecrire, 1 apercu
    @State private var showHistory = false
    @State private var linkTarget: Note?
    @State private var missingLink: String?
    @State private var deleted = false
    @State private var confirmDelete = false
    /// Evite d'ecraser la note avec des champs vides si l'ecran disparait avant
    /// d'avoir charge son contenu.
    @State private var loaded = false

    private var backlinks: [Note] {
        guard let note else { return [] }
        let others = allNotes.filter { $0.persistentModelID != note.persistentModelID }
        return NoteLinks.backlinks(to: title, in: others.map { ($0.title, $0.body) }).map { others[$0] }
    }

    var body: some View {
        Form {
            Section {
                TextField("Titre", text: $title).font(.headline)
                HStack {
                    TextField("Dossier (ex : Travail/Clients)", text: $folder)
                    let known = NoteFolders.folders(allNotes.map(\.folder))
                    if !known.isEmpty {
                        Menu {
                            Button("Racine") { folder = "" }
                            ForEach(known, id: \.self) { f in Button(f) { folder = f } }
                        } label: { Image(systemName: "folder") }
                        .accessibilityLabel("Choisir un dossier")
                    }
                }
                TextField("Tags (séparés par des virgules)", text: $tags)
            }
            Section {
                Picker("Mode", selection: $mode) {
                    Text("Écrire").tag(0)
                    Text("Aperçu").tag(1)
                }
                .pickerStyle(.segmented)
                if mode == 0 {
                    MarkdownEditorField(text: $body_)
                } else {
                    MarkdownPreview(text: body_) { line in body_ = Markdown.togglingTask(body_, line: line) }
                        .environment(\.openURL, OpenURLAction { url in
                            guard let t = NoteLinks.title(from: url) else { return .systemAction }
                            openLink(t)
                            return .handled
                        })
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                }
            } footer: {
                Text("Markdown : # titre, **gras**, _italique_, - liste, - [ ] case, [lien](https://…), [[Titre d'une note]].")
            }
            let outgoing = NoteLinks.targets(in: body_)
            if !outgoing.isEmpty {
                Section("Liens") {
                    ForEach(outgoing, id: \.self) { t in
                        Button { openLink(t) } label: {
                            Label(t, systemImage: NoteLinks.resolve(t, among: allNotes.map(\.title)) == nil ? "doc.badge.plus" : "link")
                        }
                    }
                }
            }
            if note != nil {
                Section("Liens retour") {
                    if backlinks.isEmpty {
                        Text("Aucune note ne pointe vers celle-ci. Écris [[\(title.isEmpty ? "Titre" : title)]] dans une autre note.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(backlinks) { n in
                        NavigationLink { NoteEditor(note: n) } label: { Label(n.title.isEmpty ? "Sans titre" : n.title, systemImage: "arrow.uturn.left") }
                    }
                }
            }
        }
        .navigationTitle(note == nil ? "Nouvelle note" : "Note").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $linkTarget) { NoteEditor(note: $0) }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("OK") { save(); dismiss() } }
            if note != nil {
                ToolbarItem(placement: .topBarTrailing) { moreMenu }
            }
        }
        .sheet(isPresented: $showHistory) { historySheet }
        .confirmationDialog("Créer la note « \(missingLink ?? "") » ?", isPresented: .init(get: { missingLink != nil }, set: { if !$0 { missingLink = nil } }), titleVisibility: .visible) {
            Button("Créer et ouvrir") {
                if let t = missingLink {
                    save()
                    let n = Note(title: t)
                    n.folder = NoteFolders.normalize(folder)
                    n.modified = .now
                    ctx.insert(n)
                    try? ctx.save()
                    linkTarget = n
                }
                missingLink = nil
            }
        }
        .confirmationDialog("Supprimer cette note ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let note { deleted = true; ctx.delete(note); try? ctx.save() }
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            if let note { title = note.title; body_ = note.body; tags = note.tags; folder = note.folder }
            else { folder = initialFolder }
            loaded = true
        }
        // Une note existante s'ouvre par un lien: le bouton retour jetait les
        // modifications sans prevenir. On enregistre aussi en quittant l'ecran.
        .onDisappear { if note != nil, loaded, !deleted { save() } }
    }

    private var moreMenu: some View {
        Menu {
            ShareLink(item: NoteMarkdownFile(title: title, text: NoteExport.markdown(title: title, body: body_, tags: tags, folder: NoteFolders.normalize(folder))),
                      preview: SharePreview(NoteExport.fileName(title, ext: "md"))) {
                Label("Exporter en Markdown", systemImage: "doc.plaintext")
            }
            ShareLink(item: NotePDFFile(title: title, body: body_), preview: SharePreview(NoteExport.fileName(title, ext: "pdf"))) {
                Label("Exporter en PDF", systemImage: "doc.richtext")
            }
            Button { save(); showHistory = true } label: { Label("Historique des versions", systemImage: "clock.arrow.circlepath") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer", systemImage: "trash") }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel("Plus")
    }

    private func openLink(_ target: String) {
        if let i = NoteLinks.resolve(target, among: allNotes.map(\.title)) {
            save()
            linkTarget = allNotes[i]
        } else {
            missingLink = target
        }
    }

    private var historySheet: some View {
        NavigationStack {
            let versions = Array(NoteHistory.decode(note?.historyRaw ?? "").reversed())
            List {
                if versions.isEmpty {
                    Text("Aucune version précédente. Chaque modification enregistrée garde l'ancien texte (\(NoteHistory.limit) versions au plus).")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(Array(versions.enumerated()), id: \.offset) { _, v in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.savedAt, format: .dateTime.day().month().year().hour().minute()).font(.caption.bold())
                        Text(v.title.isEmpty ? "Sans titre" : v.title).font(.subheadline)
                        Text(NotesView.preview(v.body)).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(3)
                        Button("Restaurer cette version") {
                            guard let note else { return }
                            save()
                            NoteHistory.restore(note, to: v)
                            try? ctx.save()
                            title = note.title; body_ = note.body; tags = note.tags
                            showHistory = false
                        }
                        .font(.caption.bold())
                    }
                }
            }
            .navigationTitle("Versions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showHistory = false } } }
        }
    }

    private func save() {
        if let note {
            guard !deleted, NoteHistory.save(note, title: title, body: body_, tags: tags, folder: folder) else { return }
        } else {
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty || !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let n = Note(title: title, body: body_, tags: tags)
            n.folder = NoteFolders.normalize(folder)
            n.modified = .now
            ctx.insert(n)
        }
        do { try ctx.save() }
        catch { AppLog.data.error("note non enregistree: \(error.localizedDescription, privacy: .public)") }
    }
}

/// Editeur Markdown avec barre de mise en forme. La selection n'est lisible qu'a
/// partir d'iOS 18 (TextSelection); avant, les boutons agissent en fin de texte.
struct MarkdownEditorField: View {
    @Binding var text: String

    var body: some View {
        if #available(iOS 18.0, *) {
            SelectionMarkdownEditor(text: $text)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                MarkdownFormatBar(text: $text, range: { text.count..<text.count }, setRange: { _ in })
                TextEditor(text: $text).frame(minHeight: 260)
            }
        }
    }
}

@available(iOS 18.0, *)
private struct SelectionMarkdownEditor: View {
    @Binding var text: String
    @State private var selection: TextSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownFormatBar(text: $text, range: { selectedRange }, setRange: setSelection)
            TextEditor(text: $text, selection: $selection).frame(minHeight: 260)
        }
    }

    /// Selection courante en offsets de caracteres (fin du texte sans selection).
    private var selectedRange: Range<Int> {
        let end = text.count
        guard let sel = selection, case .selection(let r) = sel.indices,
              r.lowerBound >= text.startIndex, r.upperBound <= text.endIndex else { return end..<end }
        return text.distance(from: text.startIndex, to: r.lowerBound)..<text.distance(from: text.startIndex, to: r.upperBound)
    }

    private func setSelection(_ r: Range<Int>) {
        let lo = text.index(text.startIndex, offsetBy: min(r.lowerBound, text.count))
        let hi = text.index(text.startIndex, offsetBy: min(r.upperBound, text.count))
        selection = TextSelection(range: lo..<hi)
    }
}

struct MarkdownFormatBar: View {
    @Binding var text: String
    var range: () -> Range<Int>
    var setRange: (Range<Int>) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                fmt("textformat.size.larger", "Titre") { prefix("## ") }
                fmt("bold", "Gras") { wrap("**") }
                fmt("italic", "Italique") { wrap("_") }
                fmt("list.bullet", "Liste") { prefix("- ") }
                fmt("checklist", "Case à cocher") { prefix("- [ ] ") }
                fmt("link", "Lien") { wrap("[", close: "](https://)") }
                fmt("link.badge.plus", "Lien vers une note") { wrap("[[", close: "]]") }
            }
            .padding(.vertical, 2)
        }
    }

    private func fmt(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.borderless)
            .accessibilityLabel(label)
    }

    private func wrap(_ open: String, close: String? = nil) {
        let first = Markdown.wrapping(text, selection: range(), marker: open)
        if let close, close != open {
            // Ferme avec un marqueur different: on remplace le second « open » insere.
            let chars = Array(first.text)
            let closeAt = first.selection.upperBound
            text = String(chars[..<closeAt]) + close + String(chars[(closeAt + open.count)...])
        } else {
            text = first.text
        }
        setRange(first.selection)
    }

    private func prefix(_ p: String) {
        let out = Markdown.prefixing(text, selection: range(), prefix: p)
        text = out.text
        setRange(out.selection)
    }
}

/// Rendu Markdown par blocs: titres, listes, cases cliquables, citations, liens.
struct MarkdownPreview: View {
    let text: String
    var onToggle: (Int) -> Void

    var body: some View {
        let blocks = Markdown.blocks(text)
        VStack(alignment: .leading, spacing: 8) {
            if blocks.isEmpty {
                Text("Rien à afficher.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let level, let t):
                    Text(Markdown.inline(t)).font(level == 1 ? .title2.bold() : (level == 2 ? .title3.bold() : .headline))
                case .bullet(let t, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); Text(Markdown.inline(t)) }
                        .padding(.leading, CGFloat(indent) * 16)
                case .numbered(let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(n).").monospacedDigit(); Text(Markdown.inline(t)) }
                case .task(let done, let t, let line):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button { onToggle(line) } label: {
                            Image(systemName: done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(done ? Theme.success : Theme.textSecondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(done ? "Décocher" : "Cocher")
                        Text(Markdown.inline(t)).strikethrough(done).foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                    }
                case .quote(let t):
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1).fill(Theme.stroke).frame(width: 3)
                        Text(Markdown.inline(t)).italic().foregroundStyle(Theme.textSecondary)
                    }
                case .paragraph(let t):
                    Text(Markdown.inline(t))
                case .rule:
                    Divider()
                }
            }
        }
    }
}

extension UTType {
    static let lifeosMarkdown = UTType(filenameExtension: "md") ?? .plainText
}

/// Fichier .md fabrique au moment du partage.
struct NoteMarkdownFile: Transferable {
    let title: String
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .lifeosMarkdown) { f in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(NoteExport.fileName(f.title, ext: "md"))
            try f.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

/// PDF fabrique au moment du partage.
struct NotePDFFile: Transferable {
    let title: String
    let body: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { f in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(NoteExport.fileName(f.title, ext: "pdf"))
            try NotePDF.data(title: f.title, body: f.body).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Note en PDF A4, texte reel (selectionnable), pagine.
enum NotePDF {
    static func attributed(title: String, body: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func add(_ s: String, _ font: UIFont, color: UIColor = .black, after: CGFloat = 6, indent: CGFloat = 0) {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = after
            p.headIndent = indent; p.firstLineHeadIndent = indent
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]))
        }
        add(title.isEmpty ? "Sans titre" : title, .boldSystemFont(ofSize: 22), after: 14)
        for b in Markdown.blocks(body) {
            switch b {
            case .heading(let level, let t): add(Markdown.plain(t), .boldSystemFont(ofSize: level == 1 ? 18 : (level == 2 ? 16 : 14)), after: 8)
            case .bullet(let t, let indent): add("•  " + Markdown.plain(t), .systemFont(ofSize: 12), indent: CGFloat(indent) * 14)
            case .numbered(let n, let t): add("\(n).  " + Markdown.plain(t), .systemFont(ofSize: 12))
            case .task(let done, let t, _): add((done ? "☑  " : "☐  ") + Markdown.plain(t), .systemFont(ofSize: 12))
            case .quote(let t): add(Markdown.plain(t), .italicSystemFont(ofSize: 12), color: .darkGray, indent: 14)
            case .paragraph(let t): add(Markdown.plain(t), .systemFont(ofSize: 12))
            case .rule: add("____________", .systemFont(ofSize: 12), color: .gray)
            }
        }
        return out
    }

    static func data(title: String, body: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let box = page.insetBy(dx: 48, dy: 56)
        let text = attributed(title: title, body: body)
        let setter = CTFramesetterCreateWithAttributedString(text)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            var index = 0
            repeat {
                ctx.beginPage()
                let cg = ctx.cgContext
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: page.height)
                cg.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: CGRect(x: box.minX, y: page.height - box.maxY, width: box.width, height: box.height), transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: index, length: 0), path, nil)
                CTFrameDraw(frame, cg)
                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 { break }
                index += visible.length
            } while index < text.length
        }
    }
}
