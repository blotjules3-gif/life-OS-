import XCTest
import SwiftData
@testable import LifeOS

/// Defauts du lot 7 (voyage, reveil, coach, score du jour). Chaque test echoue sur
/// l'ancien comportement.

// MARK: - Reveil

final class AuditFixesAlarmScheduleTests: XCTestCase {

    /// Avant: heure + minute en repetition quotidienne, les jours etaient ignores.
    func testOnlyChosenDaysAreScheduled() {
        let slots = NotificationManager.alarmSlots(hour: 7, minute: 0, mondayBasedDays: [1, 3])
        XCTAssertEqual(slots.map(\.id), ["lifeos.wakeup.day1", "lifeos.wakeup.day3"])
        // Lundi = weekday 2, mercredi = 4 (Calendar: 1 = dimanche)
        XCTAssertEqual(slots.map(\.alarm.weekday), [2, 4])
        XCTAssertTrue(slots.allSatisfy { $0.alarm.hour == 7 && $0.alarm.minute == 0 })
    }

    func testEveryDayKeepsTheSingleDailyIdentifier() {
        let slots = NotificationManager.alarmSlots(hour: 6, minute: 30, mondayBasedDays: Set(1...7))
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.id, "lifeos.wakeup")
        XCTAssertNil(slots.first?.alarm.weekday)
        XCTAssertEqual(slots.first?.preview.hour, 6)
        XCTAssertEqual(slots.first?.preview.minute, 25)
    }

    func testNoDayMeansNoAlarm() {
        XCTAssertTrue(NotificationManager.alarmSlots(hour: 7, minute: 0, mondayBasedDays: []).isEmpty)
    }

    /// Lundi 00:02: le preavis tombe dimanche 23:57.
    func testPreviewCrossingMidnightFallsTheDayBefore() {
        let slot = NotificationManager.alarmSlots(hour: 0, minute: 2, mondayBasedDays: [1]).first
        XCTAssertEqual(slot?.preview.weekday, 1)
        XCTAssertEqual(slot?.preview.hour, 23)
        XCTAssertEqual(slot?.preview.minute, 57)
        // Dimanche 00:02 -> samedi
        let sunday = NotificationManager.alarmSlots(hour: 0, minute: 2, mondayBasedDays: [7]).first
        XCTAssertEqual(sunday?.alarm.weekday, 1)
        XCTAssertEqual(sunday?.preview.weekday, 7)
    }

    /// Couper le reveil doit aussi couper le preavis "Reveil dans 5 minutes".
    func testCancelCoversThePreview() {
        let ids = NotificationManager.allAlarmIDs
        XCTAssertTrue(ids.contains("lifeos.wakeup"))
        XCTAssertTrue(ids.contains("lifeos.wakeup.preview"))
        XCTAssertTrue(ids.contains("lifeos.wakeup.day3"))
        XCTAssertTrue(ids.contains("lifeos.wakeup.preview.day7"))
    }

    func testStoredDaysDefaultToEveryDay() throws {
        let suite = "AuditFixesAlarmScheduleTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { ud.removePersistentDomain(forName: suite) }
        XCTAssertEqual(NotificationManager.storedWakeupDays(ud), Set(1...7))
        ud.set("1,5", forKey: AppStorageKeys.wakeupRepeatDays)
        XCTAssertEqual(NotificationManager.storedWakeupDays(ud), [1, 5])
    }
}

@MainActor
final class AuditFixesAlarmRingTests: XCTestCase {

    /// Avant: 10 s puis controle du reveil comme si la personne etait levee.
    func testRingingLastsLongAndEndsInSnoozeNotSleepCheck() {
        XCTAssertGreaterThanOrEqual(AlarmManager.ringDurationSeconds, 300)
        XCTAssertEqual(AlarmManager.tick(secondsLeft: 10), .keepRinging(secondsLeft: 9))
        XCTAssertEqual(AlarmManager.tick(secondsLeft: 1), .autoSnooze)
    }

    func testTriggerStartsWithTheFullDuration() {
        let alarm = AlarmManager.shared
        alarm.triggerAlarm()
        XCTAssertEqual(alarm.secondsLeft, AlarmManager.ringDurationSeconds)
        alarm.stopRinging()
    }

    func testSnoozeMinutesComeFromSettings() throws {
        let suite = "AuditFixesAlarmRingTests.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { ud.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AlarmManager.storedSnoozeMinutes(ud), 9)
        ud.set(15, forKey: AppStorageKeys.snoozeMinutes)
        XCTAssertEqual(AlarmManager.storedSnoozeMinutes(ud), 15)
    }
}

// MARK: - Flighto

final class AuditFixesFlightTrackerTests: XCTestCase {

    /// Avant: tout vol ajoute etait "A l'heure" sans aucune source.
    func testNewFlightStatusIsUnknown() {
        XCTAssertEqual(TrackedFlight().status, TrackedFlight.unknownStatus)
        XCTAssertNotEqual(TrackedFlight().status, "À l'heure")
        XCTAssertEqual(TrackedFlight.statuses.first, TrackedFlight.unknownStatus)
    }

    /// JFK 18:00 saisi depuis Paris: l'instant doit etre 18:00 a New York, pas a Paris.
    func testChangingZoneKeepsTheTicketTime() throws {
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let ny = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = paris
        let typed = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 18, minute: 0)))
        let fixed = TrackedFlight.keepingWallClock(typed, from: paris, to: ny)
        XCTAssertEqual(fixed.timeIntervalSince(typed), 6 * 3600, accuracy: 1)
        var nyCal = Calendar(identifier: .gregorian); nyCal.timeZone = ny
        XCTAssertEqual(nyCal.component(.hour, from: fixed), 18)
    }

    /// Les vols deja enregistres (sans fuseau) se relisent toujours.
    func testOldSavedFlightsStillDecode() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","number":"AF8","airline":"Air France","from":"CDG","to":"JFK","departure":0,"status":"À l'heure"}]"#
        let flights = try JSONDecoder().decode([TrackedFlight].self, from: Data(json.utf8))
        XCTAssertEqual(flights.count, 1)
        XCTAssertNil(flights.first?.departureTimeZoneID)
        XCTAssertEqual(flights.first?.departureTimeZone, .current)
    }
}

// MARK: - Envol

@MainActor
final class AuditFixesEnvolCardTests: XCTestCase {
    private let cdg = FlightSearch.Place(iata: "CDG", name: nil, timeZone: nil)
    private let jfk = FlightSearch.Place(iata: "JFK", name: nil, timeZone: nil)

    /// Avant: group.offers[0] plantait sur un groupe sans offre.
    func testGroupWithoutOfferHasNoSliceInsteadOfCrashing() {
        let group = FlightSearch.Group(key: "k", sources: [], analysis: .init(slices: [], totalMinutes: nil, warnings: []),
                                       offers: [], explanation: nil)
        XCTAssertTrue(FlightGroupCard.displaySlices(group).isEmpty)
    }

    /// Avant: segments.first! plantait sur un trajet sans segment.
    func testSliceWithoutSegmentSaysUnknown() {
        let slice = FlightSearch.Slice(origin: cdg, destination: jfk, durationMinutes: nil, segments: [])
        XCTAssertEqual(FlightGroupCard.timesLabel(slice), "Horaires inconnus")
        XCTAssertEqual(FlightGroupCard.carrierLabel(slice), "Compagnie inconnue")
    }

    func testSliceWithSegmentsShowsItsTimes() {
        let seg = FlightSearch.Segment(origin: cdg, destination: jfk,
                                       departingAt: "2026-11-02T10:15:00", arrivingAt: "2026-11-02T12:40:00",
                                       marketingCarrier: .init(code: "AF", name: nil), operatingCarrier: .init(code: "AF", name: nil),
                                       flightNumber: "8", cabin: nil, fareBrand: nil)
        let slice = FlightSearch.Slice(origin: cdg, destination: jfk, durationMinutes: 505, segments: [seg])
        XCTAssertEqual(FlightGroupCard.timesLabel(slice), "10:15 → 12:40")
        XCTAssertEqual(FlightGroupCard.carrierLabel(slice), "AF")
    }
}

// MARK: - Traduction

final class AuditFixesTranslatorTests: XCTestCase {

    func testSameLanguageIsBlockedBeforeTheCall() {
        XCTAssertNotNil(TranslatorRules.blockReason(input: "Bonjour", source: "fr", target: "fr"))
        XCTAssertNotNil(TranslatorRules.blockReason(input: "  \n", source: "fr", target: "en"))
        XCTAssertNil(TranslatorRules.blockReason(input: "Bonjour", source: "fr", target: "en"))
    }

    /// Meme paire: il faut invalider la configuration, sinon rien ne se relance.
    func testSamePairNeedsInvalidate() {
        XCTAssertTrue(TranslatorRules.mustInvalidate(previous: ("fr", "en"), source: "fr", target: "en"))
        XCTAssertFalse(TranslatorRules.mustInvalidate(previous: ("fr", "en"), source: "en", target: "fr"))
        XCTAssertFalse(TranslatorRules.mustInvalidate(previous: nil, source: "fr", target: "en"))
    }
}

// MARK: - Ton coach

@MainActor
final class AuditFixesCoachRoutingTests: XCTestCase {

    /// Avant: sans Apple Intelligence, une cle cloud valide etait ignoree.
    func testCloudProviderAloneIsEnoughToRoute() {
        XCTAssertTrue(OnDeviceLLM.shouldUseRouter(availabilities: [
            .unavailable(reason: .deviceNotEligible),   // Apple Intelligence
            .available                                   // fournisseur cloud avec cle
        ]))
        XCTAssertFalse(OnDeviceLLM.shouldUseRouter(availabilities: [
            .unavailable(reason: .deviceNotEligible),
            .unavailable(reason: .invalidCredentials)
        ]))
    }
}

// MARK: - Score du jour et bilan

@MainActor
final class AuditFixesDailyScoreTests: XCTestCase {
    private var container: ModelContainer!   // un ModelContext ne garde pas son container
    private var ctx: ModelContext!

    override func setUp() async throws {
        let schema = Schema([Habit.self, HabitCompletion.self, MoodEntry.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        ctx = ModelContext(container)
    }
    override func tearDown() async throws { ctx = nil; container = nil }

    private func metrics(habits: [Habit] = [], moods: [MoodEntry] = []) -> [DayMetric] {
        DailyScoreEngine.metrics(for: .now, foods: [], waters: [], habits: habits, steps: [], todos: [],
                                 workouts: [], moods: moods, dreams: [], kcalGoal: 0, proteinGoal: 0,
                                 waterGoal: 0, stepGoal: 10_000)
    }

    /// Avant: archivees et habitudes hors de leurs jours comptaient au denominateur.
    func testOnlyHabitsPlannedTodayCount() throws {
        let today = Calendar.current.component(.weekday, from: .now)
        let other = today % 7 + 1
        let done = Habit(name: "Lire")
        let rest = Habit(name: "Course", activeDaysRaw: "\(other)")
        let archived = Habit(name: "Vieux", isArchived: true)
        let pending = Habit(name: "Propose", isPending: true)
        [done, rest, archived, pending].forEach { ctx.insert($0) }
        let c = HabitCompletion(date: .now); ctx.insert(c); done.completions.append(c)
        try ctx.save()

        let habitsMetric = metrics(habits: [done, rest, archived, pending]).first { $0.label == "Habitudes" }
        XCTAssertEqual(habitsMetric?.value, "1/1")
        XCTAssertEqual(habitsMetric?.fraction ?? 0, 1, accuracy: 0.0001)
    }

    /// Jour de repos: aucune habitude prevue, pas de ligne "Habitudes" a 0 %.
    func testRestDayHasNoHabitLine() throws {
        let today = Calendar.current.component(.weekday, from: .now)
        let rest = Habit(name: "Course", activeDaysRaw: "\(today % 7 + 1)")
        ctx.insert(rest); try ctx.save()
        XCTAssertNil(metrics(habits: [rest]).first { $0.label == "Habitudes" })
    }

    /// Avant: first(where:) sur une liste non triee prenait n'importe quelle humeur.
    func testLatestMoodOfTheDayIsUsed() throws {
        let start = Calendar.current.startOfDay(for: .now)
        let older = MoodEntry(date: start.addingTimeInterval(60), score: 1)
        let newer = MoodEntry(date: start.addingTimeInterval(120), score: 5)
        ctx.insert(older); ctx.insert(newer); try ctx.save()
        let mood = metrics(moods: [older, newer]).first { $0.label == "Humeur" }
        XCTAssertEqual(mood?.value, "5/5")
    }
}

@MainActor
final class AuditFixesWeeklyBilanTests: XCTestCase {

    /// Avant: toujours divise par 7, un jour de repos comptait comme 0 %.
    func testRestDaysDoNotLowerTheWeek() {
        XCTAssertNil(WeeklyBilanMath.dayRatio(planned: 0, done: 0))
        XCTAssertEqual(WeeklyBilanMath.dayRatio(planned: 2, done: 1) ?? -1, 0.5, accuracy: 0.0001)
        let score = WeeklyBilanMath.weekScore([1, nil, 0.5, nil, nil, nil, nil])
        XCTAssertEqual(score, 0.75, accuracy: 0.0001)
        XCTAssertEqual(WeeklyBilanMath.weekScore([nil, nil]), 0)
    }

    /// Les regles locales ne font pas d'"Analyse du coach".
    func testLocalRulesReplyIsNotACoachAnalysis() {
        XCTAssertFalse(WeeklyBilanMath.isCoachAnalysis(.localRules))
        XCTAssertTrue(WeeklyBilanMath.isCoachAnalysis(.onDeviceLLM))
    }
}
