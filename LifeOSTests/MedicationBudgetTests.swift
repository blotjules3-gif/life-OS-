import XCTest
@testable import LifeOS

/// Budget commun des rappels: iOS en garde 64 par app, tous usages confondus.
final class MedicationBudgetTests: XCTestCase {

    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Paris")!; return c }()
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 6))! }

    private func dated(_ med: String, count: Int, perDay: Int) -> [MedicationBudget.Item] {
        (0..<count).map { i in
            .init(medID: med, identifier: "\(med).d\(i)",
                  fireDate: now.addingTimeInterval(Double(i / perDay) * 86_400 + Double(i % perDay) * 3600))
        }
    }

    /// L'audit: 60 jours a 3 prises ne couvraient que 7 jours (plafond de 24 par medicament).
    func testLongCourseUsesTheSharedBudgetNotAPerMedicationCap() {
        let plan = MedicationSchedule.plan(frequency: "3x/jour", hourMorning: 8, hourEvening: 20, active: true,
                                           startDate: now, endDate: now.addingTimeInterval(60 * 86_400), now: now,
                                           calendar: cal, horizonDays: 90, maxDates: 64)
        guard case .dates(let dates) = plan else { return XCTFail("\(plan)") }
        XCTAssertEqual(dates.count, 64)
        let items = dates.enumerated().map { MedicationBudget.Item(medID: "a", identifier: "a.d\($0.offset)", fireDate: $0.element) }
        let (chosen, coverage) = MedicationBudget.select(items, budget: 56)
        XCTAssertEqual(chosen.count, 56)
        guard case .until(let last) = coverage["a"] else { return XCTFail() }
        XCTAssertGreaterThan(last.timeIntervalSince(now), 17 * 86_400, "plus de deux semaines, pas 7 jours")
    }

    func testRepeatingRemindersComeFirstAndCoverWithoutEnd() {
        let rep = [MedicationBudget.Item(medID: "r", identifier: "r.0", fireDate: nil)]
        let (chosen, coverage) = MedicationBudget.select(dated("d", count: 100, perDay: 2) + rep, budget: 10)
        XCTAssertEqual(chosen.first?.identifier, "r.0")
        XCTAssertEqual(coverage["r"], .unlimited)
        XCTAssertEqual(chosen.count, 10)
    }

    /// Deux traitements se partagent la place par date, aucun n'est affame.
    func testTwoCoursesShareTheBudgetByDate() {
        let (chosen, coverage) = MedicationBudget.select(dated("a", count: 60, perDay: 3) + dated("b", count: 60, perDay: 1), budget: 40)
        XCTAssertEqual(chosen.count, 40)
        XCTAssertTrue(chosen.contains { $0.medID == "a" } && chosen.contains { $0.medID == "b" })
        let dates = chosen.compactMap(\.fireDate)
        XCTAssertEqual(dates, dates.sorted(), "les plus proches d'abord")
        if case .until = coverage["a"], case .until = coverage["b"] {} else { XCTFail() }
    }

    func testNoRoomMeansNoCoverageIsShown() {
        let (chosen, coverage) = MedicationBudget.select(dated("a", count: 5, perDay: 1), budget: 0)
        XCTAssertTrue(chosen.isEmpty)
        XCTAssertEqual(coverage["a"], MedicationBudget.Coverage.none)
    }

    func testFutureStartAndEndedCourse() {
        let future = MedicationSchedule.plan(frequency: "1x/jour", hourMorning: 9, hourEvening: nil, active: true,
                                             startDate: now.addingTimeInterval(10 * 86_400), endDate: nil, now: now,
                                             calendar: cal, horizonDays: 90, maxDates: 64)
        guard case .dates(let d) = future else { return XCTFail() }
        XCTAssertGreaterThanOrEqual(d.first!, now.addingTimeInterval(9 * 86_400), "rien avant le debut")
        let ended = MedicationSchedule.plan(frequency: "1x/jour", hourMorning: 9, hourEvening: nil, active: true,
                                            startDate: now.addingTimeInterval(-20 * 86_400), endDate: now.addingTimeInterval(-86_400),
                                            now: now, calendar: cal)
        XCTAssertEqual(ended, .none)
    }

    /// Des rappels dates restent a l'heure locale: 9 h reste 9 h apres un changement d'heure.
    func testDatedRemindersKeepLocalClockTimeAcrossDST() {
        let beforeDST = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 6))!
        let plan = MedicationSchedule.plan(frequency: "1x/jour", hourMorning: 9, hourEvening: nil, active: true,
                                           startDate: beforeDST, endDate: beforeDST.addingTimeInterval(20 * 86_400),
                                           now: beforeDST, calendar: cal, horizonDays: 90, maxDates: 64)
        guard case .dates(let d) = plan else { return XCTFail() }
        XCTAssertTrue(d.allSatisfy { cal.component(.hour, from: $0) == 9 }, "le 25 octobre (heure d'hiver) compris")
    }
}
