import XCTest
import SwiftData
@testable import LifeOS

/// Lot 7, cycle (Floé, Klue, Floé Stats). Chaque test vise un comportement
/// qui n'existait pas, ou etait faux, avant ce lot.
@MainActor
final class Lot7CycleTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h)) ?? .distantPast
    }

    private func day(_ y: Int, _ m: Int, _ dd: Int) -> Date { cal.startOfDay(for: d(y, m, dd)) }

    /// Jours de flux consecutifs, en copies d'entrees.
    private func period(_ start: Date, days: Int = 5, flow: Int = 2) -> [CycleEntrySnapshot] {
        (0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .map { CycleEntrySnapshot(date: $0, flow: flow) }
    }

    private func analyze(_ entries: [CycleEntrySnapshot], manual: Date? = nil, setLength: Int = 28,
                         today: Date, range: CycleRange = .all) -> CycleAnalysis {
        CycleAnalytics.analyze(entries: entries, manualStart: manual, setLength: setLength,
                               setPeriodLength: 5, today: today, range: range, calendar: cal)
    }

    // MARK: - Bornes explicites

    func testExplicitEndClosesPeriodAndGivesItsLength() {
        var e = period(d(2026, 1, 5), days: 6)
        e[3].isEnd = true   // regles finies le 4e jour, la suite est du spotting
        let eps = CycleStats.episodes(e.map(\.mark), today: d(2026, 1, 20), calendar: cal)
        XCTAssertEqual(eps.count, 1)
        XCTAssertEqual(eps[0].days(calendar: cal), 4)
        XCTAssertTrue(eps[0].explicitEnd)
    }

    func testExplicitStartSplitsAPeriod() {
        // 7 jours apres le debut: sans le repere, ce serait un saignement intermediaire.
        var e = period(d(2026, 1, 5), days: 2) + period(d(2026, 1, 12), days: 3)
        XCTAssertEqual(CycleStats.episodes(e.map(\.mark), today: d(2026, 2, 1), calendar: cal).count, 1)
        e[2].isStart = true
        let eps = CycleStats.episodes(e.map(\.mark), today: d(2026, 2, 1), calendar: cal)
        XCTAssertEqual(eps.map(\.start), [day(2026, 1, 5), day(2026, 1, 12)])
    }

    /// Ancien calcul (periodStarts): du flux 9 jours apres le debut ouvrait
    /// de "nouvelles regles". Un saignement intermediaire ne deplace plus le cycle.
    func testMidCycleSpottingDoesNotStartANewPeriod() {
        let e = period(d(2026, 1, 5)) + [CycleEntrySnapshot(date: d(2026, 1, 14), flow: 1)]
        XCTAssertEqual(CycleStats.periodStarts(flowDays: e.filter { $0.flow > 0 }.map(\.date), calendar: cal).count, 2,
                       "l'ancien regroupement comptait deux règles")
        let eps = CycleStats.episodes(e.map(\.mark), today: d(2026, 1, 20), calendar: cal)
        XCTAssertEqual(eps.count, 1)
    }

    func testOngoingPeriodIsNotComplete() {
        let e = period(d(2026, 1, 5), days: 2)
        let eps = CycleStats.episodes(e.map(\.mark), today: d(2026, 1, 7), calendar: cal)
        XCTAssertFalse(eps[0].isComplete)
        XCTAssertTrue(CycleStats.episodes(e.map(\.mark), today: d(2026, 1, 15), calendar: cal)[0].isComplete)
    }

    func testAveragePeriodLengthNeedsTwoCompletePeriods() {
        let one = period(d(2026, 1, 5), days: 4)
        XCTAssertNil(CycleStats.averagePeriodLength(CycleStats.episodes(one.map(\.mark), today: d(2026, 2, 1), calendar: cal)))
        let two = one + period(d(2026, 2, 2), days: 6)
        XCTAssertEqual(CycleStats.averagePeriodLength(CycleStats.episodes(two.map(\.mark), today: d(2026, 3, 1), calendar: cal),
                                                      calendar: cal), 5)
    }

    // MARK: - Previsions

    /// Acceptance du ledger: trois regles irregulieres, puis une correction
    /// retroactive: previsions et historique bougent ensemble.
    func testIrregularHistoryDrivesPredictionAndCorrectionUpdatesIt() {
        var e = period(d(2026, 1, 1)) + period(d(2026, 1, 27)) + period(d(2026, 3, 2))   // 26 puis 34 j
        var a = analyze(e, today: d(2026, 3, 10))
        XCTAssertEqual(a.prediction.basis, .history(cycles: 2))
        XCTAssertEqual(a.prediction.lengthDays, 30)
        XCTAssertEqual(a.prediction.shortestDays, 26)
        XCTAssertEqual(a.prediction.longestDays, 34)
        XCTAssertEqual(a.prediction.nextStart, day(2026, 4, 1))
        XCTAssertEqual(a.prediction.earliestStart, day(2026, 3, 28))
        XCTAssertEqual(a.prediction.latestStart, day(2026, 4, 5))
        XCTAssertEqual(a.allCycles.map(\.days), [26, 34])

        // Correction: les regles de fevrier avaient en fait commence le 29 janvier.
        e.removeAll { cal.isDate($0.date, equalTo: d(2026, 1, 27), toGranularity: .month) && $0.date >= d(2026, 1, 20) }
        e += period(d(2026, 1, 29))
        a = analyze(e, today: d(2026, 3, 10))
        XCTAssertEqual(a.allCycles.map(\.days), [28, 32])
        XCTAssertEqual(a.prediction.lengthDays, 30)
        XCTAssertEqual(a.prediction.shortestDays, 28)
        XCTAssertEqual(a.prediction.earliestStart, day(2026, 3, 30))
    }

    /// Moins de 2 cycles: duree reglee + fourchette par defaut, dit comme tel.
    func testFewerThanTwoCyclesFallsBackToSetLengthWithUncertainty() {
        let e = period(d(2026, 1, 1)) + period(d(2026, 1, 30))   // un seul cycle (29 j)
        let a = analyze(e, setLength: 32, today: d(2026, 2, 5))
        XCTAssertEqual(a.prediction.basis, .setting)
        XCTAssertEqual(a.prediction.lengthDays, 32)
        XCTAssertEqual(a.prediction.shortestDays, 32 - CyclePrediction.defaultSpread)
        XCTAssertEqual(a.prediction.longestDays, 32 + CyclePrediction.defaultSpread)
        XCTAssertNotEqual(a.prediction.earliestStart, a.prediction.latestStart, "pas d'historique = une fourchette")
    }

    /// Ancien suivi: duree reglee a la main meme avec un historique. Le
    /// suivi, les stats et le rapport lisent maintenant la meme prevision.
    func testSameNumbersInTrackerStatsAndReport() {
        let e = period(d(2026, 1, 1)) + period(d(2026, 2, 2)) + period(d(2026, 3, 6))   // 32, 32
        let a = analyze(e, setLength: 28, today: d(2026, 3, 10))
        XCTAssertEqual(a.prediction.lengthDays, 32)
        XCTAssertEqual(a.snapshot?.daysUntilPeriod, 28, "le compte à rebours suit 32 j, pas les 28 réglés")
        let report = CycleReport.text(analysis: a, rangeLabel: "Tout", entries: e, now: d(2026, 3, 10), calendar: cal)
        XCTAssertTrue(report.contains("32 jours (moyenne de 2 cycles"), report)
        XCTAssertEqual(a.rangeSummary?.averageDays, 32)
    }

    func testFertileWindowWidensWithTheRange() {
        let e = period(d(2026, 1, 1)) + period(d(2026, 1, 27)) + period(d(2026, 3, 2))   // 26 et 34
        let p = analyze(e, today: d(2026, 3, 3)).prediction
        // Ovulation estimee: jour 12 (26 j) a jour 20 (34 j). Fenetre: J7 a J21.
        XCTAssertEqual(p.fertileStart, day(2026, 3, 8))
        XCTAssertEqual(p.fertileEnd, day(2026, 3, 22))
    }

    func testPredictedDaysNeverIncludePastDays() {
        let e = period(d(2026, 1, 1)) + period(d(2026, 1, 29)) + period(d(2026, 2, 26))
        let p = analyze(e, today: d(2026, 3, 1)).prediction
        let pd = p.predictedDays(cycles: 2, today: d(2026, 3, 1), calendar: cal)
        XCTAssertTrue(pd.period.contains(day(2026, 3, 26)))
        XCTAssertTrue(pd.period.allSatisfy { $0 >= day(2026, 3, 1) })
        XCTAssertTrue(pd.period.isDisjoint(with: pd.fertile))
    }

    // MARK: - Debut du cycle

    /// Ancien comportement: le debut ecrit par le flux ne revenait jamais en
    /// arriere quand on supprimait ces regles.
    func testDeletingLatestPeriodMovesStartBack() {
        let jan = period(d(2026, 1, 1)), feb = period(d(2026, 1, 29))
        XCTAssertEqual(analyze(jan + feb, manual: d(2026, 1, 1), today: d(2026, 2, 5)).prediction.lastStart, day(2026, 1, 29))
        XCTAssertEqual(analyze(jan, manual: d(2026, 1, 1), today: d(2026, 2, 5)).prediction.lastStart, day(2026, 1, 1))
    }

    func testResolvedStartRules() {
        XCTAssertNil(CycleMath.resolvedStart(manual: nil, latestLogged: nil, calendar: cal))
        XCTAssertEqual(CycleMath.resolvedStart(manual: d(2026, 1, 1), latestLogged: d(2026, 1, 3), calendar: cal), day(2026, 1, 1))
        XCTAssertEqual(CycleMath.resolvedStart(manual: d(2026, 2, 10), latestLogged: d(2026, 1, 3), calendar: cal), day(2026, 2, 10))
        XCTAssertEqual(CycleMath.resolvedStart(manual: d(2026, 1, 3), latestLogged: d(2026, 2, 10), calendar: cal), day(2026, 2, 10))
    }

    func testOnboardingWriteIsAdoptedAsDeclaration() throws {
        let suite = "lot7.cycle.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { ud.removePersistentDomain(forName: suite) }
        ud.set(1_000_000.0, forKey: AppStorageKeys.cycleStartDate)        // ecrit par l'onboarding
        XCTAssertEqual(CycleMath.adoptManualStart(defaults: ud)?.timeIntervalSince1970, 1_000_000)
        ud.set(2_000_000.0, forKey: AppStorageKeys.cycleStartDate)        // ecrit par CycleContext
        ud.set(2_000_000.0, forKey: CycleKeys.startWritten)
        XCTAssertEqual(CycleMath.adoptManualStart(defaults: ud)?.timeIntervalSince1970, 1_000_000,
                       "notre propre écriture n'est pas une déclaration")
    }

    func testStoredSnapshotUsesPredictionLength() throws {
        let suite = "lot7.cycle.snap.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { ud.removePersistentDomain(forName: suite) }
        ud.set(d(2026, 1, 1).timeIntervalSince1970, forKey: AppStorageKeys.cycleStartDate)
        ud.set(28, forKey: AppStorageKeys.cycleLengthDays)
        ud.set(35, forKey: CycleKeys.predictionLength)
        let s = CycleMath.storedSnapshot(defaults: ud, now: d(2026, 1, 30), calendar: cal)
        XCTAssertEqual(s?.isLate, false, "35 j de prévision: le jour 30 n'est pas un retard")
        XCTAssertEqual(s?.daysUntilPeriod, 6)
    }

    // MARK: - Modes et rappels

    func testModesChangeWhatIsShownNotTheCalculation() {
        XCTAssertTrue(CycleMode.conceiving.showsFertileWindow)
        XCTAssertFalse(CycleMode.tracking.showsFertileWindow)
        XCTAssertFalse(CycleMode.contraception.showsFertileWindow)
        XCTAssertFalse(CycleReminderKind.ovulation.isAvailable(in: .contraception))
        XCTAssertTrue(CycleMode.conceiving.categories.contains(.discharge))
        XCTAssertFalse(CycleMode.tracking.categories.contains(.discharge))
        XCTAssertTrue(CycleMode.contraception.categories.contains(.contraception))
    }

    func testReminderPlanRespectsModeToggleAndLateness() {
        let e = period(d(2026, 1, 1)) + period(d(2026, 1, 29)) + period(d(2026, 2, 26))   // 28 j
        let a = analyze(e, today: d(2026, 2, 27))
        let snap = try! XCTUnwrap(a.snapshot)
        let all = CycleReminders.plan(snapshot: snap, prediction: a.prediction, mode: .tracking,
                                      disabled: [], now: d(2026, 2, 27), calendar: cal)
        XCTAssertEqual(Set(all.map(\.kind)), [.period, .pms, .ovulation])
        XCTAssertEqual(all.first { $0.kind == .period }.map { cal.startOfDay(for: $0.date) }, day(2026, 3, 23))

        let contra = CycleReminders.plan(snapshot: snap, prediction: a.prediction, mode: .contraception,
                                         disabled: [], now: d(2026, 2, 27), calendar: cal)
        XCTAssertFalse(contra.contains { $0.kind == .ovulation })

        let off = CycleReminders.plan(snapshot: snap, prediction: a.prediction, mode: .tracking,
                                      disabled: [.pms], now: d(2026, 2, 27), calendar: cal)
        XCTAssertFalse(off.contains { $0.kind == .pms })

        let baby = CycleReminders.plan(snapshot: snap, prediction: a.prediction, mode: .conceiving,
                                       disabled: [], now: d(2026, 2, 27), calendar: cal)
        let fertile = try! XCTUnwrap(baby.first { $0.kind == .ovulation })
        XCTAssertEqual(cal.startOfDay(for: fertile.date), a.prediction.fertileStart)
        XCTAssertTrue(fertile.body.contains("pas une ovulation confirmée"))

        let late = analyze(e, today: d(2026, 3, 30))
        XCTAssertEqual(CycleReminders.plan(snapshot: try! XCTUnwrap(late.snapshot), prediction: late.prediction,
                                           mode: .tracking, disabled: [], now: d(2026, 3, 30), calendar: cal), [])
    }

    func testReminderTogglesRoundTrip() throws {
        let suite = "lot7.cycle.rem.\(UUID().uuidString)"
        let ud = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { ud.removePersistentDomain(forName: suite) }
        XCTAssertEqual(CycleReminderKind.disabled(ud), [])
        CycleReminderKind.store(disabled: [.pms, .ovulation], ud)
        XCTAssertEqual(CycleReminderKind.disabled(ud), [.pms, .ovulation])
        XCTAssertEqual(CycleReminderKind.disabled(defaultsFrom: "pms,ovulation"), [.pms, .ovulation])
    }

    // MARK: - Symptomes

    func testIntensityCodecRoundTripAndDropsUnselected() {
        let codes = CycleIntensityCodec.encode(["Crampes": 3, "Acné": 1, "Fatigue": 2], keeping: ["Crampes", "Acné"])
        XCTAssertEqual(codes, ["Acné=1", "Crampes=3"])
        XCTAssertEqual(CycleIntensityCodec.decode(codes + ["bad", "X=9"]), ["Crampes": 3, "Acné": 1])
    }

    func testExclusiveCategoryKeepsOneAnswer() {
        var draft = CycleDayDraft()
        draft.toggle("Fatigue")
        draft.toggle("En forme")
        XCTAssertEqual(draft.symptoms, ["En forme"])
        draft.toggle("Crampes"); draft.toggle("Maux de tête")
        XCTAssertEqual(draft.symptoms, ["En forme", "Crampes", "Maux de tête"])
    }

    func testLegacySymptomsLandInTheirCategory() {
        for s in ["Crampes", "Maux de tête", "Ballonnements", "Fatigue", "Acné", "Seins sensibles", "Nausées", "Dos douloureux"] {
            XCTAssertNotEqual(CycleSymptomCategory.of(s), .custom, s)
        }
        XCTAssertEqual(CycleSymptomCategory.of("Migraine ophtalmique"), .custom)
        let all = CycleSymptomCategory.allCases.flatMap(\.options)
        XCTAssertEqual(all.count, Set(all).count, "un libellé = un identifiant unique")
    }

    func testCustomTagRules() {
        XCTAssertEqual(try? CycleTags.adding("  Migraine  ", to: []).get(), ["Migraine"])
        XCTAssertEqual(CycleTags.adding("crampes", to: []), .failure(.duplicate), "doublon du catalogue")
        XCTAssertEqual(CycleTags.adding("Migraine", to: ["migraine"]), .failure(.duplicate))
        XCTAssertEqual(CycleTags.adding("   ", to: []), .failure(.empty))
        XCTAssertEqual(CycleTags.adding(String(repeating: "a", count: 41), to: []), .failure(.tooLong))
        XCTAssertEqual(CycleTags.decode(CycleTags.encode(["A", "B=C"])), ["A", "B=C"])
    }

    func testSearchIgnoresAccentsAndFindsNotesAndMonths() {
        let e = CycleEntrySnapshot(date: d(2026, 3, 12), flow: 2, symptoms: ["Maux de tête"], note: "Réunion stressante")
        XCTAssertTrue(CycleInsights.matches(e, query: "maux de tete", calendar: cal))
        XCTAssertTrue(CycleInsights.matches(e, query: "reunion", calendar: cal))
        XCTAssertTrue(CycleInsights.matches(e, query: "mars", calendar: cal))
        XCTAssertTrue(CycleInsights.matches(e, query: "règles", calendar: cal))
        XCTAssertFalse(CycleInsights.matches(e, query: "acné", calendar: cal))
    }

    func testPhaseAssociationIsCountedAndNeedsEnoughDays() {
        // Deux cycles de 28 j. Crampes notees en debut de regles, maux de
        // tete en fin de cycle (phase luteale).
        let starts = [day(2026, 1, 1), day(2026, 1, 29), day(2026, 2, 26)]
        var e: [CycleEntrySnapshot] = []
        for s in starts.prefix(2) {
            e.append(CycleEntrySnapshot(date: s, flow: 3, symptoms: ["Crampes"]))
            e.append(CycleEntrySnapshot(date: cal.date(byAdding: .day, value: 1, to: s)!, flow: 2, symptoms: ["Crampes"]))
            e.append(CycleEntrySnapshot(date: cal.date(byAdding: .day, value: 24, to: s)!, symptoms: ["Maux de tête"]))
        }
        e.append(CycleEntrySnapshot(date: d(2026, 1, 20), symptoms: ["Crampes"]))
        let a = CycleInsights.phaseAssociations(e, starts: starts, fallbackLength: 28, calendar: cal)
        let cramps = try! XCTUnwrap(a.first { $0.symptom == "Crampes" })
        XCTAssertEqual(cramps.phase, .menstrual)
        XCTAssertEqual(cramps.count, 4)
        XCTAssertEqual(cramps.total, 5)
        XCTAssertNil(a.first { $0.symptom == "Maux de tête" }, "2 jours ne suffisent pas pour affirmer")
    }

    func testPhaseIsUnknownBeyondCycleLength() {
        XCTAssertNil(CycleInsights.phase(for: d(2026, 2, 10), starts: [day(2026, 1, 1)], fallbackLength: 28, calendar: cal))
        XCTAssertEqual(CycleInsights.phase(for: d(2026, 1, 25), starts: [day(2026, 1, 1)], fallbackLength: 28, calendar: cal), .luteal)
    }

    func testMonthlyTrendIncludesEmptyMonths() {
        let e = [CycleEntrySnapshot(date: d(2026, 1, 3), symptoms: ["Crampes"]),
                 CycleEntrySnapshot(date: d(2026, 1, 3, 20), symptoms: ["Crampes"]),
                 CycleEntrySnapshot(date: d(2026, 3, 3), symptoms: ["Crampes"])]
        let t = CycleInsights.monthlyTrend(e, symptoms: ["Crampes"], from: d(2026, 1, 1), to: d(2026, 3, 30), calendar: cal)
        XCTAssertEqual(t.map(\.days), [1, 0, 1], "même jour compté une fois, février vide présent")
    }

    // MARK: - Stats: periode et distribution

    func testRangeFilterAndDistribution() {
        let e = period(d(2025, 1, 1)) + period(d(2025, 1, 29))
            + period(d(2026, 1, 1)) + period(d(2026, 1, 29)) + period(d(2026, 2, 26)) + period(d(2026, 3, 27))
        let all = analyze(e, today: d(2026, 4, 1), range: .all)
        let recent = analyze(e, today: d(2026, 4, 1), range: .threeMonths)
        XCTAssertEqual(all.allCycles.count, 4, "l'année d'écart n'est pas un cycle")
        XCTAssertEqual(recent.rangeCycles.map(\.days), [28, 28, 29])
        XCTAssertEqual(recent.distribution, [CycleLengthBin(days: 28, count: 2), CycleLengthBin(days: 29, count: 1)])
        XCTAssertEqual(recent.prediction, all.prediction, "la période filtre l'affichage, pas les prévisions")
    }

    func testInsufficientDataIsNilNotZero() {
        let a = analyze(period(d(2026, 1, 1)), today: d(2026, 1, 10))
        XCTAssertNil(a.rangeSummary)
        XCTAssertTrue(a.distribution.isEmpty)
        XCTAssertEqual(a.prediction.basis, .setting)
    }

    // MARK: - Calendrier

    func testMonthGridStartsOnMonday() {
        // 1er octobre 2026 = jeudi: 3 cases vides avant.
        let cells = CycleCalendarGrid.cells(month: d(2026, 10, 15), calendar: cal)
        XCTAssertEqual(cells.prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertEqual(cells[3].map { cal.component(.day, from: $0) }, 1)
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)
    }

    // MARK: - Export

    func testCSVHasIntensitiesBoundariesAndEscaping() {
        let e = [CycleEntrySnapshot(date: d(2026, 1, 5), flow: 3, symptoms: ["Crampes"], levels: ["Crampes": 3],
                                    mood: 2, note: "Dur; très dur", isStart: true)]
        let csv = CycleReport.csv(e, calendar: cal)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "date;flux;debut_regles;fin_regles;symptomes;humeur;note")
        XCTAssertEqual(lines.last, "2026-01-05;Abondant;oui;;Crampes (fort);Irritable;\"Dur; très dur\"")
    }

    // MARK: - Base: edition d'un jour passe, doublons, suppression

    private func container() throws -> ModelContainer {
        try ModelContainer(for: CycleEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testEditPastDayMergesDuplicatesAndPersistsNewFields() throws {
        let c = try container()
        let ctx = c.mainContext
        // L'ancien ecran pouvait laisser deux entrees le meme jour.
        ctx.insert(CycleEntry(date: d(2026, 1, 5, 8), flow: 1, symptoms: ["Crampes"]))
        ctx.insert(CycleEntry(date: d(2026, 1, 5, 21), flow: 2, symptoms: ["Fatigue"], note: "soir"))
        try ctx.save()

        var draft = try CycleEntryStore.draft(for: d(2026, 1, 5), in: ctx, calendar: cal)
        XCTAssertEqual(draft.flow, 2)
        XCTAssertEqual(draft.symptoms, ["Crampes", "Fatigue"])
        draft.levels["Crampes"] = 3
        draft.isStart = true
        try CycleEntryStore.save(draft, for: d(2026, 1, 5), in: ctx, calendar: cal)

        let rows = try ctx.fetch(FetchDescriptor<CycleEntry>())
        XCTAssertEqual(rows.count, 1, "un seul jour, une seule entrée")
        XCTAssertEqual(rows[0].intensityCodes, ["Crampes=3"])
        XCTAssertTrue(rows[0].isPeriodStart)
        XCTAssertEqual(rows[0].note, "soir")
    }

    func testNewPastEntryIsDatedThatDayAndEmptyDraftDeletes() throws {
        let c = try container()
        let ctx = c.mainContext
        var draft = CycleDayDraft()
        draft.flow = 2
        try CycleEntryStore.save(draft, for: day(2025, 12, 20), in: ctx, calendar: cal)
        let row = try XCTUnwrap(try ctx.fetch(FetchDescriptor<CycleEntry>()).first)
        XCTAssertTrue(cal.isDate(row.date, inSameDayAs: d(2025, 12, 20)))

        try CycleEntryStore.save(CycleDayDraft(), for: day(2025, 12, 20), in: ctx, calendar: cal)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<CycleEntry>()), 0, "un jour vidé ne reste pas en ligne vide")
    }

    /// Acceptance Klue: une entree supprimee disparait de tous les agregats
    /// et de l'export.
    func testDeletedDayLeavesEveryAggregate() throws {
        let c = try container()
        let ctx = c.mainContext
        for s in [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 26)] {
            var dr = CycleDayDraft(); dr.flow = 2; dr.symptoms = ["Crampes"]
            try CycleEntryStore.save(dr, for: s, in: ctx, calendar: cal)
        }
        try CycleEntryStore.delete(day: d(2026, 2, 26), in: ctx, calendar: cal)
        let snaps = try ctx.fetch(FetchDescriptor<CycleEntry>()).map(\.snapshot)
        XCTAssertEqual(CycleInsights.symptomCounts(snaps).first?.1, 2)
        XCTAssertEqual(analyze(snaps, today: d(2026, 3, 1)).allCycles.count, 1)
        XCTAssertFalse(CycleReport.csv(snaps, calendar: cal).contains("2026-02-26"))
    }
}
