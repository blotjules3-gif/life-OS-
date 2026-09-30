import XCTest
@testable import LifeOS

/// Session Tabata durable: sequence complete, sauts, snapshot, reprise apres
/// fermeture ou relance, et UNE ecriture Sante par seance.
///
/// Le bug d'origine: le moteur vivait dans un `@State` de l'ecran, donc fermer
/// la vue perdait la seance. Ces tests prouvent la reprise sans attendre et
/// sans simulateur: l'horloge est injectee, Sante est un faux compteur.
@MainActor
final class TabataSessionTests: XCTestCase {

    /// 10 s de prepa, 30 s d'effort, 15 s de repos, 2 rounds, 2 series,
    /// 20 s de recup entre series, 5 s de calme.
    private let cfg = TabataConfig(prepare: 10, work: 30, rest: 15,
                                   rounds: 2, cycles: 2, restCycle: 20, cooldown: 5)

    private func makeEngine(start: TimeInterval) -> (TabataEngine, (TimeInterval) -> Void) {
        var clock = Date(timeIntervalSince1970: start)
        let e = TabataEngine(cfg: cfg)
        e.now = { clock }
        e.attach(session: TabataPresets.all[0])
        let advance = { (secs: TimeInterval) in
            clock = clock.addingTimeInterval(secs)
            e.tick()
        }
        return (e, advance)
    }

    private func makeStore() -> TabataSessionStore {
        let suite = "TabataSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return TabataSessionStore(defaults: defaults)
    }

    // MARK: - Sequence

    func testSequenceCoversWholeSessionInOrder() {
        let steps = TabataEngine.buildSteps(cfg)
        let phases = steps.map(\.phase)
        XCTAssertEqual(phases, [.prepare,
                                .work, .rest, .work,
                                .restCycle,
                                .work, .rest, .work,
                                .cooldown])
        XCTAssertEqual(steps.map(\.index), Array(0..<steps.count), "les index suivent l'ordre")
        let e = TabataEngine(cfg: cfg)
        XCTAssertEqual(steps.reduce(0) { $0 + $1.duration }, e.totalDuration,
                       "la somme des etapes est la duree totale annoncee")
        XCTAssertEqual(steps[5].round, 1); XCTAssertEqual(steps[5].cycle, 2)
    }

    func testStatusesPastCurrentFutureAcrossPhases() {
        let (e, advance) = makeEngine(start: 1_000)
        XCTAssertNil(e.currentStepIndex, "au repos, aucune etape courante")
        XCTAssertTrue(e.steps.allSatisfy { e.status(of: $0) == .future })

        e.begin()
        XCTAssertEqual(e.currentStepIndex, 0)
        advance(10)                                  // fin de la prepa
        XCTAssertEqual(e.phase, .work)
        XCTAssertEqual(e.currentStepIndex, 1)
        XCTAssertEqual(e.status(of: e.steps[0]), .past)
        XCTAssertTrue(e.isCompleted(e.steps[0]), "la prepa a ete faite par le temps")
        XCTAssertEqual(e.status(of: e.steps[1]), .current)
        XCTAssertEqual(e.status(of: e.steps[2]), .future)

        advance(30)                                  // effort 1 fini
        XCTAssertEqual(e.phase, .rest)
        XCTAssertTrue(e.isCompleted(e.steps[1]))
        XCTAssertEqual(e.workStepsCompleted, 1)

        advance(15 + 30)                             // repos + effort 2
        XCTAssertEqual(e.phase, .restCycle)
        XCTAssertEqual(e.cycle, 1)
        advance(20)                                  // recup de serie
        XCTAssertEqual(e.phase, .work); XCTAssertEqual(e.cycle, 2); XCTAssertEqual(e.round, 1)
        XCTAssertEqual(e.currentStepIndex, 5)

        advance(30 + 15 + 30 + 5)                    // serie 2 + calme
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(e.currentStepIndex, e.steps.count)
        XCTAssertEqual(e.completedSteps.count, e.steps.count, "tout a ete fait par le temps")
        XCTAssertEqual(e.workStepsCompleted, 4)
        XCTAssertEqual(e.activeSeconds, e.totalDuration)
        XCTAssertEqual(e.workSecondsDone, 4 * 30)
    }

    // MARK: - Sauts

    func testSelectingFutureStepIsNotCompletedWork() {
        let (e, advance) = makeEngine(start: 2_000)
        e.begin()
        advance(3)
        e.select(stepIndex: 6)                       // serie 2, repos du round 1
        XCTAssertEqual(e.phase, .rest); XCTAssertEqual(e.cycle, 2); XCTAssertEqual(e.round, 1)
        XCTAssertEqual(e.remaining, 15)
        XCTAssertTrue(e.running, "un saut garde l'etat lecture")
        XCTAssertTrue(e.completedSteps.isEmpty, "rien n'a ete fait, seulement saute")
        XCTAssertEqual(e.workStepsCompleted, 0)
        for i in 0..<6 {
            XCTAssertEqual(e.status(of: e.steps[i]), .past)
            XCTAssertFalse(e.isCompleted(e.steps[i]), "etape \(i) sautee, pas faite")
        }
        advance(1)
        XCTAssertEqual(e.remaining, 14, "le chrono repart de la nouvelle etape")
    }

    func testSelectingPastStepMakesItCurrentAgain() {
        let (e, advance) = makeEngine(start: 3_000)
        e.begin()
        advance(10 + 30)                             // prepa + effort 1 faits
        XCTAssertEqual(e.phase, .rest)
        e.select(stepIndex: 1)
        XCTAssertEqual(e.phase, .work); XCTAssertEqual(e.round, 1)
        XCTAssertEqual(e.status(of: e.steps[1]), .current)
        XCTAssertEqual(e.status(of: e.steps[2]), .future)
        XCTAssertTrue(e.isCompleted(e.steps[1]), "l'avoir fait une fois reste vrai")
        XCTAssertEqual(e.workStepsCompleted, 1)
    }

    func testSelectWhilePausedStaysPaused() {
        let (e, advance) = makeEngine(start: 4_000)
        e.begin()
        advance(2)
        e.startOrPause()                             // pause
        e.select(stepIndex: 3)
        XCTAssertFalse(e.running)
        XCTAssertEqual(e.phase, .work); XCTAssertEqual(e.round, 2)
        advance(60)
        XCTAssertEqual(e.remaining, 30, "en pause, rien ne defile sur la nouvelle etape")
        e.startOrPause()
        advance(1)
        XCTAssertEqual(e.remaining, 29)
    }

    func testSkipForwardToEndDoesNotCompleteAnything() {
        let (e, _) = makeEngine(start: 5_000)
        e.begin()
        for _ in 0..<10 { e.skipForward() }
        XCTAssertEqual(e.phase, .done)
        XCTAssertTrue(e.completedSteps.isEmpty)
        XCTAssertEqual(e.activeSeconds, 0)
    }

    func testSkipBackwardGoesToPreviousWorkRound() {
        let (e, _) = makeEngine(start: 5_500)
        e.begin()
        e.select(stepIndex: 5)                       // effort, serie 2 round 1
        e.skipBackward()
        XCTAssertEqual(e.phase, .work); XCTAssertEqual(e.cycle, 1); XCTAssertEqual(e.round, 2)
        e.skipBackward()
        XCTAssertEqual(e.cycle, 1); XCTAssertEqual(e.round, 1)
        e.skipBackward()
        XCTAssertEqual(e.phase, .prepare, "avant le premier effort, on revient a la prepa")
    }

    // MARK: - Snapshot et reprise

    func testSnapshotRoundTripKeepsEverything() {
        let (e, advance) = makeEngine(start: 6_000)
        e.begin()
        advance(10 + 30 + 4)                         // 4 s dans le repos du round 1
        let store = makeStore()
        let savedAt = Date(timeIntervalSince1970: 6_044)
        store.save(e.snapshot(healthSaved: false, savedAt: savedAt))

        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionID, e.sessionID)
        XCTAssertEqual(loaded?.config, cfg)
        XCTAssertEqual(loaded?.exercises, TabataPresets.all[0].exercises)
        XCTAssertEqual(loaded?.sessionKey, "hiit")
        XCTAssertEqual(loaded?.phase, "rest")
        XCTAssertEqual(loaded?.remaining, 11)
        XCTAssertEqual(loaded?.running, true)
        XCTAssertEqual(loaded?.startedAt, Date(timeIntervalSince1970: 6_000))
        XCTAssertEqual(loaded?.completedSteps, [0, 1])
        XCTAssertEqual(loaded?.activeSeconds, 44)
        XCTAssertEqual(loaded?.workSecondsDone, 30)
    }

    /// Relance de l'app pendant qu'une seance tourne: on reprend la ou l'horloge
    /// le dit, pas la ou l'ecran s'etait arrete.
    func testRestartWhileRunningCatchesUpShortGap() {
        let (e, advance) = makeEngine(start: 7_000)
        e.begin()
        advance(10 + 5)                              // 5 s dans l'effort 1
        let snap = e.snapshot(healthSaved: false, savedAt: Date(timeIntervalSince1970: 7_015))

        let relaunch = Date(timeIntervalSince1970: 7_015 + 7)
        let r = TabataEngine.restore(snap, now: { relaunch })
        XCTAssertEqual(r.sessionID, e.sessionID, "meme seance, pas une nouvelle")
        XCTAssertEqual(r.phase, .work)
        XCTAssertEqual(r.remaining, 25 - 7, "les 7 s d'absence sont rattrapees")
        XCTAssertTrue(r.running)
        XCTAssertNil(r.interruptionGap)
        XCTAssertEqual(r.exercises, TabataPresets.all[0].exercises)
        XCTAssertEqual(r.completedSteps, [0])
        XCTAssertEqual(r.activeSeconds, 15 + 7)
    }

    /// Relance longtemps apres: la seance est en pause la ou elle en etait.
    func testRestartAfterLongGapPausesWithoutCrediting() {
        let (e, advance) = makeEngine(start: 8_000)
        e.begin()
        advance(10 + 5)
        let snap = e.snapshot(healthSaved: false, savedAt: Date(timeIntervalSince1970: 8_015))

        let relaunch = Date(timeIntervalSince1970: 8_015 + 40 * 60)
        let r = TabataEngine.restore(snap, now: { relaunch })
        XCTAssertEqual(r.phase, .work)
        XCTAssertEqual(r.remaining, 25, "rien n'a ete consomme")
        XCTAssertFalse(r.running, "en pause")
        XCTAssertEqual(r.interruptionGap.map { Int($0) }, 40 * 60)
        XCTAssertEqual(r.activeSeconds, 15, "les 40 min ne sont pas creditees")
    }

    /// Reprise d'une seance mise en pause: le temps passe ne compte pas, et la
    /// lecture repart exactement de la meme seconde.
    func testPausedSessionResumesWhereItStoppedAfterRelaunch() {
        let (e, advance) = makeEngine(start: 9_000)
        e.begin()
        advance(10 + 12)
        e.startOrPause()                             // pause a 18 s d'effort restantes
        XCTAssertFalse(e.running)
        let snap = e.snapshot(healthSaved: false, savedAt: Date(timeIntervalSince1970: 9_022))

        var clock = Date(timeIntervalSince1970: 9_022 + 3 * 3600)
        let r = TabataEngine.restore(snap, now: { clock })
        XCTAssertFalse(r.running)
        XCTAssertEqual(r.phase, .work)
        XCTAssertEqual(r.remaining, 18)
        XCTAssertNil(r.interruptionGap, "une pause volontaire n'est pas une interruption")

        r.startOrPause()                             // reprendre
        XCTAssertTrue(r.running)
        clock = clock.addingTimeInterval(1); r.tick()
        XCTAssertEqual(r.remaining, 17)
        clock = clock.addingTimeInterval(17); r.tick()
        XCTAssertEqual(r.phase, .rest, "l'effort se termine par le temps")
        XCTAssertTrue(r.isCompleted(r.steps[1]))
    }

    func testRestoreDoneSnapshotStaysDone() {
        let (e, _) = makeEngine(start: 9_500)
        e.begin()
        for _ in 0..<10 { e.skipForward() }
        let snap = e.snapshot(healthSaved: true, savedAt: Date(timeIntervalSince1970: 9_500))
        let r = TabataEngine.restore(snap, now: { Date(timeIntervalSince1970: 9_600) })
        XCTAssertEqual(r.phase, .done)
        XCTAssertFalse(r.running)
        XCTAssertEqual(r.remaining, 0)
    }

    func testStoreIgnoresUnreadableSnapshot() {
        let suite = "TabataSessionTests.bad.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(Data("pas du json".utf8), forKey: TabataSessionStore.key)
        let store = TabataSessionStore(defaults: defaults)
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.data(forKey: TabataSessionStore.key), "le snapshot illisible est efface")
    }

    // MARK: - Gardien: reprise et Sante

    /// Le gardien relit le disque au premier acces: c'est ce qui rend une seance
    /// visible apres relance, avant toute config par defaut.
    func testKeeperRestoresFromStoreBeforeDefaults() {
        let store = makeStore()
        let (e, advance) = makeEngine(start: 10_000)
        e.begin()
        advance(10 + 3)
        store.save(e.snapshot(healthSaved: false, savedAt: Date(timeIntervalSince1970: 10_013)))

        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in true },
                                         now: { Date(timeIntervalSince1970: 10_013 + 2) })
        let restored = keeper.engine
        XCTAssertEqual(restored.sessionID, e.sessionID)
        XCTAssertEqual(restored.cfg, cfg, "la config de la seance, pas celle des reglages")
        XCTAssertEqual(restored.phase, .work)
        XCTAssertEqual(restored.remaining, 27 - 2)
        XCTAssertTrue(keeper.hasActiveSession)
        XCTAssertTrue(keeper.engine === restored, "un seul moteur pour tout le processus")
    }

    func testKeeperPersistsOnEveryStateChangeAndClearsOnDiscard() {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 11_000)
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in true }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = cfg
        XCTAssertNil(store.load(), "au repos, rien sur le disque")

        e.begin()
        XCTAssertEqual(store.load()?.phase, "prepare")
        clock = clock.addingTimeInterval(4); e.tick()
        XCTAssertEqual(store.load()?.remaining, 6)
        e.startOrPause()
        XCTAssertEqual(store.load()?.running, false)

        keeper.discard()
        XCTAssertNil(store.load(), "abandonner efface le snapshot")
        XCTAssertEqual(e.phase, .idle)
        XCTAssertFalse(keeper.hasActiveSession)
    }

    /// 5 + 30 + 10 + 30 = 75 s, sans calme ni recup: finie par le temps en 75 s.
    private let shortCfg = TabataConfig(prepare: 5, work: 30, rest: 10,
                                        rounds: 2, cycles: 1, restCycle: 0, cooldown: 0)

    /// UNE ecriture Sante par seance: ni au retour sur l'ecran, ni a la reprise
    /// depuis le disque, ni si `.done` est atteint deux fois. Et "ecrite" ne
    /// se dit qu'APRES la reponse de Sante, jamais au lancement de l'ecriture.
    func testHealthWrittenOnceEvenAfterRestore() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 12_000)
        var writes: [TabataHealthWorkout] = []
        let keeper = TabataSessionKeeper(store: store,
                                         healthWriter: { w in writes.append(w); return true },
                                         now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        clock = clock.addingTimeInterval(75); e.tick()
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(keeper.healthWriteCount, 1)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .pending, "lancee, pas encore acceptee")
        XCTAssertFalse(keeper.healthSaved(for: e.sessionID), "pas 'ecrite' avant la reponse")
        XCTAssertEqual(store.load()?.healthSaved, false, "le snapshot ne ment pas pendant l'ecriture")

        let ok = await keeper.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(ok, true)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.sessionID, e.sessionID)
        XCTAssertEqual(writes.first?.syncIdentifier, "lifeos.tabata.\(e.sessionID.uuidString)")
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .saved)
        XCTAssertTrue(keeper.healthSaved(for: e.sessionID))
        XCTAssertEqual(store.load()?.healthSaved, true, "le flag voyage avec le snapshot, apres succes")

        // Un second gardien (relance de l'app) relit le snapshot termine.
        let keeper2 = TabataSessionKeeper(store: store, healthWriter: { _ in
            XCTFail("aucune ecriture ne doit repartir a la reprise"); return true
        }, now: { clock })
        let r = keeper2.engine
        XCTAssertEqual(r.phase, .done)
        XCTAssertTrue(keeper2.healthSaved(for: r.sessionID))
        r.skipForward(); r.tick()
        XCTAssertEqual(keeper2.healthWriteCount, 0)

        // Recommencer = nouvelle seance = nouvelle ecriture, une seule.
        r.now = { clock }
        r.reset(); r.begin()
        XCTAssertNotEqual(r.sessionID, e.sessionID)
        XCTAssertEqual(keeper2.healthWriteCount, 0)
    }

    /// Sante refuse: la seance est `failed`, jamais `saved`, et un nouvel essai
    /// repart avec la MEME fenetre et le meme identifiant de synchronisation.
    func testFailedHealthWriteIsNotMarkedSavedAndCanBeRetried() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 15_000)
        var answers = [false, true]
        var writes: [TabataHealthWorkout] = []
        let keeper = TabataSessionKeeper(store: store,
                                         healthWriter: { w in writes.append(w); return answers.removeFirst() },
                                         now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        clock = clock.addingTimeInterval(75); e.tick()
        XCTAssertEqual(e.phase, .done)

        let first = await keeper.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(first, false)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .failed)
        XCTAssertFalse(keeper.healthSaved(for: e.sessionID), "un refus n'est pas une ecriture")
        XCTAssertEqual(store.load()?.healthSaved, false)

        clock = clock.addingTimeInterval(120)             // l'utilisateur appuie plus tard
        keeper.retryHealthWrite()
        XCTAssertEqual(keeper.healthWriteCount, 2)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .pending)
        let second = await keeper.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(second, true)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .saved)
        XCTAssertEqual(store.load()?.healthSaved, true)
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0], writes[1], "meme fenetre, meme identifiant: Sante remplace, ne double pas")

        keeper.retryHealthWrite()
        XCTAssertEqual(keeper.healthWriteCount, 2, "rien a reessayer une fois acceptee")
    }

    /// Deux `done` pendant que l'ecriture est en vol (reprise d'ecran, second
    /// rappel de fin): une seule ecriture, et l'etat reste `pending` jusqu'a la
    /// reponse.
    func testConcurrentDoneCallbacksWriteOnce() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 16_000)
        let gate = AsyncStream<Void>.makeStream()
        var calls = 0
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in
            calls += 1
            for await _ in gate.stream { break }       // reste en vol jusqu'au signal
            return true
        }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        clock = clock.addingTimeInterval(75); e.tick()
        XCTAssertEqual(e.phase, .done)
        await Task.yield()                               // laisse l'ecriture demarrer

        e.onFinished?()                                  // second `done`, ecriture en vol
        e.onFinished?()
        e.skipForward(); e.tick()
        XCTAssertEqual(keeper.healthWriteCount, 1)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .pending)
        XCTAssertFalse(keeper.healthSaved(for: e.sessionID))

        gate.continuation.yield(())
        let ok = await keeper.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(ok, true)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .saved)

        e.onFinished?()                                  // apres succes: rien non plus
        XCTAssertEqual(keeper.healthWriteCount, 1)
    }

    /// L'app est tuee entre la fin et l'acceptation par Sante (ou Sante a refuse
    /// puis l'app est fermee). Au relancement, la seance finie et non ecrite est
    /// reessayee, datee de sa vraie fin, et le succes est note.
    func testRelaunchRetriesUnsavedFinishedSession() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 17_000)
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in false }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        clock = clock.addingTimeInterval(75); e.tick()
        let finishedAt = clock
        _ = await keeper.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .failed)
        XCTAssertEqual(store.load()?.healthSaved, false)

        // Relance une heure plus tard: le snapshot dit fini et non ecrit.
        clock = clock.addingTimeInterval(3600)
        var writes: [TabataHealthWorkout] = []
        let keeper2 = TabataSessionKeeper(store: store,
                                          healthWriter: { w in writes.append(w); return true },
                                          now: { clock })
        let r = keeper2.engine
        XCTAssertEqual(r.phase, .done)
        XCTAssertEqual(r.sessionID, e.sessionID)
        XCTAssertEqual(keeper2.healthWriteCount, 1, "reessai automatique au relancement")
        let ok = await keeper2.awaitHealthWrite(for: r.sessionID)
        XCTAssertEqual(ok, true)
        XCTAssertEqual(keeper2.healthState(for: r.sessionID), .saved)
        XCTAssertEqual(store.load()?.healthSaved, true)
        XCTAssertEqual(writes.first?.end, finishedAt, "date de la vraie fin, pas du relancement")
        XCTAssertEqual(writes.first?.duration, 75)
        XCTAssertEqual(writes.first?.syncIdentifier, "lifeos.tabata.\(e.sessionID.uuidString)",
                       "meme identifiant: si la 1re ecriture etait passee malgre le crash, Sante remplace")
    }

    /// Seance en cours a la fermeture, qui se termine PENDANT le rattrapage du
    /// relancement: `onFinished` doit deja etre pose, donc Sante est ecrit.
    func testFinishDuringRestoreCatchUpWritesHealth() async {
        let store = makeStore()
        let (e, advance) = makeEngine(start: 18_000)
        e.cfg = shortCfg
        e.begin()
        advance(70)                                      // 5 s avant la fin
        XCTAssertEqual(e.phase, .work); XCTAssertEqual(e.remaining, 5)
        store.save(e.snapshot(healthSaved: false, savedAt: Date(timeIntervalSince1970: 18_070)))

        let relaunch = Date(timeIntervalSince1970: 18_070 + 30)
        var writes: [TabataHealthWorkout] = []
        let keeper = TabataSessionKeeper(store: store,
                                         healthWriter: { w in writes.append(w); return true },
                                         now: { relaunch })
        let r = keeper.engine
        XCTAssertEqual(r.phase, .done, "les 30 s d'absence couvrent les 5 s restantes")
        XCTAssertEqual(r.activeSeconds, 75)
        XCTAssertEqual(keeper.healthWriteCount, 1, "la fin pendant le rattrapage declenche l'ecriture")
        let ok = await keeper.awaitHealthWrite(for: r.sessionID)
        XCTAssertEqual(ok, true)
        XCTAssertTrue(keeper.healthSaved(for: r.sessionID))
        XCTAssertEqual(store.load()?.healthSaved, true)
        XCTAssertEqual(writes.first?.sessionID, e.sessionID)
        XCTAssertEqual(writes.first?.duration, 75, "seulement le temps actif")
        XCTAssertEqual(writes.first?.end, Date(timeIntervalSince1970: 18_075),
                       "la fin est la vraie frontiere (5 s apres la sauvegarde), pas le relancement")
        XCTAssertEqual(r.finishedAt, Date(timeIntervalSince1970: 18_075))
        XCTAssertEqual(store.load()?.finishedAt, Date(timeIntervalSince1970: 18_075),
                       "la fin voyage dans le snapshot")
    }

    /// Une pause d'une heure au milieu n'entre pas dans Sante: la fenetre
    /// ecrite dure exactement le temps actif, calee sur la fin.
    func testHealthWindowExcludesHourLongPause() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 19_000)
        var writes: [TabataHealthWorkout] = []
        let keeper = TabataSessionKeeper(store: store,
                                         healthWriter: { w in writes.append(w); return true },
                                         now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        clock = clock.addingTimeInterval(40); e.tick()   // 40 s actives
        e.startOrPause()                                 // pause
        clock = clock.addingTimeInterval(3600); e.tick() // une heure de telephone pose
        XCTAssertEqual(e.activeSeconds, 40, "la pause ne credite rien")
        e.startOrPause()                                 // reprise
        clock = clock.addingTimeInterval(35); e.tick()   // les 35 s restantes
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(e.activeSeconds, 75)

        let ok = await keeper.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(ok, true)
        let w = writes.first
        XCTAssertNotNil(w)
        XCTAssertEqual(w?.duration, 75, "75 s actives, pas 3 675 s d'horloge")
        XCTAssertEqual(w?.end, clock, "calee sur la fin de la seance")
        XCTAssertEqual(w?.start, clock.addingTimeInterval(-75))
        XCTAssertGreaterThanOrEqual(w?.start ?? .distantPast, e.startedAt ?? .distantFuture,
                                    "jamais avant le vrai debut")
    }

    func testHealthNotWrittenWhenActiveTimeUnderOneMinute() {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 13_000)
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in
            XCTFail("moins d'une minute d'activite: pas d'ecriture"); return true
        }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = cfg
        e.begin()
        clock = clock.addingTimeInterval(20); e.tick()
        for _ in 0..<20 { e.skipForward() }          // sauter jusqu'a la fin
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(e.activeSeconds, 20)
        XCTAssertEqual(keeper.healthWriteCount, 0)
        XCTAssertFalse(keeper.healthSaved(for: e.sessionID))
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .notEligible)
    }

    /// Une seance sautee en entier puis "terminee" n'ecrit rien: le saut n'est
    /// pas du travail, meme si l'heure de debut est loin.
    func testJumpingThroughWholeSessionIsNotAWorkout() {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 14_000)
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in
            XCTFail("des sauts ne font pas une seance"); return true
        }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = cfg
        e.begin()
        clock = clock.addingTimeInterval(10 * 60)        // 10 min plus tard, sans un seul tick
        for _ in 0..<20 { e.skipForward() }
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(keeper.healthWriteCount, 0)
    }

    // MARK: - Fin immuable et file Sante durable

    /// Une ecriture qui echoue TARD: entre la fin et le refus, le snapshot est
    /// resauvegarde (savedAt avance). Au relancement, le workout garde sa vraie
    /// fin, pas l'heure de la derniere sauvegarde ni celle du relancement.
    func testDelayedFailureThenRelaunchKeepsOriginalFinishTime() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 20_000)
        let gate = AsyncStream<Void>.makeStream()
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in
            for await _ in gate.stream { break }       // reponse retardee
            return false                                // ... puis refus
        }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        clock = clock.addingTimeInterval(75); e.tick()
        XCTAssertEqual(e.phase, .done)
        let realFinish = clock
        XCTAssertEqual(e.finishedAt, realFinish)
        XCTAssertEqual(store.load()?.finishedAt, realFinish)

        clock = clock.addingTimeInterval(600)            // 10 min: des sauvegardes plus tard
        keeper.persist()
        XCTAssertGreaterThan(store.load()?.savedAt ?? .distantPast, realFinish, "savedAt a bouge")
        XCTAssertEqual(store.load()?.finishedAt, realFinish, "finishedAt n'a pas bouge")

        gate.continuation.yield(())
        let first = await keeper.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(first, false)
        XCTAssertEqual(keeper.healthState(for: e.sessionID), .failed)

        clock = clock.addingTimeInterval(3600)           // relance une heure plus tard
        var writes: [TabataHealthWorkout] = []
        let keeper2 = TabataSessionKeeper(store: store,
                                          healthWriter: { w in writes.append(w); return true },
                                          now: { clock })
        let ok = await keeper2.awaitHealthWrite(for: e.sessionID)
        XCTAssertEqual(ok, true)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.end, realFinish, "meme fin qu'a la premiere tentative")
        XCTAssertEqual(writes.first?.start, realFinish.addingTimeInterval(-75))
        XCTAssertEqual(writes.first?.syncIdentifier, "lifeos.tabata.\(e.sessionID.uuidString)")
        XCTAssertEqual(keeper2.healthState(for: e.sessionID), .saved)
    }

    /// Refus, puis l'utilisateur lance une AUTRE seance (le snapshot est
    /// remplace), puis relance l'app: la premiere seance est toujours due, et
    /// elle part avec sa fenetre et son identifiant d'origine.
    func testFailedWorkoutSurvivesNewSessionAndRelaunch() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 21_000)
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in false }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        let sessionA = e.sessionID
        clock = clock.addingTimeInterval(75); e.tick()
        let finishA = clock
        _ = await keeper.awaitHealthWrite(for: sessionA)
        XCTAssertEqual(keeper.healthState(for: sessionA), .failed)
        let queued = store.loadHealthQueue()
        XCTAssertEqual(queued.map(\.sessionID), [sessionA], "la seance refusee est en file durable")

        clock = clock.addingTimeInterval(300)
        e.reset(); e.begin()                             // seance B remplace le snapshot
        let sessionB = e.sessionID
        XCTAssertNotEqual(sessionA, sessionB)
        XCTAssertEqual(store.load()?.sessionID, sessionB, "le snapshot est celui de B")
        XCTAssertEqual(store.loadHealthQueue().map(\.sessionID), [sessionA], "A reste due")
        XCTAssertEqual(keeper.healthState(for: sessionA), .failed)

        clock = clock.addingTimeInterval(3600)           // relance
        var writes: [TabataHealthWorkout] = []
        let keeper2 = TabataSessionKeeper(store: store,
                                          healthWriter: { w in writes.append(w); return true },
                                          now: { clock })
        XCTAssertEqual(keeper2.healthWriteCount, 1, "A repart au demarrage, sans ouvrir l'ecran")
        let ok = await keeper2.awaitHealthWrite(for: sessionA)
        XCTAssertEqual(ok, true)
        XCTAssertEqual(writes, [queued[0]], "exactement la fenetre calculee a la fin de A")
        XCTAssertEqual(writes.first?.end, finishA)
        XCTAssertEqual(writes.first?.syncIdentifier, "lifeos.tabata.\(sessionA.uuidString)")
        XCTAssertTrue(store.loadHealthQueue().isEmpty, "acceptee: sortie de la file")
        XCTAssertEqual(keeper2.engine.sessionID, sessionB, "la seance B en cours n'est pas touchee")
        XCTAssertEqual(keeper2.healthWriteCount, 1, "B n'est pas finie: rien d'autre n'est ecrit")
    }

    /// Ecriture EN VOL quand la seance est remplacee puis l'app tuee: la
    /// tache meurt avec le processus, la file, elle, survit et rejoue A.
    func testInFlightWriteSurvivesSessionReplacementAndTermination() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 22_000)
        let never = AsyncStream<Void>.makeStream()       // jamais de reponse
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in
            for await _ in never.stream { break }
            return true
        }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        let sessionA = e.sessionID
        clock = clock.addingTimeInterval(75); e.tick()
        let finishA = clock
        await Task.yield()
        XCTAssertEqual(keeper.healthState(for: sessionA), .pending)
        XCTAssertEqual(store.loadHealthQueue().map(\.sessionID), [sessionA],
                       "en file AVANT la reponse, pas apres")

        e.reset(); e.begin()                             // seance B pendant l'ecriture de A
        XCTAssertNotEqual(e.sessionID, sessionA)
        XCTAssertEqual(store.loadHealthQueue().map(\.sessionID), [sessionA])

        // "Fermeture de l'app": un nouveau gardien sur le meme disque, l'ancienne
        // tache n'existe plus.
        clock = clock.addingTimeInterval(120)
        var writes: [TabataHealthWorkout] = []
        let keeper2 = TabataSessionKeeper(store: store,
                                          healthWriter: { w in writes.append(w); return true },
                                          now: { clock })
        let ok = await keeper2.awaitHealthWrite(for: sessionA)
        XCTAssertEqual(ok, true)
        XCTAssertEqual(writes.map(\.sessionID), [sessionA])
        XCTAssertEqual(writes.first?.end, finishA, "datee de la fin de A, pas du relancement")
        XCTAssertEqual(writes.first?.duration, 75)
        XCTAssertTrue(store.loadHealthQueue().isEmpty)
        never.continuation.finish()
    }

    /// "Reessayer" couvre la file entiere, pas seulement la seance a l'ecran.
    func testRetryCoversQueuedSessionNotOnlyLiveOne() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 23_000)
        var accept = false
        var writes: [TabataHealthWorkout] = []
        let keeper = TabataSessionKeeper(store: store,
                                         healthWriter: { w in writes.append(w); return accept },
                                         now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        let sessionA = e.sessionID
        clock = clock.addingTimeInterval(75); e.tick()
        _ = await keeper.awaitHealthWrite(for: sessionA)
        XCTAssertEqual(keeper.healthState(for: sessionA), .failed)

        e.reset(); e.begin()                             // B a l'ecran, A n'est plus la seance vivante
        accept = true
        keeper.retryHealthWrite()
        XCTAssertEqual(keeper.healthWriteCount, 2)
        let ok = await keeper.awaitHealthWrite(for: sessionA)
        XCTAssertEqual(ok, true)
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0], writes[1], "meme fenetre, meme identifiant au reessai")
        XCTAssertEqual(keeper.healthState(for: sessionA), .saved)
        XCTAssertTrue(store.loadHealthQueue().isEmpty)
        keeper.retryHealthWrite()
        XCTAssertEqual(keeper.healthWriteCount, 2, "plus rien en file: rien ne repart")
    }

    /// "Terminer & Fermer" sur l'ecran de fin (discard) ne perd pas une
    /// ecriture encore due.
    func testDiscardAfterFailedWriteKeepsQueue() async {
        let store = makeStore()
        var clock = Date(timeIntervalSince1970: 24_000)
        let keeper = TabataSessionKeeper(store: store, healthWriter: { _ in false }, now: { clock })
        let e = keeper.engine
        e.now = { clock }
        e.cfg = shortCfg
        e.begin()
        let sessionA = e.sessionID
        clock = clock.addingTimeInterval(75); e.tick()
        _ = await keeper.awaitHealthWrite(for: sessionA)
        keeper.discard()
        XCTAssertNil(store.load(), "le snapshot est efface")
        XCTAssertEqual(store.loadHealthQueue().map(\.sessionID), [sessionA], "la file reste")
    }
}
