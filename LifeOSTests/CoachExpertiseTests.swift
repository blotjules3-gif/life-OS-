import XCTest
@testable import LifeOS

@MainActor
final class CoachExpertiseTests: XCTestCase {

    // MARK: detectTopics — chaque topic doit être détecté sur des mots-clés types

    func testDetect_fitness_onWorkoutKeywords() {
        let topics = CoachExpertise.detectTopics(in: "j'ai fait 4 séries de squat aujourd'hui")
        XCTAssertTrue(topics.contains("sport") || topics.contains("fitness"),
                      "attendu sport/fitness, obtenu \(topics)")
    }

    func testDetect_nutrition_onFoodKeywords() {
        let topics = CoachExpertise.detectTopics(in: "combien de protéines par jour pour prendre du muscle")
        XCTAssertTrue(topics.contains("nutrition"),
                      "attendu nutrition, obtenu \(topics)")
    }

    func testDetect_sleep_onSleepKeywords() {
        let topics = CoachExpertise.detectTopics(in: "j'ai mal dormi et je suis crevé")
        XCTAssertTrue(topics.contains("sommeil") || topics.contains("sleep"),
                      "attendu sommeil, obtenu \(topics)")
    }

    func testDetect_mind_onMeditationKeyword() {
        let topics = CoachExpertise.detectTopics(in: "je veux commencer la meditation")
        XCTAssertTrue(topics.contains("mind"),
                      "attendu mind, obtenu \(topics)")
    }

    func testDetect_emptyMessage_returnsEmpty() {
        let topics = CoachExpertise.detectTopics(in: "")
        XCTAssertTrue(topics.isEmpty, "vide devrait retourner vide, obtenu \(topics)")
    }

    // MARK: blocks — output doit être non-vide pour un topic valide

    func testBlocks_forFitnessTopic_returnsContent() {
        let block = CoachExpertise.blocks(forTopics: ["fitness"])
        XCTAssertFalse(block.isEmpty, "un topic connu doit produire du contenu")
    }

    func testBlocks_forNoTopic_returnsMetaRuleOnly() {
        let block = CoachExpertise.blocks(forTopics: [])
        // Aucun topic → retour de la méta-règle seule (pas vide, mais court)
        XCTAssertFalse(block.isEmpty, "un fallback méta-règle doit exister")
    }

    // MARK: combinedBlocks — l'aggrégation ne doit pas exploser sur input vide

    func testCombinedBlocks_emptyActiveModules_doesNotCrash() {
        let block = CoachExpertise.combinedBlocks(activeModules: "", includeCycle: false)
        XCTAssertFalse(block.isEmpty, "fallback avec workout+nutrition doit exister")
    }

    func testCombinedBlocks_withCycle_addsCycleBlock() {
        let withCycle = CoachExpertise.combinedBlocks(activeModules: "sleep", includeCycle: true)
        let without = CoachExpertise.combinedBlocks(activeModules: "sleep", includeCycle: false)
        XCTAssertGreaterThan(withCycle.count, without.count,
                             "activer le cycle doit ajouter du contenu")
    }
}
