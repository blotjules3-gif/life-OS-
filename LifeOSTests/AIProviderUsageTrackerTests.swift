import XCTest
@testable import LifeOS

/// Vérifie que `AIProviderUsageTracker` :
///   1. Enregistre correctement les requêtes cloud + tokens I/O
///   2. Skip silencieusement les providers gratuits (Apple, Local)
///   3. Calcule un coût USD cohérent avec le barème
///   4. Accumule sur la même journée, distingue par (provider, jour)
@MainActor
final class AIProviderUsageTrackerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AIProviderUsageTracker.shared.resetAll()
    }

    override func tearDown() {
        AIProviderUsageTracker.shared.resetAll()
        super.tearDown()
    }

    // MARK: - Recording

    func testRecord_cloudProvider_incrementsCounters() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 200)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(snap.requestCount, 1)
        XCTAssertEqual(snap.inputTokens, 1000)
        XCTAssertEqual(snap.outputTokens, 200)
    }

    func testRecord_multipleRequests_accumulates() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 500, outputTokens: 100)
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 800, outputTokens: 150)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(snap.requestCount, 2)
        XCTAssertEqual(snap.inputTokens, 1300)
        XCTAssertEqual(snap.outputTokens, 250)
    }

    /// Providers gratuits ne doivent pas polluer le tracker (silent skip).
    func testRecord_appleIntelligence_isSilent() {
        AIProviderUsageTracker.shared.record(providerID: "apple.intelligence.on-device", inputTokens: 500, outputTokens: 100)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "apple.intelligence.on-device")
        XCTAssertEqual(snap.requestCount, 0)
        XCTAssertEqual(snap.estimatedCostUSD, 0)
    }

    func testRecord_localCoach_isSilent() {
        AIProviderUsageTracker.shared.record(providerID: "local.rules.coach", inputTokens: 500, outputTokens: 100)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "local.rules.coach")
        XCTAssertEqual(snap.requestCount, 0)
    }

    func testRecord_nilTokens_stillIncrementsRequestCount() {
        AIProviderUsageTracker.shared.record(providerID: "mistral.direct", inputTokens: nil, outputTokens: nil)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "mistral.direct")
        XCTAssertEqual(snap.requestCount, 1)
        XCTAssertEqual(snap.inputTokens, 0)
        XCTAssertEqual(snap.outputTokens, 0)
    }

    // MARK: - Isolation par provider

    func testRecord_differentProviders_areIsolated() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 200)
        AIProviderUsageTracker.shared.record(providerID: "anthropic.claude", inputTokens: 500, outputTokens: 100)
        let openai = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        let anthropic = AIProviderUsageTracker.shared.todaySnapshot(providerID: "anthropic.claude")
        XCTAssertEqual(openai.requestCount, 1)
        XCTAssertEqual(openai.inputTokens, 1000)
        XCTAssertEqual(anthropic.requestCount, 1)
        XCTAssertEqual(anthropic.inputTokens, 500)
    }

    // MARK: - Cost calculation

    /// GPT-4o mini : $0.15/M input, $0.60/M output.
    /// 1M input + 1M output = $0.15 + $0.60 = $0.75
    func testCost_openai_matchesPricing() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1_000_000, outputTokens: 1_000_000)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(snap.estimatedCostUSD, 0.75, accuracy: 0.001)
    }

    func testCost_smallUsage_isNegligibleButNonZero() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 200)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        // 1000/1M * 0.15 + 200/1M * 0.60 = 0.00015 + 0.00012 = 0.00027
        XCTAssertEqual(snap.estimatedCostUSD, 0.00027, accuracy: 0.00001)
    }

    // MARK: - Reset

    func testResetAll_clearsAllCounters() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 200)
        AIProviderUsageTracker.shared.record(providerID: "mistral.direct", inputTokens: 500, outputTokens: 100)
        AIProviderUsageTracker.shared.resetAll()
        XCTAssertEqual(AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt").requestCount, 0)
        XCTAssertEqual(AIProviderUsageTracker.shared.todaySnapshot(providerID: "mistral.direct").requestCount, 0)
    }

    // MARK: - Pricing catalogue

    func testPricing_allCloudProviders_haveEntries() {
        XCTAssertNotNil(AIProviderUsageTracker.pricing(for: "openai.gpt"))
        XCTAssertNotNil(AIProviderUsageTracker.pricing(for: "anthropic.claude"))
        XCTAssertNotNil(AIProviderUsageTracker.pricing(for: "mistral.direct"))
        XCTAssertNotNil(AIProviderUsageTracker.pricing(for: "google.gemini"))
    }

    func testPricing_freeProviders_haveNoEntry() {
        XCTAssertNil(AIProviderUsageTracker.pricing(for: "apple.intelligence.on-device"))
        XCTAssertNil(AIProviderUsageTracker.pricing(for: "local.rules.coach"))
    }

    func testPricing_unknownProvider_returnsNil() {
        XCTAssertNil(AIProviderUsageTracker.pricing(for: "some.unknown.provider"))
    }

    // MARK: - Snapshot recent

    func testRecentSnapshots_returnsRequestedDays() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 200)
        let snaps = AIProviderUsageTracker.shared.recentSnapshots(providerID: "openai.gpt", days: 7)
        XCTAssertEqual(snaps.count, 7)
        // Le premier est aujourd'hui (contient les données)
        XCTAssertEqual(snaps[0].requestCount, 1)
        // Les 6 autres sont vides
        XCTAssertTrue(snaps.dropFirst().allSatisfy { $0.requestCount == 0 })
    }
}
