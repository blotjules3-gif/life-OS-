import XCTest
import SwiftData
@testable import LifeOS

/// Tests unitaires du pipeline d'extraction — regex FR + pré-processeur.
/// Ne teste pas le pass LLM (nécessite Apple Intelligence dispo).
@MainActor
final class IntelligentExtractorTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([ProfileField.self, ProfileFieldRevision.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        ProfileStore.shared.setContext(container.mainContext)
    }

    override func tearDown() async throws {
        for f in ProfileStore.shared.allFields() {
            container.mainContext.delete(f)
        }
        try? container.mainContext.save()
        container = nil
        try await super.tearDown()
    }

    // MARK: - Regex poids

    func testExtract_weight_kg() async {
        let extractions = await IntelligentExtractor.extract(from: "je fais 74 kg")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "body.currentWeightKg" && ($0.value as? Double) == 74 }))
    }

    func testExtract_weight_kilos() async {
        let extractions = await IntelligentExtractor.extract(from: "je pèse 68 kilos")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "body.currentWeightKg" && ($0.value as? Double) == 68 }))
    }

    func testExtract_weight_decimal() async {
        let extractions = await IntelligentExtractor.extract(from: "je pèse 74,5 kg")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "body.currentWeightKg" && ($0.value as? Double) == 74.5 }))
    }

    // MARK: - Regex présent tense — "je pesais X, maintenant Y"

    func testExtract_weight_pivotMaintenant_keepsNewValue() async {
        let extractions = await IntelligentExtractor.extract(
            from: "je pesais 70 kg, maintenant je fais 74 kg"
        )
        let weights = extractions.filter { $0.fieldID == "body.currentWeightKg" }
        XCTAssertEqual(weights.count, 1, "Une seule extraction poids attendue (la nouvelle)")
        XCTAssertEqual(weights.first?.value as? Double, 74)
    }

    // MARK: - Regex taille

    func testExtract_height_meterCm() async {
        let extractions = await IntelligentExtractor.extract(from: "je mesure 1m78")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "body.heightCm" && ($0.value as? Double) == 178 }))
    }

    func testExtract_height_cm() async {
        let extractions = await IntelligentExtractor.extract(from: "je fais 182 cm")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "body.heightCm" && ($0.value as? Double) == 182 }))
    }

    func testExtract_height_meterMotComplet() async {
        let extractions = await IntelligentExtractor.extract(from: "je mesure 1 mètre 80")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "body.heightCm" && ($0.value as? Double) == 180 }))
    }

    // MARK: - Regex fréquence + chiffres en lettres

    func testExtract_frequency_digits() async {
        let extractions = await IntelligentExtractor.extract(from: "je vais 4 fois par semaine à la salle")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "fitness.gymFrequency" && ($0.value as? Int) == 4 }))
    }

    func testExtract_frequency_wordNumber() async {
        let extractions = await IntelligentExtractor.extract(from: "je vais trois fois par semaine à la salle")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "fitness.gymFrequency" && ($0.value as? Int) == 3 }))
    }

    // MARK: - Multi-extraction depuis un seul message

    func testExtract_multipleFields_fromSingleMessage() async {
        let extractions = await IntelligentExtractor.extract(
            from: "j'ai 28 ans, je pèse 74 kg et je vais 4 fois par semaine à la salle"
        )
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "body.ageYears" }))
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "body.currentWeightKg" }))
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "fitness.gymFrequency" }))
    }

    // MARK: - Régime

    func testExtract_diet_vegan() async {
        let extractions = await IntelligentExtractor.extract(from: "je suis vegan depuis 2 ans")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "nutrition.diet" && ($0.value as? String) == "vegan" }))
    }

    func testExtract_diet_vegetarien_avecAccent() async {
        let extractions = await IntelligentExtractor.extract(from: "je suis végétarien")
        XCTAssertTrue(extractions.contains(where: { $0.fieldID == "nutrition.diet" }))
    }

    // MARK: - Bornes / validation

    func testExtract_weight_outOfRange_ignored() async {
        let extractions = await IntelligentExtractor.extract(from: "je pèse 500 kg")
        XCTAssertFalse(extractions.contains(where: { $0.fieldID == "body.currentWeightKg" }))
    }

    func testExtract_empty_returnsEmpty() async {
        let extractions = await IntelligentExtractor.extract(from: "")
        XCTAssertTrue(extractions.isEmpty)
    }

    // MARK: - Persist

    func testExtractAndPersist_returnsChangesWithDiff() async {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 70.0, source: .chat, confidence: 0.9)
        let changes = await IntelligentExtractor.extractAndPersist(
            from: "je pèse 74 kg", source: .chat
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.previousValueString, "70.0")
        XCTAssertEqual(changes.first?.newValueString, "74.0")
        XCTAssertEqual(changes.first?.displayName, "Poids actuel")
    }
}
