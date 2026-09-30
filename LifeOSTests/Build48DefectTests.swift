import XCTest
import SwiftUI
import SwiftData
@testable import LifeOS

/// Defauts releves par l'audit du build 48 (AUDIT-LIFEOS-BUILD48.md). Chaque test
/// reproduit un defaut precis ; il echouait sur le code du build 48.

// MARK: - 1. Sport : seance en cours isolee, prescription figee

@MainActor
final class GymSessionIsolationTests: XCTestCase {
    typealias S = StrengthProgression
    private var container: ModelContainer!   // un ModelContext ne garde pas son container
    private var ctx: ModelContext!

    override func setUp() async throws {
        let schema = Schema([WorkoutSet.self, TrainingSession.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        ctx = ModelContext(container)
    }
    override func tearDown() async throws { ctx = nil; container = nil }

    private func set(_ ago: TimeInterval, _ ex: String, _ w: Double, _ reps: Int, rpe: Double = 8,
                     session: UUID? = nil, kind: WorkoutSetKind = .work) -> S.LoggedSet {
        .init(date: Date().addingTimeInterval(-ago), exercise: ex, weight: w, reps: reps, rpe: rpe, sessionID: session, kind: kind)
    }
    private let t = S.Target(sets: 3, repLow: 8, repHigh: 10)

    /// Build 48 : une serie loguee aujourd'hui devenait "la derniere seance" et changeait
    /// la charge affichee au milieu de l'entrainement.
    func testPrescriptionIsFrozenWhenTheSessionStarts() throws {
        let done = TrainingSession(title: "Dos", start: Date().addingTimeInterval(-3 * 86_400))
        done.state = "done"; ctx.insert(done)
        for _ in 0..<3 { ctx.insert(WorkoutSet(date: Date().addingTimeInterval(-3 * 86_400), exercise: "Rowing barre", weightKg: 60, reps: 10, rpe: 8, sessionID: done.id)) }
        try ctx.save()
        let history = try ctx.fetch(FetchDescriptor<WorkoutSet>()).map(\.logged)
        let s = try GymSessionService.start(title: "Dos", exercises: ["Rowing barre 3×10"], history: history,
                                            doneSessions: [done.id], in: ctx)
        XCTAssertEqual(GymSessionService.prescriptions(of: s)["Rowing barre"]?.weight, 62.5)
        try GymSessionService.log(exercise: "Rowing barre 3×10", weightText: "62,5", reps: 4, rpe: 10, kind: .work, session: s, in: ctx)
        XCTAssertEqual(GymSessionService.prescriptions(of: s)["Rowing barre"]?.weight, 62.5, "figée, ne bouge pas en cours de séance")
        // Et la seance en cours ne sert pas de base tant qu'elle n'est pas terminee.
        let all = try ctx.fetch(FetchDescriptor<WorkoutSet>()).map(\.logged)
        let next = S.next(exercise: "Rowing barre", target: t, history: S.completed(all, doneSessions: [done.id]))
        XCTAssertEqual(next.weight, 62.5)
    }

    /// Build 48 : deux seances le meme jour etaient fusionnees (regroupement par jour).
    func testTwoSessionsTheSameDayStaySeparate() {
        let morning = UUID(), evening = UUID()
        let h = [set(10 * 3600, "Rowing barre", 80, 10, session: morning), set(10 * 3600 - 60, "Rowing barre", 80, 10, session: morning),
                 set(10 * 3600 - 120, "Rowing barre", 80, 10, session: morning),
                 set(3600, "Rowing barre", 60, 10, session: evening), set(3500, "Rowing barre", 60, 10, session: evening),
                 set(3400, "Rowing barre", 60, 10, session: evening)]
        let p = S.next(exercise: "Rowing barre", target: t, history: h)
        XCTAssertEqual(p.weight, 62.5, "la dernière séance est celle du soir à 60 kg, pas un mélange avec le matin à 80 kg")
    }

    /// Build 48 : une seance interrompue devenait une base de progression.
    func testUnfinishedOrCancelledSessionIsNotABase() {
        let done = UUID(), open = UUID(), cancelled = UUID()
        let h = [set(3 * 86_400, "Rowing barre", 60, 10, session: done), set(3 * 86_400 - 60, "Rowing barre", 60, 10, session: done),
                 set(3 * 86_400 - 120, "Rowing barre", 60, 10, session: done),
                 set(86_400, "Rowing barre", 40, 3, session: cancelled), set(600, "Rowing barre", 40, 2, session: open)]
        let p = S.next(exercise: "Rowing barre", target: t, history: S.completed(h, doneSessions: [done]))
        XCTAssertEqual(p.decision, .increase)
        XCTAssertEqual(p.weight, 62.5)
    }

    func testWarmupAndDropSetsDoNotCount() {
        let id = UUID()
        let h = [set(900, "Rowing barre", 20, 10, rpe: 5, session: id, kind: .warmup),
                 set(800, "Rowing barre", 60, 10, session: id), set(700, "Rowing barre", 60, 10, session: id),
                 set(600, "Rowing barre", 60, 10, session: id),
                 set(500, "Rowing barre", 40, 12, rpe: 9, session: id, kind: .drop)]
        XCTAssertEqual(S.next(exercise: "Rowing barre", target: t, history: h).weight, 62.5)
        XCTAssertEqual(S.weeklyHardSets(h)["Dos"], 3)
    }

    /// Build 48 : l'alerte recuperation excluait TOUT aujourd'hui, donc ne voyait pas
    /// une seance plus tot le meme jour.
    func testRecoverySeesAnEarlierSessionToday() throws {
        let earlier = UUID(), current = UUID()
        // 1 h avant : reste "aujourd'hui" meme si la suite tourne tot le matin.
        let h = [set(3600, "Rowing barre", 60, 10, session: earlier), set(60, "Rowing barre", 60, 10, session: current)]
        let hours = try XCTUnwrap(S.hoursSince(group: "Dos", in: h, excludingSession: current),
                                  "la séance plus tôt dans la journée doit être vue")
        XCTAssertEqual(hours, 1, accuracy: 0.1)
    }

    func testTargetRangesDefaultTargetAndMinIncrement() {
        XCTAssertEqual(S.target(from: "Rowing barre 3×8-12"), .init(sets: 3, repLow: 8, repHigh: 12))
        XCTAssertEqual(S.target(from: "Curl 4 x 10"), .init(sets: 4, repLow: 8, repHigh: 10))
        XCTAssertNil(S.target(from: "Rowing barre"))
        XCTAssertEqual(S.defaultTarget, .init(sets: 3, repLow: 8, repHigh: 12))
        let h = (0..<3).map { set(86_400 - Double($0 * 60), "Rowing barre", 60, 10) }
        XCTAssertEqual(S.next(exercise: "Rowing barre", target: t, history: h, minIncrement: 1.25).weight, 61.5)
    }

    func testPersonalRecordAgainstFinishedHistory() {
        let h = [set(86_400, "Rowing barre", 60, 10)]
        XCTAssertTrue(S.isPersonalRecord(set(0, "Rowing barre", 62.5, 10), history: h))
        XCTAssertFalse(S.isPersonalRecord(set(0, "Rowing barre", 60, 8), history: h))
        XCTAssertFalse(S.isPersonalRecord(set(0, "Rowing barre", 90, 10, kind: .warmup), history: h))
    }
}

// MARK: - 2. Sport : une sauvegarde ratee n'est jamais annoncee comme reussie

@MainActor
final class GymSessionSaveTests: XCTestCase {
    private struct Boom: Error, LocalizedError { var errorDescription: String? { "disque plein" } }
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() async throws {
        let schema = Schema([WorkoutSet.self, TrainingSession.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        ctx = ModelContext(container)
    }
    override func tearDown() async throws { ctx = nil; container = nil }

    private func active() throws -> TrainingSession {
        try GymSessionService.start(title: "Dos", exercises: ["Rowing barre 3×10"], history: [], doneSessions: [], in: ctx)
    }

    /// Build 48 : `try? ctx.save()` puis vibration de succes, quoi qu'il arrive.
    func testFailedSaveThrowsAndKeepsNoGhostSet() throws {
        let s = try active()
        XCTAssertThrowsError(try GymSessionService.log(exercise: "Rowing barre", weightText: "60", reps: 10, rpe: 8, kind: .work,
                                                       session: s, in: ctx, save: { _ in throw Boom() })) { e in
            guard case .saveFailed(let why)? = e as? GymSessionService.GymError else { return XCTFail("\(e)") }
            XCTAssertEqual(why, "disque plein")
        }
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WorkoutSet>()).count, 0, "aucune série fantôme")
    }

    func testButtonAndActionShareTheWeightRule() throws {
        XCTAssertNil(GymSessionService.parseWeight("-5"))
        XCTAssertNil(GymSessionService.parseWeight("abc"))
        XCTAssertNil(GymSessionService.parseWeight("5000"))
        XCTAssertEqual(GymSessionService.parseWeight("62,5"), 62.5)
        let s = try active()
        XCTAssertThrowsError(try GymSessionService.log(exercise: "Rowing barre", weightText: "-5", reps: 10, rpe: 8, kind: .work, session: s, in: ctx)) {
            XCTAssertEqual($0 as? GymSessionService.GymError, .invalidWeight)
        }
    }

    func testFailedFinishLeavesSessionActive() throws {
        let s = try active()
        XCTAssertThrowsError(try GymSessionService.finish(s, in: ctx, save: { _ in throw Boom() }))
        XCTAssertEqual(s.state, "active")
        XCTAssertNil(s.end)
        try GymSessionService.finish(s, in: ctx)
        XCTAssertEqual(s.state, "done")
        XCTAssertThrowsError(try GymSessionService.log(exercise: "Rowing barre", weightText: "60", reps: 10, rpe: 8, kind: .work, session: s, in: ctx)) {
            XCTAssertEqual($0 as? GymSessionService.GymError, .notActive)
        }
    }

    func testCancelCanEraseItsSetsAndNeverCountsAsDone() throws {
        let s = try active()
        try GymSessionService.log(exercise: "Rowing barre", weightText: "60", reps: 10, rpe: 8, kind: .work, session: s, in: ctx)
        let sets = try ctx.fetch(FetchDescriptor<WorkoutSet>())
        try GymSessionService.cancel(s, deleteSets: true, sets: sets, in: ctx)
        XCTAssertEqual(s.state, "cancelled")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WorkoutSet>()).count, 0)
        XCTAssertFalse(GymSessionService.doneIDs([s]).contains(s.id))
    }
}

// MARK: - 3. Opale : la fin d'un blocage ne depend plus de la carte

@MainActor
final class ScreenBlockExpiryTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ScreenBlockExpiryTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    /// Build 48 : l'expiration n'etait appliquee que par la carte Opale (onAppear).
    /// Ici : relance de l'app (nouvelle instance) puis activation, sans aucune carte.
    func testExpiryRunsOnAppActivationAfterRelaunch() {
        ScreenTimeBlocker(defaults: defaults).record(end: Date().addingTimeInterval(-60))
        let relaunched = ScreenTimeBlocker(defaults: defaults)
        XCTAssertNotNil(relaunched.sessionEnd)
        relaunched.appBecameActive()
        XCTAssertNil(relaunched.sessionEnd)
        XCTAssertEqual(defaults.double(forKey: ScreenTimeBlocker.endKey), 0)
    }

    func testRunningBlockIsKept() {
        let b = ScreenTimeBlocker(defaults: defaults)
        b.record(end: Date().addingTimeInterval(600))
        b.appBecameActive()
        XCTAssertNotNil(b.sessionEnd)
    }

    func testAppRootCallsTheActivationHook() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("LifeOS/LifeOSApp.swift"), encoding: .utf8)
        XCTAssertGreaterThanOrEqual(app.components(separatedBy: "ScreenTimeBlocker.shared.appBecameActive()").count - 1, 2,
                                    "lancement a froid ET retour au premier plan")
    }
}

// MARK: - 4. Palette : changer de palette ne reconstruit plus les ecrans

final class PaletteWithoutRebuildTests: XCTestCase {
    /// La MEME valeur Color se resout en couleur ou en gris selon le trait : les vues
    /// deja construites se redessinent, rien n'est reconstruit (navigation et saisies
    /// gardees). Build 48 : les couleurs etaient calculees une fois, d'ou `.id(palette)`.
    func testOneColorValueFollowsTheTrait() {
        let c = UIColor(Theme.fitness)
        let col = c.resolvedColor(with: UITraitCollection { $0.lifeOSNeutralPalette = false })
        let grey = c.resolvedColor(with: UITraitCollection { $0.lifeOSNeutralPalette = true })
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        col.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(max(r, g, b) - min(r, g, b), 0.5)
        grey.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertLessThan(max(r, g, b) - min(r, g, b), 0.01)
    }

    func testRootNoLongerRebuildsTheTree() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("LifeOS/LifeOSApp.swift"), encoding: .utf8)
        XCTAssertFalse(app.contains(".id(appPaletteRaw)"), "plus de reconstruction globale au changement de palette")
        XCTAssertTrue(app.contains(".environment(\\.neutralPalette"))
    }

    /// Une couleur choisie par l'utilisateur est enregistree en couleur, meme si
    /// l'app est en neutre (le gris n'est qu'un affichage).
    func testUserColorIsStoredInColour() {
        XCTAssertEqual(Color(hex: 0xFF5BA0).hexString, "FF5BA0")
    }
}
