import XCTest
import SwiftData
@testable import LifeOS

/// Tests scénarios — vérifie que le pipeline coach (extraction + intent + classification
/// + category detection) se comporte correctement sur des conversations réalistes.
///
/// Ne teste PAS la génération LLM elle-même (Apple Intelligence pas dispo en tests).
/// Teste ce qui EST déterministe : extraction, intent, catégorisation.
@MainActor
final class CoachScenarioTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([
            ProfileField.self, ProfileFieldRevision.self,
            AIMessage.self, MemoryEntry.self,
            Habit.self, HabitCompletion.self,
            TodoItem.self
        ])
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

    // MARK: - Scénario 1 : onboarding profil rapide

    func testScenario_onboardingQuickProfile() async {
        // "j'ai 28 ans, je fais 74 kg pour 1m80 et 4 séances de sport par semaine"
        let changes = await IntelligentExtractor.extractAndPersist(
            from: "j'ai 28 ans, je fais 74 kg pour 1m80 et 4 séances de sport par semaine",
            source: .chat
        )
        let fieldIDs = Set(changes.map { $0.fieldID })
        XCTAssertTrue(fieldIDs.contains("body.ageYears"), "age doit être extrait")
        XCTAssertTrue(fieldIDs.contains("body.currentWeightKg"), "poids doit être extrait")
        XCTAssertTrue(fieldIDs.contains("body.heightCm"), "taille doit être extraite")
        XCTAssertTrue(fieldIDs.contains("fitness.gymFrequency"), "fréquence doit être extraite")
    }

    // MARK: - Scénario 2 : correction d'une valeur ("je pesais X, maintenant Y")

    func testScenario_weightCorrection() async {
        // Initial
        _ = ProfileStore.shared.upsert("body.currentWeightKg", value: 70.0, source: .chat, confidence: 0.9)
        // Message : "je pesais 70 kg, maintenant je fais 74 kg"
        let changes = await IntelligentExtractor.extractAndPersist(
            from: "je pesais 70 kg, maintenant je fais 74 kg",
            source: .chat
        )
        let weightChanges = changes.filter { $0.fieldID == "body.currentWeightKg" }
        XCTAssertEqual(weightChanges.count, 1, "Une seule extraction poids (la nouvelle)")
        XCTAssertEqual(weightChanges.first?.newValueString, "74.0")
    }

    // MARK: - Scénario 3 : demande d'action naturelle

    func testScenario_createHabitNaturalLanguage() async {
        let intents = await IntentExecutor.detectAndExecute(
            from: "tu peux créer une habitude méditation",
            context: container.mainContext
        )
        let habitIntents = intents.filter { $0.type == .createHabit }
        XCTAssertGreaterThanOrEqual(habitIntents.count, 1, "au moins une habitude créée")
        XCTAssertTrue(
            habitIntents.contains(where: { $0.title.lowercased().contains("méditation") }),
            "titre doit contenir 'méditation'"
        )
    }

    // MARK: - Scénario 4 : multi-catégorie détectée

    func testScenario_multiCategoryDetection() {
        // "je dors mal et j'arrive pas à progresser à la salle"
        let categories = CategoryDetector.detect(from: "je dors mal et j'arrive pas à progresser à la salle")
        let names = categories.map { $0.category }
        XCTAssertTrue(names.contains("sleep"), "sleep détecté")
        XCTAssertTrue(names.contains("fitness"), "fitness détecté")
    }

    // MARK: - Scénario 5 : détresse court-circuit

    func testScenario_distressShortCircuit() {
        XCTAssertTrue(CoachSafetyScanner.detectsDistress(in: "je veux me faire du mal ce soir"))
        XCTAssertTrue(CoachSafetyScanner.distressReply.contains("3114"))
    }

    // MARK: - Scénario 6 : classification message frustré

    func testScenario_frustrationClassification() {
        let classif = MessageClassifier.classify("tu comprends rien à ce que je veux !")
        XCTAssertEqual(classif.sentiment, .frustrated)
        XCTAssertEqual(classif.intentType, .complaint)
    }
}
