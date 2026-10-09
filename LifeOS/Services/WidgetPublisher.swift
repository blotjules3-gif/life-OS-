import Foundation
import SwiftData
import SwiftUI
import WidgetKit
import EventKit

/// Seul endroit qui publie les donnees des widgets dans le groupe d'apps.
///
/// - Construit des instantanes `Codable` (types de `LifeOSShared`, que le widget
///   decode a l'identique) avec leur jour metier et leur date de mise a jour.
/// - N'ecrit que si la VALEUR change (signature sans horodatage, pas un nombre
///   d'elements) et ne recharge que les widgets concernes.
/// - Ecoute TOUTES les sauvegardes SwiftData (`ModelContext.didSave`) : un ecran
///   qui ajoute, modifie ou supprime une tache, un repas, une prise d'eau... met les
///   widgets a jour sans crochet a lui. Les reglages (objectifs, reveil) sont suivis
///   par `UserDefaults.didChangeNotification`.
/// - Applique au retour au premier plan les ordres venus des widgets (taches, eau,
///   habitudes) avant de publier.
/// - Lectures bornees (aujourd'hui, petites fenetres), jamais une table entiere.
@MainActor
final class WidgetPublisher {
    static let shared = WidgetPublisher()

    enum Domain: String, CaseIterable, Hashable {
        case tasks, agenda, habits, nutrition, water, fasting, gym, tabata, sleep, energy, theme
    }

    private(set) var container: ModelContainer?
    private var pending = Set<Domain>()
    private var debounce: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastForeground = Date.distantPast
    private var eventStore: EKEventStore?

    /// Coupe les rechargements WidgetKit (tests).
    var reloadsEnabled = true
    /// Derniers widgets recharges (tests et journal).
    private(set) var lastReloaded: Set<String> = []

    // MARK: - Demarrage

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { note in
            let domains = WidgetPublisher.domains(forSave: note.userInfo)
            MainActor.assumeIsolated { WidgetPublisher.shared.schedule(domains) }
        })
        observers.append(nc.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetPublisher.shared.schedule([.water, .nutrition, .fasting, .sleep, .tabata, .theme], delay: 0.6) }
        })
        observers.append(nc.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WidgetPublisher.shared.schedule(Set(Domain.allCases)) }
        })
        // Un widget a depose un ordre (tache, eau, habitude) : l'appliquer tout de suite.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { WidgetPublisher.shared.opsSignalled() } }
        }, WidgetOpsSignal.name as CFString, nil, .deliverImmediately)
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let store = EKEventStore()
            eventStore = store
            observers.append(nc.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
                MainActor.assumeIsolated { WidgetPublisher.shared.schedule([.agenda], delay: 1) }
            })
        }
    }

    private func context() -> ModelContext? {
        if let container { return container.mainContext }
        return try? LocalStore.container().mainContext
    }

    // MARK: - Planification

    /// Regroupe les demandes rapprochees en une seule publication.
    func schedule(_ domains: Set<Domain>, delay: Double = 0.3) {
        guard !domains.isEmpty else { return }
        pending.formUnion(domains)
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard !Task.isCancelled else { return }
            let todo = self.pending
            self.pending = []
            if let ctx = self.context() { self.publishNow(todo, ctx: ctx) }
        }
    }

    /// Retour au premier plan : ordres des widgets puis tout publier (au plus une fois
    /// par seconde, `didBecomeActive` et `scenePhase` arrivent ensemble).
    func foreground(_ ctx: ModelContext, now: Date = .now) {
        guard now.timeIntervalSince(lastForeground) > 1 else { return }
        lastForeground = now
        drainOps(ctx)
        publishNow(Set(Domain.allCases), ctx: ctx, now: now)
    }

    /// Signal d'un widget : appliquer ses ordres puis publier ce qu'ils touchent.
    func opsSignalled() {
        guard let ctx = context() else { return }
        if drainOps(ctx) > 0 { publishNow([.tasks, .agenda, .water, .habits, .energy], ctx: ctx) }
    }

    // MARK: - Publication

    /// Publie tout de suite (App Intents : le processus peut s'arreter juste apres).
    @discardableResult
    func publishNow(_ domains: Set<Domain>, ctx: ModelContext, now: Date = .now) -> Set<String> {
        var kinds = Set<String>()
        var tasksCache: [TodoItem]?
        func tasks() -> [TodoItem] {
            if let tasksCache { return tasksCache }
            let t = fetchTaskWindow(ctx, now: now)
            tasksCache = t
            return t
        }
        if domains.contains(.tasks), publishTasks(tasks(), ctx: ctx, now: now) { kinds.insert(WidgetKinds.tasks) }
        if domains.contains(.agenda), publishAgenda(tasks(), ctx: ctx, now: now) { kinds.insert(WidgetKinds.agenda) }
        if domains.contains(.habits), HabitSync.publish(ctx, now: now, reload: false) {
            kinds.formUnion(HabitSync.widgetKinds)
        }
        if domains.contains(.nutrition), publishNutrition(ctx, now: now) { kinds.insert(WidgetKinds.nutrition) }
        if domains.contains(.water), publishWater(ctx, now: now) { kinds.insert(WidgetKinds.hydration) }
        if domains.contains(.fasting), publishFasting(ctx, now: now) { kinds.insert(WidgetKinds.fasting) }
        if domains.contains(.gym), publishGym(ctx, now: now) { kinds.insert(WidgetKinds.gym) }
        if domains.contains(.tabata), publishTabata(ctx, now: now) { kinds.insert(WidgetKinds.tabata) }
        if domains.contains(.sleep), publishSleep(now: now) { kinds.insert(WidgetKinds.sleep) }
        if domains.contains(.energy), EnergyScore.publishToAppGroup(EnergyScore.today(ctx), now: now) { kinds.insert(WidgetKinds.energy) }
        if domains.contains(.theme), publishTheme() { kinds.formUnion(HabitSync.widgetKinds) }
        reload(kinds)
        return kinds
    }

    private func reload(_ kinds: Set<String>) {
        lastReloaded = kinds
        guard reloadsEnabled, !kinds.isEmpty else { return }
        kinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
    }

    /// Quelles parties publier apres une sauvegarde SwiftData. Format inconnu : tout.
    nonisolated static func domains(forSave userInfo: [AnyHashable: Any]?) -> Set<Domain> {
        var names = Set<String>()
        var found = false
        for (_, value) in userInfo ?? [:] {
            if let ids = value as? [PersistentIdentifier] { found = true; ids.forEach { names.insert($0.entityName) } }
            else if let ids = value as? Set<PersistentIdentifier> { found = true; ids.forEach { names.insert($0.entityName) } }
        }
        guard found else { return Set(Domain.allCases).subtracting([.theme]) }
        return domains(forEntities: names)
    }

    nonisolated static func domains(forEntities names: Set<String>) -> Set<Domain> {
        var out = Set<Domain>()
        for n in names {
            switch n {
            case "TodoItem": out.formUnion([.tasks, .agenda])
            case "FoodEntry": out.insert(.nutrition)
            case "WaterEntry": out.formUnion([.water, .energy])
            case "Habit", "HabitCompletion": out.formUnion([.habits, .energy])
            case "FastingSession": out.insert(.fasting)
            case "GymDay": out.formUnion([.gym, .agenda, .tabata])
            case "Supplement", "SocialEvent": out.insert(.agenda)
            case "TabataPreset", "TabataSessionLog": out.insert(.tabata)
            case "MoodEntry", "SleepNight": out.formUnion([.energy, .sleep])
            default: break
            }
        }
        return out
    }

    // MARK: - Taches

    /// Taches ouvertes jusqu'a J+7 (retards compris) et taches faites aujourd'hui.
    func fetchTaskWindow(_ ctx: ModelContext, now: Date) -> [TodoItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let limit = cal.date(byAdding: .day, value: 8, to: dayStart) ?? now
        let far = Date.distantFuture, past = Date.distantPast
        let fd = FetchDescriptor<TodoItem>(predicate: #Predicate { t in
            (t.due ?? far) < limit && (t.done == false || (t.completedAt ?? past) >= dayStart)
        })
        let items = (try? ctx.fetch(fd)) ?? []
        // Anciennes taches sans identifiant : il en faut un pour les cocher du widget.
        let missing = items.filter { $0.uid.isEmpty }
        if !missing.isEmpty {
            missing.forEach { TodoIDs.ensure($0) }
            try? ctx.save()
        }
        return items
    }

    static func taskItem(_ t: TodoItem, calendar: Calendar = .current) -> TasksSnapshot.Item {
        TasksSnapshot.Item(id: t.uid, title: t.title, due: t.due,
                           dateOnly: t.due.map { TaskSelection.isDateOnly($0, calendar: calendar) } ?? false,
                           priority: t.priority, done: t.done, completedAt: t.completedAt,
                           project: t.project,
                           recurring: !t.recurringDaysRaw.isEmpty || !t.recurrenceRule.isEmpty)
    }

    static func tasksSnapshot(_ items: [TasksSnapshot.Item], now: Date) -> TasksSnapshot {
        TasksSnapshot(day: WidgetDay.stamp(now), updatedAt: now,
                      items: TaskSelection.trimmed(items, now: now),
                      openCount: items.filter { !$0.done }.count)
    }

    private func publishTasks(_ todos: [TodoItem], ctx: ModelContext, now: Date) -> Bool {
        let items = todos.filter { !$0.uid.isEmpty }.map { Self.taskItem($0) }
        var snap = Self.tasksSnapshot(items, now: now)
        // Gestes du widget pas encore appliques : deja montres.
        for (_, op) in WidgetOps.pending() where op.kind == .task { snap = TaskSelection.applying(op, to: snap, now: now) }
        return WidgetSnapshotStore.write(snap, key: TasksSnapshot.key)
    }

    // MARK: - Agenda

    private func publishAgenda(_ todos: [TodoItem], ctx: ModelContext, now: Date) -> Bool {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let horizon = cal.date(byAdding: .day, value: 2, to: dayStart) ?? now
        var items: [AgendaSnapshot.Item] = []

        // Taches avec heure ou creneau planifie, aujourd'hui et demain.
        for t in todos where !t.done && !t.uid.isEmpty {
            if let s = t.blockStart, let e = t.blockEnd, s < horizon, e > dayStart {
                items.append(.init(id: "task-\(t.uid)", title: t.title, detail: "Créneau planifié", start: s, end: e,
                                   allDay: false, source: .task, link: WidgetLink.task(t.uid).absoluteString))
            } else if let d = t.due, d >= dayStart, d < horizon, !TaskSelection.isDateOnly(d, calendar: cal) {
                let minutes = t.estimateMinutes > 0 ? t.estimateMinutes : 30
                items.append(.init(id: "task-\(t.uid)", title: t.title, detail: "Tâche", start: d,
                                   end: d.addingTimeInterval(Double(minutes) * 60),
                                   allDay: false, source: .task, link: WidgetLink.task(t.uid).absoluteString))
            }
        }

        // Seance du programme (aujourd'hui et demain).
        let gymDays = (try? ctx.fetch(FetchDescriptor<GymDay>())) ?? []
        for offset in 0..<2 {
            guard let day = cal.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let wd = cal.component(.weekday, from: day)
            if let g = gymDays.first(where: { $0.weekday == wd && !$0.isRest && !$0.title.isEmpty }) {
                items.append(.init(id: "gym-\(WidgetDay.stamp(day))", title: g.title, detail: "Séance de sport",
                                   start: day, end: day, allDay: true, source: .gym, link: WidgetLink.gym.absoluteString))
            }
        }

        // Complements actifs, a leur heure (aujourd'hui).
        let sups = (try? ctx.fetch(FetchDescriptor<Supplement>(predicate: #Predicate { $0.active }))) ?? []
        for (i, s) in sups.prefix(6).enumerated() {
            guard let at = cal.date(bySettingHour: min(max(s.hour, 0), 23), minute: min(max(s.minute, 0), 59), second: 0, of: dayStart) else { continue }
            items.append(.init(id: "sup-\(i)-\(s.name)", title: s.name.isEmpty ? "Complément" : s.name, detail: "Complément",
                               start: at, end: at, allDay: false, source: .supplement, link: WidgetLink.nutrition.absoluteString))
        }

        // Evenements sociaux saisis dans LifeOS.
        let socials = (try? ctx.fetch(FetchDescriptor<SocialEvent>(predicate: #Predicate { $0.date >= dayStart && $0.date < horizon }))) ?? []
        for e in socials {
            items.append(.init(id: "social-\(e.date.timeIntervalSince1970)-\(e.title)", title: e.title.isEmpty ? "Événement" : e.title,
                               detail: e.location.isEmpty ? "Événement" : e.location, start: e.date, end: e.date.addingTimeInterval(3600),
                               allDay: false, source: .social, link: WidgetLink.agenda.absoluteString))
        }

        // Calendrier de l'appareil, seulement avec l'acces complet deja accorde.
        let access = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if access {
            let store = eventStore ?? EKEventStore()
            let pred = store.predicateForEvents(withStart: dayStart, end: horizon, calendars: nil)
            for ev in store.events(matching: pred).prefix(30) {
                let title = ev.title ?? "Événement"
                items.append(.init(id: "ev-\(ev.eventIdentifier ?? title)-\(ev.startDate.timeIntervalSince1970)", title: title,
                                   detail: ev.location ?? (ev.calendar?.title ?? "Calendrier"), start: ev.startDate, end: ev.endDate,
                                   allDay: ev.isAllDay, source: .event, link: WidgetLink.agenda.absoluteString))
            }
        }

        let sorted = items.sorted { ($0.start ?? .distantPast, $0.id) < ($1.start ?? .distantPast, $1.id) }
        let snap = AgendaSnapshot(day: WidgetDay.stamp(now), updatedAt: now, items: Array(sorted.prefix(40)), calendarAccess: access)
        return WidgetSnapshotStore.write(snap, key: AgendaSnapshot.key)
    }

    // MARK: - Nutrition

    static func goals(from d: UserDefaults) -> NutritionGoals {
        func int(_ k: String) -> Int? { (d.object(forKey: k) as? NSNumber)?.intValue }
        return NutritionGoals.resolve(kcal: int(AppStorageKeys.kcalGoal), protein: int(AppStorageKeys.proteinGoal),
                                      carbs: int(AppStorageKeys.carbGoal), fat: int(AppStorageKeys.fatGoal))
    }

    private func publishNutrition(_ ctx: ModelContext, now: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        let kcal = foods.reduce(0) { $0 + $1.calories }
        let protein = foods.reduce(0.0) { $0 + $1.protein }
        let carbs = foods.reduce(0.0) { $0 + $1.carbs }
        let fat = foods.reduce(0.0) { $0 + $1.fat }
        // Cles lues par le contexte du coach (inchangees).
        if let g = LifeOSGroup.defaults {
            setIfChanged(g, kcal, "today_kcal")
            setIfChanged(g, Int(protein.rounded()), "today_protein_g")
        }
        let snap = NutritionSnapshot(day: WidgetDay.stamp(now), updatedAt: now,
                                     kcal: kcal, protein: (protein * 10).rounded() / 10, carbs: (carbs * 10).rounded() / 10,
                                     fat: (fat * 10).rounded() / 10, entries: foods.count, goals: Self.goals(from: .standard))
        return WidgetSnapshotStore.write(snap, key: NutritionSnapshot.key)
    }

    // MARK: - Eau, jeune, seance du jour (cles plates existantes)

    private func publishWater(_ ctx: ModelContext, now: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
        let waters = (try? ctx.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        // Ajouts du widget pas encore appliques : comptes, sinon le retour visuel du
        // widget serait efface par cette publication.
        let today = HabitOps.businessDay(now, timeZone: .current)
        let ledger = WidgetOps.ledgerDefaults
        let pendingWater = WidgetOps.pending()
            .filter { $0.op.kind == .water && $0.op.day == today && !AppliedLedger.contains($0.op.opID, defaults: ledger) }
            .map { ($0.op.createdAt, $0.op.amount) }
        let values = WidgetDataSyncer.snapshot(waters: waters.map { ($0.date, $0.amountML) } + pendingWater, activeFastStart: nil,
                                               gymDays: [], settings: .standard, now: now)
        return writeFlat(values, keys: [WidgetKeys.waterToday, WidgetKeys.waterDay, WidgetKeys.waterGoal])
    }

    private func publishFasting(_ ctx: ModelContext, now: Date) -> Bool {
        var fd = FetchDescriptor<FastingSession>(predicate: #Predicate { $0.end == nil }, sortBy: [SortDescriptor(\.start, order: .reverse)])
        fd.fetchLimit = 1
        let active = (try? ctx.fetch(fd))?.first
        var values = WidgetDataSyncer.snapshot(waters: [], activeFastStart: active?.start, gymDays: [], settings: .standard, now: now)
        // Objectif du jeune EN COURS d'abord (il peut differer du reglage).
        if let active, active.targetHours > 0 { values[WidgetKeys.fastTarget] = active.targetHours }
        return writeFlat(values, keys: [WidgetKeys.fastStart, WidgetKeys.fastTarget])
    }

    private func publishGym(_ ctx: ModelContext, now: Date) -> Bool {
        let days = (try? ctx.fetch(FetchDescriptor<GymDay>())) ?? []
        let tuples = days.map { (weekday: $0.weekday, title: $0.title, focus: $0.focus, isRest: $0.isRest) }
        let values = WidgetDataSyncer.snapshot(waters: [], activeFastStart: nil, gymDays: tuples, settings: .standard, now: now)
        let flat = writeFlat(values, keys: [WidgetKeys.gymDay, WidgetKeys.gymTitle, WidgetKeys.gymFocus, WidgetKeys.gymRest])
        let week = GymWeekSnapshot(day: WidgetDay.stamp(now), updatedAt: now,
                                   days: tuples.sorted { $0.weekday < $1.weekday }
                                       .map { .init(weekday: $0.weekday, title: $0.title, focus: $0.focus, isRest: $0.isRest) })
        let wrote = WidgetSnapshotStore.write(week, key: GymWeekSnapshot.key)
        return flat || wrote
    }

    // MARK: - Tabata

    private func publishTabata(_ ctx: ModelContext, now: Date) -> Bool {
        let d = UserDefaults.standard
        let base = TabataSessionKeeper.defaultConfig(defaults: d)
        let sets = (d.object(forKey: AppStorageKeys.tabSets) as? Int) ?? 4
        var lastFD = FetchDescriptor<TabataSessionLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        lastFD.fetchLimit = 1
        let last = (try? ctx.fetch(lastFD))?.first
        let live = TabataSessionStore(defaults: d).load()
        let gymDays = (try? ctx.fetch(FetchDescriptor<GymDay>())) ?? []

        var name: String?
        var exercises = 0
        var work = base.work, rest = base.rest, rounds = base.rounds, cycles = base.cycles
        var inProgress = false
        if let live, live.phase != "idle", live.phase != "done" {
            name = live.sessionName
            exercises = live.exercises.count
            work = live.config.work; rest = live.config.rest; rounds = live.config.rounds; cycles = live.config.cycles
            inProgress = true
        } else if let last, !last.name.isEmpty {
            name = last.name
            exercises = Self.tabataExerciseCount(name: last.name, gymDays: gymDays)
            if exercises > 0 { rounds = exercises; cycles = sets }
        }
        let snap = TabataSnapshot(day: WidgetDay.stamp(now), updatedAt: now, name: name, exercises: exercises,
                                  work: work, rest: rest, rounds: rounds, cycles: cycles,
                                  inProgress: inProgress, lastDone: last?.date)
        return WidgetSnapshotStore.write(snap, key: TabataSnapshot.key)
    }

    /// Exercices d'une seance connue par son nom : preset integre ou jour du programme.
    static func tabataExerciseCount(name: String, gymDays: [GymDay]) -> Int {
        if let p = TabataPresets.all.first(where: { $0.name == name }) { return p.exercises.count }
        if let g = gymDays.first(where: { $0.title == name && !$0.isRest }) {
            return g.focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.count
        }
        return 0
    }

    // MARK: - Sommeil

    /// Cle posee par la synchro Sante quand elle ecrit `lastSleepHours`.
    static let lastSleepHoursAtKey = "lastSleepHoursAt"

    static func sleepSnapshot(from d: UserDefaults, now: Date) -> SleepSnapshot {
        let wakeH = (d.object(forKey: AppStorageKeys.wakeupHour) as? NSNumber)?.intValue
        let wakeM = (d.object(forKey: AppStorageKeys.wakeupMinute) as? NSNumber)?.intValue
        let targetInt = (d.object(forKey: AppStorageKeys.sleepTargetHours) as? NSNumber)?.doubleValue ?? 0
        let targetGoal = (d.object(forKey: AppStorageKeys.sleepGoalHours) as? NSNumber)?.doubleValue ?? 0
        let target = targetInt > 0 ? targetInt : (targetGoal > 0 ? targetGoal : 0)
        let last = d.double(forKey: AppStorageKeys.lastSleepHours)
        let stampTS = max(d.double(forKey: "lastSleepCheckDate"), d.double(forKey: lastSleepHoursAtKey))
        return SleepSnapshot(day: WidgetDay.stamp(now), updatedAt: now,
                             wakeHour: wakeH, wakeMinute: wakeH == nil ? nil : (wakeM ?? 0),
                             wakeEnabled: d.bool(forKey: AppStorageKeys.wakeupEnabled),
                             targetHours: target > 0 ? target : 8, targetIsDefault: target <= 0,
                             lastSleepHours: last > 0 ? last : nil,
                             lastSleepDay: stampTS > 0 ? WidgetDay.stamp(Date(timeIntervalSince1970: stampTS)) : nil)
    }

    @discardableResult
    func publishSleep(now: Date = .now) -> Bool {
        WidgetSnapshotStore.write(Self.sleepSnapshot(from: .standard, now: now), key: SleepSnapshot.key)
    }

    // MARK: - Theme

    private func publishTheme() -> Bool {
        guard let g = LifeOSGroup.defaults else { return false }
        return setIfChanged(g, Theme.currentTheme.accentHex, "widget_accent_hex")
    }

    // MARK: - Ordres venus des widgets

    /// Applique les ordres en file (taches, eau) puis ceux des habitudes. Un fichier
    /// n'est efface qu'apres une sauvegarde reussie ; un ordre deja applique (meme
    /// identifiant) est ignore. Rend le nombre d'ordres traites.
    @discardableResult
    func drainOps(_ ctx: ModelContext) -> Int {
        let pending = WidgetOps.pending()
        var handled = 0
        if !pending.isEmpty {
            let ledger = WidgetOps.ledgerDefaults
            var applied: [String] = []
            for (_, op) in pending where !AppliedLedger.contains(op.opID, defaults: ledger) {
                Self.apply(op, ctx: ctx)
                applied.append(op.opID)
            }
            do {
                try ctx.save()
                AppliedLedger.record(applied, defaults: ledger)
                pending.forEach { WidgetOps.acknowledge($0.url) }
                handled = pending.count
            } catch {
                AppLog.data.error("WidgetPublisher: sauvegarde refusée, ordres gardés en file: \(error.localizedDescription, privacy: .public)")
                ctx.rollback()
            }
        }
        HabitSync.ensureIDs(ctx)
        handled += HabitSync.drain(ctx)
        return handled
    }

    static func apply(_ op: WidgetOp, ctx: ModelContext) {
        switch op.kind {
        case .task:
            let uid = op.targetID
            var fd = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.uid == uid })
            fd.fetchLimit = 1
            guard let t = (try? ctx.fetch(fd))?.first else { return }   // tache supprimee depuis
            applyTask(op, to: t)
            if t.done { TaskReminders.cancel(t) } else { TaskReminders.schedule(t) }
        case .water:
            guard op.action == .add, op.amount > 0, op.amount <= 3000 else { return }
            let at = op.createdAt, amount = op.amount
            // Cle naturelle : une prise a cette seconde exacte et de ce volume existe deja.
            let fd = FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.date == at && $0.amountML == amount })
            if let n = try? ctx.fetchCount(fd), n > 0 { return }
            let e = WaterEntry(date: at, amountML: amount)
            e.volumeML = amount
            ctx.insert(e)
        }
    }

    /// Ordre explicite : cocher une tache deja cochee (ou une recurrente deja faite ce
    /// jour-la) ne fait rien. Decocher une recurrente avancee n'est pas possible ici.
    static func applyTask(_ op: WidgetOp, to t: TodoItem) {
        let tz = TimeZone(identifier: op.timeZone) ?? .current
        let recurring = TaskRecurrence.of(t) != .none
        switch op.action {
        case .complete:
            if t.done { return }
            if recurring, let c = t.completedAt, HabitOps.businessDay(c, timeZone: tz) == op.day { return }
            ProductivityRules.toggleDone(t, now: op.createdAt)
        case .uncomplete:
            guard t.done else { return }
            ProductivityRules.toggleDone(t, now: op.createdAt)
        case .add:
            return
        }
    }

    // MARK: - Outils

    @discardableResult
    private func writeFlat(_ values: [String: Any], keys: [String]) -> Bool {
        guard let g = LifeOSGroup.defaults else { return false }
        var changed = false
        for k in keys { if let v = values[k], !Self.same(g.object(forKey: k), v) { g.set(v, forKey: k); changed = true } }
        return changed
    }

    @discardableResult
    private func setIfChanged(_ g: UserDefaults, _ v: Any, _ k: String) -> Bool {
        guard !Self.same(g.object(forKey: k), v) else { return false }
        g.set(v, forKey: k)
        return true
    }

    nonisolated static func same(_ a: Any?, _ b: Any) -> Bool {
        switch (a, b) {
        case let (x as NSNumber, y as Int): return x.intValue == y && !(CFGetTypeID(x) == CFBooleanGetTypeID())
        case let (x as NSNumber, y as Double): return x.doubleValue == y
        case let (x as NSNumber, y as Bool): return x.boolValue == y
        case let (x as String, y as String): return x == y
        default: return false
        }
    }
}
