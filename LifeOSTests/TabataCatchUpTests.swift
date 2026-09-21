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
    func testVeryLongGapTerminatesCleanly() {
        let start = Date(timeIntervalSince1970: 4_000_000)
        var clock = start
        let e = TabataEngine(cfg: TabataConfig(prepare: 10, work: 30, rest: 15,
                                               rounds: 2, cycles: 1, restCycle: 60, cooldown: 0))
        e.now = { clock }
        e.begin()

        clock = clock.addingTimeInterval(9_000) // deux heures et demie
        e.tick()
        XCTAssertEqual(e.phase, .done, "la seance doit etre terminee, pas bloquee")
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
}
