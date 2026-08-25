import XCTest
import SwiftData
@testable import LifeOS

/// Tests du système de rappels intelligents Loop 22 :
/// - `CustomReminder` extension (frequency, weekdayMask, specificHours)
/// - `SmartReminderScheduler.plannedIdentifiers`
/// - `SmartReminderSuggestionEngine` filtre modules + anti-doublons
/// - `WeekdayMask` helpers
@MainActor
final class SmartReminderTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CustomReminder.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - WeekdayMask helpers

    func testWeekdayMask_all_hasAllDaysActive() {
        for i in 0...6 {
            XCTAssertTrue(WeekdayMask.isActive(WeekdayMask.all, weekdayIndex: i))
        }
    }

    func testWeekdayMask_weekdays_excludesWeekend() {
        for i in 0...4 { XCTAssertTrue(WeekdayMask.isActive(WeekdayMask.weekdays, weekdayIndex: i)) }
        XCTAssertFalse(WeekdayMask.isActive(WeekdayMask.weekdays, weekdayIndex: 5))
        XCTAssertFalse(WeekdayMask.isActive(WeekdayMask.weekdays, weekdayIndex: 6))
    }

    func testWeekdayMask_weekend_onlySaturdayAndSunday() {
        XCTAssertTrue(WeekdayMask.isActive(WeekdayMask.weekend, weekdayIndex: 5))
        XCTAssertTrue(WeekdayMask.isActive(WeekdayMask.weekend, weekdayIndex: 6))
        for i in 0...4 { XCTAssertFalse(WeekdayMask.isActive(WeekdayMask.weekend, weekdayIndex: i)) }
    }

    func testWeekdayMask_calendarConversion_isReversible() {
        for idx in 0...6 {
            let cal = WeekdayMask.calendarWeekdayFromIndex(idx)
            XCTAssertEqual(WeekdayMask.indexFromCalendarWeekday(cal), idx)
        }
    }

    // MARK: - CustomReminder extension

    func testFrequency_defaultIsDaily() {
        let r = CustomReminder()
        XCTAssertEqual(r.frequency, .daily)
    }

    func testSpecificHours_persistAsJSON() {
        let r = CustomReminder()
        r.specificHours = [9, 12, 15, 18]
        XCTAssertEqual(r.specificHours, [9, 12, 15, 18])
    }

    func testSpecificHours_invalidValuesFiltered() {
        let r = CustomReminder()
        r.specificHours = [9, 25, -1, 12]
        XCTAssertEqual(r.specificHours, [9, 12])
    }

    // MARK: - Scheduler.plannedIdentifiers

    func testPlannedIdentifiers_daily_returnsOnePerActiveDay() {
        let r = CustomReminder(title: "Test", hour: 9, minute: 30, weekdayMask: WeekdayMask.weekdays)
        r.frequencyRaw = "daily"
        let specs = SmartReminderScheduler.plannedIdentifiers(for: r)
        // 5 jours de semaine × 1 heure = 5
        XCTAssertEqual(specs.count, 5)
        for s in specs {
            XCTAssertEqual(s.hour, 9)
            XCTAssertEqual(s.minute, 30)
        }
    }

    func testPlannedIdentifiers_everyXHours_generatesWindowHours() {
        let r = CustomReminder(title: "Water",
                               weekdayMask: WeekdayMask.all,
                               specificHoursJSON: "[]")
        r.frequencyRaw = "everyXHours"
        r.intervalHours = 2
        r.windowStartHour = 8
        r.windowEndHour = 20
        let specs = SmartReminderScheduler.plannedIdentifiers(for: r)
        // 8/10/12/14/16/18/20 = 7 heures × 7 jours = 49
        XCTAssertEqual(specs.count, 49)
    }

    func testPlannedIdentifiers_multipleTimes_respectsSpecificHours() {
        let r = CustomReminder(title: "Meals", weekdayMask: WeekdayMask.weekdays)
        r.frequencyRaw = "multipleTimes"
        r.specificHours = [8, 12, 19]
        let specs = SmartReminderScheduler.plannedIdentifiers(for: r)
        // 3 heures × 5 jours de semaine = 15
        XCTAssertEqual(specs.count, 15)
    }

    func testPlannedIdentifiers_noActiveDays_returnsEmpty() {
        let r = CustomReminder(title: "X", weekdayMask: 0)
        XCTAssertTrue(SmartReminderScheduler.plannedIdentifiers(for: r).isEmpty)
    }

    // MARK: - Suggestion engine

    func testSuggestions_universalAlwaysPresent() {
        UserDefaults.standard.removeObject(forKey: "recommendedModules")
        let sugs = SmartReminderSuggestionEngine.suggestions(existingReminders: [])
        // Au moins la suggestion universelle "Marche 5 min"
        XCTAssertTrue(sugs.contains { $0.id.contains("universal") })
    }

    func testSuggestions_perModule_appearsWhenActive() {
        UserDefaults.standard.set("fitness,mind", forKey: "recommendedModules")
        defer { UserDefaults.standard.removeObject(forKey: "recommendedModules") }
        let sugs = SmartReminderSuggestionEngine.suggestions(existingReminders: [])
        XCTAssertTrue(sugs.contains { $0.categoryRaw == "fitness" })
        XCTAssertTrue(sugs.contains { $0.categoryRaw == "mind" })
    }

    func testSuggestions_dedupAgainstExisting() {
        UserDefaults.standard.set("nutrition", forKey: "recommendedModules")
        defer { UserDefaults.standard.removeObject(forKey: "recommendedModules") }
        let existing = CustomReminder(title: "Bois de l'eau")
        let sugs = SmartReminderSuggestionEngine.suggestions(existingReminders: [existing])
        XCTAssertFalse(sugs.contains { $0.title == "Bois de l'eau" })
    }

    func testSuggestions_capsAtMaxCount() {
        UserDefaults.standard.set("fitness,mind,productivity,sleep,nutrition,looks", forKey: "recommendedModules")
        defer { UserDefaults.standard.removeObject(forKey: "recommendedModules") }
        let sugs = SmartReminderSuggestionEngine.suggestions(existingReminders: [], maxCount: 3)
        XCTAssertLessThanOrEqual(sugs.count, 3)
    }
}
