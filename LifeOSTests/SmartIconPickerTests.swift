import XCTest
@testable import LifeOS

final class SmartIconPickerTests: XCTestCase {

    // MARK: - Tests de base et limites

    func testEmptyQueryReturns20DefaultIcons() {
        let suggestions = IconSuggestionEngine.suggest(for: "")
        XCTAssertEqual(suggestions.count, 20)
        XCTAssertEqual(suggestions, IconSuggestionEngine.default20)
    }

    func testWhitespaceOnlyQueryReturns20DefaultIcons() {
        let suggestions = IconSuggestionEngine.suggest(for: "   \n\t  ")
        XCTAssertEqual(suggestions.count, 20)
        XCTAssertEqual(suggestions, IconSuggestionEngine.default20)
    }

    func testSuggestionsContainNoDuplicates() {
        let queries = ["workout", "eau", "sommeil", "code", "lecture", "argent", "ménage", "xyzabc"]
        for q in queries {
            let suggestions = IconSuggestionEngine.suggest(for: q, limit: 20)
            XCTAssertEqual(suggestions.count, 20, "Doit toujours retourner 20 icônes pour '\(q)'")
            let uniqueSet = Set(suggestions)
            XCTAssertEqual(uniqueSet.count, suggestions.count, "Les 20 icônes doivent être uniques pour '\(q)'")
        }
    }

    // MARK: - Mots-clés Sport & Fitness

    func testWorkoutQueryPrioritizesSportIcons() {
        let suggestions = IconSuggestionEngine.suggest(for: "workout")
        XCTAssertEqual(suggestions.count, 20)
        XCTAssertTrue(suggestions.prefix(5).contains("dumbbell.fill"))
        XCTAssertTrue(suggestions.prefix(5).contains("figure.strengthtraining.traditional"))
    }

    func testMuscuQueryPrioritizesDumbbell() {
        let suggestions = IconSuggestionEngine.suggest(for: "séance de muscu")
        XCTAssertTrue(suggestions.prefix(3).contains("dumbbell.fill"))
    }

    func testRunningQueryPrioritizesRunIcon() {
        let suggestions = IconSuggestionEngine.suggest(for: "course à pied 10km")
        XCTAssertTrue(suggestions.prefix(3).contains("figure.run"))
    }

    // MARK: - Mots-clés Hydratation & Santé

    func testWaterQueryPrioritizesDropAndWaterbottle() {
        let suggestions = IconSuggestionEngine.suggest(for: "boire 2L eau")
        XCTAssertTrue(suggestions.prefix(3).contains("drop.fill"))
        XCTAssertTrue(suggestions.prefix(5).contains("waterbottle.fill"))
    }

    // MARK: - Mots-clés Lecture & Études

    func testReadingQueryPrioritizesBook() {
        let suggestions = IconSuggestionEngine.suggest(for: "lire 20 pages")
        XCTAssertTrue(suggestions.prefix(3).contains("book.fill"))
    }

    // MARK: - Mots-clés Sommeil & Bien-être avec accents

    func testSleepQueryPrioritizesBedAndMoon() {
        let suggestions = IconSuggestionEngine.suggest(for: "dormir 8h")
        XCTAssertTrue(suggestions.prefix(3).contains("bed.double.fill"))
        XCTAssertTrue(suggestions.prefix(5).contains("moon.fill"))
    }

    func testMeditationWithAccentsMatchesProperly() {
        let suggestions = IconSuggestionEngine.suggest(for: "méditation du matin")
        XCTAssertTrue(suggestions.prefix(5).contains("figure.yoga") || suggestions.prefix(5).contains("leaf.fill"))
    }

    // MARK: - Catalogue complet

    func testCatalogHasMoreThan100Icons() {
        let totalCount = IconSuggestionEngine.catalog.reduce(0) { $0 + $1.icons.count }
        XCTAssertGreaterThan(totalCount, 100, "Le catalogue doit contenir plus de 100 symboles")
    }
}
