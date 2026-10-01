import XCTest
@testable import LifeOS

/// Audit global du 1er oct. 2026, "Risques nouveaux : fusion des étiquettes animales".
/// Chaque test reproduit un des cinq risques sur la fusion base + étiquette.
@MainActor
final class PetMergeOverrideTests: XCTestCase {

    private var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("petmerge-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private let labelComposition = "Saumon (18 %), Protéines de volaille déshydratées, Blé (16 %), Protéines de pois, Graisses animales"
    private let labelValues = PetLabel.Analytics(protein: 41, fat: 20, ash: 7.5, fibre: 2, moisture: nil, taurine: 0.15)

    private func base(composition: String? = nil, protein: Double? = nil) -> CatalogProduct {
        var p = CatalogProduct(barcode: "8445290938091", source: .pet, name: "one junior")
        p.categories = ["en:cat-food"]
        p.ingredientsText = composition
        if let protein { p.petAnalysis = .init(protein: protein, fat: 9, fibre: 3, ash: 6, moisture: nil) }
        return p
    }

    private func label(composition: String?, values: PetLabel.Analytics, validated: Bool) -> PetProfile.LabelReading {
        .init(text: "", declaration: "Aliment complet pour chatons.", composition: composition, additives: nil,
              analytics: values, source: "ta photo", photoDate: nil, readAt: Date(), validated: validated, fromUserPhoto: true)
    }

    private func merged(_ p: CatalogProduct, _ l: PetProfile.LabelReading) -> CatalogProduct {
        PetMerge.apply(PetProfile(gtin: PetProfile.key(p.barcode), aliases: [], species: nil, lifeStage: nil, label: l, updatedAt: Date()), to: p)
    }

    // Risque 1 : une correction validée doit passer devant une donnée fausse de la base.

    func testValidatedLabelReplacesWrongCompositionAndValues() {
        let wrong = base(composition: "Poulet 30 %, riz, maïs, pois", protein: 99)
        let p = merged(wrong, label(composition: labelComposition, values: labelValues, validated: true))
        XCTAssertEqual(p.ingredientsText, labelComposition)
        XCTAssertEqual(p.petAnalysis?.protein, 41, "les valeurs de la base décrivent l'autre version : remplacées")
        XCTAssertEqual(p.petAnalysis?.fibre, 2)
        XCTAssertTrue(p.petFacts!.provenance.first!.contains("Remplace la composition de la base"))
        XCTAssertTrue(ProductScore.evaluate(p).confidence!.reason.contains("relus par toi"))
    }

    func testValidatedValuesAloneReplaceBaseValuesAndKeepBaseComposition() {
        let p = merged(base(composition: labelComposition, protein: 99), label(composition: nil, values: labelValues, validated: true))
        XCTAssertEqual(p.ingredientsText, labelComposition)
        XCTAssertEqual(p.petAnalysis?.protein, 41)
        XCTAssertTrue(p.petFacts!.provenance.first!.contains("Remplacent ceux de la base"))
    }

    func testAutomaticReadingNeverOverridesTheBase() {
        let b = base(composition: "Poulet 30 %, riz, maïs, pois", protein: 35)
        let p = merged(b, label(composition: labelComposition, values: labelValues, validated: false))
        XCTAssertEqual(p.ingredientsText, b.ingredientsText)
        XCTAssertEqual(p.petAnalysis?.protein, 35)
    }

    func testRemovingTheCorrectionGivesTheBaseBackAfterRelaunch() throws {
        let store = ProductStore(directory: dir)
        let wrong = base(composition: "Poulet 30 %, riz, maïs, pois", protein: 99)
        try store.saveLabel(label(composition: labelComposition, values: labelValues, validated: true), for: wrong.barcode)
        XCTAssertEqual(ProductStore(directory: dir).enriched(wrong).petAnalysis?.protein, 41)
        try store.removeLabel(for: wrong.barcode)
        let back = ProductStore(directory: dir).enriched(wrong)
        XCTAssertEqual(back.ingredientsText, wrong.ingredientsText)
        XCTAssertEqual(back.petAnalysis?.protein, 99)
    }

    // Risque 2 : deux ingrédients communs ne prouvent pas la même recette.

    func testTwoOfThreeSharedIngredientsIsNotTheSameRecipe() {
        XCTAssertEqual(PetMerge.recipeMatch("Saumon 18 %, blé, maïs, pois", "Saumon 18 %, blé, riz, pois"), .different)
        XCTAssertEqual(PetMerge.recipeMatch("Saumon (18 %), blé (16 %), protéines de pois", "Saumon 18 %, Blé, Protéines de pois, graisses"), .same)
        XCTAssertEqual(PetMerge.recipeMatch("Saumon", "Saumon, blé, maïs"), .unknown, "une liste d'un seul ingrédient ne prouve rien")
        XCTAssertEqual(PetMerge.recipeMatch("Poulet", "Saumon, blé, maïs"), .different)
    }

    func testSharedStartWithDifferentThirdIngredientDoesNotFillValues() {
        let b = base(composition: "Saumon 18 %, Protéines de volaille déshydratées, Maïs, pois")
        let p = merged(b, label(composition: labelComposition, values: labelValues, validated: false))
        XCTAssertNil(p.petAnalysis)
        XCTAssertTrue(p.petFacts!.provenance.first!.contains("valeurs non mélangées"))
    }

    // Risque 3 : des valeurs lues sans composition ne se vérifient pas.

    func testValuesReadWithoutCompositionAreNotAppliedOverABaseComposition() {
        let b = base(composition: labelComposition)
        let auto = merged(b, label(composition: nil, values: labelValues, validated: false))
        XCTAssertNil(auto.petAnalysis)
        XCTAssertTrue(auto.petFacts!.provenance.first!.contains("non appliqués"))
        let confirmed = merged(b, label(composition: nil, values: labelValues, validated: true))
        XCTAssertEqual(confirmed.petAnalysis?.protein, 41, "une fois relues par l'utilisateur, elles s'appliquent")
    }

    func testValuesAloneFillABaseWithNoCompositionAtAll() {
        let p = merged(base(), label(composition: nil, values: labelValues, validated: false))
        XCTAssertEqual(p.petAnalysis?.protein, 41, "rien à contredire")
        XCTAssertNil(ProductScore.evaluate(p).value, "toujours pas de composition, donc pas de note")
    }

    // Risque 5 : une friandise à 100 ne doit pas se lire comme un bon repas.

    func testTreatScoreSaysWhatItDoesNotCover() {
        var p = CatalogProduct(barcode: "5", source: .pet, name: "Friandises pour chat au poulet")
        p.categories = ["en:cat-treats"]
        p.ingredientsText = "Poulet 80 %, foie de poulet 10 %, minéraux"
        let r = ProductScore.evaluate(p)
        XCTAssertTrue(r.method.hasSuffix("friandise"), r.method)
        let limits = r.components.first { $0.name == "Limites" }
        XCTAssertTrue(limits?.details.first?.contains("pas un aliment principal") == true)
        XCTAssertEqual(r.confidence?.level, .low)
    }

    // Parcours complet : création → résultat → édition → suppression → relance.

    func testFullJourneyFromEditorToDeletion() throws {
        let raw = base()
        let store = ProductStore(directory: dir)
        XCTAssertNil(ProductScore.evaluate(store.enriched(raw)).value, "départ : pas de note")

        try store.saveLabel(label(composition: labelComposition, values: labelValues, validated: true), for: raw.barcode)
        let first = ProductScore.evaluate(store.enriched(raw))
        XCTAssertNotNil(first.value)
        XCTAssertTrue(first.method.contains("chaton"))

        var edited = label(composition: labelComposition, values: labelValues, validated: true)
        edited.analytics.moisture = 8
        try store.saveLabel(edited, for: raw.barcode)
        let second = ProductScore.evaluate(ProductStore(directory: dir).enriched(raw))
        XCTAssertEqual(second.confidence?.level, .high, "humidité déclarée et relue")

        try store.setPetLifeStage(.adult, for: raw.barcode)
        XCTAssertTrue(ProductScore.evaluate(store.enriched(raw)).method.hasSuffix("adulte"))

        try store.removeLabel(for: raw.barcode)
        try store.setPetLifeStage(nil, for: raw.barcode)
        let relaunched = ProductStore(directory: dir)
        XCTAssertNil(ProductScore.evaluate(relaunched.enriched(raw)).value, "après suppression et relance : la fiche d'origine")
        XCTAssertNil(relaunched.petProfile(for: raw.barcode)?.label)
    }

    // Audit du build 52, P1 : base avec valeurs mais sans composition + lecture auto
    // avec composition seule. Avant, la composition lue restait associee aux anciennes
    // valeurs, et la provenance disait que les deux venaient de la photo.
    func testAutomaticCompositionAloneIsNotPairedWithOldBaseValues() {
        var b = base()
        b.petAnalysis = .init(protein: 30, fat: 12, fibre: 2, ash: 7, moisture: 8)
        let p = merged(b, label(composition: labelComposition, values: PetLabel.Analytics(), validated: false))
        XCTAssertEqual(p.ingredientsText, labelComposition)
        XCTAssertNil(p.petAnalysis, "valeurs de la base non prouvées pour cette version")
        let prov = p.petFacts!.provenance.first!
        XCTAssertTrue(prov.hasPrefix("Composition :"), prov)
        XCTAssertFalse(prov.contains("constituants :"), "la photo n'a fourni que les ingrédients")
        XCTAssertTrue(prov.contains("mis de côté"))
    }

    // Audit du build 52, P2 : deux formules qui partagent leurs 3 premiers ingredients
    // mais pas leurs valeurs ne doivent jamais etre melangees automatiquement.
    func testTwoFormulasSharingTheirFirstThreeIngredientsAreNotMixed() {
        let baseFormula = "Saumon 18 %, Protéines de volaille déshydratées, Blé 16 %, Maïs, Pulpe de betterave"
        let otherFormula = "Saumon 26 %, Protéines de volaille déshydratées, Blé 12 %, Protéines de pois, Riz"
        XCTAssertEqual(PetMerge.recipeMatch(baseFormula, otherFormula), .same, "même début : c'est bien le piège")
        let otherValues = PetLabel.Analytics(protein: 34, fat: 15, ash: 7, fibre: 3, moisture: nil, taurine: 0.1)
        let p = merged(base(composition: baseFormula), label(composition: otherFormula, values: otherValues, validated: false))
        XCTAssertNil(p.petAnalysis)
        XCTAssertEqual(p.ingredientsText, baseFormula)
    }
}
