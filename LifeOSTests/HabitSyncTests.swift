import XCTest
import SwiftData
@testable import LifeOS

/// Ordres d'habitude venus des widgets et notifications: identifiant stable,
/// ordre explicite, file durable, application idempotente, jour metier.
@MainActor
final class HabitSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!
    private var dir: URL!

    override func setUp() async throws {
        container = try ModelContainer(for: Schema([Habit.self, HabitCompletion.self]),
                                       configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        ctx = container.mainContext
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("habitops-\(UUID())")
        HabitOps.directoryOverride = dir
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        HabitOps.directoryOverride = nil
        HabitSync.fetchOverride = nil
        LifeOSGroup.defaults?.removeObject(forKey: "widget_pending_toggles")
    }

    private func habit(_ name: String) -> Habit {
        let h = Habit(name: name); ctx.insert(h); try? ctx.save(); return h
    }

    func testDoubleTapIsIdempotent() throws {
        let h = habit("Lecture")
        try HabitOps.enqueue(HabitOp(habitID: h.uid, action: .complete, source: "widget"))
        try HabitOps.enqueue(HabitOp(habitID: h.uid, action: .complete, source: "widget"))
        XCTAssertEqual(HabitSync.drain(ctx), 2)
        XCTAssertEqual(h.completions.count, 1, "deux appuis 'cocher' = coche une fois, jamais decoche")
        XCTAssertTrue(HabitOps.pending().isEmpty, "acquittes apres sauvegarde: \(HabitOps.pending().map { "\($0.op.source):\($0.url.lastPathComponent)" })")
        try HabitOps.enqueue(HabitOp(habitID: h.uid, action: .uncomplete, source: "widget"))
        HabitSync.drain(ctx)
        XCTAssertTrue(h.completions.isEmpty)
    }

    func testSameNameOnlyTouchesTheRightHabit() throws {
        let a = habit("Sport"), b = habit("Sport")
        XCTAssertNotEqual(a.uid, b.uid)
        try HabitOps.enqueue(HabitOp(habitID: b.uid, action: .complete, source: "widget"))
        HabitSync.drain(ctx)
        XCTAssertTrue(a.completions.isEmpty)
        XCTAssertEqual(b.completions.count, 1)
    }

    func testDeletedOrRenamedHabit() throws {
        let h = habit("Yoga")
        let op = HabitOp(habitID: h.uid, action: .complete, source: "widget")
        h.name = "Yoga du matin"          // renommee: le meme identifiant marche
        try HabitOps.enqueue(op)
        HabitSync.drain(ctx)
        XCTAssertEqual(h.completions.count, 1)
        let gone = HabitOp(habitID: "supprimee", action: .complete, source: "widget")
        try HabitOps.enqueue(gone)
        XCTAssertEqual(HabitSync.drain(ctx), 1, "habitude supprimee: ordre acquitte sans rien toucher")
        XCTAssertTrue(HabitOps.pending().isEmpty)
    }

    /// Un appui a 23 h 59, rejoue le lendemain, compte pour le jour du geste.
    func testMidnightReplayKeepsTheBusinessDay() throws {
        let tz = TimeZone(identifier: "Europe/Paris")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let late = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 23, minute: 59))!
        let h = habit("Méditation")
        try HabitOps.enqueue(HabitOp(habitID: h.uid, action: .complete, at: late, timeZone: tz, source: "widget"))
        HabitSync.drain(ctx)
        XCTAssertEqual(HabitOps.businessDay(h.completions[0].date, timeZone: tz), "2026-09-28")
    }

    /// Cent ordres ecrits en meme temps depuis plusieurs taches: aucun perdu.
    func testConcurrentWritesLoseNothing() async throws {
        let id = "h1"
        await withTaskGroup(of: Void.self) { g in
            for i in 0..<100 {
                g.addTask { try? HabitOps.enqueue(HabitOp(habitID: id, action: i % 2 == 0 ? .complete : .uncomplete, source: "widget")) }
            }
        }
        XCTAssertEqual(HabitOps.pending().count, 100)
    }

    func testUnreadableFileIsSetAsideNotReplayedForever() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: dir.appendingPathComponent("1-x.json"))
        XCTAssertTrue(HabitOps.pending().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("1-x.json.bad").path))
    }

    func testOldHabitsGetStableUniqueIDs() {
        let a = habit("A"), b = habit("B")
        a.uid = ""; b.uid = ""
        XCTAssertEqual(HabitSync.ensureIDs(ctx), 2)
        XCTAssertFalse(a.uid.isEmpty); XCTAssertNotEqual(a.uid, b.uid)
        let before = a.uid
        HabitSync.ensureIDs(ctx)
        XCTAssertEqual(a.uid, before, "stable d'un lancement a l'autre")
    }

    func testLegacyNameQueueIsMigratedOnlyWhenUnambiguous() throws {
        let d = try XCTUnwrap(LifeOSGroup.defaults)
        let unique = habit("Eau"), _ = habit("Sport"), _ = habit("Sport")
        d.set([["habitName": "Eau", "timestamp": Date().timeIntervalSince1970],
               ["habitName": "Sport", "timestamp": Date().timeIntervalSince1970]], forKey: "widget_pending_toggles")
        HabitSync.drain(ctx)
        XCTAssertEqual(unique.completions.count, 1)
        let sports = try ctx.fetch(FetchDescriptor<Habit>()).filter { $0.name == "Sport" }
        XCTAssertTrue(sports.allSatisfy { $0.completions.isEmpty }, "nom ambigu: rien touche")
        XCTAssertNil(d.array(forKey: "widget_pending_toggles"))
    }

    func testSnapshotResetsAfterMidnightAndShowsPendingTaps() throws {
        let tz = TimeZone(identifier: "Europe/Paris")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let day1 = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        let snap = HabitSnapshot(day: "2026-09-28", timeZone: tz.identifier, generatedAt: day1,
                                 habits: [.init(id: "a", name: "A", icon: "x", colorHex: 0, done: true)])
        XCTAssertTrue(snap.current(now: day1, timeZone: tz).habits[0].done)
        let day2 = cal.date(byAdding: .day, value: 1, to: day1)!
        XCTAssertFalse(snap.current(now: day2, timeZone: tz).habits[0].done, "nouveau jour: rien de coche")
        let op = HabitOp(habitID: "a", action: .uncomplete, at: day1, timeZone: tz, source: "widget")
        XCTAssertFalse(snap.applying(op).habits[0].done)
    }

    func testPublishSkipsArchivedAndReflectsDoneToday() throws {
        let d = try XCTUnwrap(LifeOSGroup.defaults)
        let a = habit("Active"), b = habit("Archivee")
        b.isArchived = true
        a.completions.append(HabitCompletion(date: Date()))
        try ctx.save()
        HabitSync.publish(ctx)
        let snap = try XCTUnwrap(HabitSnapshot.read(from: d))
        XCTAssertEqual(snap.habits.map(\.name), ["Active"])
        XCTAssertEqual(snap.habits.first?.done, true)
        XCTAssertEqual(snap.habits.first?.id, a.uid)
    }

    // MARK: - Chemins de perte (audit du 29 sept apres le build 42)

    /// Une lecture de la base en erreur n'est pas une base vide: rien n'est acquitte.
    func testFetchErrorKeepsTheQueue() throws {
        let h = habit("Lecture")
        try HabitOps.enqueue(HabitOp(habitID: h.uid, action: .complete, source: "widget"))
        HabitSync.fetchOverride = { _ in throw CocoaError(.fileReadUnknown) }
        XCTAssertEqual(HabitSync.drain(ctx), 0)
        XCTAssertEqual(HabitOps.pending().count, 1, "ordre gardé en file")
        XCTAssertTrue(h.completions.isEmpty)
        HabitSync.fetchOverride = nil
        XCTAssertEqual(HabitSync.drain(ctx), 1, "rejoué une fois la base lisible")
        XCTAssertEqual(h.completions.count, 1)
    }

    func testLegacyQueueIsKeptWhenTheBaseCannotBeRead() throws {
        let d = try XCTUnwrap(LifeOSGroup.defaults)
        _ = habit("Eau")
        d.set([["habitName": "Eau", "timestamp": Date().timeIntervalSince1970]], forKey: "widget_pending_toggles")
        HabitSync.fetchOverride = { _ in throw CocoaError(.fileReadUnknown) }
        HabitSync.migrateLegacyQueue(ctx)
        XCTAssertEqual((d.array(forKey: "widget_pending_toggles") ?? []).count, 1)
    }

    /// Ecriture de l'ordre migre impossible: l'entree reste dans l'ancienne file.
    func testLegacyEntryIsKeptWhenItsOpCannotBeWritten() throws {
        let d = try XCTUnwrap(LifeOSGroup.defaults)
        _ = habit("Eau"); _ = habit("Yoga")
        d.set([["habitName": "Eau", "timestamp": Date().timeIntervalSince1970],
               ["habitName": "Yoga", "timestamp": Date().timeIntervalSince1970]], forKey: "widget_pending_toggles")
        // Un FICHIER a la place du dossier: toute ecriture d'ordre echoue.
        try Data().write(to: dir)
        HabitSync.migrateLegacyQueue(ctx)
        let left = (d.array(forKey: "widget_pending_toggles") as? [[String: Any]] ?? []).compactMap { $0["habitName"] as? String }
        XCTAssertEqual(Set(left), ["Eau", "Yoga"], "rien de perdu")
        try FileManager.default.removeItem(at: dir)
        HabitSync.migrateLegacyQueue(ctx)
        XCTAssertNil(d.array(forKey: "widget_pending_toggles"), "retirées une fois écrites")
        XCTAssertEqual(HabitOps.pending().count, 2)
    }

    /// Cocher puis decocher dans la MEME seconde: l'ordre survit a l'ecriture sur
    /// disque (ISO 8601 ne garde que la seconde, et l'UUID departageait au hasard).
    func testOppositeTapsInTheSameSecondKeepTheirOrder() throws {
        let h = habit("Sport")
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        for _ in 0..<40 {
            try HabitOps.enqueue(HabitOp(habitID: h.uid, action: .complete, at: t, source: "widget"))
            try HabitOps.enqueue(HabitOp(habitID: h.uid, action: .uncomplete, at: t, source: "widget"))
            XCTAssertEqual(HabitOps.pending().map(\.op.action), [.complete, .uncomplete])
            HabitSync.drain(ctx)
            XCTAssertTrue(h.completions.isEmpty, "le dernier geste gagne")
        }
    }

    /// Un ordre ecrit par l'ancienne version (sans champ d'ordre) se relit encore.
    func testVersion1OpStillDecodes() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let v1 = #"{"version":1,"opID":"A","habitID":"h","action":"complete","day":"2026-09-28","timeZone":"Europe/Paris","createdAt":"2026-09-28T10:00:00Z","source":"widget"}"#
        try Data(v1.utf8).write(to: dir.appendingPathComponent("1-A.json"))
        let p = HabitOps.pending()
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.first?.op.order, Int64(p.first!.op.createdAt.timeIntervalSince1970 * 1_000_000))
    }

    /// L'instantane du widget, ecrase par une ecriture concurrente, retrouve les
    /// gestes encore en file au geste suivant.
    func testWidgetSnapshotReappliesEveryPendingTap() throws {
        let d = try XCTUnwrap(LifeOSGroup.defaults)
        let today = HabitOps.businessDay(Date(), timeZone: .current)
        HabitSnapshot(day: today, timeZone: TimeZone.current.identifier, generatedAt: Date(),
                      habits: [.init(id: "a", name: "A", icon: "x", colorHex: 0, done: false),
                               .init(id: "b", name: "B", icon: "x", colorHex: 0, done: false)]).write(to: d)
        try HabitOps.enqueue(HabitOp(habitID: "a", action: .complete, source: "widget"))
        // L'ecriture du geste "a" a ete perdue (course). Geste suivant sur "b":
        try HabitOps.enqueue(HabitOp(habitID: "b", action: .complete, source: "widget"))
        var snap = try XCTUnwrap(HabitSnapshot.read(from: d)).current()
        for (_, op) in HabitOps.pending() where op.day == snap.day { snap = snap.applying(op) }
        XCTAssertEqual(snap.habits.map(\.done), [true, true])
    }
}
