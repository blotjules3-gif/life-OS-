import XCTest
import SwiftData
@testable import LifeOS

/// Vérifie que `GoalsProgress` retourne les bons objectifs actifs + %
/// progression selon les ProfileField configurés.
@MainActor
final class GoalsProgressTests: XCTestCase {

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

    func testActiveGoals_noProfile_returnsEmpty() {
        XCTAssertEqual(GoalsProgress.activeGoals().count, 0)
    }

    func testActiveGoals_weightGoalAndCurrent_hasProgressRatio() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 78.0, source: .chat, confidence: 0.9)
        _ = ProfileStore.shared.upsert("body.targetWeightKg", value: 74.0, source: .chat, confidence: 0.9)
        let goals = GoalsProgress.activeGoals()
        let weight = goals.first { $0.label == "Objectif poids" }
        XCTAssertNotNil(weight)
        XCTAssertEqual(weight?.targetValue, 74.0)
        XCTAssertEqual(weight?.currentValue, 78.0)
        XCTAssertNotNil(weight?.progressRatio, "Ratio doit être calculable avec target+current")
    }

    func testActiveGoals_targetReached_ratioIsOne() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 74.2, source: .chat, confidence: 0.9)
        _ = ProfileStore.shared.upsert("body.targetWeightKg", value: 74.0, source: .chat, confidence: 0.9)
        let goals = GoalsProgress.activeGoals()
        XCTAssertEqual(goals.first?.progressRatio, 1.0, "Écart < 0.5 kg = objectif atteint")
    }

    func testActiveGoals_multipleGoals_areAllListed() {
        _ = ProfileStore.shared.upsert("body.targetWeightKg", value: 74.0, source: .chat, confidence: 0.9)
        _ = ProfileStore.shared.upsert("fitness.gymFrequency", value: 4, source: .chat, confidence: 0.9)
        _ = ProfileStore.shared.upsert("nutrition.kcalGoal", value: 2500, source: .chat, confidence: 0.9)
        let goals = GoalsProgress.activeGoals()
        XCTAssertEqual(goals.count, 3)
    }

    func testPromptBlock_noGoals_returnsEmpty() {
        XCTAssertEqual(GoalsProgress.promptBlock(), "")
    }

    func testPromptBlock_withWeightGoal_containsExpectedFormat() {
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 78.0, source: .chat, confidence: 0.9)
        _ = ProfileStore.shared.upsert("body.targetWeightKg", value: 74.0, source: .chat, confidence: 0.9)
        let block = GoalsProgress.promptBlock()
        XCTAssertTrue(block.contains("Objectifs actifs"))
        XCTAssertTrue(block.contains("Objectif poids"))
        XCTAssertTrue(block.contains("78"))
        XCTAssertTrue(block.contains("74"))
    }
}
