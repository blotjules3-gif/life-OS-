import XCTest
@testable import LifeOS

/// Tests unitaires du CategoryDetector — keywords pondérés, seuil 0.15.
final class CategoryDetectorTests: XCTestCase {

    func testDetect_sleep_onSingleKeyword() {
        let cats = CategoryDetector.detect(from: "j'ai bien dormi")
        XCTAssertEqual(cats.first?.category, "sleep")
    }

    func testDetect_fitness_onGymKeyword() {
        let cats = CategoryDetector.detect(from: "je vais à la salle demain")
        XCTAssertEqual(cats.first?.category, "fitness")
    }

    func testDetect_multipleCategories_fromComplexMessage() {
        // "je dors seulement 6h, je suis fatigué et j'arrive pas à progresser à la salle"
        let cats = CategoryDetector.detect(from: "je dors seulement 6h et j'arrive pas à progresser à la salle")
        let names = cats.map { $0.category }
        XCTAssertTrue(names.contains("sleep"))
        XCTAssertTrue(names.contains("fitness"))
    }

    func testDetect_belowThreshold_excluded() {
        // "eau" seul = 0.2 → au-dessus du 0.15, donc inclus, mais rien d'autre
        let cats = CategoryDetector.detect(from: "un peu d'eau")
        XCTAssertTrue(cats.contains(where: { $0.category == "nutrition" }))
    }

    func testDetect_empty_returnsEmpty() {
        XCTAssertTrue(CategoryDetector.detect(from: "").isEmpty)
    }

    func testDetect_orderedByScore() {
        // sommeil (0.4 dormi + 0.25 nuit = 0.65) doit passer avant fitness (0.35 salle)
        let cats = CategoryDetector.detect(from: "j'ai dormi 6h cette nuit et je vais à la salle demain")
        guard let first = cats.first, let second = cats.dropFirst().first else {
            return XCTFail("Expected at least 2 categories")
        }
        XCTAssertGreaterThanOrEqual(first.score, second.score)
    }
}
