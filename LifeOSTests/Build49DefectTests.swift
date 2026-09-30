import XCTest
import SwiftData
@testable import LifeOS

/// Defauts releves par l'audit du build 49 (AUDIT-LIFEOS-BUILD49.md). Chaque test
/// reproduit un defaut ; il echouait sur le code du build 49.

@MainActor
final class GymSessionLinkTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() async throws {
        let schema = Schema([WorkoutSet.self, TrainingSession.self, GymDay.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        ctx = ModelContext(container)
    }
    override func tearDown() async throws { ctx = nil; container = nil }

    private func day(_ w: Int, _ title: String, _ focus: String) -> GymDay {
        let d = GymDay(weekday: w, title: title, focus: focus); ctx.insert(d); return d
    }
    private func start(_ d: GymDay, now: Date = .now) throws -> TrainingSession {
        try GymSessionService.start(day: d, title: d.title, exercises: d.focus.split(separator: "·").map(String.init),
                                    history: [], doneSessions: [], in: ctx, now: now)
    }
    private func sessions() throws -> [TrainingSession] { try ctx.fetch(FetchDescriptor<TrainingSession>()) }

    /// Build 49 : la seance active etait retrouvee par TITRE.
    func testSameTitleOnTwoDaysDoesNotShareASession() throws {
        let monday = day(2, "Haut du corps", "Rowing barre 3×10"), thursday = day(5, "Haut du corps", "Dips 3×10")
        let s = try start(monday)
        XCTAssertEqual(GymSessionService.activeSession(for: monday, in: try sessions())?.id, s.id)
        XCTAssertNil(GymSessionService.activeSession(for: thursday, in: try sessions()), "même titre, autre jour : pas la même séance")
    }

    func testRenamingTheDayKeepsItsSession() throws {
        let d = day(2, "Dos", "Rowing barre 3×10")
        let s = try start(d)
        d.title = "Dos + Biceps"
        XCTAssertEqual(GymSessionService.activeSession(for: d, in: try sessions())?.id, s.id)
    }

    /// Build 49 : l'ecran lisait `day.focus` pendant la seance.
    func testEditingTheProgrammeDoesNotChangeTheRunningSession() throws {
        let d = day(2, "Dos", "Rowing barre 3×10 · Curl marteau 3×12")
        let s = try start(d)
        d.focus = "Tractions pronation 4×8"
        XCTAssertEqual(GymSessionService.frozenExercises(of: s), ["Rowing barre 3×10", "Curl marteau 3×12"])
        let frozen = GymSessionService.prescriptions(of: s)
        for label in GymSessionService.frozenExercises(of: s) {
            XCTAssertNotNil(frozen[GymExercises.baseName(label)], "chaque exercice figé a sa prescription")
        }
    }

    func testResumeTheNextDayAfterARestDay() throws {
        let d = day(2, "Dos", "Rowing barre 3×10")
        let yesterday = Date().addingTimeInterval(-86_400)
        let s = try start(d, now: yesterday)
        XCTAssertEqual(GymSessionService.anyActive(try sessions())?.id, s.id, "reprise possible quel que soit le jour")
    }

    /// Build 49 : le repos etait un @State de l'ecran, perdu en quittant.
    func testRestEndIsStoredInTheSession() throws {
        let d = day(2, "Dos", "Rowing barre 3×10")
        let s = try start(d)
        let now = Date()
        try GymSessionService.log(exercise: "Rowing barre", weightText: "20", reps: 10, rpe: 5, kind: .warmup, session: s, restSeconds: 90, in: ctx, now: now)
        XCTAssertNil(s.restEnd, "pas de repos après un échauffement")
        try GymSessionService.log(exercise: "Rowing barre", weightText: "60", reps: 10, rpe: 8, kind: .work, session: s, restSeconds: 90, in: ctx, now: now)
        let fresh = ModelContext(container)
        let reread = try XCTUnwrap(try fresh.fetch(FetchDescriptor<TrainingSession>()).first)
        XCTAssertEqual(try XCTUnwrap(reread.restEnd).timeIntervalSince(now), 90, accuracy: 0.5, "relu depuis un autre contexte : survit à la relance")
        try GymSessionService.skipRest(s, in: ctx)
        XCTAssertNil(s.restEnd)
        try GymSessionService.log(exercise: "Rowing barre", weightText: "60", reps: 10, rpe: 8, kind: .work, session: s, restSeconds: 90, in: ctx)
        try GymSessionService.finish(s, in: ctx)
        XCTAssertNil(s.restEnd, "terminer efface le repos")
    }
}

final class ExerciseLabelTests: XCTestCase {
    /// Build 49 : baseName ne retirait que " N×N", target acceptait plus de formats.
    func testEveryTargetFormatGivesTheSameIdentity() {
        for label in ["Rowing barre 4×10", "Rowing barre 3×8-12", "Rowing barre 3x8–12", "Rowing barre 4 x 10", "Rowing barre 3 × 8 - 12", "Rowing barre"] {
            XCTAssertEqual(GymExercises.baseName(label), "Rowing barre", label)
            XCTAssertEqual(StrengthProgression.normalized(label), "rowing barre", label)
            XCTAssertEqual(GymExercises.group(of: label), "Dos", label)
        }
        XCTAssertEqual(GymExercises.baseName("3×10"), "3×10", "un libellé sans nom reste tel quel")
    }

    func testAlternativeKeepsARangeTarget() {
        let alt = GymExercises.alternative(for: "Rowing barre 3×8-12", avoiding: ["Rowing barre 3×8-12"])
        XCTAssertEqual(alt.map(GymExercises.repsSuffix), " 3×8-12")
    }

    func testTargetAndNameUseTheSameSplit() {
        XCTAssertEqual(StrengthProgression.target(from: "Curl marteau 3 x 8-12"), .init(sets: 3, repLow: 8, repHigh: 12))
        XCTAssertEqual(ExerciseLabel.split("Curl marteau 3 x 8-12").name, "Curl marteau")
    }
}

@MainActor
final class GymDataSafetyTests: XCTestCase {
    private struct Boom: Error {}
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() async throws {
        let schema = Schema([WorkoutSet.self, TrainingSession.self, GymDay.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        ctx = ModelContext(container)
    }
    override func tearDown() async throws { ctx = nil; container = nil }

    /// Build 49 : un echec de suppression faisait `ctx.rollback()`, qui jetait aussi
    /// les autres modifications en attente du contexte partage.
    func testFailedDeleteKeepsOtherPendingChanges() throws {
        let a = try GymSessionService.logStandalone(exercise: "Curl marteau", weightText: "12", reps: 10, in: ctx)
        let b = try GymSessionService.logStandalone(exercise: "Rowing barre", weightText: "60", reps: 10, in: ctx)
        a.reps = 12   // modification en attente, pas encore enregistree
        XCTAssertThrowsError(try GymSessionService.delete(b, in: ctx, save: { _ in throw Boom() }))
        XCTAssertEqual(a.reps, 12, "la modification en attente d'une autre série est gardée")
        XCTAssertTrue(ctx.hasChanges)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WorkoutSet>()).count, 2, "rien n'est supprimé")
    }

    func testSuccessfulDeleteIsSeenByTheSharedContext() throws {
        _ = try GymSessionService.logStandalone(exercise: "Curl marteau", weightText: "12", reps: 10, in: ctx)
        let b = try GymSessionService.logStandalone(exercise: "Rowing barre", weightText: "60", reps: 10, in: ctx)
        try GymSessionService.delete(b, in: ctx)
        let names = try ModelContext(container).fetch(FetchDescriptor<WorkoutSet>()).map(\.exercise)
        XCTAssertEqual(names, ["Curl marteau"])
    }

    func testStandaloneEntryIsCanonicalAndValidated() throws {
        let s = try GymSessionService.logStandalone(exercise: "Rowing barre 3×8-12", weightText: "60,5", reps: 10, in: ctx)
        XCTAssertEqual(s.exercise, "Rowing barre")
        XCTAssertNil(s.sessionID, "entrée autonome validée")
        XCTAssertThrowsError(try GymSessionService.logStandalone(exercise: "  ", weightText: "10", reps: 5, in: ctx))
        XCTAssertThrowsError(try GymSessionService.logStandalone(exercise: "Curl", weightText: "-1", reps: 5, in: ctx))
    }

    func testMigrationGivesHistoricalNamesOneIdentity() throws {
        ctx.insert(WorkoutSet(exercise: "Rowing barre 4×10", weightKg: 60, reps: 10))
        ctx.insert(WorkoutSet(exercise: "Rowing barre", weightKg: 62.5, reps: 8))
        try ctx.save()
        XCTAssertEqual(try GymSessionService.migrateExerciseNames(in: ctx), 1)
        XCTAssertEqual(Set(try ctx.fetch(FetchDescriptor<WorkoutSet>()).map(\.exercise)), ["Rowing barre"])
        XCTAssertEqual(try GymSessionService.migrateExerciseNames(in: ctx), 0, "sans effet la deuxième fois")
    }

    /// Build 49 : GuidedWorkout creait des series sans seance. Plus aucun ecran ne
    /// construit de serie lui-meme : tout passe par GymSessionService.
    func testOnlyTheServiceBuildsSets() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LifeOS")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
        var offenders: [String] = []
        for f in files where !["GymSessionService.swift", "Models_Health.swift"].contains(f.lastPathComponent) {
            let s = try String(contentsOf: f, encoding: .utf8)
            if s.contains("WorkoutSet(") { offenders.append(f.lastPathComponent) }
        }
        XCTAssertGreaterThan(files.count, 100)
        XCTAssertEqual(offenders, [], "séries construites hors du service")
    }
}

final class WidgetDataTests: XCTestCase {
    private let suite = "WidgetDataTests"

    /// Le widget d'eau lisait une autre cle que celle ecrite, le widget de jeune une
    /// cle que rien n'ecrivait, et le lancement semait des valeurs inventees.
    func testWidgetsReadTheSharedKeysAndHaveNoInventedValues() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let w = { (f: String) in try String(contentsOf: root.appendingPathComponent("LifeOSWidgets/\(f)"), encoding: .utf8) }
        let hydration = try w("HydrationWidget.swift"), fasting = try w("FastingWidget.swift"), gym = try w("GymFocusWidget.swift")
        XCTAssertTrue(hydration.contains("WidgetKeys.waterToday"))
        XCTAssertFalse(hydration.contains("1800"))
        XCTAssertTrue(fasting.contains("WidgetKeys.fastStart"))
        XCTAssertFalse(fasting.contains("14.5 * 3600"))
        XCTAssertFalse(gym.contains("Pectoraux & Triceps"))
        let main = try String(contentsOf: root.appendingPathComponent("LifeOS/Core/MainTabView.swift"), encoding: .utf8)
        XCTAssertFalse(main.contains("defaults.set(1800"), "plus de valeur inventée au lancement")
    }

    func testSnapshotPublishesTodaysRealValues() throws {
        let settings = try XCTUnwrap(UserDefaults(suiteName: suite))
        settings.removePersistentDomain(forName: suite)
        settings.set(3000, forKey: AppStorageKeys.waterGoal)
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let weekday = Calendar.current.component(.weekday, from: now)
        let v = WidgetDataSyncer.snapshot(waters: [(now, 250), (now, 500), (yesterday, 1000)],
                                          activeFastStart: nil,
                                          gymDays: [(weekday, "Dos", "Rowing barre 3×10", false)],
                                          settings: settings, now: now)
        XCTAssertEqual(v[WidgetKeys.waterToday] as? Int, 750)
        XCTAssertEqual(v[WidgetKeys.waterGoal] as? Int, 3000)
        XCTAssertEqual(v[WidgetKeys.fastStart] as? Double, 0, "pas de jeûne en cours")
        XCTAssertEqual(v[WidgetKeys.gymTitle] as? String, "Dos")
        XCTAssertEqual(WidgetKeys.waterForToday(value: 750, day: WidgetKeys.dayStamp(yesterday), now: now), 0, "valeur d'hier = 0")
        settings.removePersistentDomain(forName: suite)
    }
}
