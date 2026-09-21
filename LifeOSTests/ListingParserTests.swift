import XCTest
@testable import LifeOS

/// Lecture d'une annonce immobiliere collee.
///
/// Ces tests portent sur la seule partie ou une erreur coute de l'argent: la
/// conversion du texte en chiffres. Un prix divise par mille, ou des charges
/// annuelles prises pour des charges mensuelles, changent le cashflow et donc
/// la decision d'acheter. Tout est teste hors reseau, sur la reponse brute.
final class ListingParserTests: XCTestCase {

    func testPlainJSON() {
        let d = ListingParser.parse("""
        {"name":"T3 Nantes","city":"Nantes","value":250000,
         "monthlyRent":850,"monthlyCharges":90,"surface":65}
        """)
        XCTAssertEqual(d?.name, "T3 Nantes")
        XCTAssertEqual(d?.value, 250_000)
        XCTAssertEqual(d?.monthlyRent, 850)
        XCTAssertEqual(d?.surface, 65)
    }

    /// Les modeles repondent souvent dans un bloc de code malgre la consigne.
    func testFencedJSON() {
        let d = ListingParser.parse("""
        Voici le résultat :
        ```json
        {"name":"Studio Lyon","value":120000,"surface":25}
        ```
        N'hésite pas si tu veux autre chose.
        """)
        XCTAssertEqual(d?.name, "Studio Lyon")
        XCTAssertEqual(d?.value, 120_000)
    }

    /// Le piege principal: en France le point separe les MILLIERS.
    /// Lire "250.000" comme 250 diviserait le prix par mille.
    func testFrenchThousandSeparator() {
        let d = ListingParser.parse(#"{"name":"Maison","value":"250.000 €"}"#)
        XCTAssertEqual(d?.value, 250_000)
    }

    func testSpacedAmountWithCurrency() {
        let d = ListingParser.parse(#"{"name":"Maison","value":"1 250 000 €"}"#)
        XCTAssertEqual(d?.value, 1_250_000)
    }

    /// Une virgule reste un decimal.
    func testDecimalComma() {
        let d = ListingParser.parse(#"{"name":"Box","value":"15000","surface":"12,5"}"#)
        XCTAssertEqual(d?.surface ?? 0, 12.5, accuracy: 0.001)
    }

    /// Milliers ET decimales dans le meme montant.
    func testThousandsAndDecimals() {
        let d = ListingParser.parse(#"{"name":"Loft","value":"500.000,50"}"#)
        XCTAssertEqual(d?.value ?? 0, 500_000.5, accuracy: 0.01)
    }

    /// Les charges sont recopiees telles quelles, jamais divisees.
    ///
    /// Ce test fige une decision, pas un detail. La premiere version corrigeait
    /// "charges superieures au loyer, donc montant annuel". Avec 300 de loyer
    /// et 400 de charges, banal en petite surface, elle divisait par douze en
    /// silence. Un chiffre corrige a tort est pire qu'un chiffre a corriger a
    /// la main: personne ne le voit passer.
    func testChargesAreNeverSilentlyDivided() {
        let d = ListingParser.parse("""
        {"name":"Grand appartement","monthlyRent":300,"monthlyCharges":400}
        """)
        XCTAssertEqual(d?.monthlyCharges, 400)

        let e = ListingParser.parse("""
        {"name":"T2","value":180000,"monthlyRent":700,"monthlyCharges":1800,"surface":45}
        """)
        XCTAssertEqual(e?.monthlyCharges, 1800, "la conversion est demandée au modèle, pas devinée ici")
    }

    /// Une annonce de vente ne donne pas de loyer: le champ reste a zero,
    /// il n'est jamais estime.
    func testMissingRentStaysZero() {
        let d = ListingParser.parse(#"{"name":"T4 Rennes","value":300000,"surface":90}"#)
        XCTAssertEqual(d?.monthlyRent, 0)
    }

    func testCityBecomesNameWhenTitleMissing() {
        let d = ListingParser.parse(#"{"name":"","city":"Bordeaux","value":210000}"#)
        XCTAssertEqual(d?.name, "Bien · Bordeaux")
    }

    func testPricePerM2() {
        let d = ListingParser.parse(#"{"name":"T3","value":240000,"surface":60}"#)
        XCTAssertEqual(d?.pricePerM2 ?? 0, 4000, accuracy: 0.01)
    }

    func testPricePerM2NilWithoutSurface() {
        let d = ListingParser.parse(#"{"name":"T3","value":240000}"#)
        XCTAssertNil(d?.pricePerM2)
    }

    /// Une reponse sans aucun chiffre ne doit pas creer une fiche vide, sinon
    /// l'utilisateur ouvre un editeur vierge sans comprendre pourquoi.
    func testAllZeroGivesNil() {
        XCTAssertNil(ListingParser.parse(#"{"name":"","city":"","value":0,"monthlyRent":0}"#))
    }

    func testNoJSONGivesNil() {
        XCTAssertNil(ListingParser.parse("Je ne peux pas lire cette annonce."))
    }

    func testEmptyStringGivesNil() {
        XCTAssertNil(ListingParser.parse(""))
    }

    /// Une accolade a l'interieur d'une chaine ne doit pas couper le JSON.
    func testBraceInsideStringDoesNotTruncate() {
        let d = ListingParser.parse(#"{"name":"T2 {rénové}","value":99000}"#)
        XCTAssertEqual(d?.value, 99_000)
        XCTAssertEqual(d?.name, "T2 {rénové}")
    }

    /// Un nombre negatif est absurde ici et ne doit pas passer.
    func testNegativeIsClampedToZero() {
        let d = ListingParser.parse(#"{"name":"T1","value":150000,"monthlyCharges":-50}"#)
        XCTAssertEqual(d?.monthlyCharges, 0)
    }

    /// Deux lectures de la meme annonce donnent la meme fiche: sinon la
    /// feuille de confirmation se rouvrirait toute seule.
    func testSameTextGivesEqualDraft() {
        let raw = #"{"name":"T3","value":250000,"monthlyRent":800,"surface":60}"#
        XCTAssertEqual(ListingParser.parse(raw), ListingParser.parse(raw))
        XCTAssertEqual(ListingParser.parse(raw)?.id, ListingParser.parse(raw)?.id)
    }
}
