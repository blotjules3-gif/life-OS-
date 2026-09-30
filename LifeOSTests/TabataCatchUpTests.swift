import XCTest
@testable import LifeOS

/// Rattrapage du temps passe en arriere-plan par le minuteur Tabata.
///
/// Le bug corrige: chaque battement retirait exactement 1 seconde. Or un Timer
/// ne tourne pas quand l'app est en arriere-plan, donc verrouiller l'ecran en
/// pleine seance figeait le chrono sans rien dire. Le moteur se cale desormais
/// sur l'horloge, et ces tests le prouvent sans avoir a attendre vraiment.
@MainActor
final class TabataCatchUpTests: XCTestCase {

    /// 10 s de preparation, 30 s d'effort, 15 s de repos, 2 rounds, 1 cycle.
    private func makeEngine(at start: Date) -> (TabataEngine, () -> Void) {
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        let advance1s = { clock = clock.addingTimeInterval(1) }
        return (e, advance1s)
    }

    func testOneTickRemovesOneSecond() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()
        XCTAssertEqual(e.remaining, 10)

        clock = clock.addingTimeInterval(1)
        e.tick()
        XCTAssertEqual(e.remaining, 9, "une seconde d'horloge doit retirer une seconde")
    }

    /// Le coeur du correctif: l'app revient apres 5 s absentes, le chrono doit
    /// avoir avance de 5 s, pas de 1.
    func testCatchesUpAfterBackgroundGap() {
        let start = Date(timeIntervalSince1970: 2_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()

        clock = clock.addingTimeInterval(5)     // ecran verrouille 5 secondes
        e.tick()
        XCTAssertEqual(e.remaining, 5, "le retard doit etre rattrape d'un coup")
    }

    /// Absence plus longue qu'un intervalle: on doit traverser les phases.
    func testCatchUpCrossesPhaseBoundary() {
        let start = Date(timeIntervalSince1970: 3_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()
        XCTAssertEqual(e.phase, .prepare)

        clock = clock.addingTimeInterval(12)    // 10 s de prepa + 2 s d'effort
        e.tick()
        XCTAssertEqual(e.phase, .work, "apres la preparation on doit etre en effort")
        XCTAssertEqual(e.remaining, 28, "2 s d'effort doivent avoir ete consommees")
    }

    /// Une absence absurde ne doit ni boucler sans fin ni casser l'etat.
    /// Regle depuis le 30 septembre 2026: au-dela de 5 minutes d'absence, la
    /// seance se met en PAUSE la ou elle en etait. Avant, elle passait a
    /// "terminee" et une heure de telephone pose devenait une seance faite.
    func testVeryLongGapPausesInsteadOfCrediting() {
        let start = Date(timeIntervalSince1970: 4_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()
        clock = clock.addingTimeInterval(4)
        e.tick()

        clock = clock.addingTimeInterval(9_000) // deux heures et demie
        e.tick()
        XCTAssertEqual(e.phase, .prepare, "la seance reste ou elle en etait")
        XCTAssertEqual(e.remaining, 6, "rien de l'absence n'est consomme")
        XCTAssertFalse(e.running, "elle est mise en pause")
        XCTAssertEqual(e.interruptionGap.map { Int($0) }, 9_000)
        XCTAssertEqual(e.activeSeconds, 4, "seules les 4 s reelles sont creditees")
    }

    /// Juste sous la limite, l'absence est rattrapee comme avant.
    func testGapUnderLimitIsCaughtUp() {
        let start = Date(timeIntervalSince1970: 4_500_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()

        clock = clock.addingTimeInterval(TabataEngine.maxUnattendedGap) // 5 min pile
        e.tick()
        XCTAssertEqual(e.phase, .done, "5 min couvrent toute cette seance de 85 s")
        XCTAssertTrue(e.interruptionGap == nil)
    }

    /// En pause, l'horloge qui avance ne doit rien consommer.
    func testPausedEngineIgnoresElapsedTime() {
        let start = Date(timeIntervalSince1970: 5_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()
        e.startOrPause()                        // met en pause
        let before = e.remaining

        clock = clock.addingTimeInterval(30)
        e.tick()
        XCTAssertEqual(e.remaining, before, "en pause, le temps ne doit pas defiler")
    }

    // MARK: - Debut de seance, pour Apple Sante

    /// Le debut doit venir de l'horloge injectee, pas de `Date()`, sinon une
    /// seance enregistree dans Sante porterait la mauvaise heure.
    func testBeginRecordsStartFromInjectedClock() {
        let start = Date(timeIntervalSince1970: 7_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        XCTAssertNil(e.startedAt, "rien ne commence avant le premier départ")
        e.begin()
        XCTAssertEqual(e.startedAt, start)

        clock = clock.addingTimeInterval(120)
        e.tick()
        XCTAssertEqual(e.startedAt, start, "le début ne bouge pas pendant la séance")
    }

    /// Remettre a zero efface le debut: sinon la seance suivante serait
    /// enregistree avec la duree de la precedente.
    func testResetClearsStart() {
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { Date(timeIntervalSince1970: 8_000_000) }
        e.begin()
        XCTAssertNotNil(e.startedAt)
        e.reset()
        XCTAssertNil(e.startedAt)
    }

    func testResetReturnsToIdle() {
        let start = Date(timeIntervalSince1970: 6_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()
        clock = clock.addingTimeInterval(4)
        e.tick()

        e.reset()
        XCTAssertEqual(e.phase, .idle)
        XCTAssertEqual(e.remaining, 10)
        XCTAssertEqual(e.round, 1)
    }

    // MARK: - Fin de seance: frontiere reelle

    /// Une seance de 85 s (10 + 30 + 15 + 30) qui se termine PENDANT une absence
    /// de 200 s: la fin est datee de la 85e seconde, pas du retour a 200 s.
    func testFinishDuringCatchUpIsDatedAtRealBoundary() {
        let start = Date(timeIntervalSince1970: 9_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()
        XCTAssertNil(e.finishedAt)
        clock = clock.addingTimeInterval(200)
        e.tick()
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(e.finishedAt, start.addingTimeInterval(85), "la vraie frontiere")
        XCTAssertEqual(e.activeSeconds, 85)

        clock = clock.addingTimeInterval(50)
        e.tick()
        XCTAssertEqual(e.finishedAt, start.addingTimeInterval(85), "posee une fois, jamais recalculee")
        e.reset()
        XCTAssertNil(e.finishedAt, "une nouvelle seance repart sans fin")
    }

    /// Fin par le temps en marche normale: datee de l'horloge du tick.
    func testFinishOnNormalTickIsDatedNow() {
        let start = Date(timeIntervalSince1970: 9_500_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()
        for _ in 0..<85 { clock = clock.addingTimeInterval(1); e.tick() }
        XCTAssertEqual(e.phase, .done)
        XCTAssertEqual(e.finishedAt, clock)
    }
}
