import XCTest
import SwiftData
@testable import LifeOS

/// Lot 6, Fitbot : generateur de programme (objectif, frequence, duree, matériel),
/// filtre matériel et exclusions, supersets, application avec apercu et annulation,
/// historique par semaine de programme.

final class FitbotGeneratorTests: XCTestCase {

    private func allExercises(_ w: FitbotGenerator.Week) -> [String] { w.days.flatMap(\.exercises) }

    func testSplitFollowsFrequency() {
        XCTAssertEqual(FitbotSplit.forDays(2), .fullBody)
        XCTAssertEqual(FitbotSplit.forDays(3), .fullBody)
        XCTAssertEqual(FitbotSplit.forDays(4), .upperLower)
        XCTAssertEqual(FitbotSplit.forDays(5), .pushPullLegs)
        XCTAssertEqual(FitbotSplit.forDays(6), .pushPullLegs)
        for n in 2...6 {
            let w = FitbotGenerator.generate(goal: .hypertrophie, daysPerWeek: n, sessionMinutes: 60, equipment: [.gym])
            XCTAssertEqual(w.days.count, 7)
            XCTAssertEqual(w.days.filter { !$0.isRest }.count, n, "\(n) jours d'entraînement")
            XCTAssertEqual(w.days.map(\.weekday), gymWeekOrder, "lundi → dimanche")
            XCTAssertTrue(w.isUsable)
        }
        // Hors bornes : ramene a 2...6.
        XCTAssertEqual(FitbotGenerator.generate(goal: .force, daysPerWeek: 9, sessionMinutes: 60, equipment: [.gym]).daysPerWeek, 6)
    }

    func testGoalSetsTargetReadByTheProgressionEngine() {
        let h = FitbotGenerator.generate(goal: .hypertrophie, daysPerWeek: 3, sessionMinutes: 60, equipment: [.gym])
        let first = try! XCTUnwrap(allExercises(h).first)
        XCTAssertEqual(StrengthProgression.target(from: first), .init(sets: 3, repLow: 8, repHigh: 12))
        let f = FitbotGenerator.generate(goal: .force, daysPerWeek: 3, sessionMinutes: 60, equipment: [.gym])
        XCTAssertEqual(StrengthProgression.target(from: allExercises(f)[0]), .init(sets: 5, repLow: 3, repHigh: 5))
        XCTAssertEqual(FitbotGoal.force.restSeconds, 180)
        XCTAssertEqual(FitbotGoal.endurance.restSeconds, 45)
        // Perte de poids : un bloc cardio du catalogue en fin de seance, sans cible.
        let p = FitbotGenerator.generate(goal: .pertePoids, daysPerWeek: 3, sessionMinutes: 60, equipment: [.gym])
        let last = try! XCTUnwrap(p.days.first { !$0.isRest }?.exercises.last)
        XCTAssertEqual(GymExercises.group(of: last), "Cardio")
    }

    func testSessionLengthDecidesHowManyExercises() {
        XCTAssertLessThan(FitbotGenerator.exerciseCount(minutes: 30, goal: .hypertrophie),
                          FitbotGenerator.exerciseCount(minutes: 90, goal: .hypertrophie))
        XCTAssertLessThan(FitbotGenerator.exerciseCount(minutes: 60, goal: .force),
                          FitbotGenerator.exerciseCount(minutes: 60, goal: .hypertrophie), "repos longs = moins d'exercices")
        let short = FitbotGenerator.generate(goal: .hypertrophie, daysPerWeek: 4, sessionMinutes: 30, equipment: [.gym])
        let long = FitbotGenerator.generate(goal: .hypertrophie, daysPerWeek: 4, sessionMinutes: 90, equipment: [.gym])
        XCTAssertLessThan(allExercises(short).count, allExercises(long).count)
    }

    /// Acceptance du ledger : matériel restreint → aucun exercice impossible.
    func testRestrictedEquipmentNeverProposesAGymOnlyExercise() {
        let w = FitbotGenerator.generate(goal: .hypertrophie, daysPerWeek: 4, sessionMinutes: 60, equipment: [.dumbbells])
        XCTAssertFalse(allExercises(w).isEmpty)
        for ex in allExercises(w) {
            XCTAssertTrue(GymExercises.isAllowed(ex, with: [.dumbbells]), ex)
            XCTAssertNotNil(GymExercises.outsideGym[GymExercises.baseName(ex)], "\(ex) se fait hors salle")
        }
        XCTAssertFalse(allExercises(w).contains { $0.hasPrefix("Squat barre") })
        // Les mollets n'ont que des machines dans le catalogue : signale, pas invente.
        XCTAssertTrue(w.uncoveredGroups.contains("Mollets"))
    }

    func testBodyweightOnlyIsHonestAboutMissingContent() {
        let w = FitbotGenerator.generate(goal: .endurance, daysPerWeek: 3, sessionMinutes: 45, equipment: [.bodyweight])
        XCTAssertTrue(w.uncoveredGroups.contains("Pecs"))
        XCTAssertTrue(w.uncoveredGroups.contains("Dos"))
        for ex in allExercises(w) { XCTAssertTrue(GymExercises.isAllowed(ex, with: [.bodyweight]), ex) }
        // Aucun exercice aux élastiques dans le catalogue : meme resultat que le poids du corps.
        let bands = FitbotGenerator.generate(goal: .endurance, daysPerWeek: 3, sessionMinutes: 45, equipment: [.bands])
        XCTAssertEqual(bands.days, w.days)
    }

    func testExcludedExercisesNeverReappear() {
        let excluded: Set<String> = ["Squat barre", "Développé couché barre", "Tractions pronation"]
        for n in 2...6 {
            let w = FitbotGenerator.generate(goal: .force, daysPerWeek: n, sessionMinutes: 90, equipment: [.gym], excluded: excluded)
            XCTAssertTrue(allExercises(w).allSatisfy { !excluded.contains(GymExercises.baseName($0)) })
        }
        let alts = GymExercises.alternatives(for: "Leg extension 3×10", avoiding: [], equipment: [.gym], excluded: excluded)
        XCTAssertFalse(alts.contains { GymExercises.baseName($0) == "Squat barre" })
        XCTAssertNotEqual(GymExercises.alternative(for: "Leg extension", avoiding: [], excluded: excluded), "Squat barre")
    }

    /// Avant ce lot, le remplacement ignorait le matériel : "Rowing barre" donnait
    /// "Tractions pronation" a quelqu'un qui n'a que des haltères.
    func testSubstitutionKeepsTheMuscleGroupAndRespectsEquipment() {
        XCTAssertEqual(GymExercises.alternative(for: "Rowing barre 3×8-12", avoiding: ["Rowing barre 3×8-12"]),
                       "Tractions pronation 3×8-12", "par défaut (salle) : comme avant")
        XCTAssertEqual(GymExercises.alternative(for: "Rowing barre 3×8-12", avoiding: [], equipment: [.dumbbells]),
                       "Rowing haltère un bras 3×8-12")
        let alts = GymExercises.alternatives(for: "Curl barre EZ 3×10", avoiding: ["Curl marteau 3×10"], equipment: [.dumbbells])
        XCTAssertEqual(alts, ["Curl haltères incliné 3×10"])
        XCTAssertTrue(GymExercises.alternatives(for: "Mollets assis machine", avoiding: [], equipment: [.dumbbells]).isEmpty)
        XCTAssertTrue(GymExercises.isAllowed("Mon exercice maison", with: [.bodyweight]), "libellé libre : non jugé")
    }

    func testEquipmentAndExclusionsRoundTrip() {
        XCTAssertEqual(FitbotEquipment.parse(""), [.gym], "réglage d'avant : salle")
        XCTAssertEqual(FitbotEquipment.parse(FitbotEquipment.serialize([.dumbbells, .bands])), [.dumbbells, .bands])
        XCTAssertEqual(FitbotSettings.parseExcluded(FitbotSettings.serializeExcluded(["A b", "C"])), ["A b", "C"])
    }
}

final class FitbotSupersetTests: XCTestCase {
    private let ex = ["Développé couché barre 3×10", "Rowing barre 3×10", "Curl marteau 3×12", "Dips 3×10"]

    func testPairUnpairAndNoDoublePairing() {
        var pairs = FitbotSupersets.pair(at: 0, exercises: ex, pairs: [])
        XCTAssertEqual(pairs, [["Développé couché barre", "Rowing barre"]])
        XCTAssertEqual(FitbotSupersets.partner(of: ex[1], in: pairs), "Développé couché barre")
        XCTAssertEqual(FitbotSupersets.pair(at: 1, exercises: ex, pairs: pairs), pairs, "déjà en paire")
        XCTAssertEqual(FitbotSupersets.pair(at: 3, exercises: ex, pairs: pairs), pairs, "pas de suivant")
        pairs = FitbotSupersets.pair(at: 2, exercises: ex, pairs: pairs)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(FitbotSupersets.decode(FitbotSupersets.encode(pairs)), pairs, "persisté en JSON")
        XCTAssertEqual(FitbotSupersets.unpair("Dips", pairs: pairs), [["Développé couché barre", "Rowing barre"]])
        XCTAssertEqual(FitbotSupersets.encode([]), "")
    }

    func testRemovingOrSeparatingAnExerciseDropsItsPair() {
        let pairs = FitbotSupersets.pair(at: 0, exercises: ex, pairs: [])
        XCTAssertTrue(FitbotSupersets.prune(pairs, exercises: Array(ex.dropFirst())).isEmpty, "exercice supprimé")
        XCTAssertTrue(FitbotSupersets.prune(pairs, exercises: [ex[0], ex[2], ex[1]]).isEmpty, "plus voisins")
        XCTAssertEqual(FitbotSupersets.prune(pairs, exercises: ex), pairs)
        let renamed = FitbotSupersets.rename(ex[1], to: "Rowing haltère un bras 3×10", pairs: pairs)
        XCTAssertEqual(renamed, [["Développé couché barre", "Rowing haltère un bras"]])
    }
}

final class FitbotHistoryTests: XCTestCase {
    private let cal = FitbotHistory.mondayCalendar
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testWeeksOfAProgrammeCountDoneAgainstPlanned() {
        // Programme cree un mercredi : la semaine 1 commence le lundi, mais une seance
        // faite avant le programme ne compte pas.
        let start = date(2026, 9, 9, 12)           // mercredi
        let done = [date(2026, 9, 8),                // avant le programme
                    date(2026, 9, 10), date(2026, 9, 12),
                    date(2026, 9, 15), date(2026, 9, 16), date(2026, 9, 18),
                    date(2026, 9, 22)]
        let rows = FitbotHistory.weeks(planStart: start, planEnd: nil, planned: 3, doneSessionStarts: done,
                                       now: date(2026, 9, 23), calendar: cal)
        XCTAssertEqual(rows.map(\.index), [1, 2, 3])
        XCTAssertEqual(rows.map(\.done), [2, 3, 1])
        XCTAssertEqual(rows.map(\.planned), [3, 3, 3])
        XCTAssertEqual(cal.component(.weekday, from: rows[0].start), 2, "lundi")
    }

    func testProgrammeEndsWhenTheNextOneStarts() {
        let rows = FitbotHistory.weeks(planStart: date(2026, 9, 7), planEnd: date(2026, 9, 16, 9), planned: 4,
                                       doneSessionStarts: [date(2026, 9, 8), date(2026, 9, 15), date(2026, 9, 17)],
                                       now: date(2026, 10, 1), calendar: cal)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.done), [1, 1], "la séance du 17 appartient au programme suivant")
        XCTAssertTrue(FitbotHistory.weeks(planStart: date(2026, 10, 2), planEnd: nil, planned: 3, doneSessionStarts: [],
                                          now: date(2026, 10, 1), calendar: cal).isEmpty, "programme futur : rien")
    }
}

@MainActor
final class FitbotProgramServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() async throws {
        let schema = Schema([WorkoutSet.self, TrainingSession.self, GymDay.self, GymProgramPlan.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        ctx = ModelContext(container)
    }
    override func tearDown() async throws { ctx = nil; container = nil }

    private struct Boom: Error {}

    private func seedWeek() -> [GymDay] {
        gymWeekOrder.map { w -> GymDay in
            let d = w == 2 ? GymDay(weekday: w, title: "Dos maison", focus: "Rowing barre 4×10 · Curl marteau 3×12")
                           : GymDay(weekday: w, title: "Repos", isRest: true)
            ctx.insert(d); return d
        }
    }
    private func days() throws -> [GymDay] { try ctx.fetch(FetchDescriptor<GymDay>()) }
    private func plans() throws -> [GymProgramPlan] { try ctx.fetch(FetchDescriptor<GymProgramPlan>()) }

    func testApplyWritesIntoTheSameDaysAndUndoRestoresTheOldWeek() throws {
        let original = seedWeek()
        original[0].supersetsJSON = FitbotSupersets.encode([["Rowing barre", "Curl marteau"]])
        try ctx.save()
        let mondayID = original[0].stableID
        let before = FitbotProgramService.snapshot(original)
        let week = FitbotGenerator.generate(goal: .hypertrophie, daysPerWeek: 4, sessionMinutes: 60, equipment: [.gym])

        let plan = try FitbotProgramService.apply(week, days: original, in: ctx)
        XCTAssertEqual(try days().count, 7, "aucun jour en double")
        XCTAssertEqual(FitbotProgramService.snapshot(try days()), week.days)
        XCTAssertEqual(try days().first { $0.weekday == 2 }?.stableID, mondayID, "même identifiant de jour")
        XCTAssertEqual(FitbotProgramService.activePlan(try plans())?.split, FitbotSplit.upperLower.rawValue)
        XCTAssertTrue(FitbotProgramService.latestUndoable(try plans()) === plan)

        try FitbotProgramService.undo(plan, days: try days(), in: ctx)
        XCTAssertEqual(FitbotProgramService.snapshot(try days()), before, "semaine d'avant, supersets compris")
        XCTAssertNil(FitbotProgramService.activePlan(try plans()), "programme annulé : hors historique")
        XCTAssertNil(FitbotProgramService.latestUndoable(try plans()))
        XCTAssertThrowsError(try FitbotProgramService.undo(plan, days: try days(), in: ctx))
    }

    func testFailedSaveLeavesTheWeekUntouched() throws {
        let original = seedWeek(); try ctx.save()
        let before = FitbotProgramService.snapshot(original)
        let week = FitbotGenerator.generate(goal: .force, daysPerWeek: 3, sessionMinutes: 60, equipment: [.gym])
        XCTAssertThrowsError(try FitbotProgramService.apply(week, days: original, in: ctx, save: { _ in throw Boom() }))
        XCTAssertEqual(FitbotProgramService.snapshot(original), before)
        try ctx.save()
        XCTAssertTrue(try plans().isEmpty, "aucun programme fantôme")
    }

    func testUnusableWeekIsRefused() throws {
        let original = seedWeek(); try ctx.save()
        var week = FitbotGenerator.generate(goal: .force, daysPerWeek: 3, sessionMinutes: 60, equipment: [.gym])
        week.days[0].focus = ""
        XCTAssertThrowsError(try FitbotProgramService.apply(week, days: original, in: ctx)) {
            XCTAssertEqual($0 as? FitbotProgramService.ProgramError, .unusable)
        }
    }

    /// Acceptance du ledger : un programme genere se fait en seance, la prochaine
    /// prescription bouge selon l'historique reel, et changer de programme garde les
    /// seances passees.
    func testGeneratedDayRunsAsASessionAndNewProgrammeKeepsThePast() throws {
        let original = seedWeek(); try ctx.save()
        let week = FitbotGenerator.generate(goal: .hypertrophie, daysPerWeek: 3, sessionMinutes: 45, equipment: [.dumbbells])
        try FitbotProgramService.apply(week, days: original, in: ctx)
        let monday = try XCTUnwrap(try days().first { $0.weekday == 2 })
        let list = monday.focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        let first = try XCTUnwrap(list.first)

        let s1 = try GymSessionService.start(day: monday, title: monday.title, exercises: list, history: [],
                                             doneSessions: [], in: ctx, now: Date(timeIntervalSinceNow: -86_400 * 3))
        XCTAssertEqual(GymSessionService.frozenExercises(of: s1), list)
        for _ in 0..<3 {
            try GymSessionService.log(exercise: first, weightText: "20", reps: 12, rpe: 7, kind: .work, session: s1, in: ctx,
                                      now: Date(timeIntervalSinceNow: -86_400 * 3))
        }
        try GymSessionService.finish(s1, in: ctx, now: Date(timeIntervalSinceNow: -86_400 * 3 + 3600))

        let history = try ctx.fetch(FetchDescriptor<WorkoutSet>()).map(\.logged)
        let done = GymSessionService.doneIDs(try ctx.fetch(FetchDescriptor<TrainingSession>()))
        let s2 = try GymSessionService.start(day: monday, title: monday.title, exercises: list, history: history,
                                             doneSessions: done, in: ctx)
        let p = try XCTUnwrap(GymSessionService.prescriptions(of: s2)[GymExercises.baseName(first)])
        XCTAssertEqual(p.decision, .increase)
        XCTAssertGreaterThan(p.weight ?? 0, 20)
        try GymSessionService.cancel(s2, deleteSets: true, sets: [], in: ctx)

        // Nouveau programme : la seance passee garde ses exercices figes et ses series.
        let next = FitbotGenerator.generate(goal: .force, daysPerWeek: 5, sessionMinutes: 60, equipment: [.gym])
        try FitbotProgramService.apply(next, days: try days(), in: ctx)
        XCTAssertEqual(GymSessionService.frozenExercises(of: s1), list)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WorkoutSet>()).count, 3)
        XCTAssertEqual(FitbotProgramService.previousPlans(try plans()).count, 1)
    }
}
