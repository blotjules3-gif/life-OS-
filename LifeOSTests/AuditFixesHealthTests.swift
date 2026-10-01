import XCTest
@testable import LifeOS

/// Audit Santé, Cycle, Sommeil (1er oct.). Chaque test echoue sur l'ancien
/// calcul et passe sur le nouveau.
final class AuditFixesHealthTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min)) ?? .distantPast
    }

    // MARK: - Cycle

    /// Ancien calcul: `elapsed % 28` repartait a "Jour 3, règles dans 26 jours".
    func testCycleDoesNotWrapPastItsLength() {
        let s = CycleMath.snapshot(start: d(2026, 1, 1), today: d(2026, 1, 31), length: 28, calendar: cal)
        XCTAssertTrue(s.isLate)
        XCTAssertEqual(s.dayOfCycle, 31)
        XCTAssertEqual(s.daysUntilPeriod, 0)
        XCTAssertEqual(s.lateDays, 2)
    }

    func testCycleInsideLengthCountsDown() {
        let s = CycleMath.snapshot(start: d(2026, 1, 1), today: d(2026, 1, 11), length: 28, calendar: cal)
        XCTAssertFalse(s.isLate)
        XCTAssertEqual(s.dayOfCycle, 11)
        XCTAssertEqual(s.daysUntilPeriod, 18)
    }

    /// Ancien calcul: ovulation aux jours 14-16 meme pour un cycle de 35 jours.
    func testOvulationFollowsCycleLength() {
        XCTAssertEqual(CycleMath.ovulationDay(length: 35), 21)
        XCTAssertEqual(CycleMath.phase(day: 14, length: 35), .follicular)
        XCTAssertEqual(CycleMath.phase(day: 21, length: 35), .ovulatory)
        XCTAssertEqual(CycleMath.phase(day: 14, length: 28), .ovulatory)
        XCTAssertEqual(CycleMath.phase(day: 3, length: 35), .menstrual)
        XCTAssertEqual(CycleMath.phase(day: 25, length: 35), .luteal)
        let s = CycleMath.snapshot(start: d(2026, 1, 1), today: d(2026, 1, 14), length: 35, calendar: cal)
        XCTAssertFalse(s.isOvulationWindow)
    }

    private func days(from start: Date, count: Int) -> [Date] {
        (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// Ancien comportement: le debut n'etait pose que s'il n'existait pas.
    func testNewPeriodMovesCycleStart() {
        let flow = days(from: d(2026, 1, 1), count: 5) + days(from: d(2026, 1, 29), count: 2)
        let start = CycleMath.updatedStart(stored: d(2026, 1, 1), flowDays: flow, calendar: cal)
        XCTAssertEqual(start, cal.startOfDay(for: d(2026, 1, 29)))
    }

    func testSamePeriodLoggedLaterKeepsStart() {
        let stored = d(2026, 1, 1)
        let flow = days(from: d(2026, 1, 3), count: 2)
        XCTAssertEqual(CycleMath.updatedStart(stored: stored, flowDays: flow, calendar: cal), stored)
    }

    func testFirstFlowSetsStart() {
        let flow = days(from: d(2026, 2, 10), count: 3)
        XCTAssertEqual(CycleMath.updatedStart(stored: nil, flowDays: flow, calendar: cal),
                       cal.startOfDay(for: d(2026, 2, 10)))
    }

    /// Ancien calcul: les 3 dernieres ENTREES, meme vieilles de deux mois.
    func testRecentSymptomsOnlyLastThreeCalendarDays() {
        let now = d(2026, 3, 10, 20)
        let entries: [(date: Date, symptoms: [String])] = [
            (d(2026, 3, 10), ["Crampes"]),
            (d(2026, 3, 8), ["Crampes", "Fatigue"]),
            (d(2026, 1, 5), ["Acné"])
        ]
        let r = CycleMath.recentSymptomCounts(entries, now: now, calendar: cal)
        XCTAssertEqual(r.map(\.0), ["Crampes", "Fatigue"])
        XCTAssertEqual(r.first?.1, 2)
        XCTAssertFalse(r.contains { $0.0 == "Acné" })
    }

    // MARK: - Mesures

    /// Ancien code: toute hausse de tension etait verte.
    func testRisingBloodPressureIsNotGood() {
        XCTAssertEqual(VitalTrend.tone(type: "tension", deltas: [5]), .worse)
        XCTAssertEqual(VitalTrend.tone(type: "tension", deltas: [0, 4]), .worse, "la diastolique compte")
        XCTAssertEqual(VitalTrend.tone(type: "glycémie", deltas: [-0.2]), .neutral)
        XCTAssertEqual(VitalTrend.tone(type: "fréquence cardiaque", deltas: [3]), .worse)
        XCTAssertEqual(VitalTrend.tone(type: "poids", deltas: [-1]), .better)
        XCTAssertEqual(VitalTrend.tone(type: "poids", deltas: [0]), .neutral)
    }

    // MARK: - Rappels medicaux

    /// Ancien code: rappel fixe la veille, donc rien pour un RDV a moins de 24 h.
    func testAppointmentWithin24hStillGetsAReminder() {
        let now = d(2026, 5, 4, 10)
        let r = MedicalReminderTiming.appointment(d(2026, 5, 4, 18), now: now, calendar: cal)
        XCTAssertEqual(r?.at, d(2026, 5, 4, 16))
        XCTAssertEqual(r?.dayBefore, false)
        let far = MedicalReminderTiming.appointment(d(2026, 5, 7, 18), now: now, calendar: cal)
        XCTAssertEqual(far?.at, d(2026, 5, 6, 18))
        XCTAssertEqual(far?.dayBefore, true)
        XCTAssertNil(MedicalReminderTiming.appointment(d(2026, 5, 4, 11), now: now, calendar: cal))
    }

    /// Ancien code: 30 jours avant, donc rien si le rappel est dans moins de 30 jours.
    func testVaccineDueSoonStillGetsAReminder() {
        let now = d(2026, 5, 4, 10)
        XCTAssertEqual(MedicalReminderTiming.vaccine(due: d(2026, 5, 14), now: now, calendar: cal), d(2026, 5, 7, 9))
        XCTAssertEqual(MedicalReminderTiming.vaccine(due: d(2026, 7, 3), now: now, calendar: cal), d(2026, 6, 3, 9))
        // Veille a 9 h deja passee (il est 10 h): le jour meme a 9 h.
        XCTAssertEqual(MedicalReminderTiming.vaccine(due: d(2026, 5, 5), now: now, calendar: cal), d(2026, 5, 5, 9))
        XCTAssertNil(MedicalReminderTiming.vaccine(due: d(2026, 5, 3), now: now, calendar: cal))
    }

    // MARK: - Sommeil

    /// Ancien calcul: une nuit non notee comptait comme 0 h dormie.
    func testSleepDebtIgnoresUnloggedNights() {
        let r = SleepDebt.compute(hours: [7, nil, nil, 8, nil, nil, nil], goal: 8)
        XCTAssertEqual(r.hours, 1, accuracy: 0.001)
        XCTAssertEqual(r.nights, 2)
    }

    /// Ancien code: la derniere mesure, meme vieille de trois mois, faisait le score du jour.
    func testRecoveryScoreRefusesStaleSamples() {
        let now = d(2026, 6, 1, 8)
        let old = d(2026, 3, 1, 8)
        XCTAssertNil(RecoveryScore.score(hrv: (60, old), rhr: (55, now), now: now))
        XCTAssertNotNil(RecoveryScore.score(hrv: (60, now), rhr: (55, now), now: now))
    }

    func testDreamAudioFileIsRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dreams-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("dream-1.m4a")
        try Data([1, 2, 3]).write(to: url)
        AudioRecorder.removeFile(named: "dream-1.m4a", in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        AudioRecorder.removeFile(named: nil, in: dir)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Ecoute nocturne

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testSecondKindDuringOpenClipGetsThatClip() {
        let clip = ClipRecorder.Clip(kind: "ronflement", start: t0, end: t0.addingTimeInterval(20), file: "ronflement-1.m4a")
        let events = [
            NightEvent(kind: "ronflement", start: t0, end: t0.addingTimeInterval(5), confidence: 0.9),
            NightEvent(kind: "toux", start: t0.addingTimeInterval(10), end: t0.addingTimeInterval(11), confidence: 0.9)
        ]
        let out = NightSounds.attach(clips: [clip], to: events)
        XCTAssertEqual(out.map(\.clip), ["ronflement-1.m4a", "ronflement-1.m4a"])
    }

    func testUnreferencedClipsAreListedForDeletion() {
        var e = NightEvent(kind: "toux", start: t0, end: t0, confidence: 0.9)
        e.clip = "a.m4a"
        XCTAssertEqual(NightSounds.unreferenced(clipFiles: ["a.m4a", "b.m4a"], events: [e]), ["b.m4a"])
    }

    /// Ancien comportement: une nuit coupee gardait end = nil et la liste la cachait.
    func testOpenNightIsClosedOnRelaunch() {
        var s = NightSession(start: t0)
        s.events = [NightEvent(kind: "toux", start: t0.addingTimeInterval(500), end: t0.addingTimeInterval(600), confidence: 0.9)]
        let out = NightSounds.closeOrphans([s])
        XCTAssertEqual(out.first?.end, t0.addingTimeInterval(600))
        XCTAssertEqual(out.first?.stoppedReason, NightSounds.orphanReason)
        XCTAssertEqual(out.first?.events.count, 1)
    }

    func testClipNameParsesKindAndStart() {
        let c = NightSounds.clip(fromFileName: "bruit-fort-1790000000.m4a")
        XCTAssertEqual(c?.kind, "bruit fort")
        XCTAssertEqual(c?.start, t0)
        XCTAssertNil(NightSounds.clip(fromFileName: "nights.json"))
    }
}
