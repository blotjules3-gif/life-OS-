import SwiftUI
import SwiftData
import EventKit
import WidgetKit
import UserNotifications

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
    /// prochaine occurrence. Une ancienne tache recurrente deja cochee se rouvre.
    static func toggleDone(_ t: TodoItem, now: Date = .now) {
        let days = t.recurringDays
        guard !days.isEmpty else { t.done.toggle(); return }
        if t.done { t.done = false; return }
        // Depart : la plus tardive entre aujourd'hui et l'echeance (une tache cochee
        // en avance ne revient pas le jour meme de son echeance).
        let from = max(now, t.due ?? now)
        if let next = nextOccurrence(after: from, weekdays: days, timeOf: t.due) {
            t.due = next
            t.blockStart = nil; t.blockEnd = nil
        } else {
            t.done = true
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

    static func habitStreak(_ h: Habit, now: Date = .now) -> Int {
        habitStreak(completions: h.completions.map(\.date), activeDays: h.activeDays, now: now)
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
        let reqs: [UNNotificationRequest] = (h.isPending || h.isArchived) ? [] : h.activeDays.sorted().map { (wd: Int) -> UNNotificationRequest in
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

// MARK: - Hub Productivité


// MARK: - To-do

struct TodoView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TodoItem.due) private var todos: [TodoItem]
    @State private var showAdd = false
    @State private var filter = 0   // 0 actives, 1 toutes
    @State private var calendarAlert: String?

    private var visible: [TodoItem] {
        let base = filter == 0 ? todos.filter { !$0.done } : todos
        return base.sorted { ProductivityRules.todoPrecedes($0, $1) }
    }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                Picker("", selection: $filter) { Text("À faire").tag(0); Text("Toutes").tag(1) }
                    .pickerStyle(.segmented).padding()
                if visible.isEmpty {
                    EmptyState(icon: "checklist", title: "Rien à faire", message: "Ajoute une tâche avec le +.")
                    Spacer()
                } else {
                    List {
                        ForEach(visible) { t in
                            HStack(spacing: 12) {
                                Button { withAnimation { ProductivityRules.toggleDone(t) } } label: {
                                    Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(t.done ? Theme.success : priorityColor(t.priority))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).strikethrough(t.done).foregroundStyle(t.done ? Theme.textSecondary : Theme.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(t.project).font(.caption2).padding(.horizontal,6).padding(.vertical,2)
                                            .raisedSurface(Capsule(), .nested).foregroundStyle(Theme.textSecondary)
                                        if let d = t.due {
                                            // Une date sans heure (occurrence d'une tache recurrente)
                                            // ne s'affiche pas « 00:00 » et n'est en retard qu'au lendemain.
                                            let dateOnly = ProductivityRules.isDateOnly(d)
                                            if ProductivityRules.isLate(d) && !t.done {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "clock.badge.exclamationmark")
                                                    if dateOnly { Text(d, format: .dateTime.day().month()) }
                                                    else { Text(d, format: .dateTime.hour().minute()) }
                                                    Text("En retard")
                                                }
                                                .font(.caption2.bold())
                                                .foregroundStyle(Theme.danger)
                                            } else {
                                                Group {
                                                    if dateOnly { Text(d, format: .dateTime.weekday(.abbreviated).day().month()) }
                                                    else { Text(d, format: .dateTime.day().month().hour().minute()) }
                                                }
                                                .font(.caption2)
                                                .foregroundStyle(Theme.textSecondary)
                                            }
                                        }
                                        if !t.recurringDaysRaw.isEmpty {
                                            Image(systemName: "repeat")
                                                .font(.caption2)
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .listRowBackground(Theme.card)
                            .contextMenu {
                                Button {
                                    addToCalendar(t)
                                } label: {
                                    Label("Ajouter au calendrier", systemImage: "calendar.badge.plus")
                                }
                                Button(role: .destructive) {
                                    ctx.delete(t)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { idx in idx.map { visible[$0] }.forEach(ctx.delete) }
                    }
                    .scrollContentBackground(.hidden)
                    .alert("Calendrier", isPresented: .init(
                        get: { calendarAlert != nil },
                        set: { if !$0 { calendarAlert = nil } }
                    )) {
                        Button("OK") { calendarAlert = nil }
                    } message: {
                        Text(calendarAlert ?? "")
                    }
                }
            }
        }
        .navigationTitle("To-do").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { TodoEditor() }
    }
    private func priorityColor(_ p: Int) -> Color { p >= 2 ? Theme.danger : p == 1 ? Theme.warning : Theme.textSecondary }

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
            event.endDate   = start.addingTimeInterval(3600)
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
        if #available(iOS 17, *) {
            store.requestWriteOnlyAccessToEvents { granted, _ in
                DispatchQueue.main.async { if granted { requestAccess() } else { calendarAlert = "Accès calendrier refusé." } }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { if granted { requestAccess() } else { calendarAlert = "Accès calendrier refusé." } }
            }
        }
    }
}

struct TodoEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    var initialDue: Date? = nil

    @State private var title = ""
    @State private var project = "Perso"
    @State private var priority = 0
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var isRecurring = false
    @State private var selectedDays: Set<Int> = [2, 3, 4, 5, 6] // Lun-Ven

    init(initialDue: Date? = nil) {
        self.initialDue = initialDue
        if let initialDue {
            _hasDue = State(initialValue: true)
            _due = State(initialValue: initialDue)
        } else {
            _hasDue = State(initialValue: false)
            _due = State(initialValue: Date())
        }
    }

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

                Text("Nouvelle tâche")
                    .font(AppFont.heading(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    let recRaw = isRecurring ? selectedDays.sorted().map(String.init).joined(separator: ",") : ""
                    ctx.insert(TodoItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), due: hasDue ? due : nil, priority: priority, project: project.trimmingCharacters(in: .whitespacesAndNewlines), recurringDaysRaw: recRaw))
                    Haptics.medium()
                    dismiss()
                } label: {
                    Text("Ajouter")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(LifeOSPressStyle(scale: 0.95))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Section 1: Tâche
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DÉTAILS DE LA TÂCHE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        TextField("Que dois-tu accomplir ?", text: $title)
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .raisedSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), .nested)

                        TextField("Projet (ex: Travail, Perso, Santé)", text: $project)
                            .font(.system(size: 14, weight: .regular))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), .nested)
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 2: Priorité
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PRIORITÉ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        HStack(spacing: 10) {
                            priorityPill("Normale", tag: 0, color: .secondary)
                            priorityPill("Importante", tag: 1, color: Theme.warning)
                            priorityPill("Urgente", tag: 2, color: Theme.danger)
                        }
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 3: Échéance
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $hasDue.animation(.spring(response: 0.25))) {
                            Label("Fixer une date limite", systemImage: "calendar.badge.clock")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.primary)
                        }

                        if hasDue {
                            Divider()
                            DatePicker("Date & Heure", selection: $due)
                                .datePickerStyle(.compact)
                        }
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)

                    // Section 4: Récurrence
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $isRecurring.animation(.spring(response: 0.25))) {
                            Label("Répéter certains jours", systemImage: "repeat")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.primary)
                        }

                        if isRecurring {
                            Divider()
                            HStack(spacing: 8) {
                                ForEach(dayOptions, id: \.day) { opt in
                                    let isSel = selectedDays.contains(opt.day)
                                    Button {
                                        if isSel { selectedDays.remove(opt.day) }
                                        else { selectedDays.insert(opt.day) }
                                        Haptics.tap()
                                    } label: {
                                        Text(opt.label)
                                            .font(.system(size: 13, weight: .bold))
                                            .frame(width: 36, height: 36)
                                            .background(isSel ? Color.accentColor : Color.primary.opacity(0.06), in: Circle())
                                            .foregroundStyle(isSel ? Theme.onAccent : Theme.textPrimary)
                                    }
                                    .buttonStyle(LifeOSPressStyle(scale: 0.94))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(18)
                    .liquidGlassCard(cornerRadius: Theme.radius)
                }
                .padding(20)
            }
        }
        .background(Color.white.ignoresSafeArea())
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 460, minHeight: 520)
        #endif
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
}

// MARK: - Time-blocking auto

struct TimeBlockView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var todos: [TodoItem]
    @AppStorage(AppStorageKeys.dayStart) private var dayStart = 9
    @AppStorage(AppStorageKeys.dayEnd) private var dayEnd = 18
    @State private var blocks: [(Date, Date, TodoItem)] = []
    @State private var message: String?

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Stepper("Début \(dayStart)h", value: $dayStart, in: 5...12)
                        Divider().frame(height: 24)
                        Stepper("Fin \(dayEnd)h", value: $dayEnd, in: 13...23)
                    }.font(.footnote).card()

                    PrimaryButton(title: blocks.isEmpty ? "Générer ma journée" : "Regénérer",
                                  icon: "wand.and.stars", tint: .prodTint) { generate() }

                    if let message {
                        Text(message)
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    if blocks.isEmpty {
                        EmptyState(icon: "calendar.badge.clock",
                                   title: "Journée vide",
                                   message: "Des créneaux d'1h sont remplis avec tes tâches non terminées, les plus prioritaires d'abord, en sautant la pause déjeuner. Ajoute des tâches dans la To-do puis génère.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack { Text(b.0, style: .time).font(.caption.bold()).foregroundStyle(.prodTint) }.frame(width: 56)
                                    RoundedRectangle(cornerRadius: 3).fill(priorityColor(b.2.priority)).frame(width: 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.2.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text(b.2.project).font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                }.padding(.vertical, 10)
                                Divider().overlay(Theme.stroke)
                            }
                        }.card()

                        Button(role: .destructive) { clearBlocks() } label: {
                            Label("Effacer les créneaux", systemImage: "trash")
                                .font(.footnote)
                        }
                        .padding(.top, 2)
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Time-blocking").navigationBarTitleDisplayMode(.inline)
        // Les creneaux sont sur les taches, pas dans la vue: on les relit a
        // chaque ouverture pour retrouver la journee deja planifiee.
        .onAppear { loadSavedBlocks() }
    }
    /// Recharge les creneaux DEJA enregistres sur les taches.
    ///
    /// Avant, les creneaux ne vivaient que dans l'etat de la vue: on quittait
    /// l'ecran et tout etait perdu, alors que TodoItem a depuis toujours des
    /// champs blockStart et blockEnd que rien n'ecrivait.
    private func loadSavedBlocks() {
        let saved = todos.compactMap { t -> (Date, Date, TodoItem)? in
            guard !t.done, let s = t.blockStart, let e = t.blockEnd else { return nil }
            return (s, e, t)
        }.sorted { $0.0 < $1.0 }
        blocks = saved
    }

    private func generate() {
        let cal = Calendar.current
        // Si la journee est deja finie, on planifie DEMAIN au lieu de ne rien
        // rendre. Generer le soir renvoyait une liste vide sans rien expliquer.
        let nextHour = cal.component(.hour, from: .now) + 1
        let startsTomorrow = nextHour >= dayEnd
        let day = startsTomorrow
            ? cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            : Date()
        var hour = startsTomorrow ? dayStart : max(dayStart, nextHour)

        // Meme ordre que la To-do (priorite puis echeance la plus proche): le
        // @Query n'est pas trie, a priorite egale l'ordre etait arbitraire. Une tache
        // recurrente n'est placee que les jours ou elle revient.
        let pending = todos
            .filter { !$0.done && ($0.recurringDays.isEmpty || $0.applies(to: day)) }
            .sorted { ProductivityRules.todoPrecedes($0, $1) }
        guard !pending.isEmpty else {
            withAnimation { blocks = [] }
            message = "Aucune tâche à placer. Ajoute des tâches dans la To-do."
            return
        }

        var result: [(Date, Date, TodoItem)] = []
        var placed = 0
        for t in pending {
            while hour == 13 { hour += 1 }            // saute la pause déj
            guard hour + 1 <= dayEnd else { break }
            guard let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  let end = cal.date(byAdding: .hour, value: 1, to: start) else { break }
            t.blockStart = start
            t.blockEnd = end
            result.append((start, end, t))
            placed += 1
            hour += 1
        }
        // Les taches qui n'ont pas trouve de place ne gardent pas un vieux
        // creneau de la veille, sinon l'ecran melange deux journees.
        // Idem pour une tache recurrente qui ne revient pas ce jour-la.
        let placedIDs = Set(result.map { $0.2.persistentModelID })
        for t in todos where t.blockStart != nil && !placedIDs.contains(t.persistentModelID) {
            t.blockStart = nil
            t.blockEnd = nil
        }
        save()

        let left = pending.count - placed
        message = left > 0
            ? "\(placed) tâche\(placed > 1 ? "s" : "") placée\(placed > 1 ? "s" : "")\(startsTomorrow ? " demain" : ""), \(left) sans créneau : ta journée est pleine."
            : (startsTomorrow ? "Journée de demain planifiée." : nil)
        withAnimation { blocks = result }
    }

    /// Vide les creneaux, sans toucher aux taches elles-memes.
    private func clearBlocks() {
        for t in todos where t.blockStart != nil {
            t.blockStart = nil
            t.blockEnd = nil
        }
        save()
        message = nil
        withAnimation { blocks = [] }
    }

    private func save() {
        do { try ctx.save() }
        catch { AppLog.data.error("creneaux non sauvegardes: \(error.localizedDescription, privacy: .public)") }
    }
    private func priorityColor(_ p: Int) -> Color { p >= 2 ? Theme.danger : p == 1 ? Theme.warning : .prodTint }
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
            .navigationTitle("Habit tracker")
            .navigationBarTitleDisplayMode(.inline)
            .task {
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
                        Text("JOURS ACTIFS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

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
        let daysRaw = selectedDays.sorted().map(String.init).joined(separator: ",")
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

// MARK: - Focus / Pomodoro

struct FocusTimerView: View {
    @State private var engine = CountdownEngine(key: "focus")
    // Phase, compteur et fin de phase PERSISTES. C'etaient des @State: le moteur
    // survivait a une relance mais l'ecran affichait « Démarrer », la fin de phase
    // n'etait plus suivie (onFinish nil) et le compteur repartait a 0.
    @AppStorage("focus.isFocus") private var isFocus = true
    @AppStorage("focus.sessionsCount") private var sessionsCount = 0
    @AppStorage("focus.sessionsDay") private var sessionsDay = ""
    /// Fin absolue de la phase en cours (0 = rien ne tourne). Permet de compter une
    /// session finie pendant que l'app etait fermee.
    @AppStorage("focus.phaseEnd") private var phaseEnd: Double = 0
    @AppStorage(AppStorageKeys.focusLen) private var focusLen = 25
    @AppStorage(AppStorageKeys.breakLen) private var breakLen = 5
    @Environment(\.scenePhase) private var scenePhase

    /// Sessions du JOUR: le compteur d'hier ne s'affiche pas aujourd'hui.
    private var sessions: Int { sessionsDay == ProductivityRules.dayKey(.now) ? sessionsCount : 0 }
    /// En cours = qui tourne OU en pause avec du temps restant.
    private var running: Bool { engine.isRunning || engine.remaining > 0 }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 24) {
                if !running {
                    HStack {
                        Stepper("Focus \(focusLen)min", value: $focusLen, in: 10...60, step: 5)
                    }.font(.footnote).card()
                }
                Text(isFocus ? "CONCENTRATION" : "PAUSE").font(.caption.bold()).foregroundStyle(isFocus ? .prodTint : Theme.success)
                TimerDial(engine: engine, tint: isFocus ? Color.accentColor : Theme.success, caption: "Session \(sessions+1)")
                Label("\(sessions) sessions terminées aujourd'hui", systemImage: "checkmark.seal").font(.footnote).foregroundStyle(Theme.textSecondary)
                if !running {
                    PrimaryButton(title: "Démarrer le focus", icon: "play.fill", tint: .prodTint) { startFocus() }
                } else {
                    HStack {
                        PrimaryButton(title: engine.isRunning ? "Pause" : "Reprendre", icon: engine.isRunning ? "pause.fill" : "play.fill", tint: .prodTint) {
                            if engine.isRunning { engine.pause(); phaseEnd = 0 }
                            else { engine.resume(); phaseEnd = engine.deadline?.timeIntervalSince1970 ?? 0 }
                        }
                        PrimaryButton(title: "Stop", icon: "stop.fill", tint: Theme.bg2) { engine.stop(); phaseEnd = 0; isFocus = true }
                    }
                }
                IntegrationNotice(text: "Le « bloqueur d'apps » façon Forest nécessite la Screen Time API (DeviceActivity + FamilyControls) qui requiert une autorisation spéciale Apple. Ici le minuteur de focus est pleinement fonctionnel ; le blocage dur des apps est l'étape à activer ensuite.")
            }.padding()
        }
        .navigationTitle("Focus").navigationBarTitleDisplayMode(.inline)
        .onAppear { reattach() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reattach() } }
    }

    /// Rebranche l'ecran sur une phase lancee avant (relance, retour au premier plan).
    private func reattach() {
        engine.onFinish = finishPhase
        if engine.isRunning {
            engine.refresh()
        } else if phaseEnd > 0, engine.remaining == 0, Date(timeIntervalSince1970: phaseEnd) <= .now {
            // La phase s'est terminee app fermee: le moteur l'a effacee sans prevenir.
            // Une session de focus terminee compte; on n'enchaine pas une pause passee.
            if isFocus { countSession() }
            isFocus = true
            phaseEnd = 0
        }
    }

    private func countSession() {
        let today = ProductivityRules.dayKey(.now)
        sessionsCount = (sessionsDay == today ? sessionsCount : 0) + 1
        sessionsDay = today
    }

    private func startPhase(seconds: Int) {
        engine.onFinish = finishPhase
        engine.start(seconds: seconds)
        phaseEnd = engine.deadline?.timeIntervalSince1970 ?? 0
    }

    private func startFocus() {
        isFocus = true
        startPhase(seconds: focusLen*60)
    }
    private func finishPhase() {
        if isFocus { countSession(); isFocus = false; startPhase(seconds: breakLen*60) }
        else { isFocus = true; startPhase(seconds: focusLen*60) }
    }
}

// MARK: - Notes

struct NotesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.created, order: .reverse) private var notes: [Note]
    @State private var search = ""
    @State private var showAdd = false
    private var filtered: [Note] {
        guard !search.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) || $0.tags.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if filtered.isEmpty {
                        EmptyState(icon: "note.text", title: "Aucune note", message: "Capture une idée, un lien, une réflexion.")
                    } else {
                        ForEach(filtered) { n in
                            NavigationLink { NoteEditor(note: n) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(n.title.isEmpty ? "Sans titre" : n.title).font(.headline).foregroundStyle(Theme.textPrimary)
                                    if !n.body.isEmpty { Text(n.body).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2) }
                                    if !n.tags.isEmpty {
                                        HStack { ForEach(n.tags.split(separator: ",").map(String.init), id: \.self) { tag in
                                            Text("#\(tag.trimmingCharacters(in: .whitespaces))").font(.caption2).foregroundStyle(.prodTint)
                                        } }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).card()
                            }.buttonStyle(.plain)
                            .contextMenu { Button(role: .destructive) { ctx.delete(n) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .searchable(text: $search, prompt: "Rechercher dans tes notes")
        .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) {
            NavigationStack { NoteEditor(note: nil) }
        }
    }
}

struct NoteEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let note: Note?
    @State private var title = ""; @State private var body_ = ""; @State private var tags = ""
    var body: some View {
        Form {
            TextField("Titre", text: $title)
            TextField("Contenu…", text: $body_, axis: .vertical).lineLimit(6...20)
            TextField("Tags (séparés par virgule)", text: $tags)
        }
        .navigationTitle(note == nil ? "Nouvelle note" : "Note").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("OK") { save(); dismiss() } }
        }
        .onAppear {
            if let note { title = note.title; body_ = note.body; tags = note.tags }
            loaded = true
        }
        // Une note existante s'ouvre par un lien: le bouton retour jetait les
        // modifications sans prevenir. On enregistre aussi en quittant l'ecran.
        .onDisappear { if note != nil, loaded { save() } }
    }
    /// Evite d'ecraser la note avec des champs vides si l'ecran disparait avant
    /// d'avoir charge son contenu.
    @State private var loaded = false

    private func save() {
        if let note {
            guard note.title != title || note.body != body_ || note.tags != tags else { return }
            note.title = title; note.body = body_; note.tags = tags
        } else {
            ctx.insert(Note(title: title, body: body_, tags: tags))
        }
        do { try ctx.save() }
        catch { AppLog.data.error("note non enregistree: \(error.localizedDescription, privacy: .public)") }
    }
}
