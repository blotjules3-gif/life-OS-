import XCTest
import SwiftData
@testable import LifeOS

/// Audit du 1er oct. 2026, outils Productivite et Finances : chaque test echoue sur
/// l'ancien comportement et passe sur le nouveau.
@MainActor
final class AuditFixesProductivityTests: XCTestCase {

    private let cal = Calendar.current

    /// 5 oct. 2026 = lundi.
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Todoo : tri

    func testTodoSortPutsNearestDueFirstAtSamePriority() {
        // Ancien tri (tuple decroissant) : l'echeance la plus lointaine passait devant.
        XCTAssertTrue(ProductivityRules.todoPrecedes(priorityA: 1, dueA: date(5), priorityB: 1, dueB: date(20)))
        XCTAssertFalse(ProductivityRules.todoPrecedes(priorityA: 1, dueA: date(20), priorityB: 1, dueB: date(5)))
    }

    func testTodoSortPutsUndatedLastAndPriorityFirst() {
        XCTAssertTrue(ProductivityRules.todoPrecedes(priorityA: 0, dueA: date(5), priorityB: 0, dueB: nil),
                      "une tache sans date ne passe plus en tete")
        XCTAssertTrue(ProductivityRules.todoPrecedes(priorityA: 2, dueA: nil, priorityB: 0, dueB: date(5)))
    }

    // MARK: - Todoo : recurrence

    func testNextOccurrenceKeepsTimeOfDay() {
        let next = ProductivityRules.nextOccurrence(after: date(5, 10), weekdays: [2, 4], timeOf: date(5, 8, 30))
        XCTAssertEqual(next, date(7, 8, 30), "lundi coche -> mercredi a la meme heure")
    }

    func testCheckingRecurringTodoRollsToNextOccurrence() throws {
        let container = try ModelContainer(for: Schema([TodoItem.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let t = TodoItem(title: "Sport", due: date(5, 8, 30), recurringDaysRaw: "2,4")
        container.mainContext.insert(t)
        ProductivityRules.toggleDone(t, now: date(5, 9))
        XCTAssertFalse(t.done, "une tache recurrente cochee ne disparait plus pour toujours")
        XCTAssertEqual(t.due, date(7, 8, 30))

        // Une ancienne tache recurrente restee cochee se rouvre.
        t.done = true
        ProductivityRules.toggleDone(t, now: date(5, 9))
        XCTAssertFalse(t.done)
    }

    func testRecurringTodoWithoutTimeGetsDateOnlyOccurrence() throws {
        let container = try ModelContainer(for: Schema([TodoItem.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let t = TodoItem(title: "Vaisselle", recurringDaysRaw: "1,2,3,4,5,6,7")
        container.mainContext.insert(t)
        ProductivityRules.toggleDone(t, now: date(5, 15))
        let due = try XCTUnwrap(t.due)
        XCTAssertEqual(due, date(6))
        XCTAssertTrue(ProductivityRules.isDateOnly(due))
        XCTAssertFalse(ProductivityRules.isLate(due, now: date(6, 18)), "pas en retard le jour meme")
        XCTAssertTrue(ProductivityRules.isLate(due, now: date(7, 1)))
    }

    func testNonRecurringTodoStillToggles() throws {
        let container = try ModelContainer(for: Schema([TodoItem.self]),
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let t = TodoItem(title: "Courrier", due: date(5, 9))
        container.mainContext.insert(t)
        ProductivityRules.toggleDone(t, now: date(5, 10))
        XCTAssertTrue(t.done)
        XCTAssertEqual(t.due, date(5, 9))
    }

    // MARK: - Habitly : serie

    func testStreakSkipsInactiveDays() {
        // Lundi a vendredi, coche du lun. 5 au ven. 9 puis lun. 12.
        let done = [5, 6, 7, 8, 9, 12].map { date($0, 8) }
        let s = ProductivityRules.habitStreak(completions: done, activeDays: [2, 3, 4, 5, 6], now: date(12, 20))
        XCTAssertEqual(s, 6, "le week-end inactif ne remet plus la serie a 1 le lundi")
    }

    func testStreakTodayNotDoneDoesNotBreakButMissedDayDoes() {
        let done = [5, 6, 7, 8, 9].map { date($0, 8) }
        XCTAssertEqual(ProductivityRules.habitStreak(completions: done, activeDays: [2, 3, 4, 5, 6], now: date(12, 9)), 5)
        let gap = [5, 6, 8, 9].map { date($0, 8) }   // mercredi 7 manque
        XCTAssertEqual(ProductivityRules.habitStreak(completions: gap, activeDays: [2, 3, 4, 5, 6], now: date(9, 20)), 2)
    }

    func testAverageStreakIsMeanOfStreaksNotCompletionCount() {
        XCTAssertEqual(ProductivityRules.averageStreak([3, 4]), 4)
        XCTAssertEqual(ProductivityRules.averageStreak([]), 0)
    }

    // MARK: - Todoo : calendrier

    func testCalendarAddIsDeduplicated() {
        let sig = ProductivityRules.calendarSignature(title: "Dentiste", due: date(8, 14))
        XCTAssertEqual(ProductivityRules.calendarDecision(stored: nil, current: sig), .add)
        XCTAssertEqual(ProductivityRules.calendarDecision(stored: sig, current: sig), .alreadyAdded)
        let moved = ProductivityRules.calendarSignature(title: "Dentiste", due: date(9, 14))
        XCTAssertEqual(ProductivityRules.calendarDecision(stored: sig, current: moved), .addAgainAfterChange)
    }

    // MARK: - Pocket Money : prochain prelevement

    func testNextChargeDateAdvancesByCycleWithoutDrift() {
        let start = date(31, month: 1)
        XCTAssertEqual(SubscriptionsView.nextChargeDate(from: start, cycle: "Mensuel", now: date(15, month: 3)),
                       date(31, month: 3), "31 janv. -> 31 mars, pas 28")
        XCTAssertEqual(SubscriptionsView.nextChargeDate(from: date(10, month: 2), cycle: "Annuel", now: date(1, month: 10)),
                       date(10, month: 2, year: 2027))
        let future = date(20, month: 12)
        XCTAssertEqual(SubscriptionsView.nextChargeDate(from: future, cycle: "Mensuel", now: date(1)), future)
    }

    // MARK: - Kapital : etat de l'objectif

    func testSavingsWithoutMonthlyEffortIsNotReached() {
        XCTAssertNotEqual(SavingsView.status(target: 1000, current: 200, monthly: 0), "Objectif atteint")
        XCTAssertEqual(SavingsView.status(target: 1000, current: 1000, monthly: 0), "Objectif atteint")
        XCTAssertTrue(SavingsView.status(target: 1000, current: 400, monthly: 100).contains("6 mois"))
    }

    // MARK: - Quadricount : membres

    func testSplitMembersHaveNoInventedPeople() {
        XCTAssertEqual(SplitView.members(raw: "Moi", expenseNames: []), ["Moi"])
        XCTAssertEqual(SplitView.members(raw: "Moi,Lea", expenseNames: ["Moi", " Hugo", "Lea"]), ["Moi", "Lea", "Hugo"],
                       "une personne deja dans une depense reste dans les soldes")
    }
}
