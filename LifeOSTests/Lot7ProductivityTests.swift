import XCTest
import SwiftData
@testable import LifeOS

/// Lot 7 Productivite : Todoo, Structurd, Habitly, Forêt, Notio. Chaque test porte
/// sur une regle pure (Models_Productivity.swift) utilisee par les ecrans.
@MainActor
final class Lot7ProductivityTests: XCTestCase {

    private let cal = Calendar.current

    /// 5 oct. 2026 = lundi.
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { date(5, 10) }
    /// Un ModelContext ne garde pas son conteneur en vie: on le retient le temps du test.
    private var containers: [ModelContainer] = []

    // MARK: - Todoo : saisie rapide

    func testCaptureTomorrowTimeProjectPriority() {
        let p = TaskCapture.parse("Appeler maman demain 18h #maison !2", now: now)
        XCTAssertEqual(p.title, "Appeler maman")
        XCTAssertEqual(p.due, date(6, 18))
        XCTAssertTrue(p.hasTime)
        XCTAssertEqual(p.project, "maison")
        XCTAssertEqual(p.priority, 1, "!2 = importante")
        XCTAssertEqual(TaskCapture.parse("Payer !1", now: now).priority, 2, "!1 = urgente")
    }

    func testCaptureWeekdaysGoToNextOccurrence() {
        XCTAssertEqual(TaskCapture.parse("Sport lundi", now: now).due, date(12), "lundi un lundi = la semaine suivante")
        let r = TaskCapture.parse("Réunion vendredi 9h30", now: now)
        XCTAssertEqual(r.due, date(9, 9, 30))
        XCTAssertEqual(r.title, "Réunion")
        XCTAssertEqual(TaskCapture.parse("Courses le mardi", now: now).due, date(6))
    }

    func testCaptureExplicitDates() {
        let d = TaskCapture.parse("Dentiste le 12 octobre à 14h", now: now)
        XCTAssertEqual(d.title, "Dentiste")
        XCTAssertEqual(d.due, date(12, 14))
        XCTAssertEqual(TaskCapture.parse("Impôts 15/09", now: now).due, date(15, month: 9, year: 2027), "date passee sans annee = annee suivante")
        XCTAssertEqual(TaskCapture.parse("Truc le 3", now: now).due, date(3, month: 11), "le 3 deja passe = mois suivant")
        XCTAssertEqual(TaskCapture.parse("Voyage 2 janvier 2027", now: now).due, date(2, month: 1, year: 2027))
    }

    func testCaptureRelativeDays() {
        XCTAssertEqual(TaskCapture.parse("Rappeler dans 3 jours", now: now).due, date(8))
        XCTAssertEqual(TaskCapture.parse("Bilan dans 2 semaines", now: now).due, date(19))
        XCTAssertEqual(TaskCapture.parse("Appel Après-demain", now: now).due, date(7), "accents et casse ignores")
        let tonight = TaskCapture.parse("Lessive ce soir", now: now)
        XCTAssertEqual(tonight.due, date(5, 20)); XCTAssertTrue(tonight.hasTime)
        let today = TaskCapture.parse("Ranger aujourd'hui", now: now)
        XCTAssertEqual(today.due, date(5)); XCTAssertFalse(today.hasTime)
        XCTAssertEqual(TaskCapture.parse("Appeler demain matin", now: now).due, date(6, 9))
    }

    func testCaptureTimeOnlyAlreadyPassedGoesTomorrow() {
        XCTAssertEqual(TaskCapture.parse("Pain 8h", now: now).due, date(6, 8))
        XCTAssertEqual(TaskCapture.parse("Pain 18h", now: now).due, date(5, 18))
        XCTAssertEqual(TaskCapture.parse("Pain à midi", now: now).due, date(5, 12))
    }

    func testCaptureRecurrence() {
        let bins = TaskCapture.parse("Sortir poubelles tous les lundis et jeudis 20h", now: now)
        XCTAssertEqual(bins.title, "Sortir poubelles")
        XCTAssertEqual(bins.recurrence, .weekly([2, 5]))
        XCTAssertEqual(bins.due, date(5, 20), "premiere occurrence: aujourd'hui, l'heure n'est pas passee")

        let rent = TaskCapture.parse("Payer loyer tous les mois le 5", now: now)
        XCTAssertEqual(rent.recurrence, .monthly)
        XCTAssertEqual(rent.due, date(5))
        XCTAssertEqual(rent.title, "Payer loyer")

        XCTAssertEqual(TaskCapture.parse("Méditer tous les jours", now: now).recurrence, .daily)
        let standup = TaskCapture.parse("Stand-up en semaine 9h", now: now)
        XCTAssertEqual(standup.recurrence, .weekdays)
        XCTAssertEqual(standup.due, date(6, 9), "9 h deja passee lundi: premiere occurrence mardi")
        XCTAssertEqual(TaskCapture.parse("Bilan chaque semaine", now: now).recurrence, .weekly([2]))
    }

    func testCaptureKeepsUnknownWordsAndReadsTags() {
        let p = TaskCapture.parse("Acheter 3 pommes @courses @Maison", now: now)
        XCTAssertEqual(p.title, "Acheter 3 pommes", "un nombre seul n'est pas une date")
        XCTAssertNil(p.due)
        XCTAssertEqual(p.tags, ["courses", "Maison"])
        XCTAssertEqual(TaskCapture.parse("Appeler le plombier", now: now).title, "Appeler le plombier")
    }

    // MARK: - Todoo : recurrence

    func testMonthlyRecurrenceClampsToMonthEnd() {
        let next = TaskRecurrence.nextMonthly(after: date(31, 10, month: 1, year: 2027), dayOfMonth: 31, timeOf: date(31, 8, month: 1, year: 2027))
        XCTAssertEqual(next, date(28, 8, month: 2, year: 2027))
    }

    func testCheckingMonthlyTodoRollsToNextMonthAndResetsChecklist() throws {
        let container = try ModelContainer(for: Schema([TodoItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let t = TodoItem(title: "Loyer", due: date(5, 9))
        t.recurrenceRule = "monthly"
        t.checklistRaw = "[x] Virement\n[ ] Quittance"
        container.mainContext.insert(t)
        ProductivityRules.toggleDone(t, now: date(5, 10))
        XCTAssertFalse(t.done)
        XCTAssertEqual(t.due, date(5, 9, month: 11))
        XCTAssertEqual(Checklist.progress(t.checklistRaw).done, 0, "la prochaine occurrence repart decochee")
        XCTAssertNotNil(t.completedAt)
    }

    func testRecurringCompletedLateAcrossDSTKeepsHourAndUndoRestores() throws {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        // Dimanche 25 oct. 2026: passage a l'heure d'hiver a Paris.
        let due = paris.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9))!
        let late = paris.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 14))!
        let next = try XCTUnwrap(TaskRecurrence.weekly([1]).next(after: late, timeOf: due, calendar: paris))
        XCTAssertEqual(paris.component(.month, from: next), 11)
        XCTAssertEqual(paris.component(.day, from: next), 1)
        XCTAssertEqual(paris.component(.hour, from: next), 9, "une seule prochaine occurrence, a 9 h meme apres le changement d'heure")

        let container = try ModelContainer(for: Schema([TodoItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let t = TodoItem(title: "Courses", due: date(5, 9), recurringDaysRaw: "2")
        container.mainContext.insert(t)
        let snap = TodoSnapshot(t)
        ProductivityRules.toggleDone(t, now: date(7, 9))
        XCTAssertEqual(t.due, date(12, 9))
        snap.restore(t)
        XCTAssertEqual(t.due, date(5, 9), "annuler remet l'occurrence d'origine, rien n'est cree en double")
        XCTAssertFalse(t.done)
    }

    func testRecurrenceStorageRoundTrip() {
        for r in [TaskRecurrence.none, .daily, .weekdays, .weekly([2, 4]), .monthly] {
            XCTAssertEqual(TaskRecurrence.of(daysRaw: r.storage.daysRaw, rule: r.storage.rule), r)
        }
    }

    // MARK: - Todoo : vues, recherche, projets, sous-taches, rappels

    private func todos() throws -> (ModelContainer, [TodoItem]) {
        let container = try ModelContainer(for: Schema([TodoItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        containers.append(container)
        let items = [
            TodoItem(title: "Idée en vrac", project: ""),
            TodoItem(title: "Rapport", due: date(5, 15), priority: 1, project: "Travail"),
            TodoItem(title: "Facture en retard", due: date(3), project: "Admin"),
            TodoItem(title: "Urgente lointaine", due: date(20), priority: 2, project: "Travail"),
            TodoItem(title: "Demain normale", due: date(6, 9), project: "Perso"),
            TodoItem(title: "Faite", due: date(5), done: true, project: "Perso")
        ]
        items[1].section = "Rédaction"; items[1].tagsRaw = "bureau"
        items.forEach { container.mainContext.insert($0) }
        return (container, items)
    }

    func testInboxTodayUpcomingViews() throws {
        let (_, items) = try todos()
        XCTAssertEqual(TodoFilter.tasks(items, in: .inbox, now: now).map(\.title), ["Idée en vrac"])
        XCTAssertEqual(Set(TodoFilter.tasks(items, in: .today, now: now).map(\.title)), ["Rapport", "Facture en retard"])
        XCTAssertEqual(TodoFilter.tasks(items, in: .upcoming, now: now).map(\.title), ["Demain normale", "Urgente lointaine"],
                       "A venir suit l'ordre chronologique, la priorite ne fait pas sauter les jours")
        XCTAssertEqual(TodoFilter.tasks(items, in: .done, now: now).map(\.title), ["Faite"])
        XCTAssertEqual(TodoFilter.groupedByDay(TodoFilter.tasks(items, in: .upcoming, now: now)).count, 2)
    }

    func testSearchTagAndPriorityFilters() throws {
        let (_, items) = try todos()
        XCTAssertEqual(items.filter { TodoFilter.matches($0, search: "rapport redaction") }.map(\.title), ["Rapport"],
                       "tous les mots, accents ignores, section comprise")
        XCTAssertEqual(items.filter { TodoFilter.matches($0, search: "", tag: "Bureau") }.map(\.title), ["Rapport"])
        XCTAssertEqual(items.filter { TodoFilter.matches($0, search: "", priority: 2) }.map(\.title), ["Urgente lointaine"])
    }

    func testProjectsSectionsAndRename() throws {
        let (_, items) = try todos()
        XCTAssertEqual(TodoProjects.projects(items), ["Admin", "Perso", "Travail"])
        XCTAssertEqual(TodoProjects.sections(of: "travail", in: items), ["", "Rédaction"])
        XCTAssertEqual(TodoProjects.rename("Travail", to: "Boulot", in: items), 2)
        XCTAssertEqual(TodoProjects.projects(items), ["Admin", "Boulot", "Perso"])
    }

    func testChecklistRoundTrip() {
        let raw = "[x] Pain\n[ ] Lait\nOeufs\n[ ]   "
        let items = Checklist.parse(raw)
        XCTAssertEqual(items.map(\.title), ["Pain", "Lait", "Oeufs"])
        XCTAssertEqual(items.map(\.done), [true, false, false])
        XCTAssertEqual(Checklist.serialize(items), "[x] Pain\n[ ] Lait\n[ ] Oeufs")
        XCTAssertEqual(Checklist.progress(raw).done, 1)
        XCTAssertEqual(Checklist.progress(raw).total, 3)
    }

    func testTagListNormalizesAndDeduplicates() {
        XCTAssertEqual(TagList.parse("#maison, @Maison, travail,, "), ["maison", "travail"])
        XCTAssertTrue(TagList.contains("maison,travail", "Travail"))
    }

    func testTaskReminderFireDate() {
        XCTAssertEqual(TaskReminderRules.fireDate(due: date(6, 18), minutesBefore: 60, now: now), date(6, 17))
        XCTAssertEqual(TaskReminderRules.fireDate(due: date(6), minutesBefore: 0, now: now), date(6, 9), "sans heure: 9 h")
        XCTAssertNil(TaskReminderRules.fireDate(due: date(5, 9), minutesBefore: 0, now: now), "deja passe")
        XCTAssertNil(TaskReminderRules.fireDate(due: date(6, 18), minutesBefore: -1, now: now), "aucun rappel")
    }

    func testTodoIDsFillMissingAndDuplicates() throws {
        let container = try ModelContainer(for: Schema([TodoItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let a = TodoItem(title: "A"), b = TodoItem(title: "B"), c = TodoItem(title: "C")
        b.uid = "x"; c.uid = "x"
        [a, b, c].forEach { container.mainContext.insert($0) }
        XCTAssertEqual(TodoIDs.ensure(container.mainContext), 2)
        XCTAssertEqual(Set([a.uid, b.uid, c.uid]).count, 3)
        XCTAssertFalse(a.uid.isEmpty)
    }

    // MARK: - Structurd

    private var window: PlanSlot { PlanSlot(start: date(5, 9), end: date(5, 18)) }

    func testPlannerAvoidsMeetingWithoutOverlap() {
        let meeting = PlanSlot(start: date(5, 10), end: date(5, 11))
        let out = DayPlanner.plan(items: [PlanItem(key: "a", minutes: 30), PlanItem(key: "b", minutes: 90)],
                                  busy: [meeting], window: window, earliest: date(5, 9))
        XCTAssertEqual(out.placed["a"], PlanSlot(start: date(5, 9), end: date(5, 9, 30)))
        XCTAssertEqual(out.placed["b"], PlanSlot(start: date(5, 11), end: date(5, 12, 30)), "90 min ne tient pas avant la reunion")
        let all = Array(out.placed.values) + [meeting]
        for i in all.indices { for j in all.indices where i < j { XCTAssertFalse(all[i].overlaps(all[j])) } }
        XCTAssertTrue(out.overflow.isEmpty)
    }

    func testPlannerExplainsOverflow() {
        let short = PlanSlot(start: date(5, 9), end: date(5, 11))
        let out = DayPlanner.plan(items: [PlanItem(key: "a", minutes: 90), PlanItem(key: "b", minutes: 60), PlanItem(key: "c", minutes: 180)],
                                  busy: [], window: short, earliest: date(5, 9))
        XCTAssertEqual(out.placed["a"], PlanSlot(start: date(5, 9), end: date(5, 10, 30)))
        XCTAssertEqual(out.overflow.map(\.key), ["b", "c"])
        XCTAssertEqual(out.overflow.first?.reason, "Pas de créneau libre assez long.")
        XCTAssertEqual(out.overflow.last?.reason, "Plus longue que le temps qui reste dans ta journée.")
        XCTAssertEqual(DayPlanner.plan(items: [PlanItem(key: "x", minutes: 30)], busy: [], window: short, earliest: date(5, 12)).overflow.first?.reason,
                       "Ta journée est terminée.")
    }

    func testMovingMeetingOnlyMovesAffectedUnlockedBlock() {
        let a = PlanSlot(start: date(5, 9), end: date(5, 9, 30))
        let b = PlanSlot(start: date(5, 14), end: date(5, 15, 30))
        let movedMeeting = PlanSlot(start: date(5, 14, 30), end: date(5, 15))
        let out = DayPlanner.plan(items: [PlanItem(key: "a", minutes: 30, existing: a), PlanItem(key: "b", minutes: 90, existing: b)],
                                  busy: [movedMeeting], window: window, earliest: date(5, 9))
        XCTAssertEqual(out.placed["a"], a, "le bloc non touche reste a sa place")
        XCTAssertEqual(out.placed["b"], PlanSlot(start: date(5, 9, 30), end: date(5, 11)))
        // Sans garder l'existant, tout est recalcule depuis le debut.
        XCTAssertEqual(DayPlanner.plan(items: [PlanItem(key: "b", minutes: 90, existing: b)], busy: [], window: window,
                                       earliest: date(5, 9), keepExisting: false).placed["b"]?.start, date(5, 9))
    }

    func testPlannerBufferAndEarliest() {
        let out = DayPlanner.plan(items: [PlanItem(key: "a", minutes: 30)], busy: [PlanSlot(start: date(5, 10), end: date(5, 11))],
                                  window: window, earliest: date(5, 10, 50), bufferMinutes: 10)
        XCTAssertEqual(out.placed["a"]?.start, date(5, 11, 10), "10 min de marge apres la reunion")
        let rounded = DayPlanner.plan(items: [PlanItem(key: "a", minutes: 30)], busy: [], window: window, earliest: date(5, 9, 2))
        XCTAssertEqual(rounded.placed["a"]?.start, date(5, 9, 5), "grille de 5 min")
    }

    func testDragMoveSnapsAndStaysInWindow() {
        let s = PlanSlot(start: date(5, 9), end: date(5, 10))
        let day = PlanSlot(start: date(5, 8), end: date(5, 18))
        XCTAssertEqual(DayPlanner.moved(s, byMinutes: 22, within: day).start, date(5, 9, 15))
        XCTAssertEqual(DayPlanner.moved(s, byMinutes: -600, within: day), PlanSlot(start: date(5, 8), end: date(5, 9)))
        XCTAssertEqual(DayPlanner.moved(s, byMinutes: 600, within: day), PlanSlot(start: date(5, 17), end: date(5, 18)))
    }

    func testEstimatedDurationDefaultsToOneHour() {
        let t = TodoItem(title: "x")
        XCTAssertEqual(DayPlanner.durationOf(t), 60)
        t.estimateMinutes = 25
        XCTAssertEqual(DayPlanner.durationOf(t), 25)
    }

    // MARK: - Habitly

    func testTwiceWeeklyHabitStreakCountsWeeks() {
        let now = date(21, 12)   // mercredi
        var done = [date(5, 12), date(7, 12), date(13, 12), date(16, 12), date(19, 12)]
        XCTAssertEqual(HabitRules.streak(completions: done, activeDays: Set(1...7), weeklyTarget: 2, skipped: [], now: now), 2,
                       "semaine en cours pas finie: ne casse rien")
        done.removeAll { $0 == date(16, 12) }
        XCTAssertEqual(HabitRules.streak(completions: done, activeDays: Set(1...7), weeklyTarget: 2, skipped: [], now: now), 0)
    }

    func testWeeklyHabitLeavesTodaysListOnceTargetMet() {
        let now = date(21, 12)
        let two = [date(19, 12), date(20, 12)]
        XCTAssertFalse(HabitRules.isDueToday(activeDays: Set(1...7), weeklyTarget: 2, skipped: [], completions: two, now: now),
                       "objectif de la semaine atteint: pas de completion accidentelle")
        XCTAssertTrue(HabitRules.isDueToday(activeDays: Set(1...7), weeklyTarget: 2, skipped: [], completions: [date(19, 12)], now: now))
        XCTAssertFalse(HabitRules.isDueToday(activeDays: [2], weeklyTarget: 0, skipped: [], completions: [], now: now), "mercredi pas actif")
        XCTAssertFalse(HabitRules.isDueToday(activeDays: Set(1...7), weeklyTarget: 0, skipped: ["2026-10-21"], completions: [], now: now))
    }

    func testSkippedDayIsNeutralForStreak() {
        let done = [date(1, 12), date(2, 12), date(4, 12)]
        XCTAssertEqual(HabitRules.streak(completions: done, activeDays: Set(1...7), weeklyTarget: 0, skipped: ["2026-10-03"], now: date(4, 18)), 3)
        XCTAssertEqual(HabitRules.streak(completions: done, activeDays: Set(1...7), weeklyTarget: 0, skipped: [], now: date(4, 18)), 1)
    }

    func testStreakMatchesLegacyRuleWithoutSkips() {
        let done = [date(1, 8), date(2, 8), date(5, 8), date(6, 8)]
        for active in [Set(1...7), Set([2, 3, 4, 5, 6]), Set([2, 5])] {
            XCTAssertEqual(HabitRules.streak(completions: done, activeDays: active, weeklyTarget: 0, skipped: [], now: date(6, 20)),
                           ProductivityRules.habitStreak(completions: done, activeDays: active, now: date(6, 20)))
        }
    }

    func testPauseAndResume() {
        let paused = HabitRules.pausing("", from: date(5), through: date(7))
        XCTAssertEqual(HabitRules.skipped(paused), ["2026-10-05", "2026-10-06", "2026-10-07"])
        XCTAssertEqual(HabitRules.skipped(HabitRules.resuming(paused, from: date(6))), ["2026-10-05"], "le passe reste, l'avenir se libere")
        XCTAssertTrue(HabitRules.isPaused(date(7), on: date(7, 20)))
        XCTAssertFalse(HabitRules.isPaused(date(7), on: date(8, 1)))
        XCTAssertEqual(HabitRules.toggledSkip(HabitRules.toggledSkip("", day: date(5)), day: date(5)), "")
    }

    func testCompletionRateAndBestStreak() throws {
        let done = (1...5).map { date($0, 12) }
        let rate = HabitRules.completionRate(completions: done, activeDays: Set(1...7), weeklyTarget: 0, skipped: [], since: date(1), now: date(10, 12))
        XCTAssertEqual(try XCTUnwrap(rate), 5.0 / 9.0, accuracy: 0.0001, "aujourd'hui non fait ne compte pas encore")
        XCTAssertNil(HabitRules.completionRate(completions: [], activeDays: [2], weeklyTarget: 0, skipped: [], since: date(6), now: date(6, 12)))
        let runs = [date(1, 12), date(2, 12), date(3, 12), date(6, 12), date(7, 12)]
        XCTAssertEqual(HabitRules.bestStreak(completions: runs, activeDays: Set(1...7), weeklyTarget: 0, skipped: [], since: date(1), now: date(7, 20)), 3)
    }

    private func habitContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema([Habit.self, HabitCompletion.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    func testCountTargetCompletesOnlyAtTarget() throws {
        let container = try habitContainer()
        let ctx = container.mainContext
        let h = Habit(name: "Eau")
        h.targetKind = 1; h.targetValue = 3; h.targetUnit = "verres"
        ctx.insert(h)
        XCTAssertFalse(HabitRules.addProgress(h, amount: 1, now: now, ctx: ctx))
        XCTAssertFalse(HabitRules.addProgress(h, amount: 1, now: now, ctx: ctx))
        XCTAssertTrue(h.completions.isEmpty, "pas de completion avant l'objectif: le widget et la serie restent justes")
        XCTAssertTrue(HabitRules.addProgress(h, amount: 1, now: now, ctx: ctx))
        XCTAssertEqual(h.completions.count, 1)
        XCTAssertEqual(h.completions.first?.value, 3)
        XCTAssertEqual(HabitRules.progress(h, now: now), 3)
        XCTAssertFalse(HabitRules.addProgress(h, amount: -1, now: now, ctx: ctx))
        XCTAssertTrue(h.completions.isEmpty)
        XCTAssertEqual(HabitRules.progress(h, now: date(6, 10)), 0, "un nouveau jour repart de zero")
    }

    func testBackfillPastDayButNeverFuture() throws {
        let container = try habitContainer()
        let h = Habit(name: "Lecture")
        container.mainContext.insert(h)
        XCTAssertFalse(HabitRules.setDone(h, on: date(6), done: true, now: now, ctx: container.mainContext))
        XCTAssertTrue(h.completions.isEmpty)
        XCTAssertTrue(HabitRules.setDone(h, on: date(2), done: true, now: now, ctx: container.mainContext))
        XCTAssertEqual(h.completions.first?.date, date(2, 12), "midi du jour rattrape")
        XCTAssertEqual(HabitRules.streak(completions: h.completions.map(\.date), activeDays: [6], weeklyTarget: 0, skipped: [], now: date(4, 20)), 1)
        HabitRules.setDone(h, on: date(2), done: false, now: now, ctx: container.mainContext)
        XCTAssertTrue(h.completions.isEmpty)
    }

    // MARK: - Forêt

    func testFocusCycleWithLongBreak() {
        let c = FocusConfig(focus: 25, shortBreak: 5, longBreak: 15, cycleLength: 4)
        var next = FocusRules.phaseAfter(.focus, focusDoneInCycle: 0, config: c)
        XCTAssertEqual(next.phase, .shortBreak); XCTAssertEqual(next.minutes, 5); XCTAssertEqual(next.focusDoneInCycle, 1)
        next = FocusRules.phaseAfter(.focus, focusDoneInCycle: 3, config: c)
        XCTAssertEqual(next.phase, .longBreak); XCTAssertEqual(next.minutes, 15); XCTAssertEqual(next.focusDoneInCycle, 0)
        next = FocusRules.phaseAfter(.shortBreak, focusDoneInCycle: 2, config: c)
        XCTAssertEqual(next.phase, .focus); XCTAssertEqual(next.minutes, 25)
    }

    func testLeavingTheAppBreaksTheSession() {
        let left = date(5, 10), end = date(5, 10, 25)
        XCTAssertEqual(FocusRules.awayOutcome(leftAt: left, returnedAt: left.addingTimeInterval(5), phaseEnd: end, deviceLocked: false), .keepGoing)
        XCTAssertEqual(FocusRules.awayOutcome(leftAt: left, returnedAt: left.addingTimeInterval(30), phaseEnd: end, deviceLocked: false), .broken)
        XCTAssertEqual(FocusRules.awayOutcome(leftAt: left, returnedAt: date(5, 11), phaseEnd: end, deviceLocked: true), .finishedWhileAway,
                       "ecran verrouille: tolere")
        XCTAssertEqual(FocusRules.awayOutcome(leftAt: end.addingTimeInterval(-5), returnedAt: date(5, 12), phaseEnd: end, deviceLocked: false),
                       .finishedWhileAway, "sorti 5 s avant la fin: la session est finie")
    }

    func testTreeGrowthStages() {
        XCTAssertEqual([0, 0.2, 0.3, 0.6, 0.8, 1].map(FocusRules.growthStage), [0, 0, 1, 2, 3, 4])
        XCTAssertEqual(FocusRules.growthStage(progress: -1), 0)
    }

    func testFocusStatsPerTagAndDedupe() {
        let stats = FocusRules.stats([("Révisions", "completed", 1500), ("Révisions", "interrupted", 300), ("", "completed", 600)])
        XCTAssertEqual(stats.map(\.tag), ["Révisions", FocusRules.noTag])
        XCTAssertEqual(stats[0].completed, 1); XCTAssertEqual(stats[0].failed, 1); XCTAssertEqual(stats[0].minutes, 30)
        XCTAssertEqual(stats[0].successRate, 0.5)
        let key = FocusRules.phaseKey(start: now)
        XCTAssertTrue(FocusRules.shouldRecord(key: key, existing: []))
        XCTAssertFalse(FocusRules.shouldRecord(key: key, existing: [key]), "une relance ne recompte pas la session")
    }

    func testFocusSessionPersists() throws {
        let container = try ModelContainer(for: Schema([FocusSession.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        container.mainContext.insert(FocusSession(phaseKey: "1", start: now, end: now.addingTimeInterval(1500), plannedMinutes: 25,
                                                  focusedSeconds: 1500, tag: "Travail", outcome: "completed"))
        try container.mainContext.save()
        let rows = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isCompleted)
        XCTAssertEqual(FocusRules.stats(rows).first?.minutes, 25)
    }

    // MARK: - Notio

    func testMarkdownBlocks() {
        let md = "# Titre\n\n- un\n  - deux\n1. premier\n- [ ] faire\n- [x] fait\n> cite\n---\ntexte"
        XCTAssertEqual(Markdown.blocks(md), [
            .heading(level: 1, text: "Titre"), .bullet(text: "un", indent: 0), .bullet(text: "deux", indent: 1),
            .numbered(number: 1, text: "premier"), .task(done: false, text: "faire", line: 5), .task(done: true, text: "fait", line: 6),
            .quote(text: "cite"), .rule, .paragraph(text: "texte")
        ])
        XCTAssertEqual(Markdown.blocks("#pas un titre"), [.paragraph(text: "#pas un titre")])
    }

    func testToggleCheckboxFromPreview() {
        let md = "- [ ] a\n- [x] b"
        XCTAssertEqual(Markdown.togglingTask(md, line: 0), "- [x] a\n- [x] b")
        XCTAssertEqual(Markdown.togglingTask(md, line: 1), "- [ ] a\n- [ ] b")
        XCTAssertEqual(Markdown.togglingTask(md, line: 9), md)
    }

    func testFormattingHelpers() {
        let w = Markdown.wrapping("un mot ici", selection: 3..<6, marker: "**")
        XCTAssertEqual(w.text, "un **mot** ici"); XCTAssertEqual(w.selection, 5..<8)
        XCTAssertEqual(Markdown.wrapping("abc", selection: 3..<3, marker: "_").text, "abc__")
        let p = Markdown.prefixing("a\nb\nc", selection: 0..<3, prefix: "- ")
        XCTAssertEqual(p.text, "- a\n- b\nc")
        XCTAssertEqual(Markdown.prefixing(p.text, selection: 0..<7, prefix: "- ").text, "a\nb\nc", "deja present partout: retire")
    }

    func testInlineMarkdownBoldAndInternalLink() throws {
        let a = Markdown.inline("**gras** et [[Idée géniale]]")
        XCTAssertEqual(String(a.characters), "gras et Idée géniale")
        let link = try XCTUnwrap(a.runs.compactMap { $0.link }.first)
        XCTAssertEqual(NoteLinks.title(from: link), "Idée géniale")
        XCTAssertTrue(a.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    func testLinksAndBacklinks() {
        XCTAssertEqual(NoteLinks.targets(in: "Voir [[Projet A]] et [[projet a]] puis [[ B ]] et [[]]"), ["Projet A", "B"])
        let notes = [("Projet A", "rien"), ("Journal", "lié à [[projet a]]"), ("Autre", "[[B]]")]
        XCTAssertEqual(NoteLinks.backlinks(to: "Projet A", in: notes), [1])
        XCTAssertEqual(NoteLinks.resolve("PROJET A", among: notes.map(\.0)), 0)
        XCTAssertNil(NoteLinks.resolve("Inconnue", among: notes.map(\.0)))
    }

    func testVersionHistoryKeepsLastN() {
        var raw = ""
        for i in 0..<25 { raw = NoteHistory.pushing(.init(savedAt: now, title: "t", body: "v\(i)", tags: ""), onto: raw) }
        let v = NoteHistory.decode(raw)
        XCTAssertEqual(v.count, NoteHistory.limit)
        XCTAssertEqual(v.first?.body, "v5"); XCTAssertEqual(v.last?.body, "v24")
        XCTAssertEqual(NoteHistory.pushing(.init(savedAt: now, title: "t", body: "v24", tags: ""), onto: raw), raw, "identique: pas de doublon")
    }

    func testNoteSaveVersionsAndRestore() throws {
        let container = try ModelContainer(for: Schema([Note.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let n = Note(title: "Idée", body: "première")
        container.mainContext.insert(n)
        XCTAssertTrue(NoteHistory.save(n, title: "Idée", body: "seconde", tags: "", folder: " Travail / Clients "))
        XCTAssertEqual(n.folder, "Travail/Clients")
        XCTAssertFalse(NoteHistory.save(n, title: "Idée", body: "seconde", tags: "", folder: "Travail/Clients"), "rien n'a change")
        let old = try XCTUnwrap(NoteHistory.decode(n.historyRaw).last)
        XCTAssertEqual(old.body, "première")
        NoteHistory.restore(n, to: old)
        XCTAssertEqual(n.body, "première")
        XCTAssertEqual(NoteHistory.decode(n.historyRaw).map(\.body), ["première", "seconde"], "la version remplacee est gardee aussi")
    }

    func testFoldersSearchAndSnippet() {
        XCTAssertEqual(NoteFolders.folders(["Travail/Clients", "Perso", ""]), ["Perso", "Travail", "Travail/Clients"])
        XCTAssertTrue(NoteFolders.contains("Travail/Clients", folder: "Travail"))
        XCTAssertFalse(NoteFolders.contains("Travaux", folder: "Travail"))
        XCTAssertTrue(NoteSearch.matches(title: "Réunion", body: "budget été", tags: "", folder: "", query: "reunion ete"))
        XCTAssertFalse(NoteSearch.matches(title: "Réunion", body: "", tags: "", folder: "", query: "reunion hiver"))
        XCTAssertEqual(NoteSearch.snippet("Le budget de l'été est validé", query: "ete", radius: 3), "… l'été es…")
    }

    func testExportMarkdownAndPDF() {
        let md = NoteExport.markdown(title: "Plan", body: "- [ ] a", tags: "x, y", folder: "Travail")
        XCTAssertEqual(md, "# Plan\n\nDossier : Travail · #x #y\n\n- [ ] a\n")
        XCTAssertEqual(NoteExport.fileName("a/b:c", ext: "md"), "a-b-c.md")
        let pdf = NotePDF.data(title: "Plan", body: String(repeating: "Une ligne de texte assez longue pour remplir.\n", count: 200))
        XCTAssertEqual(pdf.prefix(4), Data("%PDF".utf8))
        XCTAssertGreaterThan(pdf.count, 2000)
    }
}
