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
        XCTAssertEqual(a?.kcal, 620)
        XCTAssertEqual(a?.protein, 45)
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
        XCTAssertEqual(a?.kcal, 430)
    }

    /// Certains modeles rendent "620" ou "620 kcal" au lieu de 620.
    func testParsesNumbersGivenAsStrings() {
        let a = FoodPhotoAnalyzer.parse(
            #"{"name":"Pâtes","kcal":"540 kcal","protein":"18","carbs":"80","fat":"12","note":""}"#
        )
        XCTAssertEqual(a?.kcal, 540)
        XCTAssertEqual(a?.protein, 18)
        XCTAssertEqual(a?.carbs, 80)
    }

    func testParsesFloatsAndRoundsCalories() {
        let a = FoodPhotoAnalyzer.parse(
            #"{"name":"Yaourt","kcal":118.6,"protein":10.2,"carbs":12.0,"fat":3.5,"note":""}"#
        )
        XCTAssertEqual(a?.kcal, 119)          // arrondi, pas tronque
        XCTAssertEqual(a?.protein ?? 0, 10.2, accuracy: 0.001)
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
        XCTAssertEqual(a?.kcal, 0)
        XCTAssertEqual(a?.protein, 0)
    }

    /// Champs manquants: on ne veut pas de crash, juste des zeros.
    func testMissingFieldsBecomeZero() {
        let a = FoodPhotoAnalyzer.parse(#"{"name":"Pomme"}"#)
        XCTAssertEqual(a?.name, "Pomme")
        XCTAssertEqual(a?.kcal, 0)
        XCTAssertEqual(a?.fat, 0)
        XCTAssertEqual(a?.note, "")
    }
}
