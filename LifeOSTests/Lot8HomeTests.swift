import XCTest
import SwiftData
@testable import LifeOS

// Lot 8 : accueil (Maintenant, 3 priorites, disposition) et capture universelle.

private func fixedCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.locale = Locale(identifier: "fr_FR")
    c.timeZone = TimeZone(identifier: "Europe/Paris")!
    c.firstWeekday = 2
    return c
}

/// Mercredi 7 octobre 2026, 10:00 (Paris).
private func wednesday10(_ cal: Calendar) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 10, minute: 0))!
}

// MARK: - Capture : lecture locale

final class Lot8CaptureParserTests: XCTestCase {
    let cal = fixedCalendar()
    var now: Date { wednesday10(cal) }

    func testFrenchAmountWithCommaAndEuroSign() {
        let p = CaptureParser.parse("12,50 € courses", now: now, calendar: cal)
        XCTAssertEqual(p.kind, .expense)
        XCTAssertEqual(p.amount, 12.5)
        XCTAssertEqual(p.category, "Courses")
        XCTAssertTrue(p.categoryGuessed)
        XCTAssertEqual(p.title, "courses")
        XCTAssertTrue(p.flags.isEmpty)
    }

    func testAmountGluedToEuroAndYesterday() {
        let p = CaptureParser.parse("café 3€ hier", now: now, calendar: cal)
        XCTAssertEqual(p.kind, .expense)
        XCTAssertEqual(p.amount, 3)
        XCTAssertEqual(p.category, "Restau")
        XCTAssertEqual(p.title, "café")
        let d = try! XCTUnwrap(p.date)
        XCTAssertEqual(cal.component(.day, from: d), 6)
    }

    func testEuroCentsForms() {
        XCTAssertEqual(CaptureParser.parse("12€50 pizza", now: now, calendar: cal).amount, 12.5)
        XCTAssertEqual(CaptureParser.parse("pizza €9", now: now, calendar: cal).amount, 9)
        XCTAssertEqual(CaptureParser.parse("loyer 1 200 €", now: now, calendar: cal).amount, 1200)
        XCTAssertEqual(CaptureParser.parse("loyer 1 200 €", now: now, calendar: cal).category, "Logement")
        XCTAssertEqual(CaptureParser.parse("cinéma 8 euros", now: now, calendar: cal).amount, 8)
    }

    func testTimesAndPrioritiesAreNotAmounts() {
        let p = CaptureParser.parse("taxi 18h 25€ !1", now: now, calendar: cal)
        XCTAssertEqual(p.kind, .expense)
        XCTAssertEqual(p.amount, 25)
        XCTAssertFalse(p.flags.contains(.multipleAmounts))
        XCTAssertEqual(p.category, "Transport")
    }

    func testExpenseWeekdayMeansLastOccurrence() {
        let p = CaptureParser.parse("courses 20€ lundi", now: now, calendar: cal)
        let d = try! XCTUnwrap(p.date)
        XCTAssertEqual(cal.component(.day, from: d), 5)   // lundi 5 octobre
        XCTAssertLessThan(d, now)
    }

    func testUnknownCategoryFallsBackToDivers() {
        let p = CaptureParser.parse("truc 7 €", now: now, calendar: cal)
        XCTAssertEqual(p.category, "Divers")
        XCTAssertFalse(p.categoryGuessed)
    }

    func testTaskWithTomorrowAndTime() {
        let p = CaptureParser.parse("appeler maman demain 18h #perso", now: now, calendar: cal)
        XCTAssertEqual(p.kind, .task)
        XCTAssertEqual(p.title, "appeler maman")
        let d = try! XCTUnwrap(p.date)
        XCTAssertEqual(cal.component(.day, from: d), 8)
        XCTAssertEqual(cal.component(.hour, from: d), 18)
        XCTAssertTrue(p.hasTime)
        XCTAssertEqual(p.task?.project, "perso")
    }

    func testTaskOnMondayIsNextMonday() {
        let p = CaptureParser.parse("réunion budget lundi", now: now, calendar: cal)
        XCTAssertEqual(p.kind, .task)
        let d = try! XCTUnwrap(p.date)
        XCTAssertEqual(cal.component(.day, from: d), 12)
    }

    func testTaskVerbWithoutDate() {
        let p = CaptureParser.parse("acheter du pain", now: now, calendar: cal)
        XCTAssertEqual(p.kind, .task)
        XCTAssertNil(p.date)
    }

    func testExplicitNoteAndFallbackNote() {
        let n = CaptureParser.parse("note: idée de cadeau pour Léa", now: now, calendar: cal)
        XCTAssertEqual(n.kind, .note)
        XCTAssertEqual(n.title, "idée de cadeau pour Léa")
        let f = CaptureParser.parse("Le livre dont parlait Paul", now: now, calendar: cal)
        XCTAssertEqual(f.kind, .note)
    }

    func testMissingAmountIsFlagged() {
        let p = CaptureParser.parse("dépense courses", now: now, calendar: cal)
        XCTAssertEqual(p.kind, .expense)
        XCTAssertNil(p.amount)
        XCTAssertTrue(p.flags.contains(.missingAmount))
    }

    func testTwoAmountsAreNeverGuessed() {
        let p = CaptureParser.parse("resto 12€ et 5€ pourboire", now: now, calendar: cal)
        XCTAssertNil(p.amount)
        XCTAssertTrue(p.flags.contains(.multipleAmounts))
        XCTAssertEqual(p.amountCandidates, [12, 5])
    }

    func testBareNumberNeedsConfirmation() {
        let p = CaptureParser.parse("payé 12 courses", now: now, calendar: cal)
        XCTAssertEqual(p.kind, .expense)
        XCTAssertEqual(p.amount, 12)
        XCTAssertTrue(p.flags.contains(.unconfirmedAmount))
    }

    func testUnknownAccountIsFlaggedKnownOneIsPicked() {
        let unknown = CaptureParser.parse("40€ courses compte Revolut", now: now, calendar: cal, accounts: ["Courant"])
        XCTAssertTrue(unknown.flags.contains(.unknownAccount))
        XCTAssertEqual(unknown.mentionedAccount, "Revolut")
        XCTAssertNil(unknown.accountName)
        let known = CaptureParser.parse("40€ courses compte revolut", now: now, calendar: cal, accounts: ["Revolut"])
        XCTAssertFalse(known.flags.contains(.unknownAccount))
        XCTAssertEqual(known.accountName, "Revolut")
        XCTAssertEqual(known.title, "courses")
    }

    func testEmptyText() {
        XCTAssertTrue(CaptureParser.parse("   ", now: now, calendar: cal).flags.contains(.emptyTitle))
    }
}

// MARK: - Capture : enregistrement et annulation

@MainActor
final class Lot8CaptureServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() async throws {
        let schema = Schema([TodoItem.self, Txn.self, Account.self, Note.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        ctx = ModelContext(container)
    }
    override func tearDown() async throws { ctx = nil; container = nil }

    private func draft(_ kind: CaptureKind, title: String = "x", amount: Double? = nil, account: UUID? = nil) -> CaptureService.Draft {
        CaptureService.Draft(kind: kind, title: title, date: .now, hasTime: false, amount: amount,
                             category: "Courses", accountID: account, noteBody: "", parsedTask: nil)
    }

    func testExpenseLowersBalanceAndUndoRestoresIt() throws {
        let acc = Account(name: "Courant", kind: "Courant", balance: 100)
        ctx.insert(acc); try ctx.save()
        let r = try CaptureService.save(draft(.expense, title: "courses", amount: 12.5, account: acc.id), in: ctx)
        XCTAssertEqual(acc.balance, 87.5, accuracy: 0.001)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Txn>()).first?.amountCents, -1250)
        try CaptureService.undo(r, in: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Txn>()), 0)
        XCTAssertEqual(acc.balance, 100, accuracy: 0.001)
    }

    func testExpenseWithoutAccountIsRefused() {
        XCTAssertThrowsError(try CaptureService.save(draft(.expense, amount: 5), in: ctx)) { e in
            XCTAssertEqual(e as? CaptureService.CaptureError, .noAccount)
        }
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Txn>()), 0)
    }

    func testTaskGoesThroughInboxAndUndoDeletesIt() throws {
        let r = try CaptureService.save(draft(.task, title: "appeler maman"), in: ctx)
        let tasks = try ctx.fetch(FetchDescriptor<TodoItem>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertFalse(tasks[0].uid.isEmpty)
        XCTAssertEqual(tasks[0].project, "")   // Boite de reception
        try CaptureService.undo(r, in: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<TodoItem>()), 0)
    }

    func testNoteAndUndo() throws {
        let r = try CaptureService.save(draft(.note, title: "idée"), in: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Note>()), 1)
        try CaptureService.undo(r, in: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Note>()), 0)
    }
}

// MARK: - Domaines prioritaires

final class Lot8PriorityDomainsTests: XCTestCase {
    func testParseCapsAtThreeAndDedupes() {
        XCTAssertEqual(PriorityDomains.parse("fitness,fitness,nutrition,sleep,finance,bogus"),
                       [.fitness, .nutrition, .sleep])
    }

    func testSeedFromRecommendedOrFallback() {
        XCTAssertEqual(PriorityDomains.seed(recommendedRaw: "mind,finance,sleep,learning"), [.mind, .finance, .sleep])
        XCTAssertEqual(PriorityDomains.seed(recommendedRaw: ""), PriorityDomains.fallback)
    }

    func testToggleRefusesAFourth() {
        let r = PriorityDomains.toggle(.mind, in: [.fitness, .nutrition, .sleep])
        XCTAssertTrue(r.refused)
        XCTAssertEqual(r.list, [.fitness, .nutrition, .sleep])
        XCTAssertEqual(PriorityDomains.toggle(.sleep, in: [.fitness, .sleep]).list, [.fitness])
    }

    func testCurrentSeedsOnlyOnceForExistingUsers() {
        let d = UserDefaults(suiteName: "lot8.domains.\(UUID().uuidString)")!
        d.set("productivity,finance,nutrition,sleep", forKey: AppStorageKeys.recommendedModules)
        XCTAssertEqual(PriorityDomains.current(d), [.productivity, .finance, .nutrition])
        // Un choix vide fait expres reste vide (pas de nouveau semis).
        PriorityDomains.save([], d)
        XCTAssertEqual(PriorityDomains.current(d), [])
    }
}

// MARK: - Disposition de l'accueil

final class Lot8HomeLayoutTests: XCTestCase {
    func testMigrationKeepsUserOrderAndHiddenBlocks() {
        let l = HomeLayout.migrate(legacyRaw: "habits,score,tasks|coach,goals")
        XCTAssertEqual(Array(l.visible.prefix(3)), [.habits, .score, .tasks])
        XCTAssertEqual(l.hidden, [.coach, .goals])
        for k in HomeWidget.lot8Kinds { XCTAssertTrue(l.visible.contains(k), "\(k) manque") }
        // Les nouveaux blocs arrivent apres ceux de l'utilisateur.
        XCTAssertGreaterThan(l.visible.firstIndex(of: .now)!, l.visible.firstIndex(of: .tasks)!)
    }

    func testStoreMigratesOnceAndResetDoesNotReviveV1() {
        let d = UserDefaults(suiteName: "lot8.layout.\(UUID().uuidString)")!
        d.set("goals,habits|score", forKey: HomeLayout.legacyKey)
        let raw = HomeLayoutStore.ensure(d)
        let l = HomeLayout.parse(raw)
        XCTAssertEqual(Array(l.visible.prefix(2)), [.goals, .habits])
        XCTAssertEqual(l.hidden, [.score])
        XCTAssertEqual(d.string(forKey: HomeLayout.storageKey), raw)
        // Indicateurs poses a la reprise.
        XCTAssertNotNil(d.string(forKey: HomeIndicator.storageKey))
        // Reinitialiser = accueil par defaut, jamais l'ancien accueil.
        let reset = HomeLayoutStore.resetRaw(d)
        d.set(reset, forKey: HomeLayout.storageKey)
        XCTAssertEqual(HomeLayoutStore.ensure(d), reset)
        XCTAssertEqual(HomeLayout.parse(reset).visible.first, .now)
    }

    func testDefaultLayoutFollowsDomainsAndHidesLegacyBlocks() {
        let l = HomeLayout.defaultLayout(for: [.nutrition, .productivity])
        XCTAssertEqual(Array(l.visible.prefix(4)), [.now, .capture, .today, .watch])
        XCTAssertTrue(l.visible.contains(.tasks))
        XCTAssertTrue(l.hidden.contains(.score))
        XCTAssertFalse(HomeLayout.defaultLayout(for: [.sleep]).visible.contains(.tasks))
    }

    func testIndicatorDefaultsFromDomains() {
        XCTAssertEqual(HomeIndicator.defaults(for: [.nutrition]), [.water, .macros])
        XCTAssertEqual(HomeIndicator.defaults(for: [.nutrition, .finance, .sleep]), [.water, .macros, .budget, .sleep])
        XCTAssertEqual(HomeIndicator.defaults(for: [.travel]), [.water, .steps, .habits])
    }

    func testRecommendationsExplainAndCanBeDismissed() {
        let r = HomeRecommendationEngine.recommendations(domains: [.nutrition], indicators: [.water],
                                                         shortcuts: ["calories"], dismissed: [])
        XCTAssertEqual(r.map(\.id), ["ind.macros", "sc.water"])
        XCTAssertEqual(r.first?.reason, "Parce que tu as choisi Nutrition")
        let after = HomeRecommendationEngine.recommendations(domains: [.nutrition], indicators: [.water],
                                                             shortcuts: ["calories"], dismissed: ["ind.macros"])
        XCTAssertEqual(after.map(\.id), ["sc.water"])
    }
}

// MARK: - Maintenant

final class Lot8NowEngineTests: XCTestCase {
    let cal = fixedCalendar()

    func testOrderingRule() {
        let now = wednesday10(cal)
        func at(_ h: Int, _ m: Int, day: Int = 7) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))! }
        let items = [
            NowCandidate(id: "agenda15", kind: .agenda, title: "Rappel", time: at(15, 0)),
            NowCandidate(id: "untimed", kind: .task, title: "Sans heure", time: at(0, 0), hasTime: false),
            NowCandidate(id: "event1030", kind: .event, title: "Réunion", time: at(10, 30)),
            NowCandidate(id: "task1030", kind: .task, title: "Appel", time: at(10, 30)),
            NowCandidate(id: "habit930", kind: .habit, title: "Méditer", time: at(9, 30)),
            NowCandidate(id: "late", kind: .task, title: "Facture", time: at(0, 0, day: 6), overdue: true, hasTime: false),
            NowCandidate(id: "lateUrgent", kind: .task, title: "Impôts", time: at(0, 0, day: 5), overdue: true, priority: 2, hasTime: false),
        ]
        let order = HomeNowEngine.ordered(items, now: now).map(\.id)
        XCTAssertEqual(order, ["lateUrgent", "late", "habit930", "task1030", "event1030", "agenda15", "untimed"])
        XCTAssertEqual(HomeNowEngine.current(items, skipped: ["lateUrgent", "late"], now: now)?.id, "habit930")
        XCTAssertNil(HomeNowEngine.current(items, skipped: Set(items.map(\.id)), now: now))
    }
}

// MARK: - 3 priorites

final class Lot8PriorityEngineTests: XCTestCase {
    let cal = fixedCalendar()

    func testSuggestionRule() {
        let now = wednesday10(cal)
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let tasks = [
            PriorityCandidate(uid: "normalNoDate", title: "Ranger", priority: 0, due: nil, done: false),
            PriorityCandidate(uid: "todayNormal", title: "Courses", priority: 0, due: today, done: false),
            PriorityCandidate(uid: "urgent", title: "Urgent", priority: 2, due: nil, done: false),
            PriorityCandidate(uid: "late", title: "En retard", priority: 0, due: yesterday, done: false),
            PriorityCandidate(uid: "important", title: "Important", priority: 1, due: nil, done: false),
            PriorityCandidate(uid: "tomorrow", title: "Demain", priority: 0, due: tomorrow, done: false),
            PriorityCandidate(uid: "done", title: "Fait", priority: 2, due: today, done: true),
        ]
        let s = HomePriorityEngine.suggestions(tasks, pinned: [], ignored: [], now: now, calendar: cal)
        XCTAssertEqual(s.map(\.uid), ["late", "urgent", "todayNormal"])
        XCTAssertEqual(s.first?.reason, "En retard")
        // Une epinglee laisse 2 places ; une ignoree disparait.
        let s2 = HomePriorityEngine.suggestions(tasks, pinned: ["late"], ignored: ["urgent"], now: now, calendar: cal)
        XCTAssertEqual(s2.map(\.uid), ["todayNormal", "important"])
        XCTAssertTrue(HomePriorityEngine.suggestions(tasks, pinned: ["a", "b", "c"], ignored: [], now: now, calendar: cal).isEmpty)
    }

    func testPinnedPrioritiesResetOnANewDay() {
        let now = wednesday10(cal)
        var l = DayScopedList.read("", today: now, calendar: cal)
        XCTAssertTrue(l.add("a", cap: 3)); XCTAssertTrue(l.add("b", cap: 3)); XCTAssertTrue(l.add("c", cap: 3))
        XCTAssertFalse(l.add("d", cap: 3))
        XCTAssertFalse(l.add("a", cap: 3))
        let raw = l.raw
        XCTAssertEqual(DayScopedList.read(raw, today: now, calendar: cal).ids, ["a", "b", "c"])
        let nextDay = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(DayScopedList.read(raw, today: nextDay, calendar: cal).ids, [])
    }
}
