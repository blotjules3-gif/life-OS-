import XCTest

/// Les cartes de recapitulatif n'affichent que des chiffres mesures.
final class RecapHonestyTests: XCTestCase {
    func testNoInventedValuesInRecapCards() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let s = try String(contentsOf: root.appendingPathComponent("LifeOS/Core/CategoryRecapCards.swift"), encoding: .utf8)
        // Valeurs de repli inventees et statuts ecrits en dur, trouves le 28 septembre.
        for bad in ["?? \"7.5h\"", "?? \"85%\"", "value: \"Actif\"", "value: \"À jour\"",
                    "value: \"Sécurisé\"", "value: \"Prêt\"", "unit: \"L / 2L\"", "max(activeHabits.count, 1)"] {
            XCTAssertFalse(s.contains(bad), "valeur inventee revenue: \(bad)")
        }
    }
}
