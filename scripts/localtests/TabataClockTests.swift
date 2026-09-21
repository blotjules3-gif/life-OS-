import XCTest

/// Horloge Tabata de la montre. Execute en local seulement: la cible Watch
/// n'a pas de suite de tests XCTest, et c'est de la logique pure.
final class TabataClockTests: XCTestCase {
    private let c = TabataClock()   // 20 s / 10 s x 8

    func testStartsInWork() {
        XCTAssertEqual(c.state(elapsed: 0), TabataClock.State(phase: .work, round: 1, remaining: 20))
    }
    func testWorkToRest() {
        XCTAssertEqual(c.state(elapsed: 20), TabataClock.State(phase: .rest, round: 1, remaining: 10))
    }
    func testSecondRound() {
        XCTAssertEqual(c.state(elapsed: 30), TabataClock.State(phase: .work, round: 2, remaining: 20))
    }
    /// 8 series, pas de repos apres la derniere: 8x30 - 10 = 230 s.
    func testTotalHasNoFinalRest() {
        XCTAssertEqual(c.totalSeconds, 230)
        XCTAssertEqual(c.state(elapsed: 229).phase, .work)
        XCTAssertEqual(c.state(elapsed: 229).round, 8)
        XCTAssertEqual(c.state(elapsed: 230).phase, .done)
    }
    /// Ecran eteint 3 minutes au poignet: on retombe au bon endroit.
    func testLongGapLandsInRightPlace() {
        XCTAssertEqual(c.state(elapsed: 205), TabataClock.State(phase: .rest, round: 7, remaining: 5))
    }
    func testNegativeElapsedIsStart() {
        XCTAssertEqual(c.state(elapsed: -5).phase, .work)
    }
    func testWayPastEndIsDone() {
        XCTAssertEqual(c.state(elapsed: 99_999).phase, .done)
    }
    func testZeroRoundsIsDone() {
        XCTAssertEqual(TabataClock(work: 20, rest: 10, rounds: 0).state(elapsed: 0).phase, .done)
    }
}
