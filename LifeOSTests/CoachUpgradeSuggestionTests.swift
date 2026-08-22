import XCTest
@testable import LifeOS

/// Vérifie la logique de suggestion d'upgrade coach cloud.
///
/// Règles Loop 7 :
/// - Aucune suggestion si l'user a une clé cloud (déjà configuré)
/// - Aucune suggestion si l'user a snoozé récemment (< 7 jours)
/// - Suggestion active si ≥ 3 dislikes en 24h ET pas de clé cloud
@MainActor
final class CoachUpgradeSuggestionTests: XCTestCase {

    private let feedbackFilename = "coach_feedback.jsonl"

    override func setUp() {
        super.setUp()
        CoachUpgradeSuggestion.shared.reset()
        // Reset le fichier feedback (le store lit un JSONL en Documents)
        resetFeedbackFile()
        // Retire toutes les clés cloud enregistrées
        for slot in AIProviderCredentials.Slot.allCases {
            AIProviderCredentials.shared.deleteKey(for: slot)
        }
    }

    override func tearDown() {
        CoachUpgradeSuggestion.shared.reset()
        resetFeedbackFile()
        for slot in AIProviderCredentials.Slot.allCases {
            AIProviderCredentials.shared.deleteKey(for: slot)
        }
        super.tearDown()
    }

    // MARK: - Pas de suggestion sans frustration

    func testShouldSuggest_noDislikes_returnsFalse() {
        XCTAssertFalse(CoachUpgradeSuggestion.shared.shouldSuggestUpgrade())
    }

    func testShouldSuggest_lessThanThreeDislikes_returnsFalse() {
        CoachFeedbackStore.record(.dislike, response: "réponse 1")
        CoachFeedbackStore.record(.dislike, response: "réponse 2")
        XCTAssertFalse(CoachUpgradeSuggestion.shared.shouldSuggestUpgrade())
    }

    // MARK: - Frustration détectée

    func testShouldSuggest_threeDislikes_returnsTrue() {
        CoachFeedbackStore.record(.dislike, response: "réponse 1")
        CoachFeedbackStore.record(.dislike, response: "réponse 2")
        CoachFeedbackStore.record(.dislike, response: "réponse 3")
        XCTAssertTrue(CoachUpgradeSuggestion.shared.shouldSuggestUpgrade())
    }

    // MARK: - Kill switch : clé cloud configurée

    func testShouldSuggest_hasCloudKey_returnsFalse() {
        // Simule que l'user a déjà branché une clé (peu importe laquelle)
        _ = AIProviderCredentials.shared.setKey(
            "sk-" + String(repeating: "a", count: 45),
            for: .openai
        )
        // Même avec 5 dislikes, ne doit pas suggérer
        for i in 0..<5 {
            CoachFeedbackStore.record(.dislike, response: "réponse \(i)")
        }
        XCTAssertFalse(CoachUpgradeSuggestion.shared.shouldSuggestUpgrade())
    }

    // MARK: - Snooze

    func testDismissForNow_disablesSuggestion() {
        // Setup frustration
        for i in 0..<5 {
            CoachFeedbackStore.record(.dislike, response: "réponse \(i)")
        }
        XCTAssertTrue(CoachUpgradeSuggestion.shared.shouldSuggestUpgrade())

        // Dismiss → plus de suggestion
        CoachUpgradeSuggestion.shared.dismissForNow()
        XCTAssertFalse(CoachUpgradeSuggestion.shared.shouldSuggestUpgrade())
    }

    func testReset_clearsSnooze() {
        CoachUpgradeSuggestion.shared.dismissForNow()
        for i in 0..<5 {
            CoachFeedbackStore.record(.dislike, response: "réponse \(i)")
        }
        XCTAssertFalse(CoachUpgradeSuggestion.shared.shouldSuggestUpgrade())

        CoachUpgradeSuggestion.shared.reset()
        XCTAssertTrue(CoachUpgradeSuggestion.shared.shouldSuggestUpgrade())
    }

    // MARK: - CoachFeedbackStore.recentDislikeCount

    func testRecentDislikeCount_countsWithinWindow() {
        CoachFeedbackStore.record(.dislike, response: "1")
        CoachFeedbackStore.record(.like, response: "2")   // like, pas dislike
        CoachFeedbackStore.record(.dislike, response: "3")
        // Window large : capte les 2 dislikes
        XCTAssertEqual(CoachFeedbackStore.recentDislikeCount(within: 86400), 2)
    }

    func testRecentDislikeCount_veryNarrowWindow_returnsZero() {
        CoachFeedbackStore.record(.dislike, response: "1")
        // Window de 0.001s : les dislikes viennent d'être écrits mais on cherche
        // dans une fenêtre quasi vide → 0.
        // (test asymptotique — la borne est stricte >= cutoff)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(CoachFeedbackStore.recentDislikeCount(within: 0.001), 0)
    }

    // MARK: - Helpers

    private func resetFeedbackFile() {
        guard let dir = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return }
        let url = dir.appendingPathComponent(feedbackFilename)
        try? FileManager.default.removeItem(at: url)
    }
}
