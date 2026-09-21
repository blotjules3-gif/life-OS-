import XCTest
@testable import LifeOS

/// Rappels de prise d'un medicament.
///
/// Ces tests existent parce que l'ecran promettait "des rappels de prise" et
/// n'en posait aucun d'utile: il appelait `schedule(id:title:body:at:)`, qui
/// ne se repete PAS. Un traitement quotidien etait donc rappele une seule
/// fois, le lendemain matin, puis plus jamais. Personne ne peut remarquer ca
/// en testant l'app cinq minutes: il faut attendre le surlendemain.
final class MedicationScheduleTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h)) ?? .distantPast
    }

    // MARK: - Nombre de prises

    func testOncePerDay() {
        let doses = MedicationSchedule.doses(frequency: "1x/jour", hourMorning: 8, hourEvening: 20)
        XCTAssertEqual(doses.count, 1)
        XCTAssertEqual(doses.first?.hour, 8)
    }

    /// Le cas qui n'existait pas: "2x/jour" ne posait qu'un rappel.
    func testTwicePerDayGivesTwoReminders() {
        let doses = MedicationSchedule.doses(frequency: "2x/jour", hourMorning: 8, hourEvening: 20)
        XCTAssertEqual(doses.count, 2)
        XCTAssertEqual(doses.map(\.hour), [8, 20])
    }

    func testThreeTimesPerDay() {
        let doses = MedicationSchedule.doses(frequency: "3x/jour", hourMorning: 8, hourEvening: 20)
        XCTAssertEqual(doses.count, 3)
        XCTAssertEqual(doses.map(\.label), ["matin", "midi", "soir"])
    }

    /// Le midi se place entre les deux prises, pas a une heure fixe: qui
    /// prend son traitement a 6 h et 18 h n'a pas midi au milieu.
    func testMiddayFollowsTheOtherTwo() {
        let doses = MedicationSchedule.doses(frequency: "3x/jour", hourMorning: 6, hourEvening: 18)
        XCTAssertEqual(doses[1].hour, 12)
        let early = MedicationSchedule.doses(frequency: "3x/jour", hourMorning: 5, hourEvening: 15)
        XCTAssertEqual(early[1].hour, 10)
    }

    // MARK: - Le cas qu'il ne faut surtout pas rappeler

    /// Un traitement "au besoin" ne se rappelle jamais. Rappeler chaque matin
    /// de prendre un antidouleur a prendre en cas de douleur pousse a le
    /// prendre sans raison.
    func testOnDemandSchedulesNothing() {
        XCTAssertTrue(MedicationSchedule.isOnDemand("Au besoin"))
        XCTAssertTrue(MedicationSchedule.doses(frequency: "Au besoin",
                                               hourMorning: 8, hourEvening: 20).isEmpty)
    }

    /// Sans accent et en majuscules, c'est toujours "au besoin".
    func testOnDemandIsAccentAndCaseInsensitive() {
        XCTAssertTrue(MedicationSchedule.isOnDemand("AU BESOIN"))
        XCTAssertTrue(MedicationSchedule.isOnDemand("au besoin"))
    }

    func testWeeklyIsDetected() {
        XCTAssertTrue(MedicationSchedule.isWeekly("1x/semaine"))
        XCTAssertFalse(MedicationSchedule.isWeekly("1x/jour"))
        XCTAssertEqual(MedicationSchedule.doses(frequency: "1x/semaine",
                                                hourMorning: 9, hourEvening: 20).count, 1)
    }

    // MARK: - Heures

    /// Une heure absente ne doit pas donner minuit: on ne reveille personne.
    func testMissingHoursFallBackToSaneDefaults() {
        let doses = MedicationSchedule.doses(frequency: "2x/jour", hourMorning: nil, hourEvening: nil)
        XCTAssertEqual(doses.map(\.hour),
                       [MedicationSchedule.defaultMorning, MedicationSchedule.defaultEvening])
    }

    /// Une heure aberrante est ramenee dans la journee au lieu de produire
    /// une notification que le systeme rejette en silence.
    func testOutOfRangeHoursAreClamped() {
        let doses = MedicationSchedule.doses(frequency: "2x/jour", hourMorning: -3, hourEvening: 99)
        XCTAssertEqual(doses.map(\.hour), [0, 23])
    }

    // MARK: - Date de fin

    func testRunningWhenActiveAndNoEndDate() {
        XCTAssertTrue(MedicationSchedule.isRunning(active: true, endDate: nil,
                                                   now: d(2026, 5, 1), calendar: cal))
    }

    func testStoppedWhenInactive() {
        XCTAssertFalse(MedicationSchedule.isRunning(active: false, endDate: nil,
                                                    now: d(2026, 5, 1), calendar: cal))
    }

    /// Le dernier jour compte: un traitement "jusqu'au 12" se prend le 12.
    func testLastDayIsIncluded() {
        XCTAssertTrue(MedicationSchedule.isRunning(active: true,
                                                   endDate: d(2026, 5, 12, 0),
                                                   now: d(2026, 5, 12, 23), calendar: cal))
    }

    func testDayAfterEndDateStops() {
        XCTAssertFalse(MedicationSchedule.isRunning(active: true,
                                                    endDate: d(2026, 5, 12),
                                                    now: d(2026, 5, 13, 1), calendar: cal))
    }

    /// Un traitement termine il y a longtemps ne doit plus sonner: c'est le
    /// trou qui restait, la date de fin n'etait jamais regardee.
    func testLongFinishedTreatmentStops() {
        XCTAssertFalse(MedicationSchedule.isRunning(active: true,
                                                    endDate: d(2025, 1, 1),
                                                    now: d(2026, 5, 1), calendar: cal))
    }
}
