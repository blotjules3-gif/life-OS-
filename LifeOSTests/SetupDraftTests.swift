import XCTest
@testable import LifeOS

/// Un questionnaire interrompu doit retrouver ses REPONSES, pas seulement sa page.
final class SetupDraftTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "SetupDraftTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testEveryValueTypeRoundTrips() {
        var d = SetupDraft()
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        d.put("n", 7); d.put("s", "Salle"); d.put("b", true); d.put("t", when)
        d.put("set", ["Force", "Cardio"]); d.put("empty", Set<String>())
        let back = SetupDraft(values: d.values)
        XCTAssertEqual(back.int("n"), 7)
        XCTAssertEqual(back.string("s"), "Salle")
        XCTAssertEqual(back.bool("b"), true)
        XCTAssertEqual(back.date("t"), when)
        XCTAssertEqual(back.set("set"), ["Force", "Cardio"])
        XCTAssertEqual(back.set("empty"), [])
        XCTAssertNil(back.int("absent"), "une cle inconnue ne doit rien inventer")
    }

    func testAnswersSurviveAndAreOnlyGivenBackForAnUnfinishedQuestionnaire() {
        var d = SetupDraft(); d.put("wake", 6)
        CategorySetup.saveAnswers(.sleep, d, defaults: defaults)
        CategorySetup.saveDraft(.sleep, page: 1, pageCount: 3, answered: true, defaults: defaults)

        // "Relance": un nouvel acces aux memes reglages.
        let reread = UserDefaults(suiteName: suite)!
        XCTAssertEqual(CategorySetup.loadAnswers(.sleep, defaults: reread)?.int("wake"), 6)

        CategorySetup.markCompleted(.sleep, defaults: reread)
        XCTAssertNil(CategorySetup.loadAnswers(.sleep, defaults: reread),
                     "un questionnaire termine se rouvre depuis les reglages appliques")
    }

    func testCompletedQuestionnaireDoesNotStoreDrafts() {
        CategorySetup.markCompleted(.finance, defaults: defaults)
        var d = SetupDraft(); d.put("budget", 900)
        CategorySetup.saveAnswers(.finance, d, defaults: defaults)
        XCTAssertNil(defaults.dictionary(forKey: "setup.draftAnswers.\(AppCategory.finance.rawValue)"))
    }

    /// Chaque questionnaire du hub doit brancher son brouillon.
    func testEveryQuestionnaireKeepsItsAnswers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("LifeOS/Modules")
        var missing: [String] = []
        var calls = 0
        for f in try FileManager.default.contentsOfDirectory(atPath: dir.path) where f.hasSuffix(".swift") {
            let s = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            // Un appel par questionnaire, un brouillon branche par appel.
            let flows = s.components(separatedBy: "SetupFlow(").count - 1
            let hooked = s.components(separatedBy: "draft: draftIO").count - 1
            calls += flows
            if flows != hooked { missing.append("\(f): \(flows) questionnaires, \(hooked) brouillons") }
        }
        XCTAssertGreaterThanOrEqual(calls, 9, "les questionnaires n'ont pas ete trouves")
        XCTAssertEqual(missing, [], "questionnaires sans brouillon de reponses")
    }
}
