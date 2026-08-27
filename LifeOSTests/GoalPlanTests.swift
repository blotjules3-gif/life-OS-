import XCTest
import SwiftData
@testable import LifeOS

/// Tests fondations Loop 24 Goal-Plan-Partner :
/// - `GoalIntentClassifier` reconnaît les intents utilisateur
/// - `GoalPlanTemplate` génère un plan cohérent par kind
/// - `PartnerCatalog` reste vide par défaut (règle absolue § 17)
@MainActor
final class GoalPlanTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        // Container in-memory dédié pour éviter pollution d'un test précédent
        // qui aurait branché un ProfileStore/SharedModelContextProvider stale.
        let schema = Schema([ProfileField.self, ProfileFieldRevision.self, UserGoal.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        ProfileStore.shared.setContext(container.mainContext)
        SharedModelContextProvider.shared.setContext(container.mainContext)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - GoalIntentClassifier

    func testDetect_weightLoss_withMagnitude() {
        let d = GoalIntentClassifier.detect(in: "je veux perdre 5 kg")
        XCTAssertEqual(d?.kind, .weightLoss)
        XCTAssertEqual(d?.magnitude, 5.0)
        XCTAssertEqual(d?.unit, "kg")
    }

    func testDetect_weightLoss_withoutMagnitude() {
        let d = GoalIntentClassifier.detect(in: "j'aimerais maigrir un peu")
        XCTAssertEqual(d?.kind, .weightLoss)
        XCTAssertEqual(d?.magnitude, 0)
    }

    func testDetect_muscleGain() {
        XCTAssertEqual(GoalIntentClassifier.detect(in: "je veux prendre du muscle")?.kind, .muscleGain)
        XCTAssertEqual(GoalIntentClassifier.detect(in: "me muscler")?.kind, .muscleGain)
    }

    func testDetect_sleepBetter() {
        XCTAssertEqual(GoalIntentClassifier.detect(in: "je veux mieux dormir")?.kind, .sleepBetter)
        XCTAssertEqual(GoalIntentClassifier.detect(in: "j'ai de la fatigue")?.kind, .sleepBetter)
    }

    func testDetect_saveMoney_withMagnitude() {
        let d = GoalIntentClassifier.detect(in: "je veux économiser 300 euros par mois")
        XCTAssertEqual(d?.kind, .saveMoney)
        XCTAssertEqual(d?.magnitude, 300)
    }

    func testDetect_productivity() {
        XCTAssertEqual(GoalIntentClassifier.detect(in: "je veux être plus productif")?.kind, .moreProductive)
    }

    func testDetect_noise_returnsNil() {
        XCTAssertNil(GoalIntentClassifier.detect(in: "bonjour ça va"))
        XCTAssertNil(GoalIntentClassifier.detect(in: "il fait beau aujourd'hui"))
    }

    func testDetect_customIfJustJeVeux() {
        XCTAssertEqual(GoalIntentClassifier.detect(in: "je veux un truc random")?.kind, .custom)
    }

    // MARK: - GoalPlanTemplate

    func testPlan_weightLoss_hasFitnessAndNutrition() {
        let goal = UserGoal(kindRaw: "weightLoss", targetValue: 5)
        let plan = GoalPlanTemplate.plan(for: goal)
        XCTAssertTrue(plan.modulesToActivate.contains("fitness"))
        XCTAssertTrue(plan.modulesToActivate.contains("nutrition"))
        XCTAssertGreaterThan(plan.habits.count, 0)
        XCTAssertGreaterThan(plan.reminders.count, 0)
    }

    func testPlan_sleepBetter_hasSleepAndMind() {
        let goal = UserGoal(kindRaw: "sleepBetter")
        let plan = GoalPlanTemplate.plan(for: goal)
        XCTAssertTrue(plan.modulesToActivate.contains("sleep"))
        XCTAssertTrue(plan.modulesToActivate.contains("mind"))
    }

    func testPlan_saveMoney_hasFinance() {
        let goal = UserGoal(kindRaw: "saveMoney", targetValue: 300)
        let plan = GoalPlanTemplate.plan(for: goal)
        XCTAssertTrue(plan.modulesToActivate.contains("finance"))
        XCTAssertTrue(plan.title.contains("300"))
    }

    func testPlan_custom_hasRecommendationEncourageDetail() {
        let goal = UserGoal(kindRaw: "custom")
        let plan = GoalPlanTemplate.plan(for: goal)
        XCTAssertTrue(plan.modulesToActivate.isEmpty)
        XCTAssertGreaterThan(plan.recommendations.count, 0)
    }

    // MARK: - Recommendations sans partenaire hardcodé (règle absolue)

    func testPlan_weightLoss_recommendationsHaveNoPartner() {
        let goal = UserGoal(kindRaw: "weightLoss")
        let plan = GoalPlanTemplate.plan(for: goal)
        for rec in plan.recommendations {
            XCTAssertNil(rec.partnerID,
                        "Aucune recommandation ne doit hardcoder un partenaire — spec §17")
        }
    }

    // MARK: - PartnerCatalog vide par défaut

    func testPartnerCatalog_isEmptyByDefault() {
        XCTAssertFalse(PartnerCatalog.shared.hasAnyPartner,
                      "Aucun partenaire ne doit être hardcodé — spec §17")
    }
}
