import XCTest
@testable import LifeOS

/// Vérifie les nouveaux matchers Loop 9 : nutrition, habits completions, todos.
@MainActor
final class ToolEnrichmentCrossDomainTests: XCTestCase {

    // MARK: - Nutrition

    func testMatchesTodayNutrition_variants() {
        XCTAssertTrue(ToolEnrichment.matchesTodayNutrition(normalize("j'ai mangé quoi aujourd'hui ?")))
        XCTAssertTrue(ToolEnrichment.matchesTodayNutrition(normalize("combien de calories aujourd'hui")))
        XCTAssertTrue(ToolEnrichment.matchesTodayNutrition(normalize("mes protéines du jour")))
        XCTAssertTrue(ToolEnrichment.matchesTodayNutrition(normalize("mes macros aujourd'hui")))
    }

    func testMatchesTodayNutrition_negatives() {
        XCTAssertFalse(ToolEnrichment.matchesTodayNutrition(normalize("bonjour ça va")))
        XCTAssertFalse(ToolEnrichment.matchesTodayNutrition(normalize("il fait beau")))
    }

    // MARK: - Habitudes

    func testMatchesHabitCompletions_variants() {
        XCTAssertTrue(ToolEnrichment.matchesHabitCompletions(normalize("mes habitudes du jour")))
        XCTAssertTrue(ToolEnrichment.matchesHabitCompletions(normalize("combien de séances cette semaine")))
        XCTAssertTrue(ToolEnrichment.matchesHabitCompletions(normalize("mon streak")))
        XCTAssertTrue(ToolEnrichment.matchesHabitCompletions(normalize("j'ai fait quoi comme sport")))
    }

    func testMatchesHabitCompletions_negatives() {
        XCTAssertFalse(ToolEnrichment.matchesHabitCompletions(normalize("j'ai bien dormi")))
    }

    // MARK: - Todos

    func testMatchesTodayTodos_variants() {
        XCTAssertTrue(ToolEnrichment.matchesTodayTodos(normalize("mes tâches")))
        XCTAssertTrue(ToolEnrichment.matchesTodayTodos(normalize("quoi faire aujourd'hui ?")))
        XCTAssertTrue(ToolEnrichment.matchesTodayTodos(normalize("ma todo")))
    }

    func testMatchesTodayTodos_negatives() {
        XCTAssertFalse(ToolEnrichment.matchesTodayTodos(normalize("quoi ?")))
    }

    // MARK: - Helper

    private func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}
