import XCTest
import SwiftData
@testable import LifeOS

@MainActor
final class MemoryExtractorTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([MemoryEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: Extraction — happy paths

    func testExtract_objectif_capturesGoal() {
        let n = MemoryExtractor.extract(from: "Je veux courir 3 fois par semaine", context: context)
        XCTAssertEqual(n, 1)
        let all = fetchAll()
        XCTAssertEqual(all.first?.category, "objectif")
    }

    func testExtract_habitude_capturesRoutine() {
        let n = MemoryExtractor.extract(from: "je fais du sport tous les matins", context: context)
        XCTAssertEqual(n, 1)
        XCTAssertEqual(fetchAll().first?.category, "habitude")
    }

    func testExtract_fait_capturesPersonalInfo() {
        let n = MemoryExtractor.extract(from: "j'habite à Paris depuis 5 ans", context: context)
        XCTAssertEqual(n, 1)
        XCTAssertEqual(fetchAll().first?.category, "fait")
    }

    func testExtract_contrainte_capturesAllergy() {
        let n = MemoryExtractor.extract(from: "je suis allergique aux fruits de mer", context: context)
        XCTAssertEqual(n, 1)
        XCTAssertEqual(fetchAll().first?.category, "contrainte")
    }

    // MARK: Extraction — blacklist / bruit filtré

    func testExtract_blacklistedJurons_ignored() {
        let n = MemoryExtractor.extract(from: "je fais chier tout le monde en ce moment", context: context)
        XCTAssertEqual(n, 0, "les jurons doivent être filtrés")
    }

    func testExtract_blacklistedVague_ignored() {
        let n = MemoryExtractor.extract(from: "j'aime bien ce truc rapide", context: context)
        XCTAssertEqual(n, 0, "les expressions vagues doivent être filtrées")
    }

    // MARK: Extraction — anti-doublon intra-message

    func testExtract_multiPatternSameMessage_dedupes() {
        // "je bosse chez X" match habitude ET fait. On veut UNE seule entrée.
        let n = MemoryExtractor.extract(from: "je bosse chez Google depuis 3 ans", context: context)
        XCTAssertLessThanOrEqual(n, 1, "un même préfixe ne doit pas créer 2 entrées")
    }

    // MARK: Extraction — messages trop courts

    func testExtract_veryShortMessage_returnsZero() {
        let n = MemoryExtractor.extract(from: "hey", context: context)
        XCTAssertEqual(n, 0)
    }

    func testExtract_emptyMessage_returnsZero() {
        let n = MemoryExtractor.extract(from: "", context: context)
        XCTAssertEqual(n, 0)
    }

    // MARK: Upsert — dédup cross-message

    func testExtract_sameGoalTwice_updatesInsteadOfDuplicating() {
        _ = MemoryExtractor.extract(from: "Je veux courir 3 fois par semaine", context: context)
        _ = MemoryExtractor.extract(from: "Je veux courir 3 fois par semaine régulièrement", context: context)
        let all = fetchAll()
        XCTAssertEqual(all.count, 1, "même préfixe → 1 seule entrée (mise à jour)")
    }

    // MARK: topMemories

    func testTopMemories_prefersPinned() {
        let m1 = MemoryEntry(content: "Objectif ancien", category: "objectif", source: "chat", created: Date().addingTimeInterval(-3600), isPinned: true)
        let m2 = MemoryEntry(content: "Fait récent", category: "fait", source: "chat", created: .now, isPinned: false)
        context.insert(m1)
        context.insert(m2)
        try? context.save()

        let top = MemoryExtractor.topMemories(context: context, limit: 10)
        XCTAssertEqual(top.first?.content, "Objectif ancien", "pinnée doit être en tête même si plus ancienne")
    }

    func testTopMemories_limitRespected() {
        for i in 0..<15 {
            context.insert(MemoryEntry(content: "Mémoire \(i)", category: "fait", source: "chat", created: .now, isPinned: false))
        }
        try? context.save()
        let top = MemoryExtractor.topMemories(context: context, limit: 5)
        XCTAssertEqual(top.count, 5)
    }

    // MARK: Helper

    private func fetchAll() -> [MemoryEntry] {
        (try? context.fetch(FetchDescriptor<MemoryEntry>())) ?? []
    }
}
