import XCTest
import SwiftData
@testable import LifeOS

/// Lot 6, Sport : Hevvy (exercices perso, mensurations, export), GOMOB (reprise,
/// routines perso, historique), TabaTime (préréglages, historique), Streakz
/// (objectif hebdo, meilleure série, calendrier, rappel), Stepometer (stats, record,
/// notification d'objectif une fois par jour).
@MainActor
final class Lot6FitnessTests: XCTestCase {

    private var cal: Calendar {
        var c = StreakEngine.frenchCalendar
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: Hevvy : exercices perso

    func testCustomExerciseNameValidation() {
        XCTAssertNotNil(ExerciseLibrary.validate(name: "  ", existing: []))
        XCTAssertNotNil(ExerciseLibrary.validate(name: "developpe larsen", existing: ["Développé Larsen"]),
                        "doublon à la casse et aux accents près")
        XCTAssertNil(ExerciseLibrary.validate(name: "Développé Larsen", existing: ["Développé Larsen"], original: "développé larsen"),
                     "garder son propre nom en modifiant n'est pas un doublon")
        XCTAssertNil(ExerciseLibrary.validate(name: "Hip thrust unilatéral", existing: ["Hip thrust"]))
    }

    func testSuggestionsMergeCustomAndLoggedWithoutDuplicates() {
        let s = ExerciseLibrary.suggestions(custom: ["Curl araignée", "squat barre"], logged: ["Squat barre", "Dips"])
        XCTAssertEqual(s, ["Curl araignée", "Dips", "squat barre"])
    }

    func testGroupPrefersCustomExerciseThenCatalog() {
        let custom = [(name: "Dips", group: "Pecs")]
        XCTAssertEqual(ExerciseLibrary.group(of: "dips", custom: custom), "Pecs")
        XCTAssertEqual(ExerciseLibrary.group(of: "Dips", custom: []), "Triceps")
        XCTAssertNil(ExerciseLibrary.group(of: "Inconnu", custom: []))
        XCTAssertEqual(ExerciseLibrary.muscleGroups.last, "Autre")
    }

    func testRenamingCustomExerciseRenamesItsLoggedSets() {
        let a = WorkoutSet(exercise: "Curl araigne", weightKg: 10, reps: 10)
        let b = WorkoutSet(exercise: "Squat barre", weightKg: 100, reps: 5)
        let n = ExerciseRename.apply(from: "Curl araigne", to: "Curl araignée", sets: [a, b])
        XCTAssertEqual(n, 1)
        XCTAssertEqual(a.exercise, "Curl araignée")
        XCTAssertEqual(b.exercise, "Squat barre")
    }

    // MARK: Hevvy : mensurations

    func testUnitConversionsRoundTripAndRefuseMismatch() throws {
        let lb = try XCTUnwrap(FitnessUnits.convert(80, from: .kg, to: .lb))
        XCTAssertEqual(lb, 176.37, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(FitnessUnits.convert(lb, from: .lb, to: .kg)), 80, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(FitnessUnits.convert(10, from: .inch, to: .cm)), 25.4, accuracy: 1e-9)
        XCTAssertNil(FitnessUnits.convert(80, from: .kg, to: .cm))
    }

    func testMeasurementSeriesConvertsMixedUnitsAndSortsByDate() throws {
        let entries = [
            BodyMeasurement(date: day(2026, 9, 10), kind: .waist, value: 32, unit: .inch),
            BodyMeasurement(date: day(2026, 9, 1), kind: .waist, value: 84, unit: .cm),
            BodyMeasurement(date: day(2026, 9, 5), kind: .weight, value: 80, unit: .kg),
            // Ligne incohérente (taille en kg) : ignorée, jamais "convertie".
            BodyMeasurement(date: day(2026, 9, 6), kind: .waist, value: 80, unit: .kg)
        ]
        let s = BodyMeasureLogic.series(entries, kind: .waist, in: .cm)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].value, 84, accuracy: 1e-9)
        XCTAssertEqual(s[1].value, 81.28, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(BodyMeasureLogic.change(s)), -2.72, accuracy: 1e-9)
        XCTAssertNil(BodyMeasureLogic.change(Array(s.prefix(1))))
    }

    func testMeasurementParsingAcceptsFrenchDecimalAndRejectsNonsense() {
        XCTAssertEqual(BodyMeasureLogic.parse("72,5", kind: .weight), 72.5)
        XCTAssertNil(BodyMeasureLogic.parse("0", kind: .weight))
        XCTAssertNil(BodyMeasureLogic.parse("abc", kind: .waist))
        XCTAssertNil(BodyMeasureLogic.parse("120", kind: .bodyFat))
    }

    func testMeasurementsPersistInStore() throws {
        let container = try ModelContainer(for: BodyMeasurement.self, CustomExercise.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        ctx.insert(BodyMeasurement(date: day(2026, 9, 1), kind: .arms, value: 38.5, unit: .cm))
        ctx.insert(CustomExercise(name: "Curl araignée", muscleGroup: "Biceps", equipment: .dumbbell))
        try ctx.save()
        let m = try ctx.fetch(FetchDescriptor<BodyMeasurement>())
        XCTAssertEqual(m.first?.kind, "arms"); XCTAssertEqual(m.first?.unit, "cm")
        let c = try ctx.fetch(FetchDescriptor<CustomExercise>())
        XCTAssertEqual(c.first?.equipment, ExerciseEquipment.dumbbell.rawValue)
    }

    // MARK: Hevvy : export CSV

    func testCSVExportEscapesAndOrdersRows() {
        let s1 = WorkoutSet(date: day(2026, 9, 2, 9), exercise: "Curl \"marteau\", haltères", weightKg: 12.5, reps: 10, rpe: 8)
        let s2 = WorkoutSet(date: day(2026, 9, 1, 9), exercise: "Squat barre", weightKg: 100, reps: 5, rpe: 9, kind: "warmup")
        let csv = SetsCSV.make([s1, s2], timeZone: TimeZone(identifier: "UTC")!)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], SetsCSV.header)
        XCTAssertEqual(lines[1], "2026-09-01 09:00,Squat barre,warmup,100,5,9,500,")
        XCTAssertEqual(lines[2], "2026-09-02 09:00,\"Curl \"\"marteau\"\", haltères\",work,12.50,10,8,125,")
        XCTAssertEqual(lines.count, 3)
    }

    // MARK: GOMOB

    func testMobilityRoutineValidationAndReorder() {
        let a = MobilityStepSpec(name: "A", seconds: 30), b = MobilityStepSpec(name: "B", seconds: 45), c = MobilityStepSpec(name: "C", seconds: 60)
        XCTAssertNotNil(MobilityRoutineRules.validate(name: "", steps: [a]))
        XCTAssertNotNil(MobilityRoutineRules.validate(name: "Soir", steps: []))
        XCTAssertNotNil(MobilityRoutineRules.validate(name: "Soir", steps: [MobilityStepSpec(name: " ", seconds: 30)]))
        XCTAssertNotNil(MobilityRoutineRules.validate(name: "Soir", steps: [MobilityStepSpec(name: "A", seconds: 2)]))
        XCTAssertNil(MobilityRoutineRules.validate(name: "Soir", steps: [a, b]))
        XCTAssertEqual(MobilityRoutineRules.totalSeconds([a, b, c]), 135)
        XCTAssertEqual(MobilityRoutineRules.moved([a, b, c], from: IndexSet(integer: 0), to: 3).map(\.name), ["B", "C", "A"])
        XCTAssertEqual(MobilityRoutineRules.moved([a, b, c], from: IndexSet(integer: 2), to: 0).map(\.name), ["C", "A", "B"])
    }

    func testMobilityRoutineStepsKeepOrderInStore() throws {
        let container = try ModelContainer(for: MobilityRoutine.self, MobilitySession.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let r = MobilityRoutine(name: "Soir", steps: [MobilityStepSpec(name: "Hanches", seconds: 60), MobilityStepSpec(name: "Dos", seconds: 30)])
        ctx.insert(r); try ctx.save()
        let fetched = try XCTUnwrap(ctx.fetch(FetchDescriptor<MobilityRoutine>()).first)
        XCTAssertEqual(fetched.steps.map(\.name), ["Hanches", "Dos"])
        fetched.steps = [MobilityStepSpec(name: "Dos", seconds: 30)]
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MobilityRoutine>()).first?.steps.count, 1)
    }

    /// Avant : l'index de l'exercice vivait en @State, un relancement repartait
    /// du premier exercice. Maintenant la reprise retombe sur le bon.
    func testMobilityResumePointAfterRelaunch() {
        let run = UUID()
        let p = MobilityProgress(routineID: "builtin-reveil", runID: run, index: 2, startedAt: .now)
        XCTAssertEqual(MobilityResume.resolve(saved: p, routineID: "builtin-reveil", stepCount: 4, engineRunning: true, engineRemaining: 20), .running(2))
        XCTAssertEqual(MobilityResume.resolve(saved: p, routineID: "builtin-reveil", stepCount: 4, engineRunning: false, engineRemaining: 12), .paused(2))
        XCTAssertEqual(MobilityResume.resolve(saved: p, routineID: "builtin-reveil", stepCount: 4, engineRunning: false, engineRemaining: 0), .expiredThenReady(3))
        var last = p; last.index = 3
        XCTAssertEqual(MobilityResume.resolve(saved: last, routineID: "builtin-reveil", stepCount: 4, engineRunning: false, engineRemaining: 0), .finished)
        var waiting = p; waiting.waiting = true
        XCTAssertEqual(MobilityResume.resolve(saved: waiting, routineID: "builtin-reveil", stepCount: 4, engineRunning: false, engineRemaining: 0), .ready(2),
                       "un exercice en attente ne doit pas être sauté une seconde fois")
        XCTAssertEqual(MobilityResume.resolve(saved: p, routineID: "builtin-assise", stepCount: 4, engineRunning: true, engineRemaining: 20), .none)
        XCTAssertEqual(MobilityResume.resolve(saved: p, routineID: "builtin-reveil", stepCount: 2, engineRunning: true, engineRemaining: 20), .none,
                       "routine raccourcie : pas de reprise hors limites")
    }

    func testMobilityProgressPersistsAcrossRelaunch() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "lot6.mobility.\(UUID().uuidString)"))
        var p = MobilityProgress(routineID: "custom-x", runID: UUID(), index: 1, startedAt: Date(timeIntervalSince1970: 1_000))
        p.doneSeconds = 45; p.doneCount = 1
        MobilityResume.save(p, d)
        XCTAssertEqual(MobilityResume.load(d), p)
        MobilityResume.clear(d)
        XCTAssertNil(MobilityResume.load(d))
    }

    func testSessionsAreRecordedOncePerRun() {
        let id = UUID()
        XCTAssertTrue(FitnessHistory.shouldRecord(id, existing: []))
        XCTAssertFalse(FitnessHistory.shouldRecord(id, existing: [UUID(), id]))
    }

    // MARK: TabaTime

    func testTabataLogNeedsRealEffortAndNamesFreeIntervals() throws {
        XCTAssertNil(FitnessHistory.tabataLog(sessionID: UUID(), finishedAt: .now, name: "Cardio", completedRounds: 0,
                                              totalRounds: 8, activeSeconds: 40, workSeconds: 0), "tout sauté n'est pas une séance")
        let log = try XCTUnwrap(FitnessHistory.tabataLog(sessionID: UUID(), finishedAt: day(2026, 9, 3), name: nil, completedRounds: 6,
                                                         totalRounds: 8, activeSeconds: 300, workSeconds: 180))
        XCTAssertEqual(log.name, "Intervalles libres")
        XCTAssertEqual(log.completedRounds, 6)
    }

    func testTabataPresetRulesAndRoundTrip() throws {
        XCTAssertNotNil(TabataPresetRules.validate(name: "", existing: []))
        XCTAssertNotNil(TabataPresetRules.validate(name: "matin", existing: ["Matin"]))
        XCTAssertNil(TabataPresetRules.validate(name: "Matin", existing: ["Matin"], original: "Matin"))
        let c = TabataConfig(prepare: 10, work: 20, rest: 10, rounds: 8, cycles: 2, restCycle: 60, cooldown: 30)
        // Même formule que l'écran de réglages : 10 + (160 + 70) × 2 + 60 + 30.
        XCTAssertEqual(TabataPresetRules.totalSeconds(c), 560)
        let s = TabataPresetRules.sanitized(TabataConfig(prepare: -5, work: 0, rest: 5, rounds: 0, cycles: 0, restCycle: 0, cooldown: 0))
        XCTAssertEqual(s.work, 5); XCTAssertEqual(s.rounds, 1); XCTAssertEqual(s.cycles, 1); XCTAssertEqual(s.prepare, 0)

        let container = try ModelContainer(for: TabataPreset.self, TabataSessionLog.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        ctx.insert(TabataPreset(name: "Matin", config: c)); try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<TabataPreset>()).first?.config, c)
    }

    // MARK: Streakz

    /// Avant : seules les séries muscu comptaient. Un jour de Tabata ou de
    /// mobilité seule ne rendait pas la journée active.
    func testTabataAndMobilityDaysCountAsActive() {
        let act = StreakEngine.activity(strength: [day(2026, 9, 28)], tabata: [day(2026, 9, 29)], mobility: [day(2026, 9, 30), day(2026, 9, 28, 20)], calendar: cal)
        XCTAssertEqual(Set(act.keys).count, 3)
        XCTAssertEqual(act[cal.startOfDay(for: day(2026, 9, 28))]?.types, 2)
        XCTAssertEqual(StreakEngine.dayStreak(Set(act.keys), today: day(2026, 9, 30), calendar: cal), 3)
    }

    func testWeeklyTargetKeepsStreakOverRestDays() {
        // Semaines du lundi 7, 14, 21 sept : 3 jours actifs chacune, repos entre.
        let dates = [day(2026, 9, 7), day(2026, 9, 9), day(2026, 9, 11),
                     day(2026, 9, 14), day(2026, 9, 16), day(2026, 9, 18),
                     day(2026, 9, 21), day(2026, 9, 23), day(2026, 9, 25)]
        let active = Set(dates.map { cal.startOfDay(for: $0) })
        // Mardi 29 sept : la semaine en cours (1 jour) n'est pas encore tenue, elle ne casse rien.
        let tuesday = day(2026, 9, 29)
        let withMonday = active.union([cal.startOfDay(for: day(2026, 9, 28))])
        XCTAssertEqual(StreakEngine.weeklyStreak(withMonday, target: 3, today: tuesday, calendar: cal), 3)
        XCTAssertEqual(StreakEngine.dayStreak(withMonday, today: tuesday, calendar: cal), 1,
                       "en jours la série tombe à chaque repos : c'est l'objectif hebdo qui les autorise")
        XCTAssertEqual(StreakEngine.weeklyStreak(active, target: 4, today: tuesday, calendar: cal), 0)
        // Semaine en cours atteinte : elle compte.
        let full = withMonday.union([cal.startOfDay(for: day(2026, 9, 29)), cal.startOfDay(for: day(2026, 9, 30))])
        XCTAssertEqual(StreakEngine.weeklyStreak(full, target: 3, today: day(2026, 9, 30), calendar: cal), 4)
        // Une semaine ratée au milieu coupe la série.
        let gap = active.subtracting([cal.startOfDay(for: day(2026, 9, 16))])
        XCTAssertEqual(StreakEngine.weeklyStreak(gap, target: 3, today: tuesday, calendar: cal), 1)
        XCTAssertEqual(StreakEngine.bestWeeklyStreak(active, target: 3, calendar: cal), 3)
        XCTAssertEqual(StreakEngine.bestWeeklyStreak(gap, target: 3, calendar: cal), 1)
    }

    func testBestDayStreak() {
        let active = Set([1, 2, 3, 5, 6].map { cal.startOfDay(for: day(2026, 9, $0)) })
        XCTAssertEqual(StreakEngine.bestDayStreak(active, calendar: cal), 3)
        XCTAssertEqual(StreakEngine.bestDayStreak([], calendar: cal), 0)
    }

    func testHeatmapShapeMondayFirstAndFutureFlag() {
        let today = day(2026, 10, 1) // jeudi
        let act = StreakEngine.activity(strength: [today], tabata: [today], mobility: [], calendar: cal)
        let grid = StreakEngine.heatmap(act, weeks: 4, today: today, calendar: cal)
        XCTAssertEqual(grid.count, 4)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        XCTAssertEqual(cal.component(.weekday, from: grid[0][0].date), 2, "lundi en haut")
        let last = grid[3]
        XCTAssertEqual(last[3].date, cal.startOfDay(for: today))
        XCTAssertEqual(last[3].types, 2)
        XCTAssertFalse(last[3].isFuture)
        XCTAssertTrue(last[4].isFuture)
    }

    func testReminderComponents() {
        XCTAssertEqual(StreakReminder.components(minutes: 18 * 60 + 30), DateComponents(hour: 18, minute: 30))
        XCTAssertEqual(StreakReminder.components(minutes: 1440 + 5), DateComponents(hour: 0, minute: 5))
    }

    // MARK: Stepometer

    func testStepSummaryAndBestDay() throws {
        let days: [(day: Date, steps: Int)] = [(day(2026, 9, 1), 4000), (day(2026, 9, 2), 12000), (day(2026, 9, 3), 0), (day(2026, 9, 4), 10000)]
        let s = StepStats.summary(days, goal: 10000)
        XCTAssertEqual(s.average, 6500)
        XCTAssertEqual(s.goalHits, 2)
        XCTAssertEqual(s.days, 4)
        XCTAssertEqual(s.best, StepStats.BestDay(day: day(2026, 9, 2), steps: 12000))
        XCTAssertNil(StepStats.summary([], goal: 10000).best)
    }

    func testStepRecordKeepsHighestEverSeen() {
        let old = StepStats.BestDay(day: day(2026, 1, 1), steps: 20000)
        XCTAssertEqual(StepStats.record(current: old, seen: [(day(2026, 9, 1), 15000)]), old,
                       "un record hors de la fenêtre lue n'est pas perdu")
        XCTAssertEqual(StepStats.record(current: old, seen: [(day(2026, 9, 1), 21000)])?.steps, 21000)
        XCTAssertNil(StepStats.record(current: nil, seen: [(day(2026, 9, 1), 0)]))
    }

    func testGoalNotificationOncePerDay() {
        let now = day(2026, 10, 1)
        let key = StepStats.dayKey(now, calendar: cal)
        XCTAssertEqual(key, "2026-10-01")
        XCTAssertTrue(StepStats.shouldNotifyGoal(steps: 10500, goal: 10000, lastNotifiedDay: "2026-09-30", now: now, calendar: cal))
        XCTAssertFalse(StepStats.shouldNotifyGoal(steps: 10500, goal: 10000, lastNotifiedDay: key, now: now, calendar: cal))
        XCTAssertFalse(StepStats.shouldNotifyGoal(steps: 9999, goal: 10000, lastNotifiedDay: "", now: now, calendar: cal))
    }
}
