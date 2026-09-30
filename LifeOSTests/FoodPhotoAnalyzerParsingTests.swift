import XCTest
@testable import LifeOS

/// Lecture de la reponse du modele de vision pour l'analyse d'un plat.
///
/// C'est le point le plus fragile de la fonctionnalite: le modele repond en
/// texte libre, et on lui demande du JSON. Il ajoute regulierement des balises
/// de code, une phrase d'introduction, ou rend un nombre sous forme de chaine.
/// Si la lecture casse, l'utilisateur voit l'estimation locale sans comprendre
/// pourquoi. Ces tests figent les formes reellement observees.
final class FoodPhotoAnalyzerParsingTests: XCTestCase {

    func testParsesPlainJSON() {
        let a = FoodPhotoAnalyzer.parse(
            #"{"name":"Poulet riz","kcal":620,"protein":45,"carbs":70,"fat":12,"note":"assiette moyenne"}"#
        )
        XCTAssertEqual(a?.name, "Poulet riz")
        XCTAssertEqual(a?.items.first?.kcal, 620)
        XCTAssertEqual(a?.items.first?.protein, 45)
        XCTAssertEqual(a?.note, "assiette moyenne")
    }

    /// Le cas le plus frequent: le modele encadre malgre la consigne.
    func testParsesJSONWrappedInCodeFence() {
        let raw = """
        Voici l'analyse :
        ```json
        {"name":"Salade César","kcal":430,"protein":22,"carbs":18,"fat":30,"note":"avec croûtons"}
        ```
        """
        let a = FoodPhotoAnalyzer.parse(raw)
        XCTAssertEqual(a?.name, "Salade César")
        XCTAssertEqual(a?.items.first?.kcal, 430)
    }

    /// Certains modeles rendent "620" ou "620 kcal" au lieu de 620.
    func testParsesNumbersGivenAsStrings() {
        let a = FoodPhotoAnalyzer.parse(
            #"{"name":"Pâtes","kcal":"540 kcal","protein":"18","carbs":"80","fat":"12","note":""}"#
        )
        XCTAssertEqual(a?.items.first?.kcal, 540)
        XCTAssertEqual(a?.items.first?.protein, 18)
        XCTAssertEqual(a?.items.first?.carbs, 80)
    }

    func testParsesFloatsAndRoundsCalories() {
        let a = FoodPhotoAnalyzer.parse(
            #"{"name":"Yaourt","kcal":118.6,"protein":10.2,"carbs":12.0,"fat":3.5,"note":""}"#
        )
        XCTAssertEqual(a?.items.first?.kcal ?? 0, 118.6, accuracy: 0.001)
        XCTAssertEqual(a?.items.first?.protein ?? 0, 10.2, accuracy: 0.001)
    }

    /// Un nom vide ne vaut rien: mieux vaut retomber sur l'estimation locale
    /// que d'enregistrer une ligne "" dans le journal alimentaire.
    func testRejectsEmptyName() {
        XCTAssertNil(FoodPhotoAnalyzer.parse(#"{"name":"","kcal":300}"#))
        XCTAssertNil(FoodPhotoAnalyzer.parse(#"{"name":"   ","kcal":300}"#))
    }

    func testRejectsNonJSON() {
        XCTAssertNil(FoodPhotoAnalyzer.parse("Je ne peux pas analyser cette photo."))
        XCTAssertNil(FoodPhotoAnalyzer.parse(""))
    }

    /// Le modele peut renvoyer des valeurs negatives absurdes. On plancher a 0
    /// plutot que de soustraire des calories a la journee de l'utilisateur.
    func testClampsNegativeValues() {
        let a = FoodPhotoAnalyzer.parse(
            #"{"name":"Eau","kcal":-50,"protein":-2,"carbs":0,"fat":0,"note":""}"#
        )
        XCTAssertEqual(a?.items.first?.kcal, 0)
        XCTAssertEqual(a?.items.first?.protein, 0)
    }

    /// Champs manquants: on ne veut pas de crash, juste des zeros.
    func testMissingFieldsBecomeZero() {
        let a = FoodPhotoAnalyzer.parse(#"{"name":"Pomme"}"#)
        XCTAssertEqual(a?.name, "Pomme")
        XCTAssertEqual(a?.items.first?.kcal, 0)
        XCTAssertEqual(a?.items.first?.fat, 0)
        XCTAssertEqual(a?.note, "")
    }

    // MARK: - Format par aliment (29 sept)

    /// Une assiette de legumes sautes rendue en aliments separes, avec alternatives:
    /// plus de "Soupe" globale impossible a corriger.
    func testParsesItemsWithAlternativesAndQuestion() {
        let a = FoodPhotoAnalyzer.parse(#"""
        {"items":[{"name":"Haricots verts","grams":150,"preparation":"sauté","confidence":0.8,"alternatives":["Pois gourmands"],"kcal":60,"protein":3,"carbs":8,"fat":2},
                  {"name":"Carottes","grams":80,"preparation":"sauté","confidence":0.7,"alternatives":[],"kcal":30,"protein":1,"carbs":6,"fat":1}],
         "question":"Combien d'huile pour la cuisson ?","note":"poêlée de légumes"}
        """#)
        XCTAssertEqual(a?.items.map(\.name), ["Haricots verts", "Carottes"])
        XCTAssertEqual(a?.items.first?.alternatives, ["Pois gourmands"])
        XCTAssertEqual(a?.items.first?.preparation, "sauté")
        XCTAssertEqual(a?.question, "Combien d'huile pour la cuisson ?")
    }

    func testEmptyItemsMeansNoFood() {
        XCTAssertEqual(FoodPhotoAnalyzer.parse(#"{"items":[],"question":null,"note":"un chat"}"#)?.items, [])
    }

    func testMissingGramsGetsAVisibleDefault() {
        XCTAssertEqual(FoodPhotoAnalyzer.parse(#"{"items":[{"name":"Riz"}]}"#)?.items.first?.grams, 150)
    }
}
