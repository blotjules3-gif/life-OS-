import XCTest
import SwiftData
@testable import LifeOS

@MainActor
final class MonthlyReviewTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "coach.monthly.enabled")
        UserDefaults.standard.removeObject(forKey: "coach.monthly.lastConfig")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "coach.monthly.enabled")
        UserDefaults.standard.removeObject(forKey: "coach.monthly.lastConfig")
        super.tearDown()
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
