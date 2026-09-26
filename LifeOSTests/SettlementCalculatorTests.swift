import XCTest
@testable import LifeOS

/// Les deux cas exacts demandes par l'audit : soldes -100 / +60 / +40, et 10 € a trois.
final class SettlementCalculatorTests: XCTestCase {

    /// L'ancien code disait "doit 100 a X" : toute la dette vers UN seul crediteur.
    /// Il faut deux virements, et la somme doit couvrir exactement les deux creances.
    func testThreeWayDebtNeedsTwoTransfers() {
        let t = SettlementCalculator.settle(balancesCents: ["A": -10_000, "B": 6_000, "C": 4_000])
        XCTAssertEqual(t.count, 2, "un seul virement ne peut pas solder deux crediteurs")
        XCTAssertTrue(t.allSatisfy { $0.from == "A" })
        XCTAssertEqual(t.reduce(0) { $0 + $1.cents }, 10_000, "le total rembourse doit egaler la dette")
        XCTAssertEqual(Set(t.map(\.to)), ["B", "C"])
        XCTAssertEqual(t.first(where: { $0.to == "B" })?.cents, 6_000)
        XCTAssertEqual(t.first(where: { $0.to == "C" })?.cents, 4_000)
    }

    /// 10 € a trois : les parts doivent redonner 10,00 € exactement.
    func testTenEurosBetweenThreeLosesNothing() {
        let parts = SettlementCalculator.split(totalCents: 1_000, between: 3)
        XCTAssertEqual(parts.reduce(0, +), 1_000, "aucun centime ne doit disparaitre")
        XCTAssertEqual(parts.sorted(), [333, 333, 334])
    }

    func testSplitHandlesExactDivisionAndSinglePerson() {
        XCTAssertEqual(SettlementCalculator.split(totalCents: 900, between: 3), [300, 300, 300])
        XCTAssertEqual(SettlementCalculator.split(totalCents: 1_000, between: 1), [1_000])
        XCTAssertEqual(SettlementCalculator.split(totalCents: 0, between: 4).reduce(0, +), 0)
        XCTAssertTrue(SettlementCalculator.split(totalCents: 100, between: 0).isEmpty,
                      "aucun participant ne doit pas planter")
    }

    /// Un remboursement (montant negatif) garde une somme exacte, sans centime en trop.
    func testNegativeTotalStillSumsBack() {
        let parts = SettlementCalculator.split(totalCents: -1_000, between: 3)
        XCTAssertEqual(parts.reduce(0, +), -1_000)
    }

    func testBalancedGroupSaysSo() {
        XCTAssertEqual(SettlementCalculator.hint(balancesCents: ["A": 0, "B": 0]), "Tout est équilibré")
    }

    /// Plus de troncature : 99,99 € ne doit pas s'afficher 99 €.
    func testCentsAreShownNotTruncated() {
        let s = SettlementCalculator.hint(balancesCents: ["A": -9_999, "B": 9_999])
        XCTAssertTrue(s.contains("99") && s.contains("99"), s)
        XCTAssertFalse(s.hasSuffix("99€."), "l'ancien rendu tronquait a l'euro")
    }

    /// Cas plus large : la somme des virements solde tout le monde.
    func testEveryoneEndsAtZero() {
        let balances = ["A": -5_050, "B": -1_950, "C": 3_000, "D": 4_000]
        var result = balances
        for t in SettlementCalculator.settle(balancesCents: balances) {
            result[t.from, default: 0] += t.cents
            result[t.to, default: 0]   -= t.cents
        }
        XCTAssertTrue(result.values.allSatisfy { $0 == 0 }, "soldes restants: \(result)")
    }
}
