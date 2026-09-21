import XCTest
@testable import LifeOS

/// Duree moyenne du cycle.
///
/// Le defaut corrige valait la peine d'un test: l'ecran Historique mesurait
/// l'ecart entre deux ENTREES consecutives avec flux, en ne gardant que les
/// ecarts de plus de 20 jours. Quand on enregistre son flux chaque jour de
/// ses regles, les ecarts recents valent 1 jour et sont tous rejetes, donc la
/// section "Stats" restait vide. L'utilisatrice la plus reguliere etait celle
/// qui ne voyait jamais rien.
final class CycleStatsTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h)) ?? .distantPast
    }

    /// Cinq jours de flux, puis cinq autres 28 jours plus tard.
    private func period(from start: Date, days: Int = 5) -> [Date] {
        (0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: - Le cas qui ne marchait pas

    /// Trois cycles de 28 jours, flux note tous les jours: la moyenne doit
    /// sortir. C'est exactement ce que l'ancien calcul ne savait pas faire.
    func testDailyLoggingStillGivesAnAverage() {
        let days = period(from: d(2026, 1, 5))
            + period(from: d(2026, 2, 2))
            + period(from: d(2026, 3, 2))
        let s = CycleStats.summary(flowDays: days, calendar: cal)
        XCTAssertEqual(s?.averageDays, 28)
        XCTAssertEqual(s?.cycleCount, 2, "trois règles donnent deux cycles")
    }

    func testPeriodStartsGroupsConsecutiveDays() {
        let days = period(from: d(2026, 1, 5)) + period(from: d(2026, 2, 2))
        let starts = CycleStats.periodStarts(flowDays: days, calendar: cal)
        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(starts.first, cal.startOfDay(for: d(2026, 1, 5)))
    }

    /// Un jour oublie au milieu des regles ne doit pas les couper en deux.
    func testOneMissedDayDoesNotSplitAPeriod() {
        let days = [d(2026, 1, 5), d(2026, 1, 6), d(2026, 1, 8), d(2026, 1, 9)]
        XCTAssertEqual(CycleStats.periodStarts(flowDays: days, calendar: cal).count, 1)
    }

    /// Trois jours de silence, en revanche, sont bien deux episodes.
    func testThreeDayGapSplitsPeriods() {
        let days = [d(2026, 1, 5), d(2026, 1, 6), d(2026, 1, 10)]
        XCTAssertEqual(CycleStats.periodStarts(flowDays: days, calendar: cal).count, 2)
    }

    // MARK: - Solidite du chiffre

    /// Deux enregistrements le meme jour ne comptent qu'une fois.
    func testSameDayLoggedTwiceCountsOnce() {
        let days = [d(2026, 1, 5, 8), d(2026, 1, 5, 20), d(2026, 2, 2, 9)]
        XCTAssertEqual(CycleStats.periodStarts(flowDays: days, calendar: cal).count, 2)
        XCTAssertEqual(CycleStats.summary(flowDays: days, calendar: cal)?.averageDays, 28)
    }

    /// L'ordre d'arrivee ne doit rien changer: la vue trie a l'envers.
    func testOrderDoesNotMatter() {
        let days = period(from: d(2026, 1, 5)) + period(from: d(2026, 2, 2))
        let a = CycleStats.summary(flowDays: days, calendar: cal)
        let b = CycleStats.summary(flowDays: days.reversed(), calendar: cal)
        XCTAssertEqual(a, b)
    }

    /// Le passage a l'heure d'ete (29 mars 2026 en France) enleve une heure.
    /// En secondes, un cycle de 28 jours en ferait 27,96 et un arrondi vers
    /// le bas donnerait 27. En jours de calendrier, il en fait 28.
    func testDaylightSavingDoesNotShortenACycle() {
        let days = period(from: d(2026, 3, 10)) + period(from: d(2026, 4, 7))
        let s = CycleStats.summary(flowDays: days, calendar: cal)
        XCTAssertEqual(s?.averageDays, 28, "un cycle à cheval sur l'heure d'été fait bien 28 jours")
    }

    /// Une longue interruption d'usage n'est pas un cycle de six mois.
    func testImplausibleGapIsIgnored() {
        let days = period(from: d(2026, 1, 5))
            + period(from: d(2026, 2, 2))
            + period(from: d(2026, 9, 1))   // six mois sans rien noter
        let s = CycleStats.summary(flowDays: days, calendar: cal)
        XCTAssertEqual(s?.averageDays, 28)
        XCTAssertEqual(s?.cycleCount, 1)
    }

    func testShortestAndLongest() {
        let days = period(from: d(2026, 1, 1))
            + period(from: d(2026, 1, 27))   // 26 jours
            + period(from: d(2026, 3, 2))    // 34 jours
        let s = CycleStats.summary(flowDays: days, calendar: cal)
        XCTAssertEqual(s?.shortestDays, 26)
        XCTAssertEqual(s?.longestDays, 34)
        XCTAssertFalse(s?.isRegular ?? true, "8 jours d'écart, ce n'est pas régulier")
    }

    func testRegularWhenSpreadIsSmall() {
        let days = period(from: d(2026, 1, 1))
            + period(from: d(2026, 1, 29))   // 28
            + period(from: d(2026, 2, 27))   // 29
        XCTAssertTrue(CycleStats.summary(flowDays: days, calendar: cal)?.isRegular ?? false)
    }

    /// Seules les regles recentes comptent: un cycle d'il y a deux ans ne
    /// doit pas peser sur la moyenne affichee aujourd'hui.
    func testOnlyRecentCyclesAreAveraged() {
        var days: [Date] = []
        var start = d(2026, 1, 1)
        for _ in 0..<10 {
            days += period(from: start)
            start = cal.date(byAdding: .day, value: 28, to: start) ?? start
        }
        XCTAssertEqual(CycleStats.summary(flowDays: days, calendar: cal)?.cycleCount,
                       CycleStats.window)
    }

    // MARK: - Pas assez de donnees

    func testNoDataGivesNil() {
        XCTAssertNil(CycleStats.summary(flowDays: [], calendar: cal))
    }

    /// Un seul episode de regles ne permet aucune moyenne: mieux vaut ne rien
    /// afficher qu'afficher zero jour.
    func testSinglePeriodGivesNil() {
        XCTAssertNil(CycleStats.summary(flowDays: period(from: d(2026, 1, 5)), calendar: cal))
    }

    /// Deux episodes trop rapproches pour etre deux cycles: rien de fiable.
    func testTwoPeriodsTooCloseGiveNil() {
        let days = period(from: d(2026, 1, 1), days: 2) + period(from: d(2026, 1, 9), days: 2)
        XCTAssertNil(CycleStats.summary(flowDays: days, calendar: cal))
    }
}
