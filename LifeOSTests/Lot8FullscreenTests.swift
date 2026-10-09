import XCTest
@testable import LifeOS

/// Lot 8, plein ecran et reprise: navigation entre etapes Tabata, pause qui
/// survit a la fermeture de l'app, rattrapage court contre pause longue,
/// instantane de lecon Trilingo (aller-retour et peremption), couleurs de
/// texte lisibles en clair.
@MainActor
final class Lot8FullscreenTests: XCTestCase {

    /// 10 s de prepa, 30 s d'effort, 15 s de repos, 2 rounds, 2 series,
    /// 20 s de recup entre series, 5 s de calme = 9 etapes, 185 s.
    private let cfg = TabataConfig(prepare: 10, work: 30, rest: 15,
                                   rounds: 2, cycles: 2, restCycle: 20, cooldown: 5)

    private func freshDefaults() -> UserDefaults {
        let suite = "Lot8FullscreenTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: - Etats passe / en cours / a venir

    func testStepStatusClassification() {
        XCTAssertEqual(TabataStepNav.status(index: 0, current: nil), .future, "au repos tout est a venir")
        XCTAssertEqual(TabataStepNav.status(index: 2, current: 3), .past)
        XCTAssertEqual(TabataStepNav.status(index: 3, current: 3), .current)
        XCTAssertEqual(TabataStepNav.status(index: 4, current: 3), .future)
        XCTAssertEqual(TabataStepNav.status(index: 8, current: 9), .past, "seance finie: tout est passe")
    }

    func testEngineStatusesFollowNavHelper() {
        var clock = Date(timeIntervalSince1970: 10_000)
        let e = TabataEngine(cfg: cfg)
        e.now = { clock }
        e.begin()
        e.select(stepIndex: 4)
        clock = clock.addingTimeInterval(1); e.tick()
        let statuses = e.steps.map { e.status(of: $0) }
        XCTAssertEqual(statuses, [.past, .past, .past, .past, .current, .future, .future, .future, .future])
    }

    func testAccessibilityLabelSaysPositionPhaseAndState() {
        let label = TabataStepNav.accessibilityLabel(index: 2, count: 24, phase: .work, exercise: "Squats",
                                                     round: 1, duration: 30, status: .current, done: false)
        XCTAssertEqual(label, "Étape 3 sur 24, effort, Squats, round 1, 30 secondes, en cours")
        let skipped = TabataStepNav.accessibilityLabel(index: 0, count: 9, phase: .prepare, exercise: nil,
                                                       round: nil, duration: 1, status: .past, done: false)
        XCTAssertEqual(skipped, "Étape 1 sur 9, préparation, 1 seconde, sautée")
        XCTAssertTrue(TabataStepNav.accessibilityLabel(index: 1, count: 9, phase: .rest, exercise: nil, round: 1,
                                                       duration: 15, status: .past, done: true).hasSuffix("faite"))
    }

    // MARK: - Navigation entre etapes (regles pures)

    func testNextAndPreviousMoves() {
        XCTAssertEqual(TabataStepNav.next(current: 3, count: 9), .select(4))
        XCTAssertEqual(TabataStepNav.next(current: 8, count: 9), .finish, "suivant sur la derniere termine")
        XCTAssertEqual(TabataStepNav.previous(current: 3, count: 9), .select(2))
        XCTAssertEqual(TabataStepNav.previous(current: 0, count: 9), .restart(0), "precedent au debut recommence")
        XCTAssertEqual(TabataStepNav.next(current: nil, count: 9), .none, "au repos, rien")
        XCTAssertEqual(TabataStepNav.previous(current: 9, count: 9), .none, "seance finie, rien")
        XCTAssertEqual(TabataStepNav.next(current: 0, count: 0), .none)
    }

    func testSkipCountAndConfirmationRule() {
        XCTAssertEqual(TabataStepNav.skippedCount(current: 2, target: 3), 1)
        XCTAssertEqual(TabataStepNav.skippedCount(current: 2, target: 6), 4)
        XCTAssertEqual(TabataStepNav.skippedCount(current: 5, target: 1), 0, "revenir en arriere ne saute rien")
        XCTAssertEqual(TabataStepNav.skippedCount(current: nil, target: 3), 3)

        XCTAssertFalse(TabataStepNav.needsConfirmation(current: 2, target: 3, running: true), "une etape: direct")
        XCTAssertTrue(TabataStepNav.needsConfirmation(current: 2, target: 4, running: true), "deux etapes en marche: confirmer")
        XCTAssertFalse(TabataStepNav.needsConfirmation(current: 2, target: 7, running: false), "en pause: direct")
        XCTAssertFalse(TabataStepNav.needsConfirmation(current: 7, target: 0, running: true), "arriere: direct")
    }

    func testRemainingTotalFromSequence() {
        let durations = TabataEngine.buildSteps(cfg).map(\.duration)
        XCTAssertEqual(durations.reduce(0, +), 185)
        XCTAssertEqual(TabataStepNav.remainingTotal(durations: durations, current: 0, remainingInStep: 10), 185)
        XCTAssertEqual(TabataStepNav.remainingTotal(durations: durations, current: 0, remainingInStep: 4), 179)
        // Etape 5 (effort serie 2) avec 12 s restantes: 12 + 15 + 30 + 5.
        XCTAssertEqual(TabataStepNav.remainingTotal(durations: durations, current: 5, remainingInStep: 12), 62)
        XCTAssertEqual(TabataStepNav.remainingTotal(durations: durations, current: 8, remainingInStep: 5), 5)
        XCTAssertEqual(TabataStepNav.remainingTotal(durations: durations, current: 9, remainingInStep: 0), 0)
    }

    // MARK: - Navigation entre etapes (moteur)

    func testEngineNextStepResetsTimerAndRecomputesTotal() {
        var clock = Date(timeIntervalSince1970: 20_000)
        let e = TabataEngine(cfg: cfg)
        e.now = { clock }
        e.begin()
        clock = clock.addingTimeInterval(13); e.tick()          // prepa finie, 3 s d'effort
        XCTAssertEqual(e.currentStepIndex, 1)
        XCTAssertEqual(e.remaining, 27)
        XCTAssertEqual(e.totalRemaining, 185 - 13)

        e.goToNextStep()                                        // repos du round 1
        XCTAssertEqual(e.currentStepIndex, 2)
        XCTAssertEqual(e.phase, .rest)
        XCTAssertEqual(e.remaining, 15, "le chrono repart de la duree pleine de l'etape")
        XCTAssertEqual(e.totalRemaining, 185 - 10 - 30, "total = etape choisie + tout ce qui suit")
        XCTAssertTrue(e.running, "un saut garde la lecture")
        XCTAssertFalse(e.isCompleted(e.steps[1]), "l'effort quitte n'est pas fait")

        clock = clock.addingTimeInterval(1); e.tick()
        XCTAssertEqual(e.remaining, 14)
    }

    func testEnginePreviousAtStartRestartsFirstStep() {
        var clock = Date(timeIntervalSince1970: 30_000)
        let e = TabataEngine(cfg: cfg)
        e.now = { clock }
        e.begin()
        clock = clock.addingTimeInterval(6); e.tick()
        XCTAssertEqual(e.remaining, 4)
        e.goToPreviousStep()
        XCTAssertEqual(e.currentStepIndex, 0)
        XCTAssertEqual(e.remaining, 10, "la premiere etape repart de zero")
        XCTAssertEqual(e.totalRemaining, 185)

        e.select(stepIndex: 3)
        e.goToPreviousStep()
        XCTAssertEqual(e.currentStepIndex, 2, "precedent recule d'une seule etape")
        XCTAssertEqual(e.remaining, 15)
    }

    func testEngineNextAtEndFinishesWithoutCompleting() {
        var clock = Date(timeIntervalSince1970: 40_000)
        let e = TabataEngine(cfg: cfg)
        e.now = { clock }
        e.begin()
        e.select(stepIndex: e.steps.count - 1)
        clock = clock.addingTimeInterval(1); e.tick()
        e.goToNextStep()
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(e.totalRemaining, 0)
        XCTAssertFalse(e.isCompleted(e.steps[e.steps.count - 1]), "terminer par un saut n'est pas faire")
        e.goToNextStep()                                        // seance finie: sans effet
        XCTAssertEqual(e.phase, .done)
        XCTAssertFalse(e.canNavigateSteps)
    }

    func testNavigationDisabledWhenIdle() {
        let e = TabataEngine(cfg: cfg)
        XCTAssertFalse(e.canNavigateSteps)
        e.goToNextStep(); e.goToPreviousStep()
        XCTAssertEqual(e.phase, .idle, "au repos, les boutons d'etape ne lancent rien")
    }

    // MARK: - Pause qui survit a la fermeture de l'app

    func testPausedSessionSurvivesKillWithExactRemaining() {
        let defaults = freshDefaults()
        var clock = Date(timeIntervalSince1970: 50_000)
        let store = TabataSessionStore(defaults: defaults)
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in true }, now: { clock })
        let e = TabataEngine(cfg: cfg)
        e.now = { clock }
        keeper.adopt(e)
        e.begin()
        clock = clock.addingTimeInterval(10 + 7); e.tick()      // 7 s dans l'effort 1
        e.startOrPause()                                        // pause: persiste
        XCTAssertFalse(e.running)
        XCTAssertEqual(e.remaining, 23)

        // L'app est tuee, relancee deux heures plus tard.
        clock = clock.addingTimeInterval(2 * 3600)
        let relaunched = TabataSessionKeeper(store: TabataSessionStore(defaults: defaults),
                                             healthWriter: { _ in true }, now: { clock })
        let r = relaunched.engine
        XCTAssertEqual(r.sessionID, e.sessionID)
        XCTAssertFalse(r.running, "en pause avant, en pause apres")
        XCTAssertEqual(r.phase, .work)
        XCTAssertEqual(r.remaining, 23, "le temps restant exact, quel que soit le temps passe")
        XCTAssertEqual(r.currentStepIndex, 1)
        XCTAssertNil(r.interruptionGap, "une pause voulue n'est pas une interruption")
        XCTAssertEqual(r.totalRemaining, e.totalRemaining)

        r.startOrPause()                                        // reprise
        clock = clock.addingTimeInterval(1); r.tick()
        XCTAssertEqual(r.remaining, 22)
    }

    func testRunningSessionCatchesUpShortGapAfterKill() {
        let defaults = freshDefaults()
        var clock = Date(timeIntervalSince1970: 60_000)
        let keeper = TabataSessionKeeper(store: TabataSessionStore(defaults: defaults),
                                         healthWriter: { _ in true }, now: { clock })
        let e = TabataEngine(cfg: cfg)
        e.now = { clock }
        keeper.adopt(e)
        e.begin()
        clock = clock.addingTimeInterval(5); e.tick()           // 5 s de prepa, sauve en marche

        clock = clock.addingTimeInterval(2 * 60)                // relance 2 min plus tard
        let r = TabataSessionKeeper(store: TabataSessionStore(defaults: defaults),
                                    healthWriter: { _ in true }, now: { clock }).engine
        XCTAssertTrue(r.running, "absence courte: rattrapee, la seance continue")
        XCTAssertNil(r.interruptionGap)
        XCTAssertEqual(r.activeSeconds, 5 + 120)
        XCTAssertEqual(r.totalRemaining, 185 - 125)
    }

    func testRunningSessionPausesAfterLongGapAfterKill() {
        let defaults = freshDefaults()
        var clock = Date(timeIntervalSince1970: 70_000)
        let keeper = TabataSessionKeeper(store: TabataSessionStore(defaults: defaults),
                                         healthWriter: { _ in true }, now: { clock })
        let e = TabataEngine(cfg: cfg)
        e.now = { clock }
        keeper.adopt(e)
        e.begin()
        clock = clock.addingTimeInterval(10 + 4); e.tick()      // 4 s dans l'effort 1

        clock = clock.addingTimeInterval(20 * 60)               // relance 20 min plus tard
        let r = TabataSessionKeeper(store: TabataSessionStore(defaults: defaults),
                                    healthWriter: { _ in true }, now: { clock }).engine
        XCTAssertFalse(r.running, "absence longue: mise en pause, rien credite")
        XCTAssertEqual(r.phase, .work)
        XCTAssertEqual(r.remaining, 26, "la ou elle en etait a la sauvegarde")
        XCTAssertEqual(r.activeSeconds, 14)
        XCTAssertNotNil(r.interruptionGap)
    }

    // MARK: - Couleurs de texte (theme clair reellement lisible)

    func testTextHexIsExplicitPerScheme() {
        for phase in [TabataEngine.Phase.prepare, .work, .rest, .restCycle, .cooldown] {
            XCTAssertEqual(TabataPalette.textHex(phase.hex, dark: true), phase.hex, "sombre: l'accent tel quel")
            XCTAssertNotEqual(TabataPalette.textHex(phase.hex, dark: false), phase.hex, "clair: teinte profonde (\(phase))")
        }
        XCTAssertEqual(TabataPalette.textHex(0x00F076, dark: false), 0x008A43)
        // Accent inconnu: assombri de 40 % au lieu d'etre laisse tel quel.
        XCTAssertEqual(TabataPalette.textHex(0x6464C8, dark: false), 0x3C3C78)
    }

    // MARK: - Reprise generique (SessionRestore)

    private struct Sample: Codable, Equatable { var step: Int; var note: String }

    func testSessionRestoreRoundTripAndExpiry() {
        let defaults = freshDefaults()
        var clock = Date(timeIntervalSince1970: 80_000)
        let restore = SessionRestore(defaults: defaults, now: { clock })
        restore.save(Sample(step: 4, note: "a"), kind: .trilingoLesson)

        clock = clock.addingTimeInterval(3600)
        let loaded = restore.load(Sample.self, kind: .trilingoLesson)
        XCTAssertEqual(loaded?.payload, Sample(step: 4, note: "a"))
        XCTAssertEqual(loaded?.savedAt, Date(timeIntervalSince1970: 80_000))

        clock = clock.addingTimeInterval(SessionRestoreKind.trilingoLesson.maxAge)
        XCTAssertNil(restore.load(Sample.self, kind: .trilingoLesson), "perime: oublie")
        XCTAssertFalse(restore.has(.trilingoLesson), "un instantane perime est efface")
    }

    func testSessionRestoreRejectsUnreadableAndFutureDated() {
        let defaults = freshDefaults()
        var clock = Date(timeIntervalSince1970: 90_000)
        let restore = SessionRestore(defaults: defaults, now: { clock })
        defaults.set(Data("pas du json".utf8), forKey: SessionRestore.key(.trilingoLesson))
        XCTAssertNil(restore.load(Sample.self, kind: .trilingoLesson))
        XCTAssertFalse(restore.has(.trilingoLesson))

        restore.save(Sample(step: 1, note: "b"), kind: .trilingoLesson)
        clock = clock.addingTimeInterval(-3600)                 // horloge reculee d'une heure
        XCTAssertNil(restore.load(Sample.self, kind: .trilingoLesson), "date d'ecriture dans le futur: pas fiable")
    }

    // MARK: - Lecon Trilingo

    private func item(_ tid: Int) -> TrilingoItem {
        TrilingoItem(sid: tid + 1000, tid: tid, s: "Bonjour \(tid)", t: "Hola \(tid)", audio: nil)
    }

    private func lesson() -> [TrilingoExercise] {
        [TrilingoExercise(kind: .intro, item: item(1), skill: .reading, isReview: false),
         TrilingoExercise(kind: .chooseMeaning, item: item(2), skill: .reading,
                          options: ["Bonjour 2", "Merci", "Oui", "Non"], isReview: true),
         TrilingoExercise(kind: .build, item: item(3), skill: .writing,
                          tiles: ["Hola", "3"], isReview: false)]
    }

    func testTrilingoSnapshotRoundTripResumesSameStep() {
        let defaults = freshDefaults()
        let restore = SessionRestore(defaults: defaults)
        let exercises = lesson()
        let id = UUID()
        let snap = TrilingoLessonSnapshot(lessonID: id, language: "spa", countsAsDay: true,
                                          exercises: exercises.map(TrilingoLessonSnapshot.Exercise.init),
                                          index: 2, correctCount: 1,
                                          built: ["Hola"], typed: "", chosen: nil, verdict: nil)
        TrilingoLessonRestore.save(snap, restore)

        let loaded = TrilingoLessonRestore.load(restore)
        XCTAssertEqual(loaded, snap)
        XCTAssertEqual(loaded?.lessonID, id)
        XCTAssertTrue(loaded?.isResumable(forLanguage: "spa") == true)
        XCTAssertFalse(loaded?.isResumable(forLanguage: "deu") == true, "une autre langue ne reprend jamais")
        XCTAssertFalse(loaded?.isResumable(forLanguage: nil) == true, "sans langue choisie, pas de lecon")

        let rebuilt = loaded?.restoredExercises
        XCTAssertEqual(rebuilt?.map(\.kind), exercises.map(\.kind))
        XCTAssertEqual(rebuilt?.map(\.item), exercises.map(\.item))
        XCTAssertEqual(rebuilt?[1].options, ["Bonjour 2", "Merci", "Oui", "Non"])
        XCTAssertEqual(rebuilt?[1].isReview, true)
        XCTAssertEqual(rebuilt?[2].tiles, ["Hola", "3"])

        TrilingoLessonRestore.clear(restore)
        XCTAssertNil(TrilingoLessonRestore.load(restore))
    }

    func testTrilingoSnapshotExpiresAndRejectsBadStep() {
        let defaults = freshDefaults()
        var clock = Date(timeIntervalSince1970: 100_000)
        let restore = SessionRestore(defaults: defaults, now: { clock })
        let snap = TrilingoLessonSnapshot(lessonID: UUID(), language: "spa", countsAsDay: false,
                                          exercises: lesson().map(TrilingoLessonSnapshot.Exercise.init),
                                          index: 1, correctCount: 0, verdict: true)
        TrilingoLessonRestore.save(snap, restore)
        clock = clock.addingTimeInterval(25 * 3600)
        XCTAssertNil(TrilingoLessonRestore.load(restore), "une lecon de plus d'un jour est oubliee")

        var outOfRange = snap
        outOfRange.index = 3
        XCTAssertFalse(outOfRange.isResumable(forLanguage: "spa"), "etape hors de la lecon")

        var unknownKind = snap
        unknownKind.exercises[0].kind = "inconnu"
        XCTAssertNil(unknownKind.restoredExercises, "un genre inconnu refuse toute la lecon")
    }
}
