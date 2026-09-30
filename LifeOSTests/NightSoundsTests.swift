import XCTest
@testable import LifeOS

/// Ecoute nocturne: regroupement des detections en evenements, resume, conservation.
@MainActor
final class NightSoundsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func d(_ s: TimeInterval, _ k: String, _ c: Double = 0.8) -> NightSounds.Detection { .init(time: t0.addingTimeInterval(s), kind: k, confidence: c) }

    /// Ronflement detecte toutes les 2 s pendant 20 s = UN evenement de 20 s.
    func testContinuousSnoringIsOneEvent() {
        let dets = stride(from: 0.0, through: 20, by: 2).map { d($0, "ronflement") }
        let e = NightSounds.events(from: dets)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].duration, 20)
    }

    func testGapSplitsEventsAndKindsStaySeparate() {
        let dets = [d(0, "ronflement"), d(2, "ronflement"), d(30, "ronflement"), d(32, "ronflement"), d(10, "toux", 0.9)]
        let e = NightSounds.events(from: dets)
        XCTAssertEqual(e.filter { $0.kind == "ronflement" }.count, 2, "30 s d'écart : deux épisodes")
        XCTAssertEqual(e.filter { $0.kind == "toux" }.count, 1, "une toux nette, même brève, est gardée")
        XCTAssertEqual(e.map(\.start), e.map(\.start).sorted())
    }

    func testWeakOrTooShortDetectionsAreDropped() {
        XCTAssertTrue(NightSounds.events(from: [d(0, "parole", 0.4), d(1, "parole", 0.5)]).isEmpty, "confiance trop faible")
        XCTAssertTrue(NightSounds.events(from: [d(0, "parole", 0.7)]).isEmpty, "0 s et pas assez sûr")
    }

    func testSummaryCountsAndMinutes() {
        var s = NightSession(start: t0)
        s.events = NightSounds.events(from: stride(from: 0.0, through: 60, by: 2).map { d($0, "ronflement") } + [d(300, "toux", 0.9)])
        let sum = NightSounds.summary(s)
        XCTAssertEqual(sum.first?.kind, "ronflement")
        XCTAssertEqual(sum.first?.minutes ?? 0, 1, accuracy: 0.01)
    }

    func testRetentionDeletesOnlyOldNights() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nights-\(UUID())")
        let store = NightStore(directory: dir)
        var old = NightSession(start: t0); old.end = t0.addingTimeInterval(3600)
        var recent = NightSession(start: t0.addingTimeInterval(20 * 86_400)); recent.end = recent.start.addingTimeInterval(3600)
        try store.save(old); try store.save(recent)
        try FileManager.default.createDirectory(at: store.folder(old), withIntermediateDirectories: true)
        UserDefaults.standard.set(14, forKey: NightStore.keepDaysKey)
        store.purge(now: t0.addingTimeInterval(21 * 86_400))
        XCTAssertEqual(store.sessions.map(\.id), [recent.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(old).path), "les extraits partent avec la nuit")
        XCTAssertEqual(NightStore(directory: dir).sessions.count, 1, "survit à une relance")
        try? FileManager.default.removeItem(at: dir)
    }

    func testAppleLabelsMapToFrenchKinds() {
        XCTAssertEqual(NightSounds.kinds["snoring"], "ronflement")
        XCTAssertEqual(NightSounds.kinds["cough"], "toux")
        XCTAssertNil(NightSounds.kinds["music"], "une musique n'est pas un événement de nuit")
    }
}
