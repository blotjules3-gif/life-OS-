import XCTest
@testable import LifeOS

/// Correctifs de l'audit (Trilingo, Blinklist, Coursia, Sweepo, HomeZen, 12pets,
/// NoGaspi, SuperCuisto). Chaque test echoue sur l'ancien comportement.
@MainActor
final class AuditFixesLearningTests: XCTestCase {

    private func item(_ tid: Int, _ s: String) -> TrilingoItem {
        TrilingoItem(sid: tid + 10_000, tid: tid, s: s, t: "t\(tid)", audio: nil)
    }

    // MARK: Trilingo

    /// Phrases sources en double dans le cours: la bonne reponse ne doit apparaitre qu'une fois.
    func testPlacementOptions_noDuplicateText() {
        let answer = item(1, "Bonjour.")
        let pool = [answer] + (2...40).map { item($0, $0 % 2 == 0 ? "Bonjour." : "Phrase \($0 % 5)") }
        let opts = TrilingoChoices.placementOptions(for: answer, pool: pool)
        XCTAssertEqual(opts.filter { $0 == "Bonjour." }.count, 1)
        XCTAssertEqual(Set(opts).count, opts.count, "Choix en double: ids ForEach en double")
        XCTAssertTrue(opts.contains("Bonjour."))
    }

    func testUniqueOptions_keepsOrder() {
        XCTAssertEqual(TrilingoChoices.unique(["a", "b", "a", "c", "b"]), ["a", "b", "c"])
    }

    /// Refaire le test plus bas doit ramener la seance au jour annonce.
    func testFirstItemIndex() {
        XCTAssertEqual(TrilingoChoices.firstItemIndex(day: 1, perDay: 12), 0)
        XCTAssertEqual(TrilingoChoices.firstItemIndex(day: 5, perDay: 12), 48)
        XCTAssertEqual(TrilingoChoices.firstItemIndex(day: 0, perDay: 12), 0)
    }

    // MARK: Blinklist

    func testAISummary_isMarkedAndBodyStripsMarker() {
        let marked = BookSummaryOrigin.markAI("- Idée 1")
        XCTAssertTrue(BookSummaryOrigin.isAI(marked))
        XCTAssertEqual(BookSummaryOrigin.body(marked), "- Idée 1")
        XCTAssertEqual(BookSummaryOrigin.markAI(marked), marked, "Pas de double marque")
        XCTAssertFalse(BookSummaryOrigin.isAI("Mon résumé à moi"))
        XCTAssertEqual(BookSummaryOrigin.body("Mon résumé à moi"), "Mon résumé à moi")
    }

    // MARK: Coursia

    func testSkillPlan_refusesDuplicateAndBlank() {
        XCTAssertNil(SkillPlanSteps.adding("Lire 1 livre", to: ["Lire 1 livre"]))
        XCTAssertNil(SkillPlanSteps.adding("  Lire 1 livre ", to: ["Lire 1 livre"]))
        XCTAssertNil(SkillPlanSteps.adding("   ", to: []))
        XCTAssertEqual(SkillPlanSteps.adding("B", to: ["A"]), ["A", "B"])
    }

    func testSkillPlan_removeCleansDoneOnlyWhenLastCopy() {
        let r = SkillPlanSteps.removing(at: 0, steps: ["A", "B"], done: ["A", "B"])
        XCTAssertEqual(r.steps, ["B"]); XCTAssertEqual(r.done, ["B"])
        let dup = SkillPlanSteps.removing(at: 0, steps: ["A", "A"], done: ["A"])
        XCTAssertEqual(dup.steps, ["A"]); XCTAssertEqual(dup.done, ["A"])
        let out = SkillPlanSteps.removing(at: 9, steps: ["A"], done: [])
        XCTAssertEqual(out.steps, ["A"])
    }

    // MARK: Sweepo

    func testChoreDueLabel_usesCalendarDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 20))!
        let thisMorning = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 8))!
        let yesterdayEvening = cal.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 21))!
        let tomorrowMorning = cal.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 8))!
        XCTAssertEqual(ChoresView.dueLabel(yesterdayEvening, now: now, calendar: cal), "En retard")
        XCTAssertEqual(ChoresView.dueLabel(thisMorning, now: now, calendar: cal), "Aujourd'hui")
        XCTAssertEqual(ChoresView.dueLabel(tomorrowMorning, now: now, calendar: cal), "Demain")
    }

    // MARK: HomeZen

    func testMaintenanceNeverDone_isDue() {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        XCTAssertTrue(TodayAgendaSection.isRecurringDue(lastDone: nil, nextDue: nil, today: today, calendar: cal))
        let future = cal.date(byAdding: .day, value: 3, to: today)!
        XCTAssertFalse(TodayAgendaSection.isRecurringDue(lastDone: today, nextDue: future, today: today, calendar: cal))
        let past = cal.date(byAdding: .day, value: -1, to: today)!
        XCTAssertTrue(TodayAgendaSection.isRecurringDue(lastDone: past, nextDue: past, today: today, calendar: cal))
    }

    // MARK: 12pets

    func testPetEventDefaultDate_isInTheFuture() {
        let now = Date()
        let d = PetEventEditor.defaultDate(now: now)
        XCTAssertGreaterThan(d, now)
        XCTAssertTrue(PetEventEditor.canRemind(at: d, now: now))
        XCTAssertFalse(PetEventEditor.canRemind(at: now.addingTimeInterval(-60), now: now))
    }

    // MARK: NoGaspi

    func testAntiWasteLog_countsAndUndo() throws {
        let suite = "AuditFixesLearningTests.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        AntiWasteLog.record(.consumed, defaults: d)
        AntiWasteLog.record(.wasted, defaults: d)
        AntiWasteLog.record(.wasted, defaults: d)
        XCTAssertEqual(AntiWasteLog.tally(defaults: d).consumed, 1)
        XCTAssertEqual(AntiWasteLog.tally(defaults: d).wasted, 2)
        AntiWasteLog.record(.wasted, delta: -1, defaults: d)
        AntiWasteLog.record(.consumed, delta: -5, defaults: d)
        XCTAssertEqual(AntiWasteLog.tally(defaults: d).wasted, 1)
        XCTAssertEqual(AntiWasteLog.tally(defaults: d).consumed, 0, "Jamais negatif")
    }

    // MARK: SuperCuisto

    func testRecipeMatching_wholeWordsAndLigature() {
        let soupe = { (have: [String]) in RecipeEngine.suggest(from: have).first { $0.name == "Soupe de légumes" }?.matched ?? 0 }
        // "pomme" ne compte plus comme "pomme de terre".
        XCTAssertEqual(soupe(["pomme", "carotte"]), 0, "carotte seule: sous le seuil de 2")
        XCTAssertEqual(soupe(["pommes de terre", "carotte"]), 2)
        XCTAssertFalse(RecipeEngine.containsPhrase(RecipeEngine.tokens("pomme de terre"), in: RecipeEngine.tokens("Pomme")))
        // "œuf" avec ligature et pluriel correspond a "oeuf".
        XCTAssertTrue(RecipeEngine.containsPhrase(RecipeEngine.tokens("oeuf"), in: RecipeEngine.tokens("Œufs bio")))
        XCTAssertTrue(RecipeEngine.containsPhrase(RecipeEngine.tokens("pâtes"), in: RecipeEngine.tokens("Pates complètes")))
        XCTAssertFalse(RecipeEngine.containsPhrase(RecipeEngine.tokens("riz"), in: RecipeEngine.tokens("cerises")))
    }
}
