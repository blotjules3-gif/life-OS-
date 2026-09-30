import XCTest
@testable import LifeOS

/// Calculs et table d'aliments de la reconnaissance photo.
///
/// La partie reseau et la partie Vision ne sont pas testables ici: il faudrait
/// une vraie photo et une vraie connexion. Tout le reste l'est, et c'est la ou
/// se cachent les erreurs qui passeraient inapercues: une portion saisie de
/// travers ou un mot cle qui en masque un autre ne font pas planter l'app,
/// ils donnent juste un mauvais chiffre a l'utilisateur.
final class FoodRecognitionPipelineTests: XCTestCase {

    private func food(grams: Double, kcal100: Double,
                      p: Double = 0, c: Double = 0, f: Double = 0)
    -> FoodRecognitionPipeline.DetectedFood {
        .init(name: "Test", confidence: 0.5, grams: grams,
              kcal100: kcal100, protein100: p, carbs100: c, fat100: f,
              source: .openFoodFacts)
    }

    // MARK: - Regle de trois

    func testCaloriesScaleWithPortion() {
        // 250 kcal/100 g sur 200 g = 500 kcal.
        XCTAssertEqual(food(grams: 200, kcal100: 250).kcal, 500)
        // La moitie d'une portion, la moitie des calories.
        XCTAssertEqual(food(grams: 50, kcal100: 250).kcal, 125)
    }

    func testMacrosScaleWithPortion() {
        let f = food(grams: 150, kcal100: 100, p: 20, c: 10, f: 5)
        XCTAssertEqual(f.protein, 30, accuracy: 0.001)
        XCTAssertEqual(f.carbs, 15, accuracy: 0.001)
        XCTAssertEqual(f.fat, 7.5, accuracy: 0.001)
    }

    func testZeroPortionGivesZero() {
        let f = food(grams: 0, kcal100: 500, p: 10, c: 10, f: 10)
        XCTAssertEqual(f.kcal, 0)
        XCTAssertEqual(f.protein, 0)
    }

    /// Les calories sont arrondies, pas tronquees: 0,6 doit monter.
    func testCaloriesAreRoundedNotTruncated() {
        XCTAssertEqual(food(grams: 101, kcal100: 99.5).kcal, 100)
    }

    /// Les macros gardent une decimale, sinon un yaourt affiche 0 g de
    /// proteines au lieu de 3,5.
    func testMacrosKeepOneDecimal() {
        let f = food(grams: 100, kcal100: 60, p: 3.55)
        XCTAssertEqual(f.protein, 3.6, accuracy: 0.001)
    }

    // MARK: - Table d'aliments

    /// Le mot cle le plus long doit l'emporter.
    ///
    /// Ce test a trouve un vrai bug: "cake" etait declare avant "pancake", et
    /// la recherche prenait la premiere correspondance. Une photo de pancakes
    /// devenait un gateau, avec la mauvaise portion et donc les mauvaises
    /// calories. Le classement par longueur supprime toute la famille de bugs.
    func testLongestKeywordWins() {
        func resolve(_ label: String) -> FoodRecognitionPipeline.FoodKey? {
            FoodRecognitionPipeline.foods
                .filter { label.contains($0.match) }
                .max(by: { $0.match.count < $1.match.count })
        }
        XCTAssertEqual(resolve("pancake")?.fr, "Pancakes", "« cake » ne doit pas capter « pancake »")
        XCTAssertEqual(resolve("cake")?.fr, "Gâteau")
        XCTAssertEqual(resolve("hot dog")?.fr, "Hot-dog")
        XCTAssertEqual(resolve("cheeseburger")?.fr, "Burger")
        XCTAssertEqual(resolve("granny smith apple")?.fr, "Pomme")
        XCTAssertNil(resolve("voiture"), "un mot non alimentaire ne doit rien rendre")
    }

    func testFoodPortionsAreCredible() {
        for f in FoodRecognitionPipeline.foods {
            XCTAssertGreaterThan(f.grams, 10, "portion trop petite pour \(f.fr)")
            XCTAssertLessThan(f.grams, 600, "portion trop grosse pour \(f.fr)")
            XCTAssertFalse(f.fr.isEmpty)
            XCTAssertFalse(f.query.isEmpty)
            XCTAssertEqual(f.match, f.match.lowercased(),
                           "les labels Vision sont compares en minuscules")
        }
    }

    /// Le repli hors ligne doit exister pour les aliments les plus courants,
    /// sinon une coupure reseau donne 200 kcal a tout.
    func testCommonFoodsHaveOfflineFallback() {
        let needed = ["Pizza", "Banane", "Riz", "Pâtes", "Poulet", "Frites"]
        let covered = Set(FoodRecognitionPipeline.foods.map(\.fr))
        for n in needed {
            XCTAssertTrue(covered.contains(n), "\(n) absent de la table")
        }
    }

    /// Le total d'un repas est la somme des lignes, pas autre chose.
    func testMealTotalIsSumOfItems() {
        let items = [food(grams: 100, kcal100: 250, p: 10),
                     food(grams: 200, kcal100: 100, p: 5)]
        XCTAssertEqual(items.reduce(0) { $0 + $1.kcal }, 450)
        XCTAssertEqual(items.reduce(0.0) { $0 + $1.protein }, 20, accuracy: 0.001)
    }

    // MARK: - Aliments generiques (Ciqual) et alternatives

    func testCiqualFindsHomeCookedFoods() {
        XCTAssertFalse(GenericFoods.all.isEmpty, "table Ciqual embarquée")
        let beans = GenericFoods.best("haricots verts", cooked: true)
        XCTAssertNotNil(beans)
        XCTAssertTrue(beans!.name.lowercased().contains("haricot vert"), beans!.name)
        XCTAssertLessThan(beans!.kcal, 60, "des haricots verts cuits, pas une conserve cuisinée")
        XCTAssertNotNil(GenericFoods.best("poulet rôti"))
    }

    /// "Soupe" remplacee par "Légumes cuits" en un geste: les valeurs suivent.
    func testChoosingAnAlternativeRecomputesFromCiqual() {
        let soup = FoodRecognitionPipeline.DetectedFood(name: "Soupe", confidence: 0.4, grams: 200,
                                                         kcal100: 40, protein100: 1, carbs100: 5, fat100: 1,
                                                         source: .estimate, alternatives: ["Haricots verts", "Ragoût"])
        let fixed = FoodRecognitionPipeline.renamed(soup, to: "Haricots verts")
        XCTAssertEqual(fixed.name, "Haricots verts")
        XCTAssertEqual(fixed.source, .ciqual)
        XCTAssertEqual(fixed.grams, 200, "la portion choisie est gardée")
        XCTAssertTrue(fixed.alternatives.contains("Soupe"), "on peut revenir en arrière")
        XCTAssertFalse(fixed.alternatives.contains("Haricots verts"))
    }

    func testSoupAlwaysOffersVegetableAlternatives() {
        XCTAssertTrue(FoodRecognitionPipeline.confusions["Soupe"]?.contains("Légumes cuits") == true)
    }

    /// Vrais labels Apple Vision releves le 29 sept (tools/calai-bench, sur Mac).
    /// Avant, "stir_fry" et "vegetable" n'avaient aucune correspondance: la poêlée
    /// devenait "Carottes 120 g" et seule une "soup" de Vision passait.
    func testRealVisionLabelsForVegetableDishes() {
        let ratatouille = [("utensil", 0.78), ("cookware", 0.78), ("pan", 0.78), ("food", 0.58), ("stir_fry", 0.55), ("vegetable", 0.39), ("tomato", 0.39)]
        XCTAssertEqual(FoodRecognitionPipeline.keys(from: ratatouille).map(\.0.fr), ["Poêlée de légumes", "Légumes", "Tomate"])
        let poelee = [("food", 0.54), ("stir_fry", 0.54), ("utensil", 0.53), ("spatula", 0.48), ("vegetable", 0.24), ("carrot", 0.21)]
        XCTAssertEqual(FoodRecognitionPipeline.keys(from: poelee).first?.0.fr, "Poêlée de légumes")
        let soup = [("tableware", 0.97), ("spoon", 0.91), ("food", 0.73), ("soup", 0.73)]
        XCTAssertEqual(FoodRecognitionPipeline.keys(from: soup).first?.0.fr, "Soupe", "une vraie soupe reste une soupe")
        XCTAssertTrue(FoodRecognitionPipeline.keys(from: [("tableware", 0.9), ("plate", 0.9)]).isEmpty, "de la vaisselle n'est pas un aliment")
    }
}
