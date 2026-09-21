import XCTest
@testable import LifeOS

/// Remise a zero mensuelle d'une enveloppe de budget.
///
/// Le bug corrige: `spent` etait stocke sans marqueur de mois et sans remise
/// a zero. Un budget dit MENSUEL cumulait donc depuis la creation, et un
/// depassement en janvier laissait la barre rouge pour toujours.
///
/// Les bascules de date sont exactement le genre de logique qu'on ne peut pas
/// verifier a la main: il faudrait attendre le mois suivant. La date est donc
/// injectee.
final class EnvelopeRolloverTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? .distantPast
    }

    func testSameMonthKeepsSpending() {
        let e = Envelope(name: "Courses", monthlyBudget: 400, spent: 120,
                         periodStart: date(2026, 3, 1))
        let changed = e.rolloverIfNeeded(now: date(2026, 3, 28), calendar: cal)
        XCTAssertFalse(changed)
        XCTAssertEqual(e.spent, 120, "on ne remet pas a zero au milieu du mois")
    }

    func testNewMonthResetsSpending() {
        let e = Envelope(name: "Courses", monthlyBudget: 400, spent: 380,
                         periodStart: date(2026, 3, 1))
        let changed = e.rolloverIfNeeded(now: date(2026, 4, 1), calendar: cal)
        XCTAssertTrue(changed)
        XCTAssertEqual(e.spent, 0)
        XCTAssertEqual(e.remaining, 400, "le plafond doit redevenir entier")
    }

    /// Le cas qui rendait l'enveloppe rouge a vie.
    func testOverspentEnvelopeRecoversNextMonth() {
        let e = Envelope(name: "Loisirs", monthlyBudget: 100, spent: 250,
                         periodStart: date(2026, 1, 15))
        XCTAssertLessThan(e.remaining, 0)
        e.rolloverIfNeeded(now: date(2026, 2, 1), calendar: cal)
        XCTAssertEqual(e.spent, 0)
        XCTAssertGreaterThan(e.remaining, 0, "l'enveloppe ne doit pas rester rouge le mois suivant")
    }

    /// Une app ouverte apres plusieurs mois d'absence ne doit pas rejouer
    /// plusieurs remises a zero, juste repartir du mois courant.
    func testLongAbsenceRollsOverOnce() {
        let e = Envelope(name: "Abonnements", monthlyBudget: 60, spent: 55,
                         periodStart: date(2025, 11, 3))
        let changed = e.rolloverIfNeeded(now: date(2026, 4, 9), calendar: cal)
        XCTAssertTrue(changed)
        XCTAssertEqual(e.spent, 0)
        XCTAssertEqual(e.periodStart, date(2026, 4, 1, 0), "on repart du 1er du mois courant")
        // Deuxieme appel le meme mois: plus rien a faire.
        XCTAssertFalse(e.rolloverIfNeeded(now: date(2026, 4, 20), calendar: cal))
    }

    /// Passage d'annee: decembre vers janvier est un nouveau mois.
    func testYearBoundary() {
        let e = Envelope(name: "Cadeaux", monthlyBudget: 200, spent: 190,
                         periodStart: date(2026, 12, 1))
        XCTAssertTrue(e.rolloverIfNeeded(now: date(2027, 1, 1), calendar: cal))
        XCTAssertEqual(e.spent, 0)
    }

    /// Le dernier jour du mois est encore le meme mois, meme tard le soir.
    func testLastDayOfMonthIsStillSameMonth() {
        let e = Envelope(name: "Essence", monthlyBudget: 150, spent: 90,
                         periodStart: date(2026, 1, 1))
        XCTAssertFalse(e.rolloverIfNeeded(now: date(2026, 1, 31, 23), calendar: cal))
        XCTAssertEqual(e.spent, 90)
    }

    /// Fevrier d'une annee bissextile: le 29 existe et reste dans le mois.
    func testLeapYearFebruary() {
        let e = Envelope(name: "Test", monthlyBudget: 100, spent: 40,
                         periodStart: date(2028, 2, 1))
        XCTAssertFalse(e.rolloverIfNeeded(now: date(2028, 2, 29), calendar: cal))
        XCTAssertTrue(e.rolloverIfNeeded(now: date(2028, 3, 1), calendar: cal))
    }

    /// Une enveloppe qui vient d'etre creee ne doit pas se vider aussitot.
    func testFreshEnvelopeDoesNotRollOverImmediately() {
        let now = date(2026, 5, 10)
        let e = Envelope(name: "Neuve", monthlyBudget: 300, spent: 25, periodStart: now)
        XCTAssertFalse(e.rolloverIfNeeded(now: now, calendar: cal))
        XCTAssertEqual(e.spent, 25)
    }
}
