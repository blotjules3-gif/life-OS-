import XCTest
import SwiftData
@testable import LifeOS

/// Vérifie que `CycleAwareness` calcule la bonne phase du cycle selon le nombre
/// de jours depuis la dernière période.
@MainActor
final class CycleAwarenessTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([ProfileField.self, ProfileFieldRevision.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        ProfileStore.shared.setContext(container.mainContext)
    }

    override func tearDown() async throws {
        for f in ProfileStore.shared.allFields() {
            container.mainContext.delete(f)
        }
        try? container.mainContext.save()
        container = nil
        try await super.tearDown()
    }

    // MARK: - No cycle configuré

    func testSnapshot_noHasCycle_returnsNil() {
        XCTAssertNil(CycleAwareness.currentSnapshot())
    }

    func testSnapshot_hasCycleButNoDate_returnsNil() {
        _ = ProfileStore.shared.upsert("body.hasCycle", value: true, source: .chat, confidence: 0.9)
        XCTAssertNil(CycleAwareness.currentSnapshot())
    }

    // MARK: - Phases

    func testSnapshot_menstrualPhase_day3() {
        setupCycle(daysAgo: 2)  // J1 = jour du start, J3 = 2 jours après
        let snap = CycleAwareness.currentSnapshot()
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.dayInCycle, 3)
        XCTAssertEqual(snap?.phase, .menstrual)
    }

    func testSnapshot_follicularPhase_day10() {
        setupCycle(daysAgo: 9)
        let snap = CycleAwareness.currentSnapshot()
        XCTAssertEqual(snap?.dayInCycle, 10)
        XCTAssertEqual(snap?.phase, .follicular)
    }

    func testSnapshot_ovulatoryPhase_day14() {
        setupCycle(daysAgo: 13)
        let snap = CycleAwareness.currentSnapshot()
        XCTAssertEqual(snap?.dayInCycle, 14)
        XCTAssertEqual(snap?.phase, .ovulatory)
    }

    func testSnapshot_lutealPhase_day22() {
        setupCycle(daysAgo: 21)
        let snap = CycleAwareness.currentSnapshot()
        XCTAssertEqual(snap?.dayInCycle, 22)
        XCTAssertEqual(snap?.phase, .luteal)
    }

    // MARK: - Modulo cycles précédents

    func testSnapshot_moduloWrapsAround_day35DoubleCycle() {
        // Cycle 28j, J35 réel → J7 dans le cycle courant (folliculaire)
        setupCycle(daysAgo: 34)
        let snap = CycleAwareness.currentSnapshot()
        XCTAssertEqual(snap?.dayInCycle, 7)
        XCTAssertEqual(snap?.phase, .follicular)
    }

    // MARK: - Prompt line

    func testPromptLine_menstrualJ2() {
        setupCycle(daysAgo: 1)
        let line = CycleAwareness.promptLine()
        XCTAssertTrue(line.contains("menstruelle"), "Obtenu : \(line)")
        XCTAssertTrue(line.contains("J2"))
    }

    func testPromptLine_noCycle_returnsEmpty() {
        XCTAssertEqual(CycleAwareness.promptLine(), "")
    }

    // MARK: - Helper

    private func setupCycle(daysAgo: Int, cycleLength: Int = 28) {
        _ = ProfileStore.shared.upsert("body.hasCycle", value: true, source: .chat, confidence: 0.9)
        _ = ProfileStore.shared.upsert("cycle.averageLengthDays", value: cycleLength, source: .chat, confidence: 0.9)
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let iso = ISO8601DateFormatter().string(from: start)
        _ = ProfileStore.shared.upsert("cycle.lastPeriodStartDate", value: iso, source: .chat, confidence: 0.9)
    }
}
