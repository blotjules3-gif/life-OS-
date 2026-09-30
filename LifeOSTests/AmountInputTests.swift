import XCTest
@testable import LifeOS

final class AmountInputTests: XCTestCase {

    private func v(_ s: String, _ r: AmountInput.Rules = .positive) -> Double? { AmountInput.parse(s, rules: r).value }

    func testCommonFormats() {
        XCTAssertEqual(v("12,50"), 12.5)
        XCTAssertEqual(v("12.50"), 12.5)
        XCTAssertEqual(v(" 12 "), 12)
        XCTAssertEqual(v("1 234,56"), 1234.56)
        XCTAssertEqual(v("1\u{202F}234,56"), 1234.56)     // fine insecable, format francais d'iOS
        XCTAssertEqual(v("1.234,56"), 1234.56)
        XCTAssertEqual(v("1,234.56"), 1234.56)
        XCTAssertEqual(v("1.234.567"), 1_234_567)
        XCTAssertEqual(v("12 €"), 12)
        XCTAssertEqual(v("€12,5"), 12.5)
        XCTAssertEqual(v(",5"), 0.5)
    }

    /// Le defaut du brief: du texte invalide devenait 0 et s'enregistrait.
    func testInvalidTextIsAnErrorNotZero() {
        for bad in ["abc", "12a", "1,2,3", "1.23.4", "12,50,3", "1.234,5,6", "--3", "1,23.456,7"] {
            let p = AmountInput.parse(bad)
            XCTAssertNil(p.value, "« \(bad) » ne doit pas donner de montant")
            XCTAssertNotNil(p.message, "« \(bad) » doit expliquer l'erreur")
        }
    }

    func testRules() {
        XCTAssertNotNil(AmountInput.parse("", rules: .positive).message, "obligatoire")
        XCTAssertEqual(AmountInput.parse("", rules: .optional), .empty)
        XCTAssertNotNil(AmountInput.parse("0").message, "zero refuse par defaut")
        XCTAssertNotNil(AmountInput.parse("-5").message, "negatif refuse par defaut")
        XCTAssertEqual(v("-5", .signed), -5)
        XCTAssertEqual(v("0", .optional), 0)
    }
}
