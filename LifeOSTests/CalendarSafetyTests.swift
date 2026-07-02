import XCTest

// Tests pour vérifier que les opérations Calendar ne crashent pas
// Ces tests couvrent les cas qui étaient des force unwrap (!) dans la codebase
final class CalendarSafetyTests: XCTestCase {

    // MARK: - date(byAdding:) — devrait toujours retourner une date valide

    func testTomorrowStartNeverNil() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let result = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)
        XCTAssertNotNil(result, "date(byAdding: +1 day) ne devrait jamais être nil")
    }

    func testFourteenDaysAgoNeverNil() {
        let result = Calendar.current.date(byAdding: .day, value: -14, to: Date())
        XCTAssertNotNil(result, "date(byAdding: -14 days) ne devrait jamais être nil")
    }

    func testWeekDataDatesNeverNil() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let weekDays = (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: todayStart)
        }
        XCTAssertEqual(weekDays.count, 7, "Les 7 jours de la semaine doivent être calculables")
    }

    func testGoalPresetDatesNeverNil() {
        let presetDays = [7, 14, 21, 30, 60, 90]
        for days in presetDays {
            let result = Calendar.current.date(byAdding: .day, value: days, to: Date())
            XCTAssertNotNil(result, "Preset +\(days) jours ne devrait jamais être nil")
        }
    }

    func testMoodHistoryPast6DaysNeverNil() {
        let past6 = (1...6).compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date())
        }
        XCTAssertEqual(past6.count, 6, "Les 6 derniers jours doivent être calculables")
    }

    // MARK: - Fallback correctness

    func testTomorrowFallbackIsAfterToday() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        XCTAssertGreaterThan(tomorrow, todayStart, "Le fallback doit être après aujourd'hui")
    }

    func testPastCutoffFallbackIsBeforeNow() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? Date()
        XCTAssertLessThan(cutoff, Date(), "La date de coupure doit être dans le passé")
    }
}
