import XCTest
import SwiftData
@testable import LifeOS

/// Lot 8, widgets : instantanes partages app + widget, ecriture a la valeur, jour
/// metier, file d'ordres idempotente, regles de selection et de calcul.
@MainActor
final class Lot8WidgetTests: XCTestCase {
    private let suiteName = "Lot8WidgetTests"
    private var defaults: UserDefaults!
    private var opsDir: URL!
    private var habitDir: URL!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        opsDir = FileManager.default.temporaryDirectory.appendingPathComponent("widgetops-\(UUID())")
        habitDir = FileManager.default.temporaryDirectory.appendingPathComponent("habitops-\(UUID())")
        WidgetOps.directoryOverride = opsDir
        WidgetOps.ledgerDefaultsOverride = defaults
        HabitOps.directoryOverride = habitDir
        WidgetPublisher.shared.reloadsEnabled = false
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: opsDir)
        try? FileManager.default.removeItem(at: habitDir)
        WidgetOps.directoryOverride = nil
        WidgetOps.ledgerDefaultsOverride = nil
        HabitOps.directoryOverride = nil
        WidgetPublisher.shared.reloadsEnabled = true
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var cal: Calendar { Calendar.current }
    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0, from now: Date) -> Date {
        let d = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }
    private func item(_ id: String, due: Date?, dateOnly: Bool = false, priority: Int = 0, done: Bool = false,
                      completedAt: Date? = nil, recurring: Bool = false) -> TasksSnapshot.Item {
        .init(id: id, title: "T \(id)", due: due, dateOnly: dateOnly, priority: priority, done: done,
              completedAt: completedAt, project: "", recurring: recurring)
    }

    // MARK: Encodage

    func testSnapshotsRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tasks = TasksSnapshot(day: "2027-01-15", updatedAt: now, items: [item("a", due: now, priority: 2)], openCount: 1)
        let agenda = AgendaSnapshot(day: "2027-01-15", updatedAt: now, items: [
            .init(id: "e", title: "Réunion", detail: "Bureau", start: now, end: now.addingTimeInterval(3600), allDay: false, source: .event, link: "lifeos://agenda")
        ], calendarAccess: true)
        let nutrition = NutritionSnapshot(day: "2027-01-15", updatedAt: now, kcal: 900, protein: 50.5, carbs: 90, fat: 30, entries: 2,
                                          goals: .resolve(kcal: 2000, protein: nil, carbs: nil, fat: nil))
        let sleep = SleepSnapshot(day: "2027-01-15", updatedAt: now, wakeHour: 6, wakeMinute: 30, wakeEnabled: true,
                                  targetHours: 7.5, targetIsDefault: false, lastSleepHours: 6.8, lastSleepDay: "2027-01-15")
        let tabata = TabataSnapshot(day: "2027-01-15", updatedAt: now, name: "Cardio HIIT", exercises: 6, work: 30, rest: 15,
                                    rounds: 6, cycles: 4, inProgress: false, lastDone: now)
        let gym = GymWeekSnapshot(day: "2027-01-15", updatedAt: now, days: [.init(weekday: 2, title: "Dos", focus: "Rowing", isRest: false)])
        let enc = WidgetSnapshotStore.encoder(), dec = WidgetSnapshotStore.decoder()
        XCTAssertEqual(try dec.decode(TasksSnapshot.self, from: enc.encode(tasks)), tasks)
        XCTAssertEqual(try dec.decode(AgendaSnapshot.self, from: enc.encode(agenda)), agenda)
        XCTAssertEqual(try dec.decode(NutritionSnapshot.self, from: enc.encode(nutrition)), nutrition)
        XCTAssertEqual(try dec.decode(SleepSnapshot.self, from: enc.encode(sleep)), sleep)
        XCTAssertEqual(try dec.decode(TabataSnapshot.self, from: enc.encode(tabata)), tabata)
        XCTAssertEqual(try dec.decode(GymWeekSnapshot.self, from: enc.encode(gym)), gym)
    }

    // MARK: Ecriture a la valeur

    func testWriteOnlyWhenValueChangesNotCount() {
        let t0 = Date()
        var snap = TasksSnapshot(day: WidgetDay.stamp(t0), updatedAt: t0, items: [item("a", due: t0)], openCount: 1)
        XCTAssertTrue(WidgetSnapshotStore.write(snap, key: "k", to: defaults), "premiere ecriture")
        snap.updatedAt = t0.addingTimeInterval(60)
        XCTAssertFalse(WidgetSnapshotStore.write(snap, key: "k", to: defaults), "meme valeur, seul l'horodatage change")
        snap.items[0].title = "Titre corrigé"
        XCTAssertTrue(WidgetSnapshotStore.write(snap, key: "k", to: defaults), "meme nombre d'elements, valeur modifiee")
        XCTAssertEqual(WidgetSnapshotStore.read(TasksSnapshot.self, key: "k", from: defaults)?.items.first?.title, "Titre corrigé")
        // Le retour visuel du widget efface la signature : l'app reecrit sa verite.
        var optimistic = snap; optimistic.items[0].done = true
        WidgetSnapshotStore.overwrite(optimistic, key: "k", to: defaults)
        XCTAssertTrue(WidgetSnapshotStore.write(snap, key: "k", to: defaults))
    }

    func testHabitSnapshotSameValueIgnoresTimestamp() {
        let e = HabitSnapshot.Entry(id: "h", name: "Lire", icon: "book", colorHex: 1, done: false)
        let a = HabitSnapshot(day: "2027-01-15", timeZone: "Europe/Paris", generatedAt: Date(), habits: [e])
        var b = a; b.generatedAt = a.generatedAt.addingTimeInterval(500)
        XCTAssertTrue(HabitSync.sameValue(a, b))
        b.habits[0].name = "Lire 20 min"
        XCTAssertFalse(HabitSync.sameValue(a, b), "un renommage doit republier")
    }

    func testSaveNotificationMapsToDomains() {
        XCTAssertEqual(WidgetPublisher.domains(forEntities: ["TodoItem"]), [.tasks, .agenda])
        XCTAssertTrue(WidgetPublisher.domains(forEntities: ["FoodEntry"]).contains(.nutrition))
        XCTAssertTrue(WidgetPublisher.domains(forEntities: ["WaterEntry"]).contains(.water))
        XCTAssertTrue(WidgetPublisher.domains(forEntities: ["HabitCompletion"]).contains(.habits))
        XCTAssertTrue(WidgetPublisher.domains(forEntities: ["Unrelated"]).isEmpty)
        XCTAssertFalse(WidgetPublisher.domains(forSave: [:]).isEmpty, "format inconnu : tout republier")
    }

    // MARK: Jour metier

    func testDayStampStaleness() {
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let n = NutritionSnapshot(day: WidgetDay.stamp(yesterday), updatedAt: yesterday, kcal: 1800, protein: 100, carbs: 200,
                                  fat: 60, entries: 4, goals: .resolve(kcal: nil, protein: nil, carbs: nil, fat: nil))
        let shown = n.current(now: now)
        XCTAssertEqual(shown.kcal, 0, "jamais les calories d'hier comme celles d'aujourd'hui")
        XCTAssertEqual(shown.entries, 0)
        XCTAssertEqual(n.current(now: yesterday).kcal, 1800)

        let s = SleepSnapshot(day: WidgetDay.stamp(now), updatedAt: now, wakeHour: 7, wakeMinute: 0, wakeEnabled: true,
                              targetHours: 8, targetIsDefault: false, lastSleepHours: 7.2, lastSleepDay: WidgetDay.stamp(yesterday))
        XCTAssertNil(s.lastNight(now: now), "nuit notee hier")
        XCTAssertEqual(s.lastNight(now: yesterday), 7.2)
        XCTAssertTrue(WidgetDay.isToday(WidgetDay.stamp(now), now: now))
        XCTAssertFalse(WidgetDay.isToday(WidgetDay.stamp(yesterday), now: now))
    }

    func testSleepSnapshotFromSettingsIsHonest() throws {
        let now = Date()
        var s = WidgetPublisher.sleepSnapshot(from: defaults, now: now)
        XCTAssertNil(s.wakeHour, "reveil jamais regle : pas de 07:00 invente")
        XCTAssertNil(s.lastSleepHours)
        XCTAssertTrue(s.targetIsDefault)
        defaults.set(6, forKey: AppStorageKeys.wakeupHour)
        defaults.set(45, forKey: AppStorageKeys.wakeupMinute)
        defaults.set(7, forKey: AppStorageKeys.sleepTargetHours)
        defaults.set(6.5, forKey: AppStorageKeys.lastSleepHours)
        defaults.set(now.timeIntervalSince1970, forKey: "lastSleepCheckDate")
        s = WidgetPublisher.sleepSnapshot(from: defaults, now: now)
        XCTAssertEqual(s.wakeHour, 6); XCTAssertEqual(s.wakeMinute, 45)
        XCTAssertEqual(s.targetHours, 7); XCTAssertFalse(s.targetIsDefault)
        XCTAssertEqual(s.lastNight(now: now), 6.5)
    }

    func testBedtimeMath() {
        XCTAssertTrue(SleepSnapshot.bedtime(wakeHour: 7, wakeMinute: 0, targetHours: 8) == (23, 0))
        XCTAssertTrue(SleepSnapshot.bedtime(wakeHour: 6, wakeMinute: 30, targetHours: 7.5) == (23, 0))
        XCTAssertTrue(SleepSnapshot.bedtime(wakeHour: 9, wakeMinute: 15, targetHours: 8) == (1, 15))
    }

    // MARK: File d'ordres

    func testOpQueueSameOpTwiceIsAppliedOnce() throws {
        let renderedAt = Date()
        let id = WidgetOp.waterOpID(day: WidgetDay.stamp(), baseML: 750, amount: 250, renderedAt: renderedAt)
        XCTAssertEqual(id, WidgetOp.waterOpID(day: WidgetDay.stamp(), baseML: 750, amount: 250, renderedAt: renderedAt),
                       "deux appuis sur le meme rendu = meme identifiant")
        let op = WidgetOp(opID: id, kind: .water, action: .add, amount: 250, source: "widget")
        XCTAssertTrue(try WidgetOps.enqueue(op))
        XCTAssertFalse(try WidgetOps.enqueue(op), "double appui : un seul fichier")
        XCTAssertEqual(WidgetOps.pending().count, 1)

        let container = try ModelContainer(for: Schema([WaterEntry.self, TodoItem.self, Habit.self, HabitCompletion.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let ctx = container.mainContext
        XCTAssertEqual(WidgetPublisher.shared.drainOps(ctx), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WaterEntry>()), 1)
        XCTAssertTrue(WidgetOps.pending().isEmpty, "acquitte apres sauvegarde")

        // Rejeu apres un arret (fichier revenu) : le registre et la cle naturelle l'arretent.
        XCTAssertFalse(try WidgetOps.enqueue(op), "deja applique : refuse a l'entree")
        try OpFileQueue.write(OpFileQueue.encoder().encode(op), name: WidgetOps.fileName(op), in: opsDir)
        WidgetPublisher.shared.drainOps(ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WaterEntry>()), 1, "jamais applique deux fois")
        XCTAssertTrue(WidgetOps.pending().isEmpty)

        // Ledger vide (perdu) : la cle naturelle (seconde + volume) suffit encore.
        defaults.removeObject(forKey: AppliedLedger.key)
        try OpFileQueue.write(OpFileQueue.encoder().encode(op), name: WidgetOps.fileName(op), in: opsDir)
        WidgetPublisher.shared.drainOps(ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WaterEntry>()), 1)
    }

    func testTaskOpsAreExplicit() {
        let now = Date()
        let t = TodoItem(title: "Courrier", due: now)
        t.uid = "u1"
        let complete = WidgetOp(kind: .task, targetID: "u1", action: .complete, at: now, source: "widget")
        WidgetPublisher.applyTask(complete, to: t)
        XCTAssertTrue(t.done)
        WidgetPublisher.applyTask(complete, to: t)
        XCTAssertTrue(t.done, "cocher deux fois ne decoche pas")

        let r = TodoItem(title: "Arroser", due: now)
        r.uid = "u2"
        r.recurringDaysRaw = "1,2,3,4,5,6,7"
        let c2 = WidgetOp(kind: .task, targetID: "u2", action: .complete, at: now, source: "widget")
        WidgetPublisher.applyTask(c2, to: r)
        let firstDue = r.due
        XCTAssertNotEqual(firstDue, now, "recurrente : prochaine occurrence")
        WidgetPublisher.applyTask(c2, to: r)
        XCTAssertEqual(r.due, firstDue, "rejouee le meme jour : n'avance pas deux fois")
    }

    // MARK: Regles

    func testFastingEatingWindow() {
        XCTAssertEqual(FastingMath.eatingWindow(targetHours: 16), 8)
        XCTAssertEqual(FastingMath.eatingWindow(targetHours: 18), 6)
        XCTAssertEqual(FastingMath.eatingWindow(targetHours: 20), 4)
        XCTAssertEqual(FastingMath.eatingWindow(targetHours: 24), 0)
        XCTAssertEqual(FastingMath.eatingWindow(targetHours: 36), 0)
        XCTAssertEqual(FastingMath.ratioLabel(targetHours: 18), "18:6")
        XCTAssertEqual(FastingMath.ratioLabel(targetHours: 36), "36 h")
        XCTAssertEqual(FastingMath.phase(elapsedHours: 17, targetHours: 16), "Objectif atteint")
        for p in ["Début du jeûne", "En cours", "Dernière ligne droite", "Objectif atteint"] {
            XCTAssertFalse(p.lowercased().contains("cétose") || p.lowercased().contains("graisse"), "aucune promesse de santé")
        }
    }

    func testTaskSelectionAndOrdering() {
        let now = at(0, 15, from: Date())
        let items = [
            item("later-today-low", due: at(0, 18, from: now), priority: 0),
            item("today-urgent", due: at(0, 17, from: now), priority: 2),
            item("overdue-yesterday", due: at(-1, 0, from: now), dateOnly: true, priority: 0),
            item("today-dateonly", due: at(0, 0, from: now), dateOnly: true, priority: 1),
            item("overdue-this-morning", due: at(0, 9, from: now), priority: 0),
            item("tomorrow", due: at(1, 10, from: now)),
            item("in-ten-days", due: at(10, 10, from: now)),
            item("done-today", due: at(0, 8, from: now), done: true, completedAt: at(0, 9, from: now)),
            item("done-yesterday", due: at(-1, 8, from: now), done: true, completedAt: at(-1, 9, from: now)),
        ]
        let today = TaskSelection.today(items, now: now).map(\.id)
        XCTAssertEqual(today, ["overdue-yesterday", "overdue-this-morning", "today-urgent", "today-dateonly", "later-today-low", "done-today"],
                       "retards d'abord (le plus ancien en tete), puis priorite, puis faites")
        XCTAssertFalse(TaskSelection.isOverdue(items[3], now: now), "date sans heure : pas en retard le jour meme")
        XCTAssertEqual(TaskSelection.upcoming(items, now: now).map(\.id), ["tomorrow"])
        XCTAssertEqual(TaskSelection.next(items, now: now)?.id, "overdue-yesterday")
        XCTAssertEqual(TaskSelection.openTodayCount(items, now: now), 5)
        // A minuit, rejoue sans l'app : "tomorrow" devient du jour.
        let tomorrowNoon = at(1, 12, from: now)
        XCTAssertTrue(TaskSelection.today(items, now: tomorrowNoon).map(\.id).contains("tomorrow"))
        XCTAssertFalse(TaskSelection.today(items, now: tomorrowNoon).map(\.id).contains("done-today"))
        // Coupe a publier : ouvertes d'abord.
        XCTAssertEqual(TaskSelection.trimmed(items, now: now, limit: 2).map(\.id), ["overdue-yesterday", "overdue-this-morning"])
    }

    func testOptimisticTaskToggle() {
        let now = Date()
        let snap = TasksSnapshot(day: WidgetDay.stamp(now), updatedAt: now,
                                 items: [item("a", due: now), item("r", due: now, recurring: true)], openCount: 2)
        let s1 = TaskSelection.applying(WidgetOp(kind: .task, targetID: "a", action: .complete, source: "w"), to: snap, now: now)
        XCTAssertEqual(s1.items.first { $0.id == "a" }?.done, true)
        let s2 = TaskSelection.applying(WidgetOp(kind: .task, targetID: "r", action: .complete, source: "w"), to: s1, now: now)
        XCTAssertNil(s2.items.first { $0.id == "r" }, "recurrente cochee : quitte la liste du jour")
    }

    func testMacroGoalsFallback() {
        let none = NutritionGoals.resolve(kcal: nil, protein: nil, carbs: nil, fat: nil)
        XCTAssertEqual(none.kcal, 2200); XCTAssertEqual(none.protein, 150); XCTAssertEqual(none.carbs, 250); XCTAssertEqual(none.fat, 70)
        XCTAssertTrue(none.kcalIsDefault); XCTAssertTrue(none.macrosAreDefault)
        let partial = NutritionGoals.resolve(kcal: 1800, protein: 120, carbs: 0, fat: -5)
        XCTAssertEqual(partial.kcal, 1800); XCTAssertEqual(partial.protein, 120)
        XCTAssertEqual(partial.carbs, 250, "0 = pas regle"); XCTAssertEqual(partial.fat, 70)
        XCTAssertFalse(partial.kcalIsDefault); XCTAssertFalse(partial.macrosAreDefault)
        defaults.set(2400, forKey: AppStorageKeys.kcalGoal)
        XCTAssertEqual(WidgetPublisher.goals(from: defaults).kcal, 2400)
        XCTAssertEqual(NutritionSnapshot.ratio(3000, 2400), 1, "borne a 100 %")
    }

    func testAgendaOrderAndRemaining() {
        let now = at(0, 12, from: Date())
        func ev(_ id: String, _ h: Int, allDay: Bool = false, dayOffset: Int = 0) -> AgendaSnapshot.Item {
            let s = at(dayOffset, h, from: now)
            return .init(id: id, title: id, detail: "", start: s, end: s.addingTimeInterval(3600), allDay: allDay, source: .event, link: "lifeos://agenda")
        }
        let items = [ev("pm", 15), ev("am", 9), ev("allday", 0, allDay: true), ev("tomorrow", 9, dayOffset: 1)]
        XCTAssertEqual(AgendaSnapshot.items(on: now, from: items).map(\.id), ["am", "pm", "allday"])
        XCTAssertEqual(AgendaSnapshot.remaining(items, now: now).map(\.id), ["pm", "allday"], "le rendez-vous du matin est passe")
        XCTAssertEqual(AgendaSnapshot.next(items, now: now)?.id, "pm")
    }

    func testOptimisticWaterAddStartsFromZeroOnNewDay() {
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        defaults.set(1800, forKey: WidgetKeys.waterToday)
        defaults.set(WidgetKeys.dayStamp(yesterday), forKey: WidgetKeys.waterDay)
        WaterWidgetState.applyOptimisticAdd(250, defaults: defaults, now: now)
        XCTAssertEqual(defaults.integer(forKey: WidgetKeys.waterToday), 250)
        XCTAssertEqual(defaults.string(forKey: WidgetKeys.waterDay), WidgetKeys.dayStamp(now))
    }

    func testGymWeekPlanPicksTodaysWeekday() {
        let now = Date()
        let wd = cal.component(.weekday, from: now)
        let other = wd == 7 ? 1 : wd + 1
        let week = GymWeekSnapshot(day: "old", updatedAt: now, days: [
            .init(weekday: wd, title: "Jambes", focus: "Squat", isRest: false),
            .init(weekday: other, title: "", focus: "", isRest: true),
        ])
        XCTAssertEqual(week.plan(for: now)?.title, "Jambes", "juste meme si l'app n'a pas ete ouverte aujourd'hui")
        XCTAssertEqual(week.plan(for: cal.date(byAdding: .day, value: 1, to: now)!)?.isRest, true)
    }
}
