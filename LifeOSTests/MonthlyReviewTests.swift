import XCTest
import SwiftData
@testable import LifeOS

@MainActor
final class MonthlyReviewTests: XCTestCase {

    /// Container in-memory dédié aux tests — évite que le `SharedModelContextProvider`
    /// hérite d'un contexte d'un test précédent (qui aurait pu être détruit
    /// → context dangling → generator produit un output non-déterministe).
    /// Fix F02 audit forensique.
    private var testContainer: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "coach.monthly.enabled")
        UserDefaults.standard.removeObject(forKey: "coach.monthly.lastConfig")
        // Reset SharedModelContextProvider avec un container in-memory
        // vide dédié pour ce test — garantit un état propre.
        let schema = Schema([Habit.self, HabitCompletion.self, VitalRecord.self, FoodEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        testContainer = try ModelContainer(for: schema, configurations: [config])
        SharedModelContextProvider.shared.setContext(testContainer.mainContext)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "coach.monthly.enabled")
        UserDefaults.standard.removeObject(forKey: "coach.monthly.lastConfig")
        testContainer = nil
        try await super.tearDown()
    }

    // MARK: - Scheduler prefs

    func testScheduler_defaultEnabled() {
        XCTAssertTrue(MonthlyReviewScheduler.isEnabled)
    }

    func testScheduler_disablePersists() {
        MonthlyReviewScheduler.isEnabled = false
        XCTAssertFalse(MonthlyReviewScheduler.isEnabled)
    }

    // MARK: - Generator

    func testGenerator_neverReturnsEmpty() {
        let summary = MonthlyReviewGenerator.generateSummary()
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("30 derniers jours"))
    }

    func testGenerator_startsWithHeader() {
        let summary = MonthlyReviewGenerator.generateSummary()
        XCTAssertTrue(summary.hasPrefix("Bilan des 30 derniers jours"))
    }

    func testGenerator_endsWithQuestionOrFallback() {
        let summary = MonthlyReviewGenerator.generateSummary()
        // Soit "Qu'est-ce que tu veux améliorer" (données présentes)
        // soit "Pas encore assez de données" (fallback)
        XCTAssertTrue(
            summary.contains("Qu'est-ce que tu veux améliorer") ||
            summary.contains("Pas encore assez de données")
        )
    }
}
