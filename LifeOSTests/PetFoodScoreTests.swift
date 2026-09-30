import XCTest
@testable import LifeOS

/// Methode "Animaux 2.0" (etait 1.0), sur de vraies fiches Open Pet Food Facts (29 sept).
final class PetFoodScoreTests: XCTestCase {
    private func pet(_ name: String, cats: [String] = ["en:cat-food"], ingredients: String?, analysis: CatalogProduct.PetAnalysis? = nil) -> CatalogProduct {
        var p = CatalogProduct(barcode: "1", source: .pet, name: name)
        p.categories = cats; p.ingredientsText = ingredients; p.petAnalysis = analysis
        return p
    }

    /// Gourmet Gold (3222270550673): "viande et sous-produits animaux (dont poulet 4%),
    /// sous-produits d'origine végétale, substances minérales, sucres". Protéines
    /// saisies en fraction (0,11), humidité 77 %.
    func testFourPercentChickenWithSugarScoresLow() {
        let p = pet("Gourmet Gold Mousse au poulet",
                    ingredients: "au poulet : viande et sous-produits animaux (dont poulet 4%), sous-produits d'origine végétale, substances minérales, sucres.",
                    analysis: .init(protein: 11, fat: 7, fibre: 0.1, ash: 3, moisture: 77))
        let r = ProductScore.evaluate(p)
        XCTAssertTrue(r.method.contains("chat"))
        XCTAssertLessThanOrEqual(r.value!, 50, "\(r.components.map(\.details))")
        XCTAssertTrue(r.components.first { $0.name == "Composition" }!.details.contains { $0.contains("minimum légal") }, "4 % = minimum légal, 0 point")
        XCTAssertTrue(r.components.first { $0.name == "Composition" }!.details.contains { $0.contains("sans espèce nommée") }, "la parenthèse « dont poulet » ne compte pas comme premier ingrédient")
        XCTAssertTrue(r.flags.contains { $0.code == "sucre" })
    }

    /// Bifensis croquettes chat (7613031571390): abats de bœuf 16 % en tête, blé,
    /// soja, maïs, gluten; protéines brutes 37 %, lipides 13, cellulose 4, cendres 7,5.
    func testCerealHeavyKibbleIsMiddling() {
        let p = pet("Croquettes Pour Chat Adulte Stérilisé Boeuf", cats: ["en:cat-food", "en:dry-cat-food"],
                    ingredients: "Abats de bœuf 16%, Protéines de volaille déshydratées, Blé 14%, Farine de soja, Maïs, Gluten de maïs, Graisses animale",
                    analysis: .init(protein: 37, fat: 13, fibre: 4, ash: 7.5, moisture: nil))
        let r = ProductScore.evaluate(p)
        let v = r.value!
        XCTAssertGreaterThan(v, 50); XCTAssertLessThan(v, 80)
        XCTAssertTrue(r.components.contains { $0.name == "Nutrition" && $0.details.contains { $0.contains("Humidité non déclarée") } })
        XCTAssertEqual(r.confidence?.level, .medium)
    }

    func testHighMeatNoFillerCatFoodScoresHigh() {
        let p = pet("Pâtée poulet", ingredients: "Poulet 70%, bouillon de poulet, foie de poulet 5%, huile de saumon, minéraux, taurine",
                    analysis: .init(protein: 12, fat: 5, fibre: 0.5, ash: 2, moisture: 80))
        XCTAssertGreaterThanOrEqual(ProductScore.evaluate(p).value!, 85)
    }

    func testToxicIngredientForDogCapsAt49() {
        let p = pet("Friandises pour chien", cats: ["en:dog-food"], ingredients: "Poulet 60%, farine de riz, xylitol, arôme",
                    analysis: .init(protein: 30, fat: 10, fibre: 2, ash: 6, moisture: 12))
        let r = ProductScore.evaluate(p)
        XCTAssertLessThanOrEqual(r.value!, 49)
        XCTAssertTrue(r.flags.contains { $0.level == .high && $0.name.lowercased().contains("xylitol") })
    }

    func testNoCompositionMeansNoScoreAndUnknownSpeciesIsSaid() {
        XCTAssertNil(ProductScore.evaluate(pet("Croquettes chat", ingredients: nil)).value)
        guard case .notApplicable = ProductScore.evaluate(pet("Mélange pour oiseaux", cats: [], ingredients: "graines de tournesol, millet")).outcome else { return XCTFail() }
    }

    /// Sans constituants analytiques: une note, mais annoncee en confiance faible.
    func testCompositionOnlyGivesLowConfidence() {
        let r = ProductScore.evaluate(pet("Pâtée chat", ingredients: "Poulet 50%, eau, minéraux"))
        XCTAssertNotNil(r.value)
        XCTAssertEqual(r.confidence?.level, .low)
    }

    func testPetFoodNeverUsesPersonalGoals() {
        let p = pet("Croquettes chat", ingredients: "Poulet 50%, riz")
        XCTAssertTrue(ProductFit.evaluate(p, goals: Set(ProductGoal.allCases)).verdicts.isEmpty)
    }

    func testMeatPercentageIsReadFromTheList() {
        XCTAssertEqual(ProductScore.petIngredients("viande et sous-produits animaux (dont poulet 4%), sucres").meatPercent, 4)
        XCTAssertEqual(ProductScore.petIngredients("Poulet frais 26%, riz 20%, dinde 10%").meatPercent, 26)
    }

    /// Vraie fiche Gourmet (29 sept): categorie vague, nom sans "chat". La marque suffit.
    func testKnownCatBrandGivesTheSpecies() {
        var p = pet("Les Mousselines au poulet, au saumon, aux rognons, au lapin", cats: ["en:open-pet-food-facts"],
                    ingredients: "viande et sous-produits animaux (dont poulet 4%), sucres")
        p.brand = "Gourmet"
        XCTAssertEqual(ProductScore.species(p), .cat)
        XCTAssertNotNil(ProductScore.evaluate(p).value)
    }

    func testUserChoiceWinsWhenTheBaseIsSilent() {
        let p = pet("Pâtée au bœuf", cats: [], ingredients: "Boeuf 40%, eau")
        XCTAssertNil(ProductScore.species(p))
        var q = p
        q.petFacts = .init(userSpecies: .dog)
        XCTAssertEqual(ProductScore.species(q), .dog)
        XCTAssertTrue(ProductScore.evaluate(q).method.contains("chien"))
    }
}
