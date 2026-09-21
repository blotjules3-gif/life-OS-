import XCTest
@testable import LifeOS

/// Impot sur le revenu francais.
///
/// Trois defauts corriges, tous dans le sens qui trompe l'utilisateur:
///   1. Le bareme etait celui de 2024, affiche en 2026.
///   2. Le plafonnement du quotient familial n'existait pas, donc une
///      famille nombreuse voyait un impot tres inferieur au reel.
///   3. La decote n'existait pas, donc un revenu modeste voyait un impot
///      alors qu'il n'en doit aucun.
///
/// Les montants attendus ont ete calcules a part, tranche par tranche, avant
/// d'ecrire le code, et pas releves sur la sortie du code.
final class FrenchTaxTests: XCTestCase {

    // MARK: - Bareme

    /// Sous la premiere tranche, aucun impot.
    func testBelowFirstBracket() {
        XCTAssertEqual(FrenchTax.compute(income: 11_000, parts: 1, status: .single).total, 0)
    }

    /// Cas de reference: 35 000 € pour une part.
    /// 17 979 a 11 % font 1 977,69 et 5 421 a 30 % font 1 626,30.
    func testSinglePersonMiddleIncome() {
        let r = FrenchTax.compute(income: 35_000, parts: 1, status: .single)
        XCTAssertEqual(r.total, 3_604)
        XCTAssertEqual(r.marginalRate, 0.30, accuracy: 0.0001)
        XCTAssertEqual(r.capLoss, 0)
        XCTAssertEqual(r.decote, 0)
    }

    func testTopBracket() {
        let r = FrenchTax.compute(income: 250_000, parts: 1, status: .single)
        XCTAssertEqual(r.total, 89_024)
        XCTAssertEqual(r.marginalRate, 0.45, accuracy: 0.0001)
    }

    func testZeroIncome() {
        let r = FrenchTax.compute(income: 0, parts: 1, status: .single)
        XCTAssertEqual(r.total, 0)
        XCTAssertEqual(r.marginalRate, 0, accuracy: 0.0001)
    }

    // MARK: - Decote

    /// 16 000 € pour une part donnent 484 € d'impot brut. La decote vaut
    /// 897 moins 45,25 % de 484, soit plus que l'impot: il ne reste rien.
    /// L'ancien ecran affichait 484 €.
    func testDecoteWipesOutSmallTax() {
        let r = FrenchTax.compute(income: 16_000, parts: 1, status: .single)
        XCTAssertEqual(r.beforeDecote, 484)
        XCTAssertEqual(r.decote, 484)
        XCTAssertEqual(r.total, 0)
    }

    /// La decote ne peut jamais rendre de l'argent.
    func testDecoteNeverGoesNegative() {
        for income in stride(from: 11_000.0, through: 22_000.0, by: 250) {
            let r = FrenchTax.compute(income: income, parts: 1, status: .single)
            XCTAssertGreaterThan(r.total + 1, 0)
            XCTAssertLessThanOrEqual(r.decote, r.beforeDecote)
        }
    }

    /// Elle touche aussi un couple a revenu moyen: 60 000 € sur 3 parts
    /// donnent 2 772 € d'impot, sous le seuil de 3 277 €.
    func testDecoteAppliesToCoupleToo() {
        let r = FrenchTax.compute(income: 60_000, parts: 3, status: .couple)
        XCTAssertEqual(r.beforeDecote, 2_772)
        XCTAssertEqual(r.decote, 229)
        XCTAssertEqual(r.total, 2_543)
    }

    /// Au-dessus du seuil, aucune decote.
    func testNoDecoteAboveCeiling() {
        XCTAssertEqual(FrenchTax.compute(income: 35_000, parts: 1, status: .single).decote, 0)
    }

    // MARK: - Plafonnement du quotient familial

    /// Le defaut le plus couteux. Couple a 120 000 € avec 4 parts:
    /// sans plafond l'impot tombe a 8 416 €, mais chaque demi-part
    /// supplementaire ne peut faire gagner que 1 807 €, soit 7 228 € pour
    /// quatre demi-parts. Le vrai impot est 14 980 €.
    func testFamilyQuotientIsCapped() {
        let r = FrenchTax.compute(income: 120_000, parts: 4, status: .couple)
        XCTAssertEqual(r.beforeCap, 8_416, "impôt sans plafond")
        XCTAssertEqual(r.capLoss, 6_564, "avantage refusé par le plafond")
        XCTAssertEqual(r.total, 14_980)
    }

    /// Un couple sans enfant n'a pas de demi-part supplementaire, donc rien
    /// a plafonner.
    func testNoCapWithoutExtraHalfParts() {
        let r = FrenchTax.compute(income: 120_000, parts: 2, status: .couple)
        XCTAssertEqual(r.capLoss, 0)
        XCTAssertEqual(r.total, 22_208)
    }

    /// A revenu modeste, le plafond ne mord pas: l'avantage reel est
    /// inferieur au plafond, donc le quotient familial joue en entier.
    func testCapDoesNotBiteOnModestIncome() {
        let r = FrenchTax.compute(income: 40_000, parts: 3, status: .couple)
        XCTAssertEqual(r.capLoss, 0)
    }

    /// Une part de plus ne doit JAMAIS augmenter l'impot.
    func testMorePartsNeverIncreasesTax() {
        for parts in stride(from: 2.0, through: 5.0, by: 0.5) {
            let less = FrenchTax.compute(income: 90_000, parts: parts, status: .couple).total
            let more = FrenchTax.compute(income: 90_000, parts: parts + 0.5, status: .couple).total
            XCTAssertLessThanOrEqual(more, less, "\(parts + 0.5) parts coûtent plus que \(parts)")
        }
    }

    // MARK: - Situation de famille

    /// Un couple ne peut pas avoir moins de deux parts, meme si l'appelant
    /// en demande une.
    func testCoupleNeverDropsBelowTwoParts() {
        XCTAssertEqual(FrenchTax.compute(income: 60_000, parts: 1, status: .couple),
                       FrenchTax.compute(income: 60_000, parts: 2, status: .couple))
    }

    /// A revenu egal, un couple paie moins qu'un celibataire.
    func testCoupleePaysLessThanSingle() {
        let single = FrenchTax.compute(income: 60_000, parts: 1, status: .single).total
        let couple = FrenchTax.compute(income: 60_000, parts: 2, status: .couple).total
        XCTAssertLessThan(couple, single)
    }

    // MARK: - Monotonie generale

    /// L'impot ne doit jamais baisser quand le revenu monte. C'est la
    /// propriete qui attrape une borne de tranche mal recopiee.
    func testTaxNeverDecreasesWithIncome() {
        var previous = -1.0
        for income in stride(from: 5_000.0, through: 250_000.0, by: 1_000) {
            let t = FrenchTax.compute(income: income, parts: 1, status: .single).total
            XCTAssertGreaterThan(t + 0.001, previous, "l'impôt baisse à \(income) €")
            previous = t
        }
    }

    /// Et il ne doit jamais depasser le revenu.
    func testTaxNeverExceedsIncome() {
        for income in stride(from: 5_000.0, through: 250_000.0, by: 5_000) {
            XCTAssertLessThan(FrenchTax.compute(income: income, parts: 1, status: .single).total,
                              income)
        }
    }
}
