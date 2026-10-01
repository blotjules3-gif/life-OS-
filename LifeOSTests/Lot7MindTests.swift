import XCTest
import SwiftData
import UserNotifications
@testable import LifeOS

/// Lot 7, outils Mental: Breathwerk, Headplace, Endlo, Daylia, Fabuleux.
/// On teste la logique pure extraite des ecrans et les ecritures SwiftData
/// dans un magasin en memoire.
@MainActor
final class Lot7MindTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Breathwerk

    func testLibraryDescribesTheFourKnownTechniquesByTheirRhythm() {
        XCTAssertEqual(BreathTechnique.coherence.phases.map(\.seconds), [5, 5])
        XCTAssertEqual(BreathTechnique.box.phases.map(\.seconds), [4, 4, 4, 4])
        XCTAssertEqual(BreathTechnique.relax478.phases.map(\.seconds), [4, 7, 8])
        XCTAssertEqual(BreathTechnique.sigh.phases.map(\.kind), [.inhale, .topUp, .exhale])
        // Ancienne version: 3 cas en dur, pas de soupir physiologique.
        XCTAssertEqual(BreathLibrary.items(custom: []).count, 4)
    }

    func testPhaseEncodingRoundTripsAndIgnoresGarbage() {
        let phases: [BreathPhase] = [.init(kind: .inhale, seconds: 3), .init(kind: .holdEmpty, seconds: 2)]
        XCTAssertEqual(BreathPhase.decode(BreathPhase.encode(phases)), phases)
        XCTAssertEqual(BreathPhase.decode("inhale:4,bogus:3,exhale:x,exhale:0,exhale:6").map(\.seconds), [4, 6])
    }

    func testSearchIgnoresAccentsAndPutsFavoritesFirst() {
        let items = BreathLibrary.items(custom: [])
        XCTAssertEqual(BreathLibrary.filter(items, query: "COHERENCE", favorites: []).map(\.id), [BreathTechnique.coherence.id])
        XCTAssertEqual(BreathLibrary.filter(items, query: "carrée", favorites: []).map(\.id), [BreathTechnique.box.id])
        let favFirst = BreathLibrary.filter(items, query: "", favorites: [BreathTechnique.sigh.id])
        XCTAssertEqual(favFirst.first?.id, BreathTechnique.sigh.id)
        XCTAssertEqual(BreathLibrary.decodeFavorites(BreathLibrary.encodeFavorites(["a", "b"])), ["a", "b"])
    }

    func testPauseAndResumeNeverSkipAPhase() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var run = BreathRun(phases: BreathTechnique.relax478.phases, rounds: 2, minutes: 0)
        XCTAssertEqual(run.start(at: t0), [.phase(.init(kind: .inhale, seconds: 4), round: 0)])
        _ = run.tick(at: t0.addingTimeInterval(3))
        run.pause(at: t0.addingTimeInterval(3))
        XCTAssertTrue(run.isPaused)
        // Pause longue: au retour on est toujours dans l'inspiration, avec 1 s restante.
        run.resume(at: t0.addingTimeInterval(300))
        XCTAssertEqual(run.tick(at: t0.addingTimeInterval(300.5)), [])
        XCTAssertEqual(run.position(atElapsed: run.elapsed(at: t0.addingTimeInterval(300.5))).phaseRemaining, 0.5, accuracy: 0.01)
        XCTAssertEqual(run.tick(at: t0.addingTimeInterval(301.1)), [.phase(.init(kind: .holdFull, seconds: 7), round: 0)])
    }

    func testCompletionIsReportedExactlyOnce() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var run = BreathRun(phases: BreathTechnique.coherence.phases, rounds: 1, minutes: 0)
        _ = run.start(at: t0)
        XCTAssertEqual(run.tick(at: t0.addingTimeInterval(5.2)), [.phase(.init(kind: .exhale, seconds: 5), round: 0)])
        XCTAssertEqual(run.tick(at: t0.addingTimeInterval(10.1)), [.finished])
        XCTAssertEqual(run.tick(at: t0.addingTimeInterval(11)), [])
        XCTAssertEqual(run.tick(at: t0.addingTimeInterval(20)), [])
        XCTAssertTrue(run.finished)
        XCTAssertEqual(run.completedRounds(at: t0.addingTimeInterval(20)), 1)
    }

    func testFreeDurationEndsOnAWholeCycle() {
        // 4-7-8 = 19 s par cycle: 1 minute devient 4 cycles (76 s), jamais une expiration coupee.
        XCTAssertEqual(BreathRun(phases: BreathTechnique.relax478.phases, rounds: 0, minutes: 1).totalSeconds, 76)
        XCTAssertEqual(BreathRun(phases: BreathTechnique.box.phases, rounds: 3, minutes: 9).totalSeconds, 48)
    }

    func testAbandonedSessionIsNotLoggedButFinishedOneIs() {
        XCTAssertFalse(BreathingView.shouldLog(completed: false, activeSeconds: 8))
        XCTAssertTrue(BreathingView.shouldLog(completed: false, activeSeconds: 45))
        XCTAssertTrue(BreathingView.shouldLog(completed: true, activeSeconds: 10))
    }

    func testCustomPatternAndHistoryPersist() throws {
        let c = try ModelContainer(for: BreathPattern.self, BreathSessionLog.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let p = BreathPattern(name: "Expiration longue", phases: [.init(kind: .inhale, seconds: 4), .init(kind: .exhale, seconds: 8)], rounds: 6)
        ctx.insert(p)
        ctx.insert(BreathSessionLog(patternKey: p.key, patternName: p.name, activeSeconds: 72, rounds: 6, completed: true))
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<BreathPattern>())
        XCTAssertEqual(fetched.first?.phases.map(\.seconds), [4, 8])
        XCTAssertFalse(fetched.first?.uid.isEmpty ?? true)
        XCTAssertEqual(BreathLibrary.items(custom: fetched).last?.rounds, 6)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<BreathSessionLog>()).count, 1)
    }

    // MARK: Headplace

    func testIntervalBellsNeverDuplicateTheEndBell() {
        XCTAssertEqual(MeditationLogic.intervalOffsets(totalSeconds: 600, intervalMinutes: 5), [300])
        XCTAssertEqual(MeditationLogic.intervalOffsets(totalSeconds: 900, intervalMinutes: 5), [300, 600])
        XCTAssertEqual(MeditationLogic.intervalOffsets(totalSeconds: 600, intervalMinutes: 0), [])
    }

    func testRunFinishedWhileAppClosedIsDetectedOnce() {
        let now = Date(timeIntervalSince1970: 10_000)
        let run = MeditationLogic.StoredRun(title: "Assise", sourceKey: "preset.x", totalSeconds: 600,
                                            deadline: now.addingTimeInterval(-30), intervalMinutes: 0, endBell: true)
        XCTAssertTrue(MeditationLogic.isFinished(run, engineRunning: false, now: now))
        XCTAssertFalse(MeditationLogic.isFinished(run, engineRunning: true, now: now))
        XCTAssertFalse(MeditationLogic.isFinished(nil, engineRunning: false, now: now))
        var future = run; future.deadline = now.addingTimeInterval(60)
        XCTAssertFalse(MeditationLogic.isFinished(future, engineRunning: false, now: now))
    }

    func testLibrarySearchByTitleAndDurationWithFavoritesFirst() {
        let items: [MeditationLogic.LibraryItem] = [
            .init(id: "a", title: "Scan corporel", minutes: 20, isFavorite: false, isAudio: true),
            .init(id: "b", title: "Assise courte", minutes: 5, isFavorite: false, isAudio: false),
            .init(id: "c", title: "Assise longue", minutes: 30, isFavorite: true, isAudio: false)
        ]
        XCTAssertEqual(MeditationLogic.filter(items, query: "assise", maxMinutes: nil).map(\.id), ["c", "b"])
        XCTAssertEqual(MeditationLogic.filter(items, query: "", maxMinutes: 10).map(\.id), ["b"])
        XCTAssertEqual(MeditationLogic.filter(items, query: "CORPOREL", maxMinutes: 20).map(\.id), ["a"])
    }

    func testRecommendationComesOnlyFromOwnHistory() {
        let morning = date(2026, 10, 1, 7)
        let logs: [(sourceKey: String, date: Date)] = [
            ("preset.matin", date(2026, 9, 28, 7)), ("preset.matin", date(2026, 9, 29, 8)),
            ("audio.soir", date(2026, 9, 28, 22)), ("audio.soir", date(2026, 9, 29, 22)), ("audio.soir", date(2026, 9, 30, 22))
        ]
        let available: Set<String> = ["preset.matin", "audio.soir"]
        XCTAssertEqual(MeditationLogic.recommend(logs: logs, available: available, now: morning, calendar: cal), "preset.matin")
        XCTAssertEqual(MeditationLogic.recommend(logs: logs, available: available, now: date(2026, 10, 1, 23), calendar: cal), "audio.soir")
        XCTAssertNil(MeditationLogic.recommend(logs: [], available: available, now: morning, calendar: cal))
        // Une seance supprimee n'est plus recommandee.
        XCTAssertEqual(MeditationLogic.recommend(logs: logs, available: ["audio.soir"], now: morning, calendar: cal), "audio.soir")
    }

    func testStreakEndsTodayOrYesterday() {
        let now = date(2026, 10, 1, 20)
        let days = [date(2026, 9, 29), date(2026, 9, 30), date(2026, 10, 1), date(2026, 10, 1, 21)]
        XCTAssertEqual(MindStats.streak(dates: days, now: now, calendar: cal), 3)
        XCTAssertEqual(MindStats.streak(dates: [date(2026, 9, 29), date(2026, 9, 30)], now: now, calendar: cal), 2)
        XCTAssertEqual(MindStats.streak(dates: [date(2026, 9, 28)], now: now, calendar: cal), 0)
    }

    func testMeditationPresetsAudioAndLogsPersist() throws {
        let c = try ModelContainer(for: MeditationTimerPreset.self, MeditationAudio.self, MeditationLog.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let p = MeditationTimerPreset(name: "Assise", minutes: 20, intervalMinutes: 5)
        let a = MeditationAudio(title: "Mon enregistrement", fileName: "x.m4a", durationSeconds: 600)
        a.resumePosition = 125
        ctx.insert(p); ctx.insert(a)
        ctx.insert(MeditationLog(kind: "minuteur", title: p.name, seconds: 1200, completed: true, sourceKey: "preset.\(p.uid)"))
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MeditationAudio>()).first?.resumePosition, 125)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MeditationTimerPreset>()).first?.intervalMinutes, 5)
        XCTAssertNotEqual(p.uid, a.uid)
    }

    // MARK: Endlo

    func testFadeReachesTheTargetOnTimeWithoutOvershoot() {
        let step = EndloLogic.fadeStep(fadeSeconds: 2, sampleRate: 100)
        var g: Float = 0
        for _ in 0..<199 { g = EndloLogic.advance(gain: g, target: 1, step: step) }
        XCTAssertLessThan(g, 1)
        for _ in 0..<5 { g = EndloLogic.advance(gain: g, target: 1, step: step) }
        XCTAssertEqual(g, 1)
        for _ in 0..<400 { g = EndloLogic.advance(gain: g, target: 0, step: step) }
        XCTAssertEqual(g, 0)
    }

    func testTwoLayerMixKeepsLevelsAndNeverClips() {
        XCTAssertEqual(EndloLogic.mix(0.5, 0.5, levelA: 1, levelB: 0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(EndloLogic.mix(0.5, 0.5, levelA: 0.5, levelB: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(EndloLogic.mix(0.9, 0.9, levelA: 1, levelB: 1), 1)
        XCTAssertEqual(EndloLogic.mix(-0.9, -0.9, levelA: 1, levelB: 1), -1)
    }

    func testScheduledSessionAutoStartsOnlyInItsWindowAndOncePerDay() {
        let at = date(2026, 10, 1, 22, 40)
        XCTAssertTrue(EndloLogic.shouldAutoStart(enabled: true, hour: 22, minute: 30, lastAutoStartDay: "", isPlaying: false, now: at, calendar: cal))
        XCTAssertFalse(EndloLogic.shouldAutoStart(enabled: true, hour: 22, minute: 30, lastAutoStartDay: "2026-10-01", isPlaying: false, now: at, calendar: cal))
        XCTAssertFalse(EndloLogic.shouldAutoStart(enabled: true, hour: 22, minute: 30, lastAutoStartDay: "", isPlaying: true, now: at, calendar: cal))
        XCTAssertFalse(EndloLogic.shouldAutoStart(enabled: false, hour: 22, minute: 30, lastAutoStartDay: "", isPlaying: false, now: at, calendar: cal))
        XCTAssertFalse(EndloLogic.shouldAutoStart(enabled: true, hour: 22, minute: 30, lastAutoStartDay: "", isPlaying: false, now: date(2026, 10, 1, 22, 10), calendar: cal))
        XCTAssertFalse(EndloLogic.shouldAutoStart(enabled: true, hour: 22, minute: 30, lastAutoStartDay: "", isPlaying: false, now: date(2026, 10, 1, 23, 30), calendar: cal))
    }

    func testSuggestedModeFollowsTheClock() {
        XCTAssertEqual(EndloLogic.suggestedModeRaw(hour: 9), "focus")
        XCTAssertEqual(EndloLogic.suggestedModeRaw(hour: 19), "detente")
        XCTAssertEqual(EndloLogic.suggestedModeRaw(hour: 23), "sommeil")
        XCTAssertEqual(EndloLogic.suggestedModeRaw(hour: 3), "sommeil")
        XCTAssertNotNil(SoundMode(rawValue: EndloLogic.suggestedModeRaw(hour: 19)))
    }

    func testMixConfigSurvivesARelaunch() throws {
        let mix = NoiseMix(a: .brown, levelA: 0.6, b: .ocean, levelB: 0.3)
        let cfg = SoundscapeController.Config(mix: mix, timerMinutes: 45, fadeSeconds: 10, volume: 0.5)
        let back = try JSONDecoder().decode(SoundscapeController.Config.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back.mix, mix)
        XCTAssertEqual(back.timerMinutes, 45)
        XCTAssertEqual(SoundscapeController.Config(mix: NoiseMix(a: .white, levelA: 1, b: nil, levelB: 0), timerMinutes: 0, fadeSeconds: 0, volume: 1).mix.b, nil)
        XCTAssertEqual(mix.label, "Bruit brun + Océan")
    }

    func testControllerPersistsItsMixInDefaults() {
        let suite = UserDefaults(suiteName: "lot7.endlo.\(UUID().uuidString)")!
        let ctl = SoundscapeController(defaults: suite)
        ctl.mix = SoundMode.sommeil.mix
        ctl.timerMinutes = 30
        let again = SoundscapeController(defaults: suite)
        XCTAssertEqual(again.mix, SoundMode.sommeil.mix)
        XCTAssertEqual(again.timerMinutes, 30)
        XCTAssertFalse(again.noise.isPlaying)
    }

    // MARK: Daylia

    func testUniqueDateNeverCollidesWithAnExistingEntry() {
        let d = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let u = MoodAnalytics.uniqueDate(d, existing: [d, d.addingTimeInterval(0.001)])
        XCTAssertFalse(MoodAnalytics.sameInstant(u, d))
        XCTAssertFalse(MoodAnalytics.sameInstant(u, d.addingTimeInterval(0.001)))
        XCTAssertTrue(MoodAnalytics.sameInstant(MoodAnalytics.uniqueDate(d, existing: []), d))
    }

    private func row(_ d: Date, _ s: Int, _ acts: [String] = [], note: String = "") -> MoodAnalytics.Row {
        .init(date: d, score: s, note: note, gratitude: "", moodName: "", activities: acts)
    }

    func testSeveralEntriesOnOneDayAllCount() {
        let rows = [row(date(2026, 10, 1, 8), 2), row(date(2026, 10, 1, 20), 4), row(date(2026, 10, 2), 5)]
        let avgs = MoodAnalytics.dailyAverages(rows, calendar: cal)
        XCTAssertEqual(avgs["2026-10-01"], 3)
        XCTAssertEqual(avgs["2026-10-02"], 5)
    }

    func testAssociationsNeedEnoughDataAndCompareWithAndWithout() {
        var rows = (0..<3).map { row(date(2026, 9, $0 + 1), 5, ["sport"]) }
        rows += (0..<2).map { row(date(2026, 9, $0 + 10), 2) }
        // 3 avec, 2 sans: trop peu pour comparer.
        XCTAssertTrue(MoodAnalytics.associations(rows).isEmpty)
        rows.append(row(date(2026, 9, 20), 2))
        let a = MoodAnalytics.associations(rows)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].averageWith, 5)
        XCTAssertEqual(a[0].averageWithout, 2)
        XCTAssertEqual(a[0].withCount, 3)
    }

    func testFiltersByActivityLevelAndText() {
        let rows = [row(date(2026, 9, 1), 4, ["sport"], note: "Course au parc"), row(date(2026, 9, 2), 2, ["travail"]),
                    row(date(2026, 9, 3), 4, ["travail"], note: "Réunion")]
        XCTAssertEqual(MoodAnalytics.filter(rows, query: "", activityUID: "travail", score: nil).count, 2)
        XCTAssertEqual(MoodAnalytics.filter(rows, query: "", activityUID: "travail", score: 4).count, 1)
        XCTAssertEqual(MoodAnalytics.filter(rows, query: "reunion", activityUID: nil, score: nil).count, 1)
    }

    func testCSVEscapesCommasQuotesAndLineBreaks() {
        let r = MoodAnalytics.Row(date: date(2026, 10, 1, 8, 5), score: 4, note: "Bien, \"vraiment\"\nfin", gratitude: "Soleil",
                                  moodName: "Serein", activities: ["s", "inconnu"])
        let csv = MoodAnalytics.csv([r], activityNames: ["s": "Sport"], calendar: cal)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "date,heure,niveau,humeur,activites,note,gratitude")
        XCTAssertTrue(csv.contains("2026-10-01,08:05,4,Serein,Sport,\"Bien, \"\"vraiment\"\"\nfin\",Soleil"))
    }

    func testEditingAPastEntryMovesItsExtraAndUpdatesAnalytics() throws {
        let c = try ModelContainer(for: MoodEntry.self, MoodEntryExtra.self, MoodActivity.self, MoodCustomMood.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let sport = MoodActivity(name: "Sport", emoji: "🏃")
        ctx.insert(sport)
        // Deux entrees le meme jour, dont une saisie apres coup.
        var d1 = MoodDraft(); d1.date = date(2026, 9, 30, 8); d1.score = 2
        var d2 = MoodDraft(); d2.date = date(2026, 9, 30, 8); d2.score = 4; d2.activityUIDs = [sport.uid]
        let e1 = MoodStore.insert(d1, existingDates: [], ctx: ctx)
        let e2 = MoodStore.insert(d2, existingDates: [e1.date], ctx: ctx)
        try ctx.save()
        XCTAssertFalse(MoodAnalytics.sameInstant(e1.date, e2.date))
        var extras = try ctx.fetch(FetchDescriptor<MoodEntryExtra>())
        XCTAssertEqual(extras.count, 1)
        XCTAssertNil(MoodStore.extra(for: e1, in: extras))
        XCTAssertEqual(MoodStore.extra(for: e2, in: extras)?.activityUIDs, [sport.uid])

        var edit = MoodStore.draft(for: e2, extras: extras)
        edit.score = 5
        edit.date = date(2026, 9, 29, 21)
        MoodStore.update(e2, with: edit, extras: extras, otherDates: [e1.date], ctx: ctx)
        try ctx.save()
        extras = try ctx.fetch(FetchDescriptor<MoodEntryExtra>())
        XCTAssertEqual(MoodStore.extra(for: e2, in: extras)?.activityUIDs, [sport.uid], "le complement suit la nouvelle date")
        let entries = try ctx.fetch(FetchDescriptor<MoodEntry>())
        let avgs = MoodAnalytics.dailyAverages(entries.map { row($0.date, $0.score) }, calendar: cal)
        XCTAssertEqual(avgs["2026-09-30"], 2)
        XCTAssertEqual(avgs["2026-09-29"], 5)

        MoodStore.delete(e2, extras: extras, ctx: ctx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MoodEntry>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MoodEntryExtra>()).count, 0)
    }

    func testWeeklyGoalCountsDistinctDays() {
        let now = date(2026, 10, 1, 20) // jeudi
        let dates = [date(2026, 9, 28), date(2026, 9, 28, 20), date(2026, 9, 30), date(2026, 9, 27)]
        XCTAssertEqual(MindStats.daysThisWeek(dates: dates, now: now, calendar: cal), 2)
    }

    // MARK: Fabuleux

    func testRoutineDayIsCompleteOnlyWhenEveryStepIsChecked() {
        let steps = ["a", "b"]
        let checks: [(stepUID: String, day: String)] = [("a", "2026-10-01"), ("b", "2026-10-01"), ("a", "2026-09-30"),
                                                        ("a", "2026-09-29"), ("b", "2026-09-29")]
        XCTAssertTrue(RoutineLogic.isComplete(stepUIDs: steps, checks: checks, day: "2026-10-01"))
        XCTAssertFalse(RoutineLogic.isComplete(stepUIDs: steps, checks: checks, day: "2026-09-30"))
        XCTAssertFalse(RoutineLogic.isComplete(stepUIDs: [], checks: checks, day: "2026-10-01"))
        XCTAssertEqual(RoutineLogic.streak(stepUIDs: steps, checks: checks, now: date(2026, 10, 1, 20), calendar: cal), 1)
    }

    func testRoutineChecksPersistPerDay() throws {
        let c = try ModelContainer(for: RoutineStep.self, RoutineCheck.self, DailyReflection.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let s = RoutineStep(title: "Verre d'eau", period: .morning, order: 0)
        ctx.insert(s)
        ctx.insert(RoutineCheck(stepUID: s.uid, day: "2026-10-01"))
        ctx.insert(DailyReflection(day: "2026-10-01", prompt: RoutineLogic.prompts[0], text: "Finir le dossier"))
        try ctx.save()
        let checks = try ctx.fetch(FetchDescriptor<RoutineCheck>())
        XCTAssertTrue(RoutineLogic.isComplete(stepUIDs: [s.uid], checks: checks.map { ($0.stepUID, $0.day) }, day: "2026-10-01"))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DailyReflection>()).first?.text, "Finir le dossier")
    }

    func testBriefingNeverInventsAgendaOrSleep() {
        let now = date(2026, 10, 1, 8)
        let b = DayBriefingBuilder.make(
            now: now,
            tasks: [.init(title: "Rapport", done: false, due: date(2026, 9, 30), recurringDays: [], priority: 1),
                    .init(title: "Plus tard", done: false, due: date(2026, 10, 5), recurringDays: [], priority: 2)],
            events: [.init(title: "Dentiste", date: date(2026, 10, 1, 14), location: "Centre"),
                     .init(title: "Demain", date: date(2026, 10, 2, 10), location: "")],
            habits: [.init(activeToday: true, archived: false, doneToday: true), .init(activeToday: true, archived: false, doneToday: false),
                     .init(activeToday: false, archived: false, doneToday: false), .init(activeToday: true, archived: true, doneToday: false)],
            sleepCheckDate: date(2026, 9, 30, 7), sleepHours: 7, sleepQuality: 4,
            routineDone: 1, routineTotal: 3, calendar: cal)
        XCTAssertEqual(b.tasks.map(\.title), ["Rapport"])
        XCTAssertTrue(b.tasks[0].overdue)
        XCTAssertEqual(b.events.map(\.title), ["Dentiste"])
        XCTAssertEqual(b.habitsDue, 2)
        XCTAssertEqual(b.habitsDone, 1)
        // Nuit notee hier: rien n'est affiche comme si c'etait la nuit derniere.
        XCTAssertNil(b.sleepHours)
        let spoken = DayBriefingBuilder.spokenText(b, calendar: cal)
        XCTAssertTrue(spoken.contains("Rapport"))
        XCTAssertTrue(spoken.contains("Dentiste à 14 heures 00"))
        XCTAssertFalse(spoken.contains("Nuit"))
        XCTAssertFalse(spoken.contains("Demain"))
    }

    func testEmptyDayIsSaidHonestly() {
        let b = DayBriefingBuilder.make(now: date(2026, 10, 1), tasks: [], events: [], habits: [],
                                        sleepCheckDate: date(2026, 10, 1, 7), sleepHours: 6.5, sleepQuality: 3,
                                        routineDone: 0, routineTotal: 0, calendar: cal)
        XCTAssertEqual(b.sleepHours, 6.5)
        XCTAssertEqual(DayBriefingBuilder.spokenText(b, calendar: cal),
                       "Aucune tâche planifiée aujourd'hui. Rien à l'agenda. Nuit notée : 6,5 heures.")
    }

    func testOldEntryPointRuleIsTheSharedOne() {
        let now = date(2026, 10, 1, 9)
        let thursday = cal.component(.weekday, from: now)
        XCTAssertEqual(MorningBriefingView.isPriorityToday(done: false, due: nil, recurringDays: [thursday], now: now, calendar: cal),
                       DayBriefingBuilder.isPriorityToday(done: false, due: nil, recurringDays: [thursday], now: now, calendar: cal))
    }

    func testReflectionPromptChangesEachDay() {
        XCTAssertNotEqual(RoutineLogic.prompt(for: date(2026, 10, 1), calendar: cal),
                          RoutineLogic.prompt(for: date(2026, 10, 2), calendar: cal))
    }

    // MARK: Rappels

    func testDailyReminderOpensItsTool() throws {
        let r = MindNotifications.makeDailyRequest(id: "daylia.daily", title: "Humeur", body: "?", hour: 21, minute: 15, route: "daylia")
        XCTAssertEqual(r.content.userInfo["route"] as? String, "daylia")
        let t = try XCTUnwrap(r.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(t.repeats)
        XCTAssertEqual(t.dateComponents.hour, 21)
        XCTAssertEqual(t.dateComponents.minute, 15)
    }
}
