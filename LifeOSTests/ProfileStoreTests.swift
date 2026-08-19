import XCTest
import SwiftData
@testable import LifeOS

/// Tests unitaires de `ProfileStore` — upsert, contradictions, historique, confidence gate.
///
/// Container SwiftData isolé en mémoire pour chaque test, pas d'effets de bord.
@MainActor
final class ProfileStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([ProfileField.self, ProfileFieldRevision.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        ProfileStore.shared.setContext(context)
    }

    override func tearDown() async throws {
        // Purge tous les fields entre tests (le store est un singleton)
        for f in ProfileStore.shared.allFields() {
            context.delete(f)
        }
        try? context.save()
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Upsert basiques

    func testUpsert_createsField_whenAbsent() {
        let result = ProfileStore.shared.upsert(
            "body.currentWeightKg", value: 74.5, source: .chat, confidence: 0.95
        )
        guard case .created(let field) = result else {
            return XCTFail("Expected .created, got \(result)")
        }
        XCTAssertEqual(field.fieldID, "body.currentWeightKg")
        XCTAssertEqual(field.valueString, "74.5")
        XCTAssertEqual(field.confidence, 0.95, accuracy: 0.001)
        XCTAssertEqual(field.source, "chat")
    }

    func testUpsert_updatesExisting_withHigherConfidence() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 70.0, source: .chat, confidence: 0.7)
        let result = ProfileStore.shared.upsert("body.currentWeightKg", value: 72.0, source: .chat, confidence: 0.9)
        guard case .updated(let field) = result else {
            return XCTFail("Expected .updated, got \(result)")
        }
        XCTAssertEqual(field.valueString, "72.0")
        XCTAssertEqual(field.confidence, 0.9, accuracy: 0.001)
    }

    func testUpsert_ignoresLowConfidence() {
        let result = ProfileStore.shared.upsert(
            "body.currentWeightKg", value: 74, source: .chat, confidence: 0.4
        )
        guard case .ignored(let reason) = result else {
            return XCTFail("Expected .ignored, got \(result)")
        }
        XCTAssertEqual(reason, .confidenceTooLow)
    }

    func testUpsert_ignoresUnknownFieldID() {
        let result = ProfileStore.shared.upsert(
            "unknown.field.id", value: 42, source: .chat, confidence: 0.9
        )
        guard case .ignored(let reason) = result else {
            return XCTFail("Expected .ignored, got \(result)")
        }
        XCTAssertEqual(reason, .unknownFieldID)
    }

    // MARK: - History

    func testUpsert_createsRevision_beforeUpdate() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 70.0, source: .chat, confidence: 0.9)
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 72.0, source: .chat, confidence: 0.9)
        let field = ProfileStore.shared.field("body.currentWeightKg")
        XCTAssertEqual(field?.history.count, 1, "Une révision doit être créée avant l'update")
        XCTAssertEqual(field?.history.first?.previousValueString, "70.0")
    }

    func testUpsert_noHistory_forFirstInsertion() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 70, source: .chat, confidence: 0.9)
        let field = ProfileStore.shared.field("body.currentWeightKg")
        XCTAssertEqual(field?.history.count, 0)
    }

    // MARK: - Contradiction / source protection

    func testUpsert_blocksLLM_overManual() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 70.0, source: .manual, confidence: 1.0)
        let result = ProfileStore.shared.upsert("body.currentWeightKg", value: 75.0, source: .chat, confidence: 0.95)
        guard case .blocked(let contradiction) = result else {
            return XCTFail("Expected .blocked, got \(result)")
        }
        XCTAssertEqual(contradiction.newValueString, "75.0")
        // La valeur d'origine ne doit PAS avoir changé
        XCTAssertEqual(ProfileStore.shared.field("body.currentWeightKg")?.valueString, "70.0")
    }

    func testUpsert_allowsOverwriteManual_whenExplicit() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 70, source: .manual, confidence: 1.0)
        let result = ProfileStore.shared.upsert(
            "body.currentWeightKg", value: 75, source: .chat, confidence: 0.95, allowOverwriteManual: true
        )
        guard case .updated = result else {
            return XCTFail("Expected .updated, got \(result)")
        }
        XCTAssertEqual(ProfileStore.shared.field("body.currentWeightKg")?.valueString, "75")
    }

    // MARK: - missingFields

    func testMissingFields_excludesFilledWithHighConfidence() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 74, source: .manual, confidence: 1.0)
        let missing = ProfileStore.shared.missingFields(minImportance: .critical)
        XCTAssertFalse(missing.contains(where: { $0.id == "body.currentWeightKg" }))
    }

    func testMissingFields_excludesDepsNotSatisfied() {
        // body.targetWeightKg dépend de body.currentWeightKg
        // Sans currentWeight, target ne doit pas être proposé
        let missing = ProfileStore.shared.missingFields(minImportance: .medium)
        XCTAssertFalse(missing.contains(where: { $0.id == "body.targetWeightKg" }))
    }

    // MARK: - Type decoding

    func testValueDecoding_int() {
        _ = ProfileStore.shared.upsert("fitness.gymFrequency", value: 4, source: .chat, confidence: 0.9)
        let v: Int? = ProfileStore.shared.value("fitness.gymFrequency")
        XCTAssertEqual(v, 4)
    }

    func testValueDecoding_double() throws {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 74.5, source: .chat, confidence: 0.9)
        let v = try XCTUnwrap(ProfileStore.shared.value("body.currentWeightKg") as Double?)
        XCTAssertEqual(v, 74.5, accuracy: 0.001)
    }
}
