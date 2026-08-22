import XCTest
import SwiftData
@testable import LifeOS

/// Vérifie que `RecentConversationFetcher.recent` retourne les derniers
/// échanges du chat en ordre chronologique, filtre vides et "thinking".
@MainActor
final class RecentConversationFetcherTests: XCTestCase {

    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([AIMessage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testRecent_emptyContext_returnsEmpty() {
        let msgs = RecentConversationFetcher.recent(context: container.mainContext, pairs: 3)
        XCTAssertTrue(msgs.isEmpty)
    }

    func testRecent_nilContext_returnsEmpty() {
        let msgs = RecentConversationFetcher.recent(context: nil, pairs: 3)
        XCTAssertTrue(msgs.isEmpty)
    }

    func testRecent_ordersChronologically_oldestFirst() {
        insertMessages([
            ("user", "message 1", -60),
            ("assistant", "réponse 1", -55),
            ("user", "message 2", -30),
            ("assistant", "réponse 2", -25),
        ])
        let msgs = RecentConversationFetcher.recent(context: container.mainContext, pairs: 3)
        XCTAssertEqual(msgs.count, 4)
        XCTAssertEqual(msgs[0].content, "message 1")
        XCTAssertEqual(msgs[1].content, "réponse 1")
        XCTAssertEqual(msgs[2].content, "message 2")
        XCTAssertEqual(msgs[3].content, "réponse 2")
    }

    func testRecent_filtersEmptyMessages() {
        insertMessages([
            ("user", "vraie question", -60),
            ("assistant", "", -55),   // vide → filtré
            ("user", "autre question", -30),
        ])
        let msgs = RecentConversationFetcher.recent(context: container.mainContext, pairs: 3)
        XCTAssertEqual(msgs.count, 2)
    }

    func testRecent_filtersThinkingMarker() {
        insertMessages([
            ("user", "salut", -60),
            ("assistant", "…", -55),   // thinking transient → filtré
            ("assistant", "vraie réponse", -50),
        ])
        let msgs = RecentConversationFetcher.recent(context: container.mainContext, pairs: 3)
        XCTAssertEqual(msgs.count, 2)
    }

    func testRecent_capsAtRequestedPairs() {
        var pairs: [(String, String, Int)] = []
        for i in 0..<10 {
            pairs.append(("user", "q\(i)", -100 + i * 2))
            pairs.append(("assistant", "r\(i)", -100 + i * 2 + 1))
        }
        insertMessages(pairs)
        let msgs = RecentConversationFetcher.recent(context: container.mainContext, pairs: 3)
        // 3 paires = 6 messages max
        XCTAssertEqual(msgs.count, 6)
        // Le premier doit être une question dans les 3 dernières paires
        XCTAssertTrue(msgs[0].content.hasPrefix("q"))
    }

    func testRecent_convertsRolesCorrectly() {
        insertMessages([
            ("user", "test", -60),
            ("assistant", "reply", -55),
        ])
        let msgs = RecentConversationFetcher.recent(context: container.mainContext, pairs: 3)
        XCTAssertEqual(msgs[0].role, .user)
        XCTAssertEqual(msgs[1].role, .assistant)
    }

    // MARK: - Helper

    private func insertMessages(_ msgs: [(String, String, Int)]) {
        for (role, text, secondsOffset) in msgs {
            let msg = AIMessage(role: role, text: text)
            msg.date = Date().addingTimeInterval(TimeInterval(secondsOffset))
            container.mainContext.insert(msg)
        }
        try? container.mainContext.save()
    }
}
