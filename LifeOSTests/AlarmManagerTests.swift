import XCTest
@testable import LifeOS

// Tests pour la logique non-UI d'AlarmManager
@MainActor
final class AlarmManagerTests: XCTestCase {
    var alarm: AlarmManager!

    override func setUp() async throws {
        try await super.setUp()
        alarm = AlarmManager.shared
    }

    // MARK: - État initial

    func testInitialStateNotRinging() {
        // L'alarm ne sonne pas au lancement de l'app
        XCTAssertFalse(alarm.isRinging)
        XCTAssertFalse(alarm.showAlarmScreen)
        XCTAssertFalse(alarm.showBriefing)
        XCTAssertFalse(alarm.showSleepCheck)
    }

    // MARK: - Snooze logic

    func testSnoozeStopsRinging() {
        // Simuler alarme active
        alarm.triggerAlarm()
        XCTAssertTrue(alarm.isRinging, "L'alarme doit sonner après triggerAlarm()")
        alarm.snooze(minutes: 9)
        XCTAssertFalse(alarm.isRinging, "L'alarme doit s'arrêter après snooze()")
        XCTAssertFalse(alarm.showAlarmScreen, "L'écran d'alarme doit être caché après snooze()")
    }

    func testStopRingingResetsState() {
        alarm.triggerAlarm()
        alarm.stopRinging()
        XCTAssertFalse(alarm.isRinging)
        XCTAssertFalse(alarm.isSpeaking)
    }

    // MARK: - Double trigger guard

    func testTriggerAlarmIsIdempotent() {
        alarm.triggerAlarm()
        let secondsAfterFirst = alarm.secondsLeft
        alarm.triggerAlarm() // second appel devrait être ignoré
        XCTAssertEqual(alarm.secondsLeft, secondsAfterFirst, "Double trigger ne doit pas reset le countdown")
        alarm.stopRinging()
    }

    // MARK: - Stop and show briefing

    func testStopAndShowBriefingHidesAlarmScreen() {
        alarm.triggerAlarm()
        alarm.stopAndShowBriefing()
        XCTAssertFalse(alarm.showAlarmScreen, "L'écran d'alarme doit être caché")
        XCTAssertTrue(alarm.showSleepCheck, "Le sleep check doit apparaître")
        XCTAssertFalse(alarm.isRinging, "L'alarme ne doit plus sonner")
        alarm.phase = .idle // cleanup
    }
}
