import XCTest
@testable import LifeOS

/// Le compte a rebours doit survivre a l'arriere plan et a l'arret du processus.
///
/// L'ancienne version decrementait un compteur dans un `Timer` en process. Un `Timer`
/// ne tourne pas en arriere plan et disparait si le processus est tue : une sieste de
/// 20 minutes, telephone verrouille, affichait encore 19:58 au retour.
///
/// Ces controles n'attendent jamais reellement : ils manipulent l'horloge via l'etat
/// persiste, ce qui est justement possible parce que l'autorite est une DATE de fin.
@MainActor
final class CountdownEngineTests: XCTestCase {

    private func clean(_ key: String) {
        UserDefaults.standard.removeObject(forKey: "countdown.\(key)")
    }

    override func tearDown() { clean("test"); clean("nap"); super.tearDown() }

    func testRemainingIsDerivedFromTheClockNotACounter() {
        clean("test")
        let e = CountdownEngine(key: "test")
        e.start(seconds: 600)
        XCTAssertTrue(e.isRunning)
        // Sans avancer l'horloge, il reste ~600 s. Le point est qu'aucun tick n'est
        // necessaire : la valeur se deduit de la date de fin.
        assertNear(e.remaining, 600, tolerance: 1)
    }

    /// Le cas qui echouait : processus tue pendant que ca tourne, puis relance.
    func testSessionSurvivesProcessRestart() {
        clean("nap")
        let first = CountdownEngine(key: "nap")
        first.start(seconds: 1200)
        assertNear(first.remaining, 1200, tolerance: 1)

        // Nouvelle instance = ce que fait un relancement de l'app.
        let second = CountdownEngine(key: "nap")
        XCTAssertTrue(second.isRunning, "la session doit etre reprise")
        assertNear(second.remaining, 1200, tolerance: 2, "le temps restant vient de la date de fin, pas d'un compteur perdu")
    }

    /// Echeance depassee pendant que l'app etait fermee : on ne doit pas reprendre
    /// une session morte ni afficher un reste faux.
    func testDeadlineThatPassedWhileClosedDoesNotResume() {
        clean("nap")
        UserDefaults.standard.set([
            "total": 600,
            "isRunning": true,
            "pausedRemaining": 600,
            "deadline": Date().addingTimeInterval(-30).timeIntervalSince1970
        ], forKey: "countdown.nap")

        let e = CountdownEngine(key: "nap")
        XCTAssertFalse(e.isRunning, "une echeance passee ne redemarre pas")
        XCTAssertEqual(e.remaining, 0)
        XCTAssertNil(UserDefaults.standard.dictionary(forKey: "countdown.nap"),
                     "la session terminee est nettoyee")
    }

    func testPauseFreezesAndResumeRebasesTheDeadline() {
        clean("test")
        let e = CountdownEngine(key: "test")
        e.start(seconds: 300)
        e.pause()
        XCTAssertFalse(e.isRunning)
        let frozen = e.remaining
        assertNear(frozen, 300, tolerance: 1, "en pause le reste est fige")

        e.resume()
        XCTAssertTrue(e.isRunning)
        assertNear(e.remaining, frozen, tolerance: 1, "reprendre repart du reste fige")
    }

    /// Deux timers differents ne doivent pas partager leur etat.
    func testTwoEnginesDoNotShareState() {
        clean("test"); clean("nap")
        let a = CountdownEngine(key: "test"); a.start(seconds: 100)
        let b = CountdownEngine(key: "nap")
        XCTAssertFalse(b.isRunning, "une autre session ne doit pas heriter de la premiere")
    }

    func testStopClearsPersistedState() {
        clean("test")
        let e = CountdownEngine(key: "test")
        e.start(seconds: 120)
        e.stop()
        XCTAssertFalse(e.isRunning)
        XCTAssertEqual(e.remaining, 0)
        XCTAssertNil(UserDefaults.standard.dictionary(forKey: "countdown.test"))
    }
}

private extension XCTestCase {
    /// Nom distinct : une surcharge appelee `XCTAssertEqual` masque la fonction globale
    /// et casse tous les autres appels du fichier.
    func assertNear(_ a: Int, _ b: Int, tolerance: Int = 1, _ msg: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(abs(a - b) <= tolerance, "\(msg) (\(a) vs \(b) ±\(tolerance))", file: file, line: line)
    }
}
