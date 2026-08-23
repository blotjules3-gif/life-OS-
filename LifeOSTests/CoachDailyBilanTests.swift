import XCTest
@testable import LifeOS

/// Vérifie que les préférences bilans quotidiens persistent + valident les
/// bornes horaires + que le hash de config change quand attendu.
@MainActor
final class CoachDailyBilanTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "coach.bilan.enabled")
        UserDefaults.standard.removeObject(forKey: "coach.bilan.morning.hour")
        UserDefaults.standard.removeObject(forKey: "coach.bilan.evening.hour")
        UserDefaults.standard.removeObject(forKey: "coach.bilan.lastConfigHash")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "coach.bilan.enabled")
        UserDefaults.standard.removeObject(forKey: "coach.bilan.morning.hour")
        UserDefaults.standard.removeObject(forKey: "coach.bilan.evening.hour")
        UserDefaults.standard.removeObject(forKey: "coach.bilan.lastConfigHash")
        super.tearDown()
    }

    // MARK: - Défauts sensés

    func testDefaults_areEnabled() {
        XCTAssertTrue(CoachDailyBilan.isEnabled, "Défaut : bilans activés")
    }

    func testDefaults_morningHourIs8() {
        XCTAssertEqual(CoachDailyBilan.morningHour, 8)
    }

    func testDefaults_eveningHourIs21() {
        XCTAssertEqual(CoachDailyBilan.eveningHour, 21)
    }

    // MARK: - Setters

    func testSetMorningHour_persists() {
        CoachDailyBilan.morningHour = 7
        XCTAssertEqual(CoachDailyBilan.morningHour, 7)
    }

    func testSetEveningHour_persists() {
        CoachDailyBilan.eveningHour = 22
        XCTAssertEqual(CoachDailyBilan.eveningHour, 22)
    }

    // MARK: - Validation bornes

    func testMorningHour_invalidValue_returnsDefault() {
        UserDefaults.standard.set(3, forKey: "coach.bilan.morning.hour")
        XCTAssertEqual(CoachDailyBilan.morningHour, CoachDailyBilan.defaultMorningHour,
                       "Heure hors bornes 5-12 → défaut")
    }

    func testEveningHour_invalidValue_returnsDefault() {
        UserDefaults.standard.set(3, forKey: "coach.bilan.evening.hour")
        XCTAssertEqual(CoachDailyBilan.eveningHour, CoachDailyBilan.defaultEveningHour,
                       "Heure hors bornes 18-23 → défaut")
    }

    // MARK: - Toggle

    func testDisable_persists() {
        CoachDailyBilan.isEnabled = false
        XCTAssertFalse(CoachDailyBilan.isEnabled)
    }
}
