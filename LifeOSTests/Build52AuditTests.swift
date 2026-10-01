import XCTest
import SwiftData
@testable import LifeOS

/// Audit du build 52, Finario : le prix d'achat n'avait pas de devise alors que le cours
/// est converti en euros. Un titre US saisi en dollars donnait une fausse plus-value.
@MainActor
final class FinarioCurrencyTests: XCTestCase {

    func testCostIsConvertedAtThePurchaseDayRate() {
        // 10 actions a 100 USD, 1 USD = 0,90 EUR le jour d'achat : 900 EUR de cout.
        XCTAssertEqual(HoldingMath.costEUR(quantity: 10, buyPrice: 100, currency: "USD", fxToEUR: 0.9) ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(HoldingMath.costEUR(quantity: 10, buyPrice: 100, currency: "EUR", fxToEUR: 0) ?? 0, 1000, accuracy: 0.001)
    }

    func testUnknownCurrencyOrRateGivesNoGainRatherThanAWrongOne() {
        XCTAssertNil(HoldingMath.costEUR(quantity: 10, buyPrice: 100, currency: "", fxToEUR: 1), "position d'avant : devise inconnue")
        XCTAssertNil(HoldingMath.costEUR(quantity: 10, buyPrice: 100, currency: "GBP", fxToEUR: 0), "taux indisponible")
        XCTAssertNil(HoldingMath.pnlPct(value: 1200, cost: nil))
    }

    func testLegacyHoldingHasUnknownCurrencyAndNoGain() throws {
        let c = try ModelContainer(for: Holding.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let h = Holding(symbol: "AAPL", kind: "Action", quantity: 10, buyPrice: 150, currentPrice: 160)
        h.buyCurrency = ""   // ce qu'une position d'avant la mise à jour reçoit à la migration
        ctx.insert(h)
        XCTAssertNil(h.pnl)
        XCTAssertNil(h.pnlPct)
        XCTAssertEqual(h.value, 1600, accuracy: 0.001, "la valeur actuelle reste juste")
    }

    func testMixedPortfolioTotalsOnlyCountKnownCosts() {
        let t = HoldingMath.totals([(value: 1100, cost: 1000), (value: 500, cost: nil), (value: 300, cost: 400)])
        XCTAssertEqual(t.value, 1900, accuracy: 0.001)
        XCTAssertEqual(t.pnl, 0, accuracy: 0.001, "+100 et -100")
        XCTAssertEqual(t.costKnown, 1400, accuracy: 0.001)
        XCTAssertEqual(t.excluded, 1)
    }

    func testHistoricalRateParsingAndPence() {
        let json = Data(#"{"amount":1.0,"base":"EUR","date":"2024-01-12","rates":{"USD":1.0942}}"#.utf8)
        let r = ExchangeRates.parseHistorical(json, code: "USD")
        XCTAssertEqual(r?.eurPerUnit ?? 0, 1 / 1.0942, accuracy: 1e-9)
        XCTAssertEqual(r?.day, "2024-01-12", "un samedi rend le vendredi : la date réelle est gardée")
        XCTAssertNil(ExchangeRates.parseHistorical(Data("{}".utf8), code: "USD"))
        // Londres : cours en pence ramené en livres avant conversion (audit du 1er oct.).
        XCTAssertEqual(StockService.normalized(price: 2500, currency: "GBp").price, 25)
    }
}

/// Superset en seance (lot 6) : pas de repos entre les deux exercices d'une paire.
@MainActor
final class SupersetSessionTests: XCTestCase {
    func testNoRestBetweenTheTwoExercisesOfAPair() {
        let s = TrainingSession(title: "Haut")
        s.supersetsJSON = FitbotSupersets.encode([["Développé couché", "Rowing barre"]])
        XCTAssertEqual(GymSessionService.restSeconds(after: "Développé couché 4×8", in: s, default: 90), 0)
        XCTAssertEqual(GymSessionService.restSeconds(after: "Rowing barre", in: s, default: 90), 90)
        XCTAssertEqual(GymSessionService.restSeconds(after: "Curl", in: s, default: 90), 90)
        XCTAssertEqual(GymSessionService.supersetPartner(of: "Rowing barre", in: s), "Développé couché")
    }
}

/// Bouton « Oui » de la notification de complément (lot 6) : la prise est notée une fois.
@MainActor
final class SupplementNotificationDoseTests: XCTestCase {
    func testSlotIsTheLastPlannedTimeAlreadyPassed() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Paris")!
        let t = [SupplementSchedule.Time(hour: 8, minute: 0), SupplementSchedule.Time(hour: 20, minute: 0)]
        let at = { (h: Int) in c.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: h))! }
        XCTAssertEqual(SupplementDoseLog.slot(for: at(9), times: t, calendar: c), t[0])
        XCTAssertEqual(SupplementDoseLog.slot(for: at(21), times: t, calendar: c), t[1])
        XCTAssertEqual(SupplementDoseLog.slot(for: at(6), times: t, calendar: c), t[0], "prise en avance")
    }

    func testYesLogsOnceAndLowersStock() throws {
        let c = try ModelContainer(for: Supplement.self, SupplementDose.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let s = Supplement(name: "Vitamine D", hour: 8, minute: 0, active: true, moment: "matin")
        s.stableID = "abc"; s.trackStock = true; s.stock = 10; s.unitsPerDose = 1
        ctx.insert(s); try ctx.save()
        XCTAssertTrue(SupplementDoseLog.logTaken(confirmKey: "supp.abc", in: ctx))
        XCTAssertFalse(SupplementDoseLog.logTaken(confirmKey: "supp.abc", in: ctx), "pas deux fois pour la même heure")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SupplementDose>()).count, 1)
        XCTAssertEqual(s.stock, 9)
        XCTAssertFalse(SupplementDoseLog.logTaken(confirmKey: "workout.x", in: ctx))
    }
}
