import XCTest
@testable import LifeOS

/// Lot Nutrition apres l'audit du build 49 : jeune, liste de courses, regimes.
final class FastingStatsTests: XCTestCase {
    func testSummaryCountsReachedAndAverage() {
        let d = Date()
        let s = FastingStats.summary([(d, d.addingTimeInterval(16 * 3600), 16),
                                      (d, d.addingTimeInterval(12 * 3600), 16)])
        XCTAssertEqual(s, .init(count: 2, reached: 1, averageHours: 14))
        XCTAssertEqual(FastingStats.summary([]).count, 0)
    }

    func testCorrectedStartIsNeverInTheFutureNorOlderThan72h() {
        let now = Date()
        XCTAssertEqual(FastingStats.clampStart(now.addingTimeInterval(3600), now: now), now)
        XCTAssertEqual(FastingStats.clampStart(now.addingTimeInterval(-100 * 3600), now: now), now.addingTimeInterval(-72 * 3600))
    }
}

final class ShoppingListOpsTests: XCTestCase {
    func testNoDuplicateOfAnItemStillToBuy() {
        let list = [ShoppingListOps.Item(name: "Lait", checked: false), .init(name: "Pâtes", checked: true)]
        XCTAssertFalse(ShoppingListOps.shouldAdd("  lait ", existing: list))
        XCTAssertTrue(ShoppingListOps.shouldAdd("pates", existing: list), "un article déjà coché peut revenir")
        XCTAssertFalse(ShoppingListOps.shouldAdd("   ", existing: list))
    }

    func testAisleGuess() {
        XCTAssertEqual(Aisle.guess("Yaourt nature"), "Crèmerie")
        XCTAssertEqual(Aisle.guess("baguette"), "Boulangerie")
        XCTAssertEqual(Aisle.guess("éponge"), "Divers")
    }
}

final class AllergenCheckerTests: XCTestCase {
    /// Casher pouvait etre coche sans aucune regle.
    func testKosherHasRules() {
        XCTAssertFalse(AllergenChecker.check("crevettes à l'ail", against: ["Casher"]).isEmpty)
        XCTAssertFalse(AllergenChecker.check("Jambon", against: ["Casher"]).isEmpty)
    }

    /// "noix de coco" bloquait "Sans fruits à coque", "lait d'amande" bloquait le lactose.
    func testHarmlessPhrasesAreNotFlagged() {
        XCTAssertTrue(AllergenChecker.check("lait de coco, noix de coco râpée", against: ["Sans fruits à coque", "Sans lactose"]).isEmpty)
        XCTAssertTrue(AllergenChecker.check("Lait d'amande", against: ["Sans lactose"]).isEmpty)
        XCTAssertFalse(AllergenChecker.check("amandes grillées", against: ["Sans fruits à coque"]).isEmpty)
    }

    func testEUMajorAllergensAndAccents() {
        XCTAssertFalse(AllergenChecker.check("graines de SÉSAME", against: ["Sans sésame"]).isEmpty)
        XCTAssertFalse(AllergenChecker.check("Œufs frais", against: ["Sans œuf"]).isEmpty)
        XCTAssertFalse(AllergenChecker.check("sauce soja", against: ["Sans soja"]).isEmpty)
        XCTAssertTrue(AllergenChecker.check("farine de blé", against: []).isEmpty, "aucun régime coché, rien à signaler")
    }
}
