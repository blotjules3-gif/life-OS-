import XCTest
import UIKit
@testable import LifeOS

/// Cas reel du prompt "Yuko aliments chat" (1er oct. 2026) : fiche "one junior",
/// GTIN 8445290938091 dans Open Pet Food Facts. La base n'a ni composition, ni
/// categorie utile, ni marque : seules les photos de l'etiquette disent tout.
///
/// Fixtures = texte lu par Vision (meme reglage que l'app) sur les photos choisies de
/// la fiche, telechargees le 1er oct. 2026 :
///   nutrition_fr.13 https://images.openpetfoodfacts.org/images/products/844/529/093/8091/nutrition_fr.13.full.jpg
///   ingredients_fr.7 https://images.openpetfoodfacts.org/images/products/844/529/093/8091/ingredients_fr.7.full.jpg
/// Le texte finit par "445290 938091" : le code imprime sur le sac est bien celui de la fiche.
/// La recette est au SAUMON : la page fabricant "junior chaton poulet" n'est PAS ce produit
/// et aucune de ses valeurs n'est utilisee ici.
/// Photos : Open Pet Food Facts, licence CC BY-SA.
@MainActor
final class PetFoodRealCaseTests: XCTestCase {

    static let gtin = "8445290938091"

    /// Photo nette (nutrition_fr.13), texte brut de Vision.
    static let sharpLabel = """
-BIFENSIS®- . SANS ARÔMES NI CONSERVATEURS ARTIFICIELS AJO ALIMENT COMPLET POUR CHATONS. CONVIENT AUSSI AUX CHATTES EN GESTATION OU EN LACTATION. COMPOSITION : Saumon (dont tête, arête, chair) (18 %), Protéines de volaille déshydratées, Blé (16 %), Protéines de pois, Graisses animales, Farine de soja, Farine de protéines de maïs, Amidon de mais, Racine de chicorée déshydratée (2 %), Gluten de blé, Substances minérales, Hydrolysat (avec ajout de 0,025% de poudre de Lactobacillus Delbrueckii et Fermentum traitée thermiquement), Levures déshydratées. ADDITIFS : ADDITIFS NUTRITIONNELS : Ul/kg : Vitamine A : 27000 ; Vitamine D, : 900 ; Vitamine E : 400 ; mg/kg : Vitamine C : 140 ; Sulfate de fer (I) monohydraté : (Fe: 140) ; lodate de calcium anhydre : (I: 2,2) ; Sulfate de cuivre (II) pentahydraté : (Cu: 15) ; Sulfate manganeux monohydraté : (Mn: 52) ; Sulfate de zinc monohydraté : (Zn: 130) ; Sélénite de sodium : (Se: 0,15). Antioxygènes. CONSTITUANTS ANALYTIQUES : Protéine : 41,0 %, Teneur en matières grasses : 20,0 %, Cendres LES brutes : 7,5 %, Cellulose brute : 2,0 %, DHA (Acide docosahexaénoïque) : 0,2 %, Acides gras Oméga 3 : 0,7 %, Acides gras Oméga 6 : 2,8 %, Taurine : 0,15 %. Ce sac n'est pas un jouet. Pour éviter tout risque d'étouffement, laissez ce sac hors de portée de vos enfants et animaux de compagnie. A utiliser de préférence avant : / Numéros de lot et d'enregistrement : voir sur le fond de l'emballage. A conserver dans un endroit frais et sec. 12568623 FR 0806 800 3 Un conseil, * Reg. Tra 44295355 445290 938091
"""

    /// Photo floue (ingredients_fr.7) : Vision y lit "Be 18 9)" pour "Blé (16 %)" et "07 %%" pour 0,7 %.
    static let blurryLabel = """
S. SANS AROMES NI CONSERVATEURS ARTIFICIELS AJOUTE ALINENT COMPLET POUR CHATONS. CONVIENT AUSSI AUX CHATTES EN GESTATION OU EN LACTATION. COMPOSITION : Saumon (dont tête, arête, chair) (18 %), Protéines de volaile déshydrates, Be 18 9) Protéines de pois, Graisses animales, Farine de soja, Farine de protéines de mais, Amidón de mas, Racine de chicorée deshydratée (2%), Gluten de blé, Substances minérales, Hydrolysat lavec ajout de 0,025% de pudre. de Lactobacillus Delbrueckii et Fermentum traitée thermiquement), Levures déshydratées. ADDITIFS : ADDITIFS NUTRITIONNELS : UI/kg : Vitamine A : 27000 ; Vitamine D, : 900 : Vitamine E : 400 mg/kg : Vitamine C : 140 ; Sulfate de fer (II) monohydraté : (Fe: 140) ; lodate de calcium anhudre - 1557 Sulfate de cuivre (II) pentahydraté : (Cu: 15) ; Sulfate manganeux monohydraté : (Mn: 52) ; Sulfate de al monohydraté : (Zn: 130) ; Sélénite de sodium : (Se: 0,15). Antioxygènes. CONSTITUANTS ANALYTIQUES : Protéine : 41,0 %, Teneur en matières grasses : 20,0 %, Ca brutes : 7,5 %, Cellulose brute : 2,0 %, DHA (Acide docosahexaénoïque) : 0,2 %, Acides gras Oméga 3: 07 %% Acides gras Oméga 6 : 2,8 %, Taurine : 0,15 %. Ce sac n'est pas un jouet. Pour éviter tout risque d'étouffement, laissez ce sac hors de portée de vost Ce sac n'est pas un jouet. Pour éviter tout risque d'étouffement, laissez ce sac hors de porte de v enfants et animaux de compagnie. À utiliser de préférence avant : / Numéros de lot et d'enregis voir sur le fond de l'emballage. A conserver dans un endroit frais et sec.
"""

    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("petfood-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func oneJunior() -> CatalogProduct {
        var p = CatalogProduct(barcode: Self.gtin, source: .pet, name: "one junior")
        p.categories = ["en:open-pet-food-facts"]
        return p
    }

    private func reading(_ text: String, validated: Bool = false, user: Bool = false) -> PetProfile.LabelReading {
        let sec = PetLabel.sections(text)
        return .init(text: text, declaration: sec.declaration, composition: sec.composition, additives: sec.additives,
                     analytics: sec.analytics.map(PetLabel.analytics) ?? PetLabel.analytics(text),
                     source: "photo déposée dans Open Pet Food Facts", photoDate: nil, readAt: Date(),
                     validated: validated, fromUserPhoto: user)
    }

    private func profile(_ code: String, label: PetProfile.LabelReading?, species: PetLabel.Species? = nil,
                         stage: PetLabel.LifeStage? = nil) -> PetProfile {
        PetProfile(gtin: PetProfile.key(code), aliases: [], species: species, lifeStage: stage, label: label, updatedAt: Date())
    }

    private func component(_ r: ProductScore.Result, _ name: String) -> ProductScore.Component? {
        r.components.first { $0.name == name }
    }

    // MARK: Lecture de l'etiquette

    func testRealLabelSplitsIntoItsFourParts() {
        let s = PetLabel.sections(Self.sharpLabel)
        XCTAssertTrue(s.declaration?.contains("ALIMENT COMPLET POUR CHATONS") == true, s.declaration ?? "nil")
        XCTAssertTrue(s.composition?.hasPrefix("Saumon") == true, s.composition ?? "nil")
        XCTAssertTrue(s.composition?.hasSuffix("Levures déshydratées") == true, "la composition s'arrete avant ADDITIFS")
        XCTAssertTrue(s.additives?.contains("Vitamine A : 27000") == true)
        XCTAssertTrue(s.analytics?.contains("Taurine : 0,15 %") == true)
        XCTAssertFalse(s.analytics?.contains("jouet") == true, "le texte d'apres (\"Ce sac n'est pas un jouet\") est coupe")
    }

    func testRealLabelAnalyticsWithUnitsAndNoInventedMoisture() {
        let a = PetLabel.analytics(PetLabel.sections(Self.sharpLabel).analytics!)
        XCTAssertEqual(a.protein, 41); XCTAssertEqual(a.fat, 20); XCTAssertEqual(a.ash, 7.5); XCTAssertEqual(a.fibre, 2)
        XCTAssertEqual(a.dha, 0.2); XCTAssertEqual(a.omega3, 0.7); XCTAssertEqual(a.omega6, 2.8); XCTAssertEqual(a.taurine, 0.15)
        XCTAssertNil(a.moisture, "l'etiquette ne declare pas l'humidite : on ne l'invente pas")
        XCTAssertNil(a.calcium, "calcium seulement dans les additifs (iodate de calcium) : pas une teneur")
    }

    func testRealIngredientsKeepParenthesesAndDecimals() {
        let ings = PetLabel.ingredients(PetLabel.sections(Self.sharpLabel).composition!)
        XCTAssertEqual(ings.count, 13, ings.map(\.name).description)
        XCTAssertEqual(ings[0].name, "Saumon"); XCTAssertEqual(ings[0].percent, 18)
        XCTAssertEqual(ings[0].detail, "dont tête, arête, chair")
        XCTAssertEqual(ings[2].name, "Blé"); XCTAssertEqual(ings[2].percent, 16)
        let hydro = ings.first { $0.name.hasPrefix("Hydrolysat") }!
        XCTAssertNil(hydro.percent, "0,025 % est la part d'un sous-ingredient, pas de l'hydrolysat")
        XCTAssertTrue(hydro.detail!.contains("0,025%"), "la virgule decimale ne coupe pas")
    }

    func testImpossibleValueFromALostCommaIsDropped() {
        let a = PetLabel.analytics(PetLabel.sections(Self.blurryLabel).analytics!)
        XCTAssertNil(a.omega3, "« 07 %% » sur la photo floue : 7 % d'omega 3 est impossible, donc vide")
        XCTAssertEqual(a.protein, 41)
    }

    func testFullSizePhotoIsOrientedAndReduced() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "opff-8445290938091-label", withExtension: "jpg"))
        let img = try XCTUnwrap(PetLabelReader.prepared(Data(contentsOf: url), maxPixels: 1000))
        XCTAssertEqual(max(img.width, img.height), 1000)
        XCTAssertGreaterThan(img.height, img.width, "photo en portrait gardee en portrait")
    }

    func testSharperPhotoIsPreferredOverBlurryOne() {
        let sharp = PetLabel.sections(Self.sharpLabel), blurry = PetLabel.sections(Self.blurryLabel)
        XCTAssertGreaterThan(PetLabelReader.quality(sharp, Self.sharpLabel), PetLabelReader.quality(blurry, Self.blurryLabel))
    }

    // MARK: Identite

    func testOneJuniorAloneSaysBothMissingFields() {
        let r = ProductScore.evaluate(oneJunior())
        XCTAssertNil(r.value)
        XCTAssertNil(ProductScore.species(oneJunior()))
        XCTAssertTrue(r.missing.contains { $0.hasPrefix("espèce") }, r.missing.description)
        XCTAssertTrue(r.missing.contains("composition"), "les deux manques sont dits ensemble : " + r.missing.description)
    }

    func testJuniorOrPurinaAloneDoNotMeanCat() {
        var p = CatalogProduct(barcode: "1", source: .pet, name: "Purina One Junior")
        p.brand = "Purina"
        let id = ProductScore.petIdentity(p)
        XCTAssertNil(id.species)
        XCTAssertFalse(id.ambiguous)
    }

    func testCatAndDogWordsTogetherAskTheUser() {
        var p = CatalogProduct(barcode: "1", source: .pet, name: "Croquettes chats et chiens")
        p.ingredientsText = "Poulet 30 %, riz"
        let r = ProductScore.evaluate(p)
        XCTAssertNil(r.value)
        XCTAssertTrue(ProductScore.petIdentity(p).ambiguous)
        XCTAssertTrue(r.missing.first?.contains("chat ET de chien") == true)
    }

    // MARK: Le cas complet, avec le calcul explique

    /// Calcul attendu, ecrit a la main depuis les regles "Animaux 2.0" (pas une note choisie) :
    /// - Composition /45 : saumon nomme en tete +15 ; 18 % declares (14 a 25 %) +8 ;
    ///   ble et proteines de pois dans les 5 premiers, 2 x 3 = -6 sur 10, donc +4. Total 27.
    /// - Nutrition /25 : chaton = croissance FEDIAF, 28 % de proteines MS minimum.
    ///   Constituants declares 41 + 20 + 7,5 + 2 = 70,5 % : ce ne peut pas etre une patee.
    ///   Humidite non declaree donc 0 a 14 % : proteines 41 a 47,7 % MS, valeur basse 41
    ///   = entre 28 + 10 et 28 + 20 : 20 points. Graisses >= 9, taurine 0,15 >= 0,10,
    ///   glucides 18 a 29,5 % MS (valeur basse sous 25) : pas de retrait. Total 20.
    /// - Additifs /30 : ni sucre, ni colorant, ni antioxydant surveille, additifs
    ///   nutritionnels non penalises. Total 30.
    /// = 77/100, confiance moyenne (lu automatiquement, humidite supposee).
    func testOneJuniorWithItsLabelPhotoIsScoredAsKitten() {
        let p = PetMerge.apply(profile(Self.gtin, label: reading(Self.sharpLabel)), to: oneJunior())
        let id = ProductScore.petIdentity(p)
        XCTAssertEqual(id.species, .cat); XCTAssertEqual(id.lifeStage, .young); XCTAssertEqual(id.kind, .complete)

        let r = ProductScore.evaluate(p)
        XCTAssertTrue(r.method.contains("chaton"), r.method)
        XCTAssertEqual(component(r, "Composition")?.points, 27, component(r, "Composition")?.details.description ?? "")
        let n = component(r, "Nutrition")
        XCTAssertEqual(n?.points, 20, n?.details.description ?? "")
        XCTAssertTrue(n?.details.first?.contains("chaton en croissance (FEDIAF 2021) : 28 %") == true, n?.details.first ?? "")
        XCTAssertTrue(n?.details.contains { $0.contains("70,5 %") } == true)
        XCTAssertTrue(n?.details.contains { $0.contains("Glucides estimés : 18 à 29,5 %") } == true, n?.details.description ?? "")
        XCTAssertEqual(component(r, "Additifs et ingrédients à éviter")?.points, 30)
        XCTAssertEqual(r.value, 27 + 20 + 30)
        XCTAssertEqual(r.confidence?.level, .medium)
        XCTAssertTrue(p.petFacts!.provenance.first!.contains("lue automatiquement, à vérifier"))
    }

    func testKittenIsNotComparedToTheAdultThreshold() {
        XCTAssertEqual(ProductScore.requirement(.cat, .young).protein, 28)
        XCTAssertEqual(ProductScore.requirement(.cat, .adult).protein, 25)
        XCTAssertEqual(ProductScore.requirement(.cat, nil).protein, 25)
        // 26,5 % MS : au-dessus du repere adulte, sous celui du chaton.
        func food(_ name: String) -> CatalogProduct {
            var p = CatalogProduct(barcode: "2", source: .pet, name: name)
            p.categories = ["en:cat-food"]
            p.ingredientsText = "Poulet 30 %, riz, minéraux"
            p.petAnalysis = .init(protein: 5.3, fat: 7.5, fibre: 0.5, ash: 2.5, moisture: 80)   // glucides 21 % MS : sans retrait
            return p
        }
        XCTAssertEqual(component(ProductScore.evaluate(food("Pâtée chat adulte")), "Nutrition")?.points, 8)
        XCTAssertEqual(component(ProductScore.evaluate(food("Pâtée chaton")), "Nutrition")?.points, 0)
    }

    func testMoistureIsNeverAssumedForAPossiblyWetFood() {
        var p = CatalogProduct(barcode: "3", source: .pet, name: "Aliment chat")
        p.categories = ["en:cat-food"]
        p.ingredientsText = "Poulet 40 %, bouillon, minéraux"
        p.petAnalysis = .init(protein: 10, fat: 5, fibre: 0.5, ash: 2, moisture: nil)
        let r = ProductScore.evaluate(p)
        XCTAssertNil(component(r, "Nutrition")?.points, "17,5 % declares : patee ou croquette, on ne sait pas")
        XCTAssertTrue(component(r, "Nutrition")!.details[1].contains("mi-points"))
        // Composition seule ramenee a 100 : c'etait 100/100 sans aucune valeur. Ici 12,5 au plus.
        XCTAssertLessThanOrEqual(r.value!, 88)
        XCTAssertTrue(r.missing.first?.contains("humidité") == true)
        XCTAssertEqual(r.confidence?.level, .low)
    }

    func testNutritionalAdditivesAreNotPoison() {
        var p = PetMerge.apply(profile(Self.gtin, label: reading(Self.sharpLabel)), to: oneJunior())
        XCTAssertTrue(p.petFacts!.additivesText!.contains("Sulfate de cuivre"))
        XCTAssertTrue(ProductScore.evaluate(p).flags.isEmpty, "vitamines et oligo-elements : aucune alerte")
        p.petFacts!.additivesText! += " ; colorant E102 ; BHA"
        let flags = ProductScore.evaluate(p).flags.map(\.code)
        XCTAssertTrue(flags.contains("colorant")); XCTAssertTrue(flags.contains("E320"))
    }

    // MARK: Decoupage : decimales, imbrication, faux amis

    func testFrenchAndEnglishDecimals() {
        let a = PetLabel.analytics("Crude protein 32.5 %, fat content: 14,5 %; crude ash 7 %; moisture 8.0%")
        XCTAssertEqual(a.protein, 32.5); XCTAssertEqual(a.fat, 14.5); XCTAssertEqual(a.ash, 7); XCTAssertEqual(a.moisture, 8)
        let i = PetLabel.ingredients("Chicken 26.5%, rice 10,5 %, maize")
        XCTAssertEqual(i.map(\.percent), [26.5, 10.5, nil])
    }

    func testNestedParenthesesDoNotGiveTheSubIngredientPercent() {
        let i = PetLabel.ingredients("Viandes et sous-produits animaux (dont poulet 4 %, dont [foie 1 %]), céréales, sucres")
        XCTAssertEqual(i.count, 3)
        XCTAssertNil(i[0].percent, "4 % est le poulet, pas toutes les viandes")
        XCTAssertEqual(ProductScore.petIngredients("viande et sous-produits animaux (dont poulet 4%), sucres").meatPercent, 4,
                       "le poulet declare compte comme part de viande nommee")
    }

    /// Lu par Vision a 2 400 px sur la photo nette : "Blé (16 %}".
    func testOCRBraceOrUnclosedParenthesisDoesNotSwallowTheList() {
        let i = PetLabel.ingredients("Saumon (18 %), Protéines de volaille, Blé (16 %}, Protéines de pois, Graisses animales")
        XCTAssertEqual(i.map(\.name), ["Saumon", "Protéines de volaille", "Blé", "Protéines de pois", "Graisses animales"])
        XCTAssertEqual(i[2].percent, 16)
        let open = PetLabel.ingredients("Saumon (18 %, Blé, Protéines de pois")
        XCTAssertEqual(open.count, 3, "parenthese jamais refermee : la liste reste decoupee")
    }

    func testFishIsNotPeaAndFishMealIsNotCereal() {
        var p = CatalogProduct(barcode: "4", source: .pet, name: "Croquettes chat")
        p.categories = ["en:cat-food"]
        p.ingredientsText = "Poisson 30 %, farine de poisson, pommes de terre, graisse de volaille, minéraux"
        let comp = component(ProductScore.evaluate(p), "Composition")!
        XCTAssertTrue(comp.details.contains { $0.contains("Ni céréale ni protéine végétale") }, comp.details.description)
    }

    // MARK: Identite canonique, alias, pas de fusion

    func testAliasesShareOneProfileAndSurviveRelaunch() throws {
        let store = ProductStore(directory: dir)
        try store.setPetSpecies(.cat, for: "0" + Self.gtin)          // GTIN-14 avec son zero
        XCTAssertEqual(store.petProfile(for: Self.gtin)?.species, .cat)
        XCTAssertEqual(store.petProfile(for: Self.gtin)?.aliases, ["0" + Self.gtin])
        try store.saveLabel(reading(Self.sharpLabel), for: Self.gtin)

        let relaunched = ProductStore(directory: dir)
        let p = relaunched.enriched(oneJunior())
        XCTAssertEqual(ProductScore.species(p), .cat)
        XCTAssertEqual(ProductScore.evaluate(p).value, 77, "meme note apres relance")
        // Scan (code a 14 chiffres) et recherche (code de la base) donnent la meme fiche.
        var scanned = CatalogProduct(barcode: "0" + Self.gtin, source: .pet, name: "one junior")
        scanned.categories = ["en:open-pet-food-facts"]
        XCTAssertEqual(ProductScore.evaluate(relaunched.enriched(scanned)).value, 77)
    }

    func testUPCAAndInvalidCodes() {
        XCTAssertEqual(PetProfile.key("012345678905"), "0012345678905")
        XCTAssertEqual(PetProfile.key("0012345678905"), PetProfile.key("012345678905"))
        XCTAssertNil(Barcode.normalize("123"))
        XCTAssertEqual(PetProfile.key("abc"), "abc", "code illisible : garde tel quel, jamais rattache a un autre")
    }

    func testAnotherGTINNeverGetsThisLabel() throws {
        let store = ProductStore(directory: dir)
        try store.saveLabel(reading(Self.sharpLabel), for: Self.gtin)
        var other = CatalogProduct(barcode: "7613035614482", source: .pet, name: "Purina One Junior poulet")
        other.categories = ["en:cat-food"]
        let e = store.enriched(other)
        XCTAssertNil(store.petProfile(for: other.barcode))
        XCTAssertNil(e.ingredientsText, "pas d'ingredients saumon sur une autre fiche au nom proche")
        XCTAssertNil(e.petAnalysis)
    }

    func testDifferentRecipeOnTheLabelIsNotMixedWithTheBase() {
        var base = oneJunior()
        base.ingredientsText = "Poulet 20 %, riz, protéines de volaille déshydratées, maïs"
        let p = PetMerge.apply(profile(Self.gtin, label: reading(Self.sharpLabel)), to: base)
        XCTAssertEqual(p.ingredientsText, base.ingredientsText, "la base garde sa composition")
        XCTAssertNil(p.petAnalysis, "valeurs d'une recette saumon pas collees sur une composition poulet")
        XCTAssertTrue(p.petFacts!.provenance.contains { $0.contains("valeurs non mélangées") })
    }

    /// Audit du build 52 : la meme recette au debut ne suffit plus, il faut valider.
    func testSameRecipeStartDoesNotFillValuesWithoutConfirmation() {
        var base = oneJunior()
        base.ingredientsText = PetLabel.sections(Self.sharpLabel).composition
        let p = PetMerge.apply(profile(Self.gtin, label: reading(Self.sharpLabel)), to: base)
        XCTAssertNil(p.petAnalysis)
        XCTAssertTrue(p.petFacts!.provenance.first!.contains("Relis et valide"))
        let confirmed = PetMerge.apply(profile(Self.gtin, label: reading(Self.sharpLabel, validated: true)), to: base)
        XCTAssertEqual(confirmed.petAnalysis?.protein, 41)
    }

    // MARK: Choix et corrections de l'utilisateur

    func testUserChoicesWinAndRecomputeImmediately() throws {
        let store = ProductStore(directory: dir)
        try store.saveLabel(reading(Self.sharpLabel), for: Self.gtin)
        XCTAssertTrue(ProductScore.evaluate(store.enriched(oneJunior())).method.contains("chaton"))
        try store.setPetLifeStage(.adult, for: Self.gtin)
        let r = ProductScore.evaluate(store.enriched(oneJunior()))
        XCTAssertTrue(r.method.hasSuffix("adulte"), r.method)
        XCTAssertTrue(component(r, "Nutrition")!.details[0].contains("chat adulte"))
        XCTAssertTrue(component(r, "Pour qui")!.details.last!.contains("stade de vie choisi par toi"))
    }

    func testValidatedCorrectionReplacesTheAutomaticReading() throws {
        let store = ProductStore(directory: dir)
        try store.saveLabel(reading(Self.blurryLabel), for: Self.gtin)
        var fixed = reading(Self.sharpLabel, validated: true)
        fixed.analytics.moisture = 8                                   // l'utilisateur ajoute ce qu'il lit sur le sac
        try store.saveLabel(fixed, for: Self.gtin)
        let p = ProductStore(directory: dir).enriched(oneJunior())
        XCTAssertEqual(p.petAnalysis?.moisture, 8)
        XCTAssertEqual(ProductScore.evaluate(p).confidence?.level, .high, "relue par l'utilisateur et humidite declaree")
        try store.removeLabel(for: Self.gtin)
        XCTAssertNil(store.enriched(oneJunior()).ingredientsText, "retirer la lecture rend la fiche d'origine")
    }

    func testTreatsAndComplementaryFoodsAreNotComparedToCompleteNeeds() {
        var p = CatalogProduct(barcode: "5", source: .pet, name: "Friandises pour chat au saumon")
        p.categories = ["en:cat-treats"]
        p.ingredientsText = "Saumon 60 %, amidon de pomme de terre, glycérine"
        p.petAnalysis = .init(protein: 30, fat: 10, fibre: 1, ash: 5, moisture: 20)
        let r = ProductScore.evaluate(p)
        XCTAssertNil(component(r, "Nutrition"))
        XCTAssertEqual(r.confidence?.level, .low)
        XCTAssertTrue(r.confidence!.reason.contains("friandise"))
    }

    // MARK: Reseau : panne n'est pas absence

    func testTimeoutIsReportedAsRetryableNotAsNoPhoto() async {
        var p = oneJunior()
        let none = await PetLabelReader.read(p, database: "OPFF")
        XCTAssertEqual(none.failureValue, .noPhoto)
        p.labelPhotos = [.init(kind: .nutrition, lang: "fr", url: URL(string: "https://images.openpetfoodfacts.org/x.jpg")!, uploaded: nil)]
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        let saved = PetLabelReader.session
        PetLabelReader.session = URLSession(configuration: c)
        StubURLProtocol.failWith = URLError(.timedOut)
        defer { PetLabelReader.session = saved; StubURLProtocol.failWith = nil }
        guard case .failure(.network) = await PetLabelReader.read(p, database: "OPFF") else { return XCTFail("un timeout doit rester reessayable") }
    }

    // MARK: Vision sur la vraie photo (reduite a 1800 px)

    func testOnDeviceOCRReadsTheRealLabelPhoto() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "opff-8445290938091-label", withExtension: "jpg"))
        let img = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let text = try await PetLabelReader.recognize(img)
        let p = PetMerge.apply(profile(Self.gtin, label: reading(text)), to: oneJunior())
        XCTAssertEqual(ProductScore.petIdentity(p).lifeStage, .young)
        XCTAssertEqual(p.petAnalysis?.protein, 41)
        XCTAssertTrue(p.ingredientsText?.hasPrefix("Saumon") == true, p.ingredientsText ?? text)
        XCTAssertNotNil(ProductScore.evaluate(p).value)
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let e) = self { return e }; return nil }
}
