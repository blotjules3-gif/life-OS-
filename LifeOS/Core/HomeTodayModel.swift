import SwiftUI
import SwiftData
import EventKit

/// Un evenement du calendrier du telephone, lu seulement si l'acces complet est
/// deja accorde (l'accueil ne demande jamais l'acces tout seul).
struct HomeCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
}

/// Les chiffres du bloc « A surveiller ». nil = pas de donnee (etat vide honnete).
struct HomeIndicatorValues: Equatable {
    var waterML = 0
    var kcal = 0
    var protein = 0.0, carbs = 0.0, fat = 0.0
    var foodCount = 0
    var steps: Int?
    var sleepHours: Double?
    var sleepIsLastNight = false
    var budgetLeftCents: Int?
    var budgetTotalCents = 0
    var weightLast: Double?
    var weightUnit = "kg"
    var weightDelta: Double?
    var fastElapsedHours: Double?
    var fastTargetHours = 16
    var focusMinutes = 0
    var habitsDone = 0
    var habitsPlanned = 0
}

/// Ce qu'ouvre une proposition de « Maintenant ».
enum HomeNowTarget {
    case task(TodoItem)
    case habit(Habit)
    case agenda(AgendaItem)
    case event(HomeCalendarEvent)
}

/// Donnees du jour de l'accueil, lues UNE fois puis relues a chaque enregistrement
/// (`ModelContext.didSave`), au retour au premier plan et au changement de jour.
/// Toutes les lectures sont filtrees (aujourd'hui, 7 ou 60 derniers jours, ouvertes) :
/// l'accueil ne relit plus des tables entieres a chaque rendu.
@MainActor
@Observable
final class HomeTodayModel {
    private(set) var openTasks: [TodoItem] = []
    private(set) var pinnedTasks: [TodoItem] = []
    private(set) var habitsToday: [Habit] = []
    private(set) var agenda: [AgendaItem] = []
    private(set) var events: [HomeCalendarEvent] = []
    private(set) var calendarAccess: CalendarBusy.Access = .notInThisVersion
    private(set) var values = HomeIndicatorValues()
    private(set) var nowCandidates: [NowCandidate] = []
    private(set) var nowTargets: [String: HomeNowTarget] = [:]
    private(set) var loadedDay = ""
    private(set) var refreshedAt: Date = .distantPast

    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var eventStore: EKEventStore?

    // MARK: Lecture

    func refresh(_ ctx: ModelContext, pinnedUIDs: [String], now: Date = .now) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        loadedDay = DayScopedList.dayKey(now)

        func fetch<T: PersistentModel>(_ d: FetchDescriptor<T>) -> [T] { (try? ctx.fetch(d)) ?? [] }

        // Taches ouvertes (une liste de taches non faites reste de taille humaine).
        var open = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.done == false },
                                            sortBy: [SortDescriptor(\.due)])
        open.fetchLimit = 500
        openTasks = fetch(open)
        if pinnedUIDs.isEmpty {
            pinnedTasks = []
        } else {
            let uids = pinnedUIDs
            let found = fetch(FetchDescriptor<TodoItem>(predicate: #Predicate { uids.contains($0.uid) }))
            pinnedTasks = pinnedUIDs.compactMap { uid in found.first { $0.uid == uid } }
        }

        // Habitudes prevues aujourd'hui.
        let habits = fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.isArchived == false && $0.isPending == false },
                                                  sortBy: [SortDescriptor(\.scheduledHour), SortDescriptor(\.scheduledMinute)]))
        habitsToday = habits.filter { $0.isActive(on: now) }

        agenda = TodayAgendaBuilder.items(ctx: ctx, now: now)

        calendarAccess = CalendarBusy.access()
        events = calendarAccess == .authorized ? readEvents(from: today, to: tomorrow, now: now) : []

        values = readIndicators(ctx, habits: habits, now: now, today: today, tomorrow: tomorrow)
        buildNow(now: now)
        refreshedAt = now
    }

    /// Plusieurs enregistrements rapproches (une saisie, une synchro) = une relecture.
    func scheduleRefresh(_ ctx: ModelContext, pinnedUIDs: @escaping () -> [String]) {
        pendingReload?.cancel()
        pendingReload = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.refresh(ctx, pinnedUIDs: pinnedUIDs())
        }
    }

    /// Pas du jour : Sante d'abord (asynchrone), sinon ce qui a ete saisi a la main.
    func refreshSteps(_ ctx: ModelContext) async {
        let health = await HealthService.shared.cachedStepsToday()
        if health > 0 { values.steps = health; return }
        let today = Calendar.current.startOfDay(for: .now)
        let manual = ((try? ctx.fetch(FetchDescriptor<StepEntry>(predicate: #Predicate { $0.day >= today }))) ?? [])
            .reduce(0) { $0 + $1.steps }
        values.steps = manual > 0 ? manual : nil
    }

    // MARK: Taches du jour

    /// Taches a faire aujourd'hui : en retard, echeance aujourd'hui, ou recurrentes
    /// ce jour de la semaine.
    func todayTasks(now: Date = .now) -> [TodoItem] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        return openTasks.filter { t in
            if let d = t.due {
                return cal.isDate(d, inSameDayAs: now) || ProductivityRules.isLate(d, now: now)
            }
            return t.recurringDays.contains(weekday)
        }
    }

    func isDone(_ h: Habit, now: Date = .now) -> Bool {
        h.completions.contains { Calendar.current.isDate($0.date, inSameDayAs: now) }
    }

    // MARK: Maintenant

    private func buildNow(now: Date) {
        let cal = Calendar.current
        var items: [NowCandidate] = []
        var targets: [String: HomeNowTarget] = [:]

        for t in todayTasks(now: now) {
            TodoIDs.ensure(t)
            let id = "task.\(t.uid)"
            let timed = t.due.map { !ProductivityRules.isDateOnly($0) } ?? false
            let late = t.due.map { ProductivityRules.isLate($0, now: now) } ?? false
            items.append(NowCandidate(id: id, kind: .task, title: t.title, time: t.due,
                                      overdue: late, priority: t.priority, hasTime: timed))
            targets[id] = .task(t)
        }
        for h in habitsToday where !isDone(h, now: now) {
            let id = "habit.\(h.uid.isEmpty ? h.name : h.uid)"
            let at = cal.date(bySettingHour: h.scheduledHour, minute: h.scheduledMinute, second: 0, of: now)
            items.append(NowCandidate(id: id, kind: .habit, title: h.name, time: at))
            targets[id] = .habit(h)
        }
        for a in agenda {
            let at = a.hasTime ? cal.date(bySettingHour: a.sortKey / 60, minute: a.sortKey % 60, second: 0, of: now) : nil
            items.append(NowCandidate(id: a.key, kind: .agenda, title: a.title, time: at, hasTime: a.hasTime))
            targets[a.key] = .agenda(a)
        }
        for e in events where e.end > now {
            let id = "event.\(e.id)"
            items.append(NowCandidate(id: id, kind: .event, title: e.title, time: e.allDay ? nil : e.start,
                                      hasTime: !e.allDay))
            targets[id] = .event(e)
        }
        nowCandidates = items
        nowTargets = targets
    }

    // MARK: Calendrier

    /// A appeler apres que l'utilisateur a touche « Afficher mon agenda ».
    func requestCalendar(_ ctx: ModelContext, pinnedUIDs: [String]) async {
        _ = await CalendarBusy.requestRead()
        eventStore = nil
        refresh(ctx, pinnedUIDs: pinnedUIDs)
    }

    private func readEvents(from: Date, to: Date, now: Date) -> [HomeCalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = eventStore ?? EKEventStore()
        eventStore = store
        let pred = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: pred)
            .map { HomeCalendarEvent(id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                                     title: $0.title ?? "Événement", start: $0.startDate, end: $0.endDate,
                                     allDay: $0.isAllDay) }
            .sorted { $0.start < $1.start }
    }

    // MARK: Indicateurs

    private func readIndicators(_ ctx: ModelContext, habits: [Habit], now: Date, today: Date, tomorrow: Date) -> HomeIndicatorValues {
        let cal = Calendar.current
        func fetch<T: PersistentModel>(_ d: FetchDescriptor<T>) -> [T] { (try? ctx.fetch(d)) ?? [] }
        var v = HomeIndicatorValues()
        v.steps = values.steps   // relu a part (asynchrone)

        v.waterML = fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.date >= today && $0.date < tomorrow }))
            .reduce(0) { $0 + $1.amountML }
        let foods = fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= today && $0.date < tomorrow }))
        v.foodCount = foods.count
        v.kcal = foods.reduce(0) { $0 + $1.calories }
        v.protein = foods.reduce(0) { $0 + $1.protein }
        v.carbs = foods.reduce(0) { $0 + $1.carbs }
        v.fat = foods.reduce(0) { $0 + $1.fat }

        // Sommeil : la nuit rattachee a aujourd'hui (jour de reveil), sinon hier.
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        var nights = FetchDescriptor<SleepNight>(predicate: #Predicate { $0.date >= yesterday },
                                                 sortBy: [SortDescriptor(\.date, order: .reverse)])
        nights.fetchLimit = 4
        if let n = fetch(nights).first {
            v.sleepHours = n.hours
            v.sleepIsLastNight = cal.isDate(n.date, inSameDayAs: now)
        }

        // Budget du mois (enveloppes Ynabi, meme calcul que l'ecran).
        let envelopes = fetch(FetchDescriptor<Envelope>()).filter { $0.monthlyBudget > 0 && $0.uid != nil }
        if !envelopes.isEmpty {
            let month = EnvelopeMath.monthKey(now)
            let firstMonth = envelopes.filter(\.carryOver)
                .map { EnvelopeMath.monthKey($0.createdAt == .distantPast ? now : $0.createdAt) }
                .min() ?? month
            let since = EnvelopeMath.startOfMonth(min(firstMonth, month))
            let entries = fetch(FetchDescriptor<EnvelopeEntry>(predicate: #Predicate { $0.date >= since }))
            let txns = fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.date >= since && $0.amountCents < 0 }))
            v.budgetTotalCents = envelopes.reduce(0) { $0 + EnvelopeBudget.cents($1.monthlyBudget) }
            v.budgetLeftCents = envelopes.reduce(0) {
                $0 + EnvelopeBudget.availableCents($1, month: month, entries: entries, txns: txns)
            }
        }

        // Poids : derniere pesee des 60 derniers jours, ecart avec une pesee d'au moins 6 jours avant.
        let weightKind = MeasurementKind.weight.rawValue
        let since60 = cal.date(byAdding: .day, value: -60, to: today) ?? today
        var weights = FetchDescriptor<BodyMeasurement>(predicate: #Predicate { $0.kind == weightKind && $0.date >= since60 },
                                                       sortBy: [SortDescriptor(\.date, order: .reverse)])
        weights.fetchLimit = 40
        let w = fetch(weights)
        if let last = w.first {
            v.weightLast = last.value
            v.weightUnit = last.unit
            let limit = cal.date(byAdding: .day, value: -6, to: last.date) ?? last.date
            if let older = w.first(where: { $0.date <= limit && $0.unit == last.unit }) {
                v.weightDelta = last.value - older.value
            }
        }

        // Jeune en cours.
        var fast = FetchDescriptor<FastingSession>(predicate: #Predicate { $0.end == nil },
                                                   sortBy: [SortDescriptor(\.start, order: .reverse)])
        fast.fetchLimit = 1
        if let f = fetch(fast).first {
            v.fastElapsedHours = f.elapsed / 3600
            v.fastTargetHours = f.targetHours
        }

        // Concentration du jour.
        v.focusMinutes = fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.start >= today }))
            .reduce(0) { $0 + $1.focusedSeconds } / 60

        // Habitudes : meme regle que le score (prevues ce jour).
        let planned = DailyScoreEngine.plannedHabits(habits, on: now)
        v.habitsPlanned = planned.count
        v.habitsDone = planned.filter { isDone($0, now: now) }.count
        return v
    }

    // MARK: Actions (une seule voie, comme Todoo et le suivi d'habitudes)

    func toggleTask(_ t: TodoItem, ctx: ModelContext) {
        ProductivityRules.toggleDone(t)
        do { try ctx.save() } catch { AppLog.data.error("tache accueil: \(error.localizedDescription, privacy: .public)") }
        if t.done { TaskReminders.cancel(t) } else { TaskReminders.schedule(t) }
    }

    func toggleHabit(_ h: Habit, ctx: ModelContext, now: Date = .now) {
        if let c = h.completions.first(where: { Calendar.current.isDate($0.date, inSameDayAs: now) }) {
            ctx.delete(c)
        } else {
            h.completions.append(HabitCompletion(date: now))
        }
        HabitStore.commit(ctx)
    }
}
