import XCTest
@testable import LifeOS

/// Les rappels d'un traitement respectent la frequence ET les bornes.
///
/// Defaut corrige (audit du 28 septembre): une date de fin envoyait toujours vers
/// la branche quotidienne, donc un traitement hebdomadaire avec fin sonnait tous
/// les jours.
final class MedicationPlanTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // lundi 28 septembre 2026, 10:00
    private var now: Date { date(2026, 9, 28, 10) }

    private func dates(_ p: MedicationSchedule.Plan) -> [Date] {
        if case .dates(let d) = p { return d }
        XCTFail("attendu des dates, recu \(p)"); return []
    }

    func testWeeklyWithEndDateStaysWeekly() {
        let p = MedicationSchedule.plan(frequency: "1x/semaine", hourMorning: 9, hourEvening: nil,
                                        active: true, startDate: date(2026, 9, 29), endDate: date(2026, 10, 20),
                                        now: now, calendar: cal)
        let ds = dates(p)
        XCTAssertEqual(ds.count, 2, "14 jours d'avance, un mardi par semaine: 29/09 et 06/10")
        XCTAssertTrue(ds.allSatisfy { cal.component(.weekday, from: $0) == 3 }, "tous des mardis")
    }

    func testDailyWithEndDateIsInclusiveAndSkipsPastTimeToday() {
        let p = MedicationSchedule.plan(frequency: "2x/jour", hourMorning: 8, hourEvening: 20,
                                        active: true, startDate: date(2026, 9, 20), endDate: date(2026, 9, 29),
                                        now: now, calendar: cal)
        let ds = dates(p)
        // aujourd'hui 8h est passe; restent 20h aujourd'hui, 8h et 20h demain (dernier jour inclus)
        XCTAssertEqual(ds, [date(2026, 9, 28, 20), date(2026, 9, 29, 8), date(2026, 9, 29, 20)])
    }

    func testFutureStartWaitsForItsDay() {
        let p = MedicationSchedule.plan(frequency: "1x/jour", hourMorning: 8, hourEvening: nil,
                                        active: true, startDate: date(2026, 10, 5), endDate: nil,
                                        now: now, calendar: cal)
        let ds = dates(p)
        XCTAssertEqual(ds.first, date(2026, 10, 5, 8), "rien avant le debut")
        XCTAssertEqual(ds.count, 8, "du 5 au 12 octobre inclus (14 jours d'avance)")
    }

    func testOpenEndedUsesRepeatingTriggers() {
        XCTAssertEqual(MedicationSchedule.plan(frequency: "1x/jour", hourMorning: 7, hourEvening: nil,
                                               active: true, startDate: date(2026, 9, 1), endDate: nil,
                                               now: now, calendar: cal),
                       .repeatingDaily([.init(hour: 7, minute: 0, label: "matin")]))
        XCTAssertEqual(MedicationSchedule.plan(frequency: "1x/semaine", hourMorning: 7, hourEvening: nil,
                                               active: true, startDate: date(2026, 9, 2), endDate: nil,
                                               now: now, calendar: cal),
                       .repeatingWeekly(weekday: 4, doses: [.init(hour: 7, minute: 0, label: "matin")]),
                       "le jour de semaine vient de la date de debut (mercredi)")
    }

    func testEndedInactiveOrOnDemandSchedulesNothing() {
        let yesterday = date(2026, 9, 27)
        XCTAssertEqual(MedicationSchedule.plan(frequency: "1x/jour", hourMorning: 8, hourEvening: nil,
                                               active: true, startDate: date(2026, 9, 1), endDate: yesterday,
                                               now: now, calendar: cal), .none)
        XCTAssertEqual(MedicationSchedule.plan(frequency: "1x/jour", hourMorning: 8, hourEvening: nil,
                                               active: false, startDate: date(2026, 9, 1), endDate: nil,
                                               now: now, calendar: cal), .none)
        XCTAssertEqual(MedicationSchedule.plan(frequency: "Au besoin", hourMorning: 8, hourEvening: nil,
                                               active: true, startDate: date(2026, 9, 1), endDate: nil,
                                               now: now, calendar: cal), .none)
    }

    func testLongBoundedTreatmentStaysUnderTheNotificationBudget() {
        let p = MedicationSchedule.plan(frequency: "3x/jour", hourMorning: 7, hourEvening: 21,
                                        active: true, startDate: date(2026, 9, 1), endDate: date(2027, 1, 1),
                                        now: now, calendar: cal)
        XCTAssertLessThanOrEqual(dates(p).count, MedicationSchedule.maxDatedPerMedication)
    }
}
