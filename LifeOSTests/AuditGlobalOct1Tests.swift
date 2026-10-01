import XCTest
@testable import LifeOS

/// Audit global du 1er oct. 2026 : les totaux lus par le coach et les widgets ne se
/// mettaient a jour qu'a l'ajout ou la suppression (onChange sur `.count`). Corriger les
/// calories d'un repas, une serie, une humeur ou une nuit gardait l'ancien total jusqu'a
/// la reouverture de l'app. Garde : ces vues observent les valeurs, plus le nombre.
final class AuditGlobalOct1Tests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testSyncersWatchValuesNotCounts() throws {
        let checks: [(String, [String])] = [
            ("LifeOS/Services/LifeSignalSyncer.swift", ["foods.count", "waters.count", "moods.count", "nights.count", "memories.count"]),
            ("LifeOS/Core/MainTabView.swift", ["sets.count"]),
            ("LifeOS/Modules/CalAIView.swift", ["foods.count"]),
            ("LifeOS/Modules/NutritionModule.swift", ["onChange(of: entries.count)"]),
        ]
        for (file, banned) in checks {
            let s = try source(file)
            for b in banned {
                XCTAssertFalse(s.contains("onChange(of: \(b)") || s.contains(b.hasPrefix("onChange") ? b : "onChange(of: \(b))"),
                               "\(file) observe encore \(b) : une modification ne rafraichit pas les totaux")
            }
        }
    }

    // Impots+ : avec le plafonnement, la tranche suit les parts de base.
    func testMarginalRateFollowsBasePartsWhenTheCapApplies() {
        let r = FrenchTax.compute(income: 250_000, parts: 3, status: .couple)
        XCTAssertGreaterThan(r.capLoss, 0, "le plafonnement s'applique bien ici")
        XCTAssertEqual(r.marginalRate, 0.41, accuracy: 0.0001, "250 000 / 2 parts = 125 000 par part : 41 %, pas 30 %")
        let uncapped = FrenchTax.compute(income: 60_000, parts: 3, status: .couple)
        XCTAssertEqual(uncapped.capLoss, 0)
        XCTAssertEqual(uncapped.marginalRate, 0.11, accuracy: 0.0001, "sans plafonnement : parts totales (20 000 par part)")
    }

    func testThirdChildCountsAWholePart() {
        XCTAssertEqual(FrenchTax.parts(status: .couple, children: 0), 2)
        XCTAssertEqual(FrenchTax.parts(status: .couple, children: 2), 3)
        XCTAssertEqual(FrenchTax.parts(status: .couple, children: 3), 4, "pas 3,5")
        XCTAssertEqual(FrenchTax.parts(status: .single, children: 4), 4)
    }

    // Finario : Yahoo cote Londres en pence.
    func testPenceQuotesAreConvertedToPounds() {
        let q = StockService.normalized(price: 1234, currency: "GBp")
        XCTAssertEqual(q.price, 12.34, accuracy: 0.0001)
        XCTAssertEqual(q.currency, "GBP")
        XCTAssertEqual(StockService.normalized(price: 10, currency: "usd").currency, "USD")
        XCTAssertEqual(StockService.normalized(price: 500, currency: "ZAc").price, 5)
    }
}

final class ToolRouteTests: XCTestCase {
    func testTrilingoReminderOpensTheLesson() {
        let t = ToolRoute.target(for: "trilingo")
        XCTAssertEqual(t?.category, .learning)
        XCTAssertNotNil(t.flatMap { ToolRoute.tool($0.tool, in: $0.category) }, "l'outil existe bien dans sa catégorie")
        XCTAssertNil(ToolRoute.target(for: "inconnu"))
    }
}
