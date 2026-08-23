import XCTest
@testable import LifeOS

/// Vérifie que la détection auto d'à côté fonctionne :
/// - Reformulation similaire dans les 90s = signal d'à côté
/// - Message très différent = pas de signal
/// - Hors fenêtre = pas de signal
@MainActor
final class CoachOffTopicDetectorTests: XCTestCase {

    // MARK: - Jaccard

    func testJaccard_identicalTexts_returnsOne() {
        let s = "j'ai mal dormi cette nuit"
        XCTAssertEqual(CoachOffTopicDetector.jaccardSimilarity(s, s), 1.0)
    }

    func testJaccard_completelyDifferent_returnsZero() {
        let a = "je fais du sport"
        let b = "chaleur atmosphérique"
        XCTAssertLessThan(CoachOffTopicDetector.jaccardSimilarity(a, b), 0.1)
    }

    func testJaccard_reformulation_returnsHigh() {
        let a = "j'ai mal dormi cette nuit"
        let b = "j'ai mal dormi hier soir"
        // "mal", "dormi" en commun → similarité forte
        XCTAssertGreaterThan(CoachOffTopicDetector.jaccardSimilarity(a, b), 0.3)
    }

    func testJaccard_ignoresStopwords() {
        // "que", "qui" sont dans stopwords → devraient être filtrés
        let a = "qui suis-je"
        let b = "je"
        XCTAssertEqual(CoachOffTopicDetector.jaccardSimilarity(a, b), 0)
    }

    func testJaccard_isCaseInsensitiveAndAccentFolded() {
        let a = "SPORT énergie"
        let b = "sport energie"
        XCTAssertEqual(CoachOffTopicDetector.jaccardSimilarity(a, b), 1.0)
    }
}
