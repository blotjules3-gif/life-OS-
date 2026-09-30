import XCTest
@testable import LifeOS

/// Le questionnaire montre ce qui change avant d'ecrire, et "Annuler" doit tout
/// remettre. Rien n'est ecrit en base avant "Appliquer" (voir `SetupSession`), donc
/// ce qu'il faut prouver ici: les reglages ecrits au fil des choix reviennent, et
/// les etats (ignore, en cours, termine) se suivent correctement.
@MainActor
final class SetupSessionTests: XCTestCase {

    private func suite() -> UserDefaults {
        let name = "SetupSessionTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testCancelRestoresChangedAndRemovesAddedSettings() {
        let d = suite()
        d.set(2200, forKey: "kcalGoal")
        d.set("x", forKey: "untouched")
        let session = SetupSession(category: .nutrition, defaults: d)
        session.begin()

        d.set(1800, forKey: "kcalGoal")          // modifie
        d.set(150, forKey: "proteinGoal")        // ajoute

        let changes = session.pendingChanges()
        XCTAssertEqual(Set(changes.map(\.key)), ["kcalGoal", "proteinGoal"])
        let kcal = changes.first { $0.key == "kcalGoal" }
        XCTAssertEqual(kcal?.label, "Objectif calories")
        XCTAssertEqual(kcal?.before, "2200 kcal")
        XCTAssertEqual(kcal?.after, "1800 kcal")

        session.cancel()
        XCTAssertEqual(d.integer(forKey: "kcalGoal"), 2200)
        XCTAssertNil(d.object(forKey: "proteinGoal"))
        XCTAssertEqual(d.string(forKey: "untouched"), "x")
    }

    func testBookkeepingKeysAreNeitherShownNorReverted() {
        let d = suite()
        let session = SetupSession(category: .nutrition, defaults: d)
        session.begin()
        d.set(Date(), forKey: "analytics.firstLaunchLogged")
        d.set(true, forKey: "setup.prompted.nutrition")
        XCTAssertTrue(session.pendingChanges().isEmpty)
        session.cancel()
        XCTAssertNotNil(d.object(forKey: "analytics.firstLaunchLogged"),
                        "une ecriture etrangere pendant le questionnaire survit a l'annulation")
    }

    func testEditModeIsKnownFromTheStartState() {
        let d = suite()
        CategorySetup.markCompleted(.sleep, defaults: d)
        let session = SetupSession(category: .sleep, defaults: d)
        session.begin()
        XCTAssertTrue(session.wasCompleted, "rouvrir un questionnaire termine = modifier")
    }

    func testUnrelatedBackgroundWritesAreIgnored() {
        let d = suite()
        let session = SetupSession(category: .sleep, defaults: d)
        session.begin()
        d.set("fitness", forKey: "lifeos.weekly.suggestedModule")
        d.set("{}", forKey: "toolNames.v1")
        XCTAssertTrue(session.pendingChanges().isEmpty, "un cache ecrit en fond n'est pas une reponse")
        session.cancel()
        XCTAssertEqual(d.string(forKey: "toolNames.v1"), "{}", "et annuler ne le remet pas en arriere")
    }

    func testModulePreviewSkipsUnchangedValues() {
        XCTAssertNil(SetupSession.Change.make("Budget", "1500 €", "1500 €"))
        XCTAssertEqual(SetupSession.Change.make("Budget", "1500 €", "1800 €")?.after, "1800 €")
    }

    func testStatusLifecycleSkipPartialCompleteEdit() {
        let d = suite()
        XCTAssertEqual(CategorySetup.status(.sleep, defaults: d), .notStarted)

        // Plus tard des la premiere page, rien de repondu: ignore.
        CategorySetup.saveDraft(.sleep, page: 0, pageCount: 4, answered: false, defaults: d)
        XCTAssertEqual(CategorySetup.status(.sleep, defaults: d), .skipped)

        // Plus tard a l'etape 3: brouillon repris a l'etape 3 apres relance.
        CategorySetup.saveDraft(.sleep, page: 2, pageCount: 4, answered: true, defaults: d)
        XCTAssertEqual(CategorySetup.status(.sleep, defaults: d), .partial(page: 2, of: 4))
        XCTAssertEqual(CategorySetup.resumePage(.sleep, pageCount: 4, defaults: d), 2)

        CategorySetup.markCompleted(.sleep, defaults: d)
        XCTAssertEqual(CategorySetup.status(.sleep, defaults: d), .completed)
        XCTAssertEqual(CategorySetup.resumePage(.sleep, pageCount: 4, defaults: d), 0,
                       "modifier ses reponses repart du debut, pre-rempli")

        // "Plus tard" en modification ne doit pas faire retomber a "en cours".
        CategorySetup.saveDraft(.sleep, page: 3, pageCount: 4, answered: true, defaults: d)
        XCTAssertEqual(CategorySetup.status(.sleep, defaults: d), .completed)

        // Un questionnaire raccourci ne doit pas reprendre au-dela de sa fin.
        CategorySetup.saveDraft(.mind, page: 7, pageCount: 9, answered: true, defaults: d)
        XCTAssertEqual(CategorySetup.resumePage(.mind, pageCount: 3, defaults: d), 2)
    }
}
