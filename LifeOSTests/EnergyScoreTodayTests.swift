import XCTest
@testable import LifeOS

/// Le score du jour ne doit lire que des donnees du jour, ne pas punir un jour
/// de repos, et suivre les objectifs de l'utilisateur.
final class EnergyScoreTodayTests: XCTestCase {

    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Paris")!; return c }()
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 14))! }
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: now)! }

    func testYesterdaysSleepIsNotTodaysSleep() {
        let raw = EnergyScore.Raw(sleepHours: 8, sleepQuality: 5, sleepRecordedAt: yesterday,
                                  moods: [(now, 3)])
        let e = EnergyScore.explain(raw, goals: .standard, now: now, calendar: cal)
        XCTAssertEqual(e.result.coverage, 0.15, accuracy: 0.001, "seule l'humeur doit compter")
        let sleep = e.parts.first { $0.name == "Sommeil" }
        XCTAssertEqual(sleep?.used, false)
        XCTAssertTrue(sleep?.detail.contains("trop ancienne") == true)
    }

    func testThisMorningsSleepCounts() {
        let morning = cal.date(bySettingHour: 7, minute: 30, second: 0, of: now)!
        let raw = EnergyScore.Raw(sleepHours: 8, sleepQuality: 5, sleepRecordedAt: morning)
        let e = EnergyScore.explain(raw, goals: .standard, now: now, calendar: cal)
        XCTAssertEqual(e.result.score, 100)
        XCTAssertEqual(e.parts.first { $0.name == "Sommeil" }?.used, true)
    }

    func testRestDayDoesNotLowerTheScore() {
        let base = EnergyScore.Raw(moods: [(now, 4)], waters: [(now, 2500)])
        var rest = base
        rest.habits = [.init(plannedToday: false, doneToday: false), .init(plannedToday: false, doneToday: false)]
        let a = EnergyScore.explain(base, goals: .standard, now: now, calendar: cal).result
        let b = EnergyScore.explain(rest, goals: .standard, now: now, calendar: cal).result
        XCTAssertEqual(a, b, "des habitudes non prevues aujourd'hui ne doivent rien changer")

        var busy = base
        busy.habits = [.init(plannedToday: true, doneToday: false), .init(plannedToday: false, doneToday: false)]
        let c = EnergyScore.explain(busy, goals: .standard, now: now, calendar: cal)
        XCTAssertLessThan(c.result.score, a.score, "une habitude prevue et pas faite compte")
        XCTAssertTrue(c.parts.contains { $0.detail == "0 sur 1 prévues aujourd'hui" })
    }

    func testPersonalWaterGoalIsUsed() {
        let raw = EnergyScore.Raw(moods: [(now, 5)], waters: [(now, 1500)])
        let fixed = EnergyScore.explain(raw, goals: .standard, now: now, calendar: cal).result.score
        let mine = EnergyScore.explain(raw, goals: .init(waterML: 1500, sleepHours: 8), now: now, calendar: cal).result.score
        XCTAssertEqual(mine, 100, "1 500 ml bus sur 1 500 ml visés = objectif atteint")
        XCTAssertLessThan(fixed, mine)
    }

    func testLatestMoodOfTheDayWins() {
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: now)!
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        // Ordre de lecture volontairement inverse.
        let raw = EnergyScore.Raw(moods: [(noon, 5), (morning, 1), (yesterday, 3)])
        XCTAssertEqual(EnergyScore.explain(raw, goals: .standard, now: now, calendar: cal).result.score, 100)
    }

    func testOldWaterDoesNotCountToday() {
        let raw = EnergyScore.Raw(moods: [(now, 5)], waters: [(yesterday, 3000)])
        let e = EnergyScore.explain(raw, goals: .standard, now: now, calendar: cal)
        XCTAssertEqual(e.parts.first { $0.name == "Eau" }?.used, false)
    }

    func testEveryShownScoreListsItsInputs() {
        let raw = EnergyScore.Raw(sleepHours: 7, sleepQuality: 4, sleepRecordedAt: now, moods: [(now, 4)])
        let e = EnergyScore.explain(raw, goals: .standard, now: now, calendar: cal)
        XCTAssertTrue(e.isShown)
        XCTAssertEqual(Set(e.parts.map(\.name)), ["Sommeil", "Humeur", "Eau"])
    }
}
