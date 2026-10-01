import XCTest
import SwiftData
import UserNotifications
import Speech
@testable import LifeOS

/// Lot 7 Sommeil: Sleep Circle, Pzazz, Rize, Awaken, Whoosh, Nuit sonore.
@MainActor
final class Lot7SleepTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
    private func hm(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    // MARK: Sleep Circle

    /// Avant: 15 min d'endormissement en dur. 30 min decale le coucher de 15 min.
    func testLatencyShiftsBedtime() {
        let wake = at(2026, 10, 2, 7)
        XCTAssertEqual(hm(SleepCycles.bedtime(wake: wake, cycles: 5, latencyMinutes: 15)), "23:15")
        XCTAssertEqual(hm(SleepCycles.bedtime(wake: wake, cycles: 5, latencyMinutes: 30)), "23:00")
        XCTAssertEqual(hm(SleepCycles.wakeTime(bedtime: at(2026, 10, 1, 23), cycles: 5, latencyMinutes: 0)), "06:30")
        XCTAssertEqual(SleepCycles.clampLatency(500), 90)
        XCTAssertEqual(SleepCycles.clampLatency(-4), 0)
    }

    func testTimelinePointsAndInvertedNightRefused() throws {
        let p = try XCTUnwrap(SleepTimeline.points(bedtime: at(2026, 10, 1, 23), wake: at(2026, 10, 2, 7),
                                                   latencyMinutes: 20, awakeMinutes: 30))
        XCTAssertEqual(hm(p.asleep), "23:20")
        XCTAssertEqual(p.inBedHours, 8, accuracy: 0.001)
        XCTAssertEqual(p.asleepHours, 7 + 10.0 / 60, accuracy: 0.001, "7h40 endormi moins 30 min d'éveil")
        XCTAssertEqual(p.asleepFraction, 20.0 / 480, accuracy: 0.0001)
        XCTAssertNil(SleepTimeline.points(bedtime: at(2026, 10, 2, 7), wake: at(2026, 10, 2, 7), latencyMinutes: 0),
                     "pas de chronologie inventée")
        let short = try XCTUnwrap(SleepTimeline.points(bedtime: at(2026, 10, 2, 1), wake: at(2026, 10, 2, 1, 10), latencyMinutes: 30))
        XCTAssertEqual(short.asleep, short.wake, "l'endormissement ne dépasse jamais le réveil")
    }

    /// Avant: le jour etait toujours aujourd'hui, impossible de noter la nuit d'hier.
    func testLogRulesCrossMidnightAndPastDay() {
        let yesterday = at(2026, 10, 1, 15)
        let r = SleepLogRules.dates(day: yesterday, bedMinutes: 23 * 60, wakeMinutes: 7 * 60, cal: cal)
        XCTAssertEqual(r.day, cal.startOfDay(for: yesterday))
        XCTAssertEqual(r.wake, at(2026, 10, 1, 7))
        XCTAssertEqual(r.bed, at(2026, 9, 30, 23))
        let late = SleepLogRules.dates(day: yesterday, bedMinutes: 60, wakeMinutes: 9 * 60, cal: cal)
        XCTAssertEqual(late.bed, at(2026, 10, 1, 1), "coucher après minuit: même jour que le réveil")
    }

    func testSameDayNightIsReplacedNotDoubled() {
        let items = [(id: 1, day: at(2026, 10, 1, 0)), (id: 2, day: at(2026, 10, 2, 0))]
        XCTAssertEqual(SleepLogRules.conflict(items, day: at(2026, 10, 2, 9), excluding: nil, cal: cal), 2)
        XCTAssertNil(SleepLogRules.conflict(items, day: at(2026, 10, 2, 9), excluding: 2, cal: cal), "la nuit modifiée ne se remplace pas elle-même")
        XCTAssertNil(SleepLogRules.conflict(items, day: at(2026, 10, 3, 9), excluding: nil, cal: cal))
    }

    func testHealthImportNeedsBothTimesInOrder() {
        XCTAssertNil(SleepHealthImport.night(bedtime: nil, wake: at(2026, 10, 2, 7)))
        XCTAssertNil(SleepHealthImport.night(bedtime: at(2026, 10, 2, 7), wake: at(2026, 10, 2, 6)))
        XCTAssertNil(SleepHealthImport.night(bedtime: at(2026, 10, 1, 7), wake: at(2026, 10, 2, 7)), "24 h: pas une nuit")
        XCTAssertNotNil(SleepHealthImport.night(bedtime: at(2026, 10, 1, 23), wake: at(2026, 10, 2, 7)))
    }

    func testTrendOnePointPerDayInsideWindow() {
        let now = at(2026, 10, 2, 12)
        let nights: [(date: Date, hours: Double, quality: Int)] = [
            (at(2026, 10, 2, 0), 6, 2), (at(2026, 10, 2, 0), 7.5, 4),   // deux saisies le même jour
            (at(2026, 9, 25, 0), 8, 9),                                 // qualité hors bornes
            (at(2026, 8, 1, 0), 8, 3),                                  // hors fenêtre
        ]
        let p = SleepTrend.points(nights, days: 30, now: now, cal: cal)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.last?.hours, 7.5, "la plus longue des deux")
        XCTAssertEqual(p.first?.quality, 5, "bornée à 5")
        XCTAssertEqual(p.map(\.day), p.map(\.day).sorted())
        XCTAssertEqual(SleepTrend.averageQuality(p) ?? 0, 4.5, accuracy: 0.001)
        XCTAssertNil(SleepTrend.averageQuality([]))
    }

    func testCSVEscapesAndSorts() {
        let rows = [
            SleepCSV.Row(day: at(2026, 10, 2, 0), bed: at(2026, 10, 1, 23), asleep: at(2026, 10, 1, 23, 15), wake: at(2026, 10, 2, 7),
                         hours: 7.75, quality: 4, source: "Santé", note: "réveil; \"chat\"\nencore"),
            SleepCSV.Row(day: at(2026, 9, 30, 0), bed: at(2026, 9, 29, 22), asleep: at(2026, 9, 29, 22), wake: at(2026, 9, 30, 6),
                         hours: 8, quality: 3, source: "manuel", note: ""),
        ]
        let csv = SleepCSV.make(rows)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(String(lines[0]), SleepCSV.header)
        XCTAssertTrue(lines[1].hasPrefix("2026-09-30;22:00;22:00;06:00;8,00;3;manuel;"), "trié par date")
        XCTAssertTrue(csv.contains("\"réveil; \"\"chat\"\"\nencore\""), "note échappée")
        XCTAssertTrue(csv.contains(";7,75;4;Santé;"))
    }

    func testNightDetailsFoundAndDeletedWithNight() throws {
        let c = try ModelContainer(for: SleepNight.self, SleepNightDetails.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let a = SleepNight(date: at(2026, 10, 2, 0), bedtime: at(2026, 10, 1, 23), wake: at(2026, 10, 2, 7))
        let b = SleepNight(date: at(2026, 10, 1, 0), bedtime: at(2026, 9, 30, 23), wake: at(2026, 10, 1, 7))
        ctx.insert(a); ctx.insert(b)
        ctx.insert(SleepNightDetails(night: a, latencyMinutes: 40, source: "sante", awakeMinutes: 12))
        try ctx.save()
        XCTAssertEqual(SleepNightStore.fetchDetails(for: a, in: ctx)?.latencyMinutes, 40)
        XCTAssertNil(SleepNightStore.fetchDetails(for: b, in: ctx))
        let p = SleepNightStore.points(for: a, details: SleepNightStore.fetchDetails(for: a, in: ctx), defaultLatency: 15)
        XCTAssertEqual(p.map { hm($0.asleep) }, "23:40")
        SleepNightStore.delete(a, in: ctx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SleepNightDetails>()).count, 0, "les infos partent avec la nuit")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SleepNight>()).count, 1)
    }

    // MARK: Pzazz

    func testNapDurationIsFreeButBounded() {
        XCTAssertEqual(NapPlan.clamp(2), 5)
        XCTAssertEqual(NapPlan.clamp(500), 180)
        XCTAssertEqual(NapPlan.clamp(37), 37, "durée libre, pas seulement 20 ou 90")
        XCTAssertTrue(NapPlan.advice(20).contains("inertie"))
        XCTAssertTrue(NapPlan.advice(90).contains("cycle complet"))
        XCTAssertTrue(NapPlan.advice(50).contains("sommeil profond"))
    }

    func testSoundscapeFadesOutOverLastMinute() {
        XCTAssertEqual(NapPlan.fadeVolume(remaining: 600, base: 0.6), 0.6)
        XCTAssertEqual(NapPlan.fadeVolume(remaining: 30, base: 0.6), 0.3, accuracy: 0.0001)
        XCTAssertEqual(NapPlan.fadeVolume(remaining: 0, base: 0.6), 0)
        XCTAssertEqual(NapPlan.fadeVolume(remaining: 10, fadeSeconds: 0, base: 0.6), 0.6)
    }

    func testWakeSoundsAreSystemSoundsOnly() {
        XCTAssertNil(NapWakeSound.none.systemID)
        XCTAssertEqual(NapWakeSound.allCases.compactMap(\.systemID).count, 3)
    }

    func testNapCloseHappensOnlyOnce() throws {
        let c = try ModelContainer(for: NapSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let t0 = at(2026, 10, 2, 14)
        let nap = NapSession(start: t0, plannedMinutes: 20)
        ctx.insert(nap)
        let closed = NapLog.close([nap], at: t0.addingTimeInterval(1200), completed: true)
        XCTAssertTrue(closed === nap)
        XCTAssertEqual(nap.actualMinutes ?? 0, 20, accuracy: 0.01)
        XCTAssertNil(NapLog.close([nap], at: t0.addingTimeInterval(1500), completed: false), "pas de seconde fin")
        XCTAssertTrue(nap.completed)
    }

    /// App tuee pendant la sieste: la fiche restait ouverte pour toujours.
    func testNapRecoveryAfterKill() throws {
        let c = try ModelContainer(for: NapSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let now = at(2026, 10, 2, 15)
        let old = NapSession(start: now.addingTimeInterval(-3600), plannedMinutes: 20)
        let live = NapSession(start: now.addingTimeInterval(-300), plannedMinutes: 20)
        ctx.insert(old); ctx.insert(live)
        let fixed = NapLog.recover([old, live], now: now, timerActive: true)
        XCTAssertEqual(fixed.count, 1)
        XCTAssertEqual(old.end, old.plannedEnd)
        XCTAssertTrue(old.completed)
        XCTAssertNil(live.end, "la sieste qui tourne reste ouverte")
        NapLog.recover([old, live], now: now, timerActive: false)
        XCTAssertEqual(live.end, now)
        XCTAssertFalse(live.completed, "arrêtée avant l'heure prévue")
        let s = NapLog.summary([old, live])
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.completed, 1)
    }

    // MARK: Rize

    func testEveningContinuesAfterMidnight() {
        XCTAssertEqual(EveningRoutine.eveningDay(for: at(2026, 10, 2, 0, 30), cal: cal), at(2026, 10, 1, 0))
        XCTAssertEqual(EveningRoutine.eveningDay(for: at(2026, 10, 2, 21), cal: cal), at(2026, 10, 2, 0))
    }

    func testChecklistToggleProgressAndTitles() {
        var done: [String] = []
        done = EveningRoutine.toggled(done, "Tisane")
        done = EveningRoutine.toggled(done, "Lecture")
        done = EveningRoutine.toggled(done, "Tisane")
        XCTAssertEqual(done, ["Lecture"])
        let p = EveningRoutine.progress(done: done + ["Ancienne étape"], items: ["Lecture", "Douche"])
        XCTAssertEqual(p.done, 1, "une étape retirée ne compte plus")
        XCTAssertEqual(p.total, 2)
        XCTAssertNil(EveningRoutine.cleanTitle("  lecture ", existing: ["Lecture"]))
        XCTAssertEqual(EveningRoutine.cleanTitle("  Douche  ", existing: ["Lecture"]), "Douche")
        XCTAssertNil(EveningRoutine.cleanTitle("   ", existing: []))
        XCTAssertFalse(EveningRoutine.defaultItems.contains { $0.title.contains("—") || $0.detail.contains("—") })
    }

    func testChecklistPersists() throws {
        let c = try ModelContainer(for: EveningChecklistItem.self, EveningChecklistDay.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        ctx.insert(EveningChecklistItem(title: "Tisane", order: 0))
        ctx.insert(EveningChecklistDay(day: at(2026, 10, 1, 0), doneTitles: ["Tisane"], totalItems: 1))
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<EveningChecklistDay>()).first?.doneTitles, ["Tisane"])
    }

    /// Dette sur 14 nuits: une nuit non notee est inconnue, pas 0 h.
    func testDebtOverFourteenNightsIgnoresUnknown() {
        let now = at(2026, 10, 2, 12)
        let nights: [(date: Date, hours: Double)] = [(at(2026, 10, 2, 0), 6), (at(2026, 9, 30, 0), 7), (at(2026, 9, 25, 0), 8),
                                                     (at(2026, 9, 1, 0), 2)]   // hors fenêtre
        let w = SleepDebt.window(nights, days: 14, now: now, cal: cal)
        XCTAssertEqual(w.count, 14)
        XCTAssertEqual(w.compactMap { $0 }.count, 3)
        XCTAssertEqual(w.last ?? nil, 6, "aujourd'hui en dernier")
        let (debt, counted) = SleepDebt.compute(hours: w, goal: 8)
        XCTAssertEqual(counted, 3)
        XCTAssertEqual(debt, 3, accuracy: 0.001, "2 h + 1 h + 0 h, jamais 11 nuits x 8 h")
    }

    func testBedtimeSuggestionRuleAndMidnight() {
        let p = BedtimePlan.suggest(wakeMinutes: 7 * 60, needHours: 8, latencyMinutes: 15)
        XCTAssertEqual(BedtimePlan.label(p.bedMinutes), "22:45")
        XCTAssertEqual(BedtimePlan.label(p.windDownMinutes), "22:00")
        let early = BedtimePlan.suggest(wakeMinutes: 30, needHours: 7.5, latencyMinutes: 0)
        XCTAssertEqual(BedtimePlan.label(early.bedMinutes), "17:00", "passe la veille sans valeur négative")
        let wakeChanged = BedtimePlan.suggest(wakeMinutes: 6 * 60, needHours: 8, latencyMinutes: 15)
        XCTAssertEqual(wakeChanged.bedMinutes, p.bedMinutes - 60, "changer le réveil recalcule tout")
        XCTAssertEqual(BedtimePlan.label(BedtimePlan.suggest(wakeMinutes: 60, needHours: 0.5, latencyMinutes: 30).windDownMinutes), "23:15")
    }

    func testCalendarConflictBeforeWake() {
        let wake = at(2026, 10, 3, 8)
        XCTAssertEqual(BedtimePlan.earliestConflict(eventStarts: [at(2026, 10, 3, 9), at(2026, 10, 3, 7, 30), at(2026, 10, 3, 6)], wake: wake),
                       at(2026, 10, 3, 6))
        XCTAssertNil(BedtimePlan.earliestConflict(eventStarts: [at(2026, 10, 3, 9)], wake: wake))
    }

    // MARK: Awaken

    func testTagsParsedWithoutDuplicates() {
        XCTAssertEqual(DreamSearch.parseTags("Lucide, vol ,#famille, lucide, Vol"), ["Lucide", "vol", "famille"])
        XCTAssertEqual(DreamSearch.parseTags("Rêve, reve"), ["Rêve"])
        XCTAssertEqual(DreamSearch.parseTags(" , ,"), [])
    }

    func testSearchIsAccentInsensitiveAndUsesTagsAndTranscript() {
        let m = { (q: String) in DreamSearch.matches(title: "Rêve de mer", text: "Je volais", tags: ["Lucide", "famille"],
                                                     transcript: "il y avait ma grand-mère", query: q) }
        XCTAssertTrue(m(""))
        XCTAssertTrue(m("reve"))
        XCTAssertTrue(m("GRAND-MERE"))
        XCTAssertTrue(m("#lucide"))
        XCTAssertFalse(m("#luc"), "#tag = tag exact")
        XCTAssertTrue(m("luc"), "un mot nu cherche aussi dans les tags")
        XCTAssertTrue(m("mer volais"))
        XCTAssertFalse(m("mer chat"), "tous les mots doivent correspondre")
        let counts = DreamSearch.tagCounts([["Vol", "lucide"], ["vol"], []])
        XCTAssertEqual(counts.first?.tag, "Vol")
        XCTAssertEqual(counts.first?.count, 2)
    }

    /// Rien n'est efface avant "Enregistrer"; remplacer supprime l'ancienne note.
    func testAudioPlanIsTransactional() {
        let replace = DreamAudioPlan.resolve(existing: "old.m4a", recorded: "new.m4a", removeExisting: false)
        XCTAssertEqual(replace.keep, "new.m4a")
        XCTAssertEqual(replace.delete, ["old.m4a"])
        let remove = DreamAudioPlan.resolve(existing: "old.m4a", recorded: nil, removeExisting: true)
        XCTAssertNil(remove.keep)
        XCTAssertEqual(remove.delete, ["old.m4a"])
        let keep = DreamAudioPlan.resolve(existing: "old.m4a", recorded: nil, removeExisting: false)
        XCTAssertEqual(keep.keep, "old.m4a")
        XCTAssertTrue(keep.delete.isEmpty)
        XCTAssertEqual(DreamAudioPlan.resolve(existing: nil, recorded: "n.m4a", removeExisting: true).delete, [])
    }

    func testPlaybackPositionClampAndLabel() {
        XCTAssertEqual(DreamPlayback.clamp(-3, duration: 10), 0)
        XCTAssertEqual(DreamPlayback.clamp(30, duration: 10), 10)
        XCTAssertEqual(DreamPlayback.label(65), "1:05")
        XCTAssertEqual(DreamPlayback.label(0), "0:00")
    }

    func testRealityCheckHoursRespectQuietHours() throws {
        XCTAssertEqual(RealityCheck.parse("3, 10,10, 23, 14,x"), [10, 14])
        XCTAssertEqual(RealityCheck.serialize([22, 8, 2]), "8,22")
        let reqs = RealityCheck.requests(hours: [14, 3, 10])
        XCTAssertEqual(reqs.map(\.identifier), ["reality-10", "reality-14"])
        let trigger = try XCTUnwrap(reqs.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 10)
        XCTAssertTrue(trigger.repeats)
    }

    func testTranscriptionRefusalIsExplained() {
        XCTAssertNil(DreamTranscription.failure(for: .authorized))
        XCTAssertEqual(DreamTranscription.failure(for: .denied), .denied)
        XCTAssertEqual(DreamTranscription.failure(for: .restricted), .restricted)
        for f in [DreamTranscription.Failure.denied, .restricted, .unavailable, .noOnDevice, .noAudio, .empty] {
            let m = DreamTranscription.message(f)
            XCTAssertFalse(m.isEmpty)
            XCTAssertFalse(m.contains("IA"))
            XCTAssertFalse(m.contains("—"))
        }
        XCTAssertTrue(DreamTranscription.message(.denied).contains("Réglages"), "une issue est proposée")
    }

    func testDreamDetailsUpsertAndDelete() throws {
        let c = try ModelContainer(for: DreamEntry.self, DreamDetails.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let d = DreamEntry(title: "Vol", text: "Au-dessus de la ville")
        let other = DreamEntry(title: "Autre")
        ctx.insert(d); ctx.insert(other)
        let x = DreamStore.upsert(for: d, in: ctx)
        x.tags = ["lucide"]
        try ctx.save()
        XCTAssertTrue(DreamStore.upsert(for: d, in: ctx) === x, "pas de seconde fiche")
        XCTAssertNil(DreamStore.fetchDetails(for: other, in: ctx))
        DreamStore.delete(d, in: ctx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DreamDetails>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DreamEntry>()).count, 1)
    }

    // MARK: Whoosh

    private func series(_ values: [Double], endingBefore day: Date) -> [(value: Double, date: Date)] {
        values.enumerated().map { i, v in (v, day.addingTimeInterval(-Double(values.count - i) * 86_400)) }
    }

    func testBaselineNeedsSevenDistinctDays() {
        let now = at(2026, 10, 2, 7)
        let six = series([50, 52, 48, 51, 49, 50], endingBefore: now)
        XCTAssertNil(RecoveryBaseline.stat(six, before: now, cal: cal).stat)
        XCTAssertEqual(RecoveryBaseline.stat(six, before: now, cal: cal).days, 6)
        // Trois mesures le meme jour comptent pour un seul jour.
        let sameDay = six + [(70, now.addingTimeInterval(-86_400 + 60)), (70, now.addingTimeInterval(-86_400 + 120))]
        XCTAssertEqual(RecoveryBaseline.stat(sameDay, before: now, cal: cal).days, 6)
        let seven = series([50, 52, 48, 51, 49, 50, 50], endingBefore: now)
        XCTAssertEqual(RecoveryBaseline.stat(seven, before: now, cal: cal).stat?.days, 7)
        // La mesure du jour n'entre pas dans sa propre ligne de base.
        XCTAssertEqual(RecoveryBaseline.stat(seven + [(200, now)], before: now, cal: cal).stat?.mean ?? 0, 50, accuracy: 0.001)
    }

    func testPersonalScoreFollowsBaselineAndExplainsItself() throws {
        let now = at(2026, 10, 2, 7)
        let hrvHist = series([40, 42, 38, 41, 39, 40, 40, 41], endingBefore: now)
        let rhrHist = series([60, 61, 59, 60, 60, 62, 58, 60], endingBefore: now)
        let good = try XCTUnwrap(RecoveryBaseline.evaluate(hrv: (48, now), rhr: (56, now), hrvHistory: hrvHist, rhrHistory: rhrHist, now: now, cal: cal))
        let bad = try XCTUnwrap(RecoveryBaseline.evaluate(hrv: (34, now), rhr: (65, now), hrvHistory: hrvHist, rhrHistory: rhrHist, now: now, cal: cal))
        XCTAssertTrue(good.personal)
        XCTAssertGreaterThan(good.score, 60)
        XCTAssertLessThan(bad.score, 40)
        // Meme VFC de 48 ms: le repere fixe de 80 ms la jugeait mediocre.
        XCTAssertGreaterThan(good.score, RecoveryScore.score(hrv: (48, now), rhr: (56, now), now: now)!)
        XCTAssertEqual(good.contributions.map(\.id), ["hrv", "rhr"])
        XCTAssertEqual(Int(good.contributions.reduce(0) { $0 + $1.points }.rounded()), good.score)
        XCTAssertTrue(good.contributions[0].explanation.contains("ta moyenne"))
        // Meme jeu de donnees, meme resultat.
        XCTAssertEqual(good, RecoveryBaseline.evaluate(hrv: (48, now), rhr: (56, now), hrvHistory: hrvHist, rhrHistory: rhrHist, now: now, cal: cal))
        // Retirer des mesures recalcule: sous 7 jours, retour a la calibration.
        let fewer = try XCTUnwrap(RecoveryBaseline.evaluate(hrv: (48, now), rhr: (56, now), hrvHistory: Array(hrvHist.suffix(3)),
                                                            rhrHistory: rhrHist, now: now, cal: cal))
        XCTAssertFalse(fewer.personal)
        XCTAssertEqual(fewer.calibrationDays, 3)
    }

    func testCalibrationFallsBackToLegacyScoreAndStaleIsSuppressed() {
        let now = at(2026, 10, 2, 7)
        let r = RecoveryBaseline.evaluate(hrv: (60, now), rhr: (55, now), hrvHistory: [], rhrHistory: [], now: now, cal: cal)
        XCTAssertEqual(r?.score, RecoveryScore.score(hrv: (60, now), rhr: (55, now), now: now))
        XCTAssertEqual(r?.personal, false)
        XCTAssertTrue(r?.contributions.first?.explanation.contains("repère fixe") ?? false)
        let old = now.addingTimeInterval(-40 * 3600)
        XCTAssertNil(RecoveryBaseline.evaluate(hrv: (60, old), rhr: (55, now), hrvHistory: [], rhrHistory: [], now: now, cal: cal))
        XCTAssertNil(RecoveryBaseline.evaluate(hrv: nil, rhr: (55, now), hrvHistory: [], rhrHistory: [], now: now, cal: cal))
    }

    func testReadingsAreDedupedAndExpire() {
        let t = at(2026, 10, 2, 7)
        XCTAssertTrue(RecoveryBaseline.isDuplicate(kind: "hrv", date: t.addingTimeInterval(10), existing: [("hrv", t)]))
        XCTAssertFalse(RecoveryBaseline.isDuplicate(kind: "rhr", date: t, existing: [("hrv", t)]))
        XCTAssertTrue(RecoveryBaseline.isExpired(t.addingTimeInterval(-121 * 86_400), now: t))
        XCTAssertFalse(RecoveryBaseline.isExpired(t.addingTimeInterval(-30 * 86_400), now: t))
    }

    // MARK: Nuit sonore

    private func session(_ start: Date, hours: Double, snoreSeconds: [TimeInterval], reason: String? = nil, open: Bool = false) -> NightSession {
        var s = NightSession(start: start)
        s.end = open ? nil : start.addingTimeInterval(hours * 3600)
        s.events = snoreSeconds.enumerated().map { i, d in
            NightEvent(kind: "ronflement", start: start.addingTimeInterval(Double(i) * 600), end: start.addingTimeInterval(Double(i) * 600 + d),
                       confidence: 0.9, clip: i == 0 ? "ronflement-1.m4a" : nil)
        }
        s.stoppedReason = reason
        return s
    }

    func testSnoringTrendAcrossNights() {
        let sessions = [
            session(at(2026, 10, 1, 23), hours: 8, snoreSeconds: [120, 60]),
            session(at(2026, 9, 29, 23), hours: 6, snoreSeconds: [600]),
            session(at(2026, 9, 30, 23), hours: 7, snoreSeconds: []),
            session(at(2026, 10, 2, 23), hours: 1, snoreSeconds: [30], open: true),
        ]
        let t = NightSounds.trend(sessions)
        XCTAssertEqual(t.count, 3, "la nuit encore ouverte n'entre pas")
        XCTAssertEqual(t.map(\.start), t.map(\.start).sorted())
        XCTAssertEqual(t.first?.minutes ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(t.last?.minutes ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(t.last?.minutesPerHour ?? 0, 3.0 / 8, accuracy: 0.001)
        XCTAssertEqual(NightSounds.trend(sessions, limit: 1).count, 1)
    }

    func testLowBatteryStopRule() {
        XCTAssertTrue(NightSounds.shouldStopForBattery(level: 0.09, charging: false))
        XCTAssertTrue(NightSounds.shouldStopForBattery(level: 0.10, charging: false))
        XCTAssertFalse(NightSounds.shouldStopForBattery(level: 0.09, charging: true), "sur secteur: on continue")
        XCTAssertFalse(NightSounds.shouldStopForBattery(level: -1, charging: false), "niveau inconnu: on n'arrête rien")
        XCTAssertFalse(NightSounds.shouldStopForBattery(level: 0.5, charging: false))
        XCTAssertTrue(NightSounds.lowBatteryReason(level: 0.09).contains("9 %"))
    }

    func testNightExportSummaryAndClipList() {
        let sessions = [
            session(at(2026, 10, 1, 23), hours: 8, snoreSeconds: [120, 60], reason: "Batterie faible (9 %) : écoute arrêtée; fin"),
            session(at(2026, 10, 2, 23), hours: 1, snoreSeconds: [30], open: true),
        ]
        let sum = NightSounds.csvSummary(sessions).split(separator: "\n").map(String.init)
        XCTAssertEqual(sum.first, NightSounds.csvSummaryHeader)
        XCTAssertEqual(sum.count, 2, "seulement les nuits terminées")
        XCTAssertTrue(sum[1].hasPrefix("2026-10-01;23:00;07:00;480;2;3,00;0;0;0;0;0;"))
        XCTAssertTrue(sum[1].hasSuffix("\"Batterie faible (9 %) : écoute arrêtée; fin\""), "raison échappée")
        let clips = NightSounds.csvClips(sessions).split(separator: "\n").map(String.init)
        XCTAssertEqual(clips.first, NightSounds.csvClipsHeader)
        XCTAssertEqual(clips.count, 3)
        XCTAssertTrue(clips[1].contains(";ronflement;120;90;night-"))
        XCTAssertTrue(clips[1].hasSuffix("/ronflement-1.m4a"))
        XCTAssertTrue(clips[2].hasSuffix(";"), "pas d'extrait gardé: colonne vide")
    }
}
