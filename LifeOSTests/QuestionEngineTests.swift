import XCTest
import SwiftData
@testable import LifeOS

/// Tests unitaires du QuestionEngine — priorité, dépendances, fallback template.
/// Ne teste pas la formulation LLM (nécessite Apple Intelligence dispo).
@MainActor
final class QuestionEngineTests: XCTestCase {

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

    // MARK: - Ranking

    func testRankedCandidates_ordersByPriorityScore() {
        let candidates = QuestionEngine.rankedCandidates(subGoal: .muscleGain, minImportance: .medium)
        guard candidates.count >= 2 else {
            return XCTFail("Expected at least 2 candidates")
        }
        XCTAssertGreaterThanOrEqual(candidates[0].score, candidates[1].score)
    }

    func testRankedCandidates_excludesDepsNotSatisfied() {
        // body.targetWeightKg dépend de body.currentWeightKg
        // Sans currentWeight, target ne doit pas être ranké
        let candidates = QuestionEngine.rankedCandidates(subGoal: .muscleGain, minImportance: .medium)
        XCTAssertFalse(candidates.contains(where: { $0.spec.id == "body.targetWeightKg" }))
    }

    func testRankedCandidates_includesDepsAfterFilled() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 74, source: .chat, confidence: 0.95)
        let candidates = QuestionEngine.rankedCandidates(subGoal: .muscleGain, minImportance: .medium)
        XCTAssertTrue(candidates.contains(where: { $0.spec.id == "body.targetWeightKg" }))
    }

    // MARK: - PriorityScore

    func testPriorityScore_criticalHigherThanMedium() {
        let critical = ProfileFieldCatalog.all["body.currentWeightKg"]!  // critical
        let medium = ProfileFieldCatalog.all["nutrition.mealsPerDay"]!    // medium
        let s1 = QuestionEngine.priorityScore(spec: critical, subGoal: .muscleGain)
        let s2 = QuestionEngine.priorityScore(spec: medium, subGoal: .muscleGain)
        XCTAssertGreaterThan(s1, s2)
    }

    func testPriorityScore_droppedForFilledField() {
        let spec = ProfileFieldCatalog.all["body.currentWeightKg"]!
        let scoreBefore = QuestionEngine.priorityScore(spec: spec, subGoal: .muscleGain)
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 74, source: .chat, confidence: 1.0)
        let scoreAfter = QuestionEngine.priorityScore(spec: spec, subGoal: .muscleGain)
        XCTAssertLessThan(scoreAfter, scoreBefore)
    }

    // MARK: - Template fallback

    func testTemplateQuestion_containsDisplayName() {
        let spec = ProfileFieldCatalog.all["body.currentWeightKg"]!
        let q = QuestionEngine.templateQuestion(for: spec)
        XCTAssertTrue(q.contains("Poids actuel"))
    }

    func testTemplateQuestion_containsUnit() {
        let spec = ProfileFieldCatalog.all["body.currentWeightKg"]!
        let q = QuestionEngine.templateQuestion(for: spec)
        XCTAssertTrue(q.contains("kg"))
    }
}
