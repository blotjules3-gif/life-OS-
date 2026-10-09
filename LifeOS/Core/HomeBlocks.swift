import SwiftUI
import SwiftData

// Les 4 blocs de l'accueil du lot 8 : Maintenant, Aujourd'hui, A surveiller,
// Capture rapide. Ils lisent `HomeTodayModel` (deja filtre) et n'interrogent jamais
// la base dans `body`.

// MARK: - En-tete commun

struct HomeBlockHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.heading(size: 20, weight: .black))
                    .textCase(.uppercase)
                    .kerning(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let trailing, let action {
                Button(action: action) {
                    Text(trailing)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Une ligne cochable (tache, habitude), cible >= 44 pt.
private struct HomeCheckButton: View {
    let done: Bool
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Theme.success : tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "\(label), fait. Toucher pour rouvrir" : "Marquer fait : \(label)")
    }
}

// MARK: - Maintenant

struct HomeNowBlock: View {
    let model: HomeTodayModel
    @Binding var skippedRaw: String
    let onChanged: () -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingTask: TodoItem?
    @State private var openHabit: Habit?
    @State private var addKind: AddAnythingSheet.Kind?
    @State private var openTool: QuickTool?
    @State private var busy = false

    private var skipped: DayScopedList { DayScopedList.read(skippedRaw, today: .now) }
    private var current: NowCandidate? {
        HomeNowEngine.current(model.nowCandidates, skipped: Set(skipped.ids), now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeBlockHeader(title: "Maintenant")
            Group {
                if let c = current, let target = model.nowTargets[c.id] {
                    card(c, target)
                } else {
                    emptyCard
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: current?.id)
        }
        .sheet(item: $editingTask) { t in TodoEditor(task: t) }
        .sheet(item: $openHabit) { h in NavigationStack { HabitDetailView(habit: h) } }
        .sheet(item: $addKind) { k in AddAnythingSheet(initialKind: k) }
        .sheet(item: $openTool) { t in NavigationStack { t.destination } }
    }

    private func card(_ c: NowCandidate, _ target: HomeNowTarget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { open(target) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: target))
                        .font(.body.weight(.bold))
                        .foregroundStyle(tint(for: target))
                        .frame(width: 40, height: 40)
                        .glassControl(RoundedRectangle(cornerRadius: 11, style: .continuous), interactive: false)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kindLabel(target))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(c.overdue ? Theme.danger : Theme.textSecondary)
                        Text(c.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = detail(c) {
                            Label(detail, systemImage: c.overdue ? "exclamationmark.circle" : "clock")
                                .font(.subheadline)
                                .foregroundStyle(c.overdue ? Theme.danger : Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre l'élément")

            HStack(spacing: 10) {
                if let primary = primaryAction(target) {
                    Button(action: primary.run) {
                        Label(primary.title, systemImage: primary.icon)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .glassControl(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textPrimary)
                    .disabled(busy)
                }
                Button { skip(c.id) } label: {
                    Text("Autre chose")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .glassControl(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHint("Montre la proposition suivante")
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous), tint: tint(for: target))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.nowCandidates.isEmpty ? "Rien de prévu pour l'instant" : "Tu as tout passé en revue",
                  systemImage: "checkmark.seal")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(model.nowCandidates.isEmpty
                 ? "Ajoute une tâche avec une heure, une habitude ou un événement : la prochaine action s'affichera ici."
                 : "Les propositions passées reviennent demain, ou maintenant si tu veux.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !skipped.ids.isEmpty {
                Button("Tout remontrer") {
                    skippedRaw = ""
                    Haptics.tap()
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: Actions

    private struct Action { let title: String; let icon: String; let run: () -> Void }

    private func primaryAction(_ t: HomeNowTarget) -> Action? {
        switch t {
        case .task(let task):
            return Action(title: "Fait", icon: "checkmark") {
                guard !busy else { return }
                busy = true
                model.toggleTask(task, ctx: ctx)
                Haptics.success()
                onChanged()
                busy = false
            }
        case .habit(let h):
            return Action(title: "Valider", icon: "checkmark") {
                guard !busy else { return }
                busy = true
                model.toggleHabit(h, ctx: ctx)
                Haptics.success()
                onChanged()
                busy = false
            }
        case .agenda, .event:
            return nil
        }
    }

    private func skip(_ id: String) {
        var l = skipped
        _ = l.add(id)
        skippedRaw = l.raw
        Haptics.tap()
    }

    private func open(_ t: HomeNowTarget) {
        switch t {
        case .task(let task): editingTask = task
        case .habit(let h): openHabit = h
        case .agenda(let a):
            if let tool = a.tool { openTool = tool }
            else if let k = a.addKind { addKind = k }
            else if let cat = a.category {
                NotificationCenter.default.post(name: .lifeOSOpenModule, object: nil, userInfo: ["module": cat.rawValue])
            }
        case .event(let e):
            if let url = URL(string: "calshow:\(e.start.timeIntervalSinceReferenceDate)") { openURL(url) }
        }
    }

    // MARK: Textes

    private func kindLabel(_ t: HomeNowTarget) -> String {
        switch t {
        case .task(let task): return task.priority >= 2 ? "Tâche urgente" : "Tâche"
        case .habit: return "Habitude"
        case .agenda: return "Prévu aujourd'hui"
        case .event: return "Agenda"
        }
    }

    private func detail(_ c: NowCandidate) -> String? {
        guard let t = c.time else { return c.kind == .task ? "Aujourd'hui" : nil }
        let cal = Calendar.current
        if c.overdue {
            if !c.hasTime || ProductivityRules.isDateOnly(t) {
                return "En retard depuis le \(t.formatted(.dateTime.day().month()))"
            }
            return cal.isDateInToday(t) ? "En retard depuis \(t.formatted(date: .omitted, time: .shortened))"
                                         : "En retard depuis le \(t.formatted(.dateTime.day().month()))"
        }
        guard c.hasTime else { return "Aujourd'hui" }
        return "À \(t.formatted(date: .omitted, time: .shortened))"
    }

    private func icon(for t: HomeNowTarget) -> String {
        switch t {
        case .task: return "checklist"
        case .habit(let h): return h.icon
        case .agenda(let a): return a.icon
        case .event: return "calendar"
        }
    }

    private func tint(for t: HomeNowTarget) -> Color {
        switch t {
        case .task: return AppCategory.productivity.tint
        case .habit: return AppCategory.productivity.tint
        case .agenda(let a): return a.category?.tint ?? Theme.accent
        case .event: return AppCategory.productivity.tint
        }
    }
}

// MARK: - Aujourd'hui (agenda, 3 priorites, habitudes)

struct HomeTodayBlock: View {
    let model: HomeTodayModel
    @Binding var pinnedRaw: String
    @Binding var ignoredRaw: String
    let onChanged: () -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @State private var editingTask: TodoItem?
    @State private var addKind: AddAnythingSheet.Kind?
    @State private var showPicker = false
    @State private var expanded = false
    @State private var busy = false

    private var pinned: DayScopedList { DayScopedList.read(pinnedRaw, today: .now) }
    private var ignored: DayScopedList { DayScopedList.read(ignoredRaw, today: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeBlockHeader(title: "Aujourd'hui",
                            subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
            prioritiesCard
            agendaCard
            if !model.habitsToday.isEmpty { habitsCard }
        }
        .sheet(item: $editingTask) { t in TodoEditor(task: t) }
        .sheet(item: $addKind) { k in AddAnythingSheet(initialKind: k) }
        .sheet(isPresented: $showPicker) {
            HomePriorityPicker(tasks: model.openTasks, pinned: pinned.ids) { uid in pin(uid) }
        }
    }

    // MARK: 3 priorites

    private var suggestions: [PrioritySuggestion] {
        HomePriorityEngine.suggestions(
            model.openTasks.map { PriorityCandidate(uid: $0.uid, title: $0.title, priority: $0.priority, due: $0.due, done: $0.done) },
            pinned: pinned.ids, ignored: ignored.ids, now: .now)
    }

    private var prioritiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("3 priorités", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(pinned.ids.count)/\(HomePriorityEngine.maxPinned)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("\(pinned.ids.count) sur 3 épinglées")
            }
            ForEach(model.pinnedTasks, id: \.persistentModelID) { t in
                HStack(spacing: 4) {
                    HomeCheckButton(done: t.done, tint: AppCategory.productivity.tint, label: t.title) {
                        guard !busy else { return }
                        busy = true
                        model.toggleTask(t, ctx: ctx)
                        Haptics.soft()
                        onChanged()
                        busy = false
                    }
                    Button { editingTask = t } label: {
                        Text(t.title)
                            .font(.body.weight(.medium))
                            .strikethrough(t.done)
                            .foregroundStyle(t.done ? Theme.textSecondary : Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { unpin(t.uid) } label: {
                        Image(systemName: "pin.slash")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retirer des priorités : \(t.title)")
                }
            }
            let sugg = suggestions
            if !sugg.isEmpty {
                ForEach(sugg, id: \.uid) { s in suggestionRow(s) }
                Text("Suggestions : tâches en retard, urgentes ou prévues aujourd'hui. Épingle ou ignore.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.pinnedTasks.isEmpty {
                Text(model.openTasks.isEmpty
                     ? "Aucune tâche ouverte. Ajoute-en une avec la capture rapide."
                     : "Choisis jusqu'à 3 tâches qui comptent vraiment aujourd'hui.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if pinned.ids.count < HomePriorityEngine.maxPinned && !model.openTasks.isEmpty {
                Button { showPicker = true } label: {
                    Label("Choisir une priorité", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(14)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func suggestionRow(_ s: PrioritySuggestion) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Suggestion")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .glassControl(Capsule(), interactive: false)
                    Text(s.reason).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Text(s.title).font(.body).foregroundStyle(Theme.textPrimary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button { pin(s.uid) } label: {
                Image(systemName: "pin.fill")
                    .frame(width: 44, height: 44)
                    .glassControl(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityLabel("Épingler : \(s.title)")
            Button { ignore(s.uid) } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ignorer la suggestion : \(s.title)")
        }
    }

    private func pin(_ uid: String) {
        var l = pinned
        guard l.add(uid, cap: HomePriorityEngine.maxPinned) else { Haptics.warning(); return }
        pinnedRaw = l.raw
        Haptics.tap()
        onChanged()
    }

    private func unpin(_ uid: String) {
        var l = pinned
        l.remove(uid)
        pinnedRaw = l.raw
        Haptics.tap()
        onChanged()
    }

    private func ignore(_ uid: String) {
        var l = ignored
        _ = l.add(uid)
        ignoredRaw = l.raw
        Haptics.tap()
    }

    // MARK: Agenda fusionne

    private enum Row: Identifiable {
        case task(TodoItem), agenda(AgendaItem), event(HomeCalendarEvent)
        var id: String {
            switch self {
            case .task(let t): return "t.\(t.uid).\(t.persistentModelID.hashValue)"
            case .agenda(let a): return a.key
            case .event(let e): return "e.\(e.id)"
            }
        }
        /// Minutes depuis minuit, 24 h = sans heure (fin de liste), -1 = en retard.
        var sortMinutes: Int {
            let cal = Calendar.current
            switch self {
            case .task(let t):
                guard let d = t.due else { return 24 * 60 }
                if ProductivityRules.isLate(d) { return -1 }
                if ProductivityRules.isDateOnly(d) { return 24 * 60 }
                return cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
            case .agenda(let a): return a.sortKey
            case .event(let e):
                if e.allDay { return 24 * 60 - 1 }
                guard cal.isDateInToday(e.start) else { return 0 }
                return cal.component(.hour, from: e.start) * 60 + cal.component(.minute, from: e.start)
            }
        }
    }

    private var rows: [Row] {
        let tasks = model.todayTasks().filter { t in !pinned.ids.contains(t.uid) }.map(Row.task)
        let all = tasks + model.agenda.map(Row.agenda) + model.events.map(Row.event)
        return all.enumerated().sorted { a, b in
            a.element.sortMinutes != b.element.sortMinutes ? a.element.sortMinutes < b.element.sortMinutes : a.offset < b.offset
        }.map(\.element)
    }

    private var agendaCard: some View {
        let all = rows
        let shown = expanded ? all : Array(all.prefix(6))
        return VStack(alignment: .leading, spacing: 4) {
            Label("Agenda", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 4)
            if all.isEmpty {
                Text("Rien de prévu aujourd'hui. Les tâches datées, rappels et séances apparaîtront ici.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(shown) { r in row(r) }
            if all.count > 6 {
                Button(expanded ? "Voir moins" : "Voir les \(all.count) éléments") {
                    expanded.toggle()
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
            calendarAccessRow
        }
        .padding(14)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    @ViewBuilder private var calendarAccessRow: some View {
        switch model.calendarAccess {
        case .canAsk:
            Button {
                Task { await model.requestCalendar(ctx, pinnedUIDs: pinned.ids) }
            } label: {
                Label("Afficher mon agenda", systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityHint("Demande l'accès au calendrier du téléphone")
        case .denied:
            Text("Calendrier non autorisé : Réglages > LifeOS > Calendriers.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func row(_ r: Row) -> some View {
        switch r {
        case .task(let t):
            HStack(spacing: 4) {
                HomeCheckButton(done: t.done, tint: AppCategory.productivity.tint, label: t.title) {
                    guard !busy else { return }
                    busy = true
                    model.toggleTask(t, ctx: ctx)
                    Haptics.soft()
                    onChanged()
                    busy = false
                }
                Button { editingTask = t } label: {
                    rowText(title: t.title, detail: taskDetail(t), late: r.sortMinutes < 0)
                }
                .buttonStyle(.plain)
            }
        case .agenda(let a):
            if let tool = a.tool {
                NavigationLink { tool.destination } label: { agendaLabel(a) }.buttonStyle(.plain)
            } else if let k = a.addKind {
                Button { addKind = k } label: { agendaLabel(a) }.buttonStyle(.plain)
            } else if let cat = a.category {
                NavigationLink { cat.destination } label: { agendaLabel(a) }.buttonStyle(.plain)
            } else {
                agendaLabel(a)
            }
        case .event(let e):
            Button {
                if let url = URL(string: "calshow:\(e.start.timeIntervalSinceReferenceDate)") { openURL(url) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .foregroundStyle(AppCategory.productivity.tint)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    rowText(title: e.title,
                            detail: e.allDay ? "Toute la journée"
                                : "\(e.start.formatted(date: .omitted, time: .shortened)) à \(e.end.formatted(date: .omitted, time: .shortened))",
                            late: false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre le calendrier")
        }
    }

    private func agendaLabel(_ a: AgendaItem) -> some View {
        HStack(spacing: 4) {
            Image(systemName: a.icon)
                .foregroundStyle(a.category?.tint ?? Theme.accent)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            rowText(title: a.title, detail: a.detail, late: false)
        }
    }

    private func rowText(title: String, detail: String?, late: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body).foregroundStyle(Theme.textPrimary).lineLimit(2)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(late ? Theme.danger : Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func taskDetail(_ t: TodoItem) -> String? {
        guard let d = t.due else { return t.recurringDays.isEmpty ? nil : "Récurrente" }
        if ProductivityRules.isLate(d) { return "En retard" }
        if ProductivityRules.isDateOnly(d) { return "Aujourd'hui" }
        return d.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Habitudes

    private var habitsCard: some View {
        let ordered = model.habitsToday.sorted { a, b in
            let da = model.isDone(a), db = model.isDone(b)
            return da != db ? !da : false
        }
        let done = model.habitsToday.filter { model.isDone($0) }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Habitudes", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(done)/\(model.habitsToday.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("\(done) sur \(model.habitsToday.count) faites")
            }
            ForEach(ordered, id: \.persistentModelID) { h in
                let isDone = model.isDone(h)
                HStack(spacing: 4) {
                    HomeCheckButton(done: isDone, tint: Color(hex: UInt(h.colorHex)), label: h.name) {
                        guard !busy else { return }
                        busy = true
                        model.toggleHabit(h, ctx: ctx)
                        Haptics.soft()
                        onChanged()
                        busy = false
                    }
                    rowText(title: h.name,
                            detail: String(format: "%02dh%02d", h.scheduledHour, h.scheduledMinute),
                            late: false)
                        .strikethrough(isDone)
                }
            }
        }
        .padding(14)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

// MARK: - Choisir une priorite

struct HomePriorityPicker: View {
    let tasks: [TodoItem]
    let pinned: [String]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let available = tasks.filter { !pinned.contains($0.uid) && !$0.uid.isEmpty }
                    .sorted(by: ProductivityRules.todoPrecedes)
                if available.isEmpty {
                    Text("Aucune autre tâche ouverte.").foregroundStyle(Theme.textSecondary)
                }
                ForEach(available, id: \.persistentModelID) { t in
                    Button {
                        onPick(t.uid)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).foregroundStyle(Theme.textPrimary)
                            if let d = t.due {
                                Text(d.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Choisir une priorité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - A surveiller

struct HomeWatchBlock: View {
    let model: HomeTodayModel
    @Binding var indicatorsRaw: String
    @Binding var shortcutsRaw: String
    @Binding var dismissedRaw: String
    let domains: [AppCategory]

    @AppStorage(AppStorageKeys.waterGoal) private var waterGoal = 2500
    @AppStorage(AppStorageKeys.kcalGoal) private var kcalGoal = 2200
    @AppStorage(AppStorageKeys.proteinGoal) private var proteinGoal = 0
    @AppStorage(AppStorageKeys.carbGoal) private var carbGoal = 0
    @AppStorage(AppStorageKeys.fatGoal) private var fatGoal = 0
    @AppStorage(AppStorageKeys.stepGoal) private var stepGoal = 10000
    @AppStorage(AppStorageKeys.sleepGoalHours) private var sleepGoal = 8.0
    @State private var editing = false

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private var indicators: [HomeIndicator] { HomeIndicator.parse(indicatorsRaw) }
    private var dismissed: Set<String> { Set(dismissedRaw.split(separator: ",").map(String.init)) }
    private var recommendations: [HomeRecommendation] {
        HomeRecommendationEngine.recommendations(
            domains: domains, indicators: indicators,
            shortcuts: shortcutsRaw.split(separator: ",").map(String.init), dismissed: dismissed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeBlockHeader(title: "À surveiller", trailing: "Choisir") { editing = true }
            if indicators.isEmpty {
                Text("Aucun indicateur choisi. Touche « Choisir » pour suivre l'eau, le sommeil, ton budget…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            } else {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(indicators) { i in
                        NavigationLink { destination(i).floatingBarClearance() } label: { tile(i) }
                            .buttonStyle(LifeOSPressStyle(scale: 0.97))
                    }
                }
            }
            ForEach(recommendations) { r in recommendationRow(r) }
        }
        .sheet(isPresented: $editing) {
            HomeOrderEditor(title: "À surveiller",
                            options: HomeIndicator.allCases.map {
                                HomeOrderOption(id: $0.rawValue, label: $0.label, icon: $0.icon, tint: $0.domain.tint)
                            },
                            raw: $indicatorsRaw)
        }
    }

    // MARK: Tuile

    private struct Reading { let value: String; let detail: String; let progress: Double?; let empty: Bool }

    private func reading(_ i: HomeIndicator) -> Reading {
        let v = model.values
        switch i {
        case .water:
            return Reading(value: "\(v.waterML) ml", detail: "sur \(waterGoal) ml",
                           progress: waterGoal > 0 ? Double(v.waterML) / Double(waterGoal) : nil, empty: false)
        case .macros:
            guard v.foodCount > 0 else {
                return Reading(value: "0 kcal", detail: "Aucun repas noté aujourd'hui. Ajoute-le dans Calories.", progress: 0, empty: true)
            }
            var parts = ["P \(Int(v.protein))\(proteinGoal > 0 ? "/\(proteinGoal)" : "") g"]
            parts.append("G \(Int(v.carbs))\(carbGoal > 0 ? "/\(carbGoal)" : "") g")
            parts.append("L \(Int(v.fat))\(fatGoal > 0 ? "/\(fatGoal)" : "") g")
            return Reading(value: "\(v.kcal) / \(kcalGoal) kcal", detail: parts.joined(separator: " · "),
                           progress: kcalGoal > 0 ? Double(v.kcal) / Double(kcalGoal) : nil, empty: false)
        case .steps:
            guard let s = v.steps else {
                return Reading(value: "–", detail: "Pas encore de pas lus. Autorise Santé dans Profil.", progress: nil, empty: true)
            }
            return Reading(value: s.formatted(), detail: "sur \(stepGoal.formatted()) pas",
                           progress: stepGoal > 0 ? Double(s) / Double(stepGoal) : nil, empty: false)
        case .sleep:
            guard let h = v.sleepHours else {
                return Reading(value: "–", detail: "Aucune nuit notée. Ajoute-la dans Sommeil.", progress: nil, empty: true)
            }
            let m = Int((h * 60).rounded())
            return Reading(value: "\(m / 60) h \(String(format: "%02d", m % 60))",
                           detail: v.sleepIsLastNight ? "cette nuit, objectif \(sleepGoal.formatted()) h" : "nuit d'avant-hier",
                           progress: sleepGoal > 0 ? h / sleepGoal : nil, empty: false)
        case .budget:
            guard let left = v.budgetLeftCents else {
                return Reading(value: "–", detail: "Aucune enveloppe. Crée un budget dans Ynabi.", progress: nil, empty: true)
            }
            let euros = Double(left) / 100
            return Reading(value: euros.formatted(.currency(code: "EUR").precision(.fractionLength(0))),
                           detail: left < 0 ? "dépassé ce mois-ci" : "restant ce mois-ci",
                           progress: v.budgetTotalCents > 0 ? max(0, Double(left)) / Double(v.budgetTotalCents) : nil,
                           empty: false)
        case .weight:
            guard let w = v.weightLast else {
                return Reading(value: "–", detail: "Aucune pesée ces 60 jours. Ajoute-la dans Mensurations.", progress: nil, empty: true)
            }
            let delta: String
            if let d = v.weightDelta {
                delta = d == 0 ? "stable sur une semaine" : String(format: "%@%.1f %@ en une semaine", d > 0 ? "+" : "", d, v.weightUnit)
            } else {
                delta = "une seule pesée récente"
            }
            return Reading(value: String(format: "%.1f %@", w, v.weightUnit), detail: delta, progress: nil, empty: false)
        case .fasting:
            guard let e = v.fastElapsedHours else {
                return Reading(value: "–", detail: "Aucun jeûne en cours. Lance-le dans Jeûne.", progress: nil, empty: true)
            }
            return Reading(value: String(format: "%.1f h", e), detail: "sur \(v.fastTargetHours) h",
                           progress: v.fastTargetHours > 0 ? e / Double(v.fastTargetHours) : nil, empty: false)
        case .focus:
            return Reading(value: "\(v.focusMinutes) min", detail: v.focusMinutes == 0 ? "Aucune session aujourd'hui." : "de concentration aujourd'hui",
                           progress: nil, empty: v.focusMinutes == 0)
        case .habits:
            guard v.habitsPlanned > 0 else {
                return Reading(value: "–", detail: "Aucune habitude prévue aujourd'hui.", progress: nil, empty: true)
            }
            return Reading(value: "\(v.habitsDone)/\(v.habitsPlanned)", detail: "faites aujourd'hui",
                           progress: Double(v.habitsDone) / Double(v.habitsPlanned), empty: false)
        }
    }

    private func tile(_ i: HomeIndicator) -> some View {
        let r = reading(i)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: i.icon).foregroundStyle(i.domain.tint).accessibilityHidden(true)
                Text(i.label).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Text(r.value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(r.empty ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(r.detail)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let p = r.progress {
                ProgressView(value: min(1, max(0, p)))
                    .tint(i.domain.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre l'outil")
    }

    @ViewBuilder private func destination(_ i: HomeIndicator) -> some View {
        switch i {
        case .water:   HydrationView()
        case .macros:  CalAIView()
        case .steps:   StepsView()
        case .sleep:   SleepDashboardView()
        case .budget:  BudgetView()
        case .weight:  BodyMeasurementsView()
        case .fasting: FastingView()
        case .focus:   FocusTimerView()
        case .habits:  HabitTrackerView()
        }
    }

    // MARK: Recommandations

    private func recommendationRow(_ r: HomeRecommendation) -> some View {
        let title: String
        let icon: String
        switch r.kind {
        case .indicator(let i):
            title = "Suivre « \(i.label) »"; icon = i.icon
        case .shortcut(let s):
            title = "Ajouter le raccourci « \(ShortcutTool(rawValue: s)?.label ?? s) »"
            icon = ShortcutTool(rawValue: s)?.icon ?? "square.grid.2x2"
        }
        return HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(r.domain.tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(r.reason).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Button("Ajouter") { accept(r) }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .glassControl(Capsule())
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
            Button { dismiss(r) } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ignorer cette recommandation")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .nested)
    }

    private func accept(_ r: HomeRecommendation) {
        switch r.kind {
        case .indicator(let i):
            indicatorsRaw = (indicators + [i]).map(\.rawValue).joined(separator: ",")
        case .shortcut(let s):
            var list = shortcutsRaw.split(separator: ",").map(String.init)
            if !list.contains(s) { list.append(s) }
            shortcutsRaw = list.joined(separator: ",")
        }
        Haptics.success()
    }

    private func dismiss(_ r: HomeRecommendation) {
        var d = dismissed
        d.insert(r.id)
        dismissedRaw = d.sorted().joined(separator: ",")
        Haptics.tap()
    }
}

// MARK: - Capture rapide

struct HomeCaptureBlock: View {
    let onOpen: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var hint: String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let p = CaptureParser.parse(t)
        switch p.kind {
        case .expense:
            if let a = p.amount, !p.flags.contains(.unconfirmedAmount) {
                return "Dépense · \(a.formatted(.currency(code: "EUR"))) · \(p.category)"
            }
            return "Dépense · montant à préciser"
        case .task:
            if let d = p.date {
                return "Tâche · " + (p.hasTime ? d.formatted(.dateTime.weekday(.abbreviated).day().hour().minute())
                                               : d.formatted(.dateTime.weekday(.abbreviated).day().month()))
            }
            return "Tâche"
        case .note:
            return "Note"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                TextField("Une tâche, une dépense, une note…", text: $text)
                    .focused($focused)
                    .submitLabel(.next)
                    .onSubmit(open)
                    .frame(minHeight: 44)
                Button(action: open) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel(text.isEmpty ? "Ouvrir la capture" : "Vérifier avant d'enregistrer")
            }
            if let hint {
                Text(hint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 28)
                    .accessibilityLabel("Compris comme : \(hint)")
            } else {
                Text("Ex : « café 3 € hier », « appeler maman demain 18h », « note : idée cadeau »")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func open() {
        let t = text
        focused = false
        text = ""
        onOpen(t)
    }
}
