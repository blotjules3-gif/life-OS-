import XCTest
@testable import LifeOS

/// Vérifie que `AICostGuard` bloque les providers cloud une fois le seuil
/// user atteint, tout en laissant passer Apple Intelligence et LocalCoach.
///
/// Loop 6 — kill switch coût quotidien.
@MainActor
final class AICostGuardTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AIProviderUsageTracker.shared.resetAll()
        AICostGuardPreference.shared.reset()
    }

    override func tearDown() {
        AIProviderUsageTracker.shared.resetAll()
        AICostGuardPreference.shared.reset()
        super.tearDown()
    }

    // MARK: - Cap disabled = never blocked

    func testIsBlocked_whenCapDisabled_alwaysFalse() {
        // Cap = 0 → jamais bloqué même avec beaucoup d'usage
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 10_000_000, outputTokens: 10_000_000)
        XCTAssertFalse(AICostGuard.isBlocked(providerID: "openai.gpt"))
        XCTAssertFalse(AICostGuard.isBlocked(providerID: "anthropic.claude"))
    }

    // MARK: - Free providers = never blocked

    func testIsBlocked_appleIntelligence_neverBlocked() {
        AICostGuardPreference.shared.dailyCapEUR = 0.01  // seuil ridiculement bas
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 10_000_000, outputTokens: 10_000_000)
        // Apple Intelligence ne doit JAMAIS être bloqué
        XCTAssertFalse(AICostGuard.isBlocked(providerID: "apple.intelligence.on-device"))
    }

    func testIsBlocked_localCoach_neverBlocked() {
        AICostGuardPreference.shared.dailyCapEUR = 0.01
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 10_000_000, outputTokens: 10_000_000)
        XCTAssertFalse(AICostGuard.isBlocked(providerID: "local.rules.coach"))
    }

    // MARK: - Cap reached = cloud blocked

    func testIsBlocked_whenCapReached_blocksCloudProvider() {
        AICostGuardPreference.shared.dailyCapEUR = 0.10  // seuil 10 centimes
        // Simule un gros usage : 1M input + 1M output OpenAI = $0.15 + $0.60 = $0.75 = ~0.69 EUR
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1_000_000, outputTokens: 1_000_000)
        XCTAssertTrue(AICostGuard.isBlocked(providerID: "openai.gpt"))
        XCTAssertTrue(AICostGuard.isBlocked(providerID: "anthropic.claude"), "Cumul global bloque tous les cloud")
    }

    func testIsBlocked_belowCap_notBlocked() {
        AICostGuardPreference.shared.dailyCapEUR = 5.0  // seuil 5 EUR
        // Petit usage : 1000 in + 200 out = ~0.00027 USD = ~0.0002 EUR
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 200)
        XCTAssertFalse(AICostGuard.isBlocked(providerID: "openai.gpt"))
    }

    // MARK: - Cumul all providers

    func testCumulativeCostEUR_sumsAllCloudProviders() {
        // OpenAI : 1M/1M = 0.75 USD = 0.69 EUR
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1_000_000, outputTokens: 1_000_000)
        // Mistral : 1M/1M = 0.40 USD = 0.368 EUR
        AIProviderUsageTracker.shared.record(providerID: "mistral.direct", inputTokens: 1_000_000, outputTokens: 1_000_000)
        let cumul = AICostGuard.todayCumulativeCostEUR()
        // Attendu ~ (0.75 + 0.40) * 0.92 = 1.058 EUR
        XCTAssertEqual(cumul, 1.058, accuracy: 0.01)
    }

    func testCumulativeCostEUR_noUsage_isZero() {
        XCTAssertEqual(AICostGuard.todayCumulativeCostEUR(), 0)
    }

    // MARK: - Preference

    func testPreference_defaults_areSensible() {
        AICostGuardPreference.shared.reset()
        XCTAssertEqual(AICostGuardPreference.shared.dailyCapEUR, 0)
        XCTAssertFalse(AICostGuardPreference.shared.isEnabled)
    }

    func testPreference_settingCap_enables() {
        AICostGuardPreference.shared.dailyCapEUR = 5.0
        XCTAssertTrue(AICostGuardPreference.shared.isEnabled)
    }

    func testPreference_reset_disables() {
        AICostGuardPreference.shared.dailyCapEUR = 5.0
        AICostGuardPreference.shared.reset()
        XCTAssertFalse(AICostGuardPreference.shared.isEnabled)
    }

    // MARK: - Notification de-dup

    func testCheckAndNotify_alreadyNotifiedToday_noOp() {
        AICostGuardPreference.shared.dailyCapEUR = 0.10
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1_000_000, outputTokens: 1_000_000)

        // Premier check → marque notifié
        AICostGuard.checkAndNotifyIfCapReached()
        let firstNotifDay = AICostGuardPreference.shared.lastNotifiedDay
        XCTAssertEqual(firstNotifDay, AIProviderUsageTracker.today())

        // Second check même jour → doit rester le même (pas de re-notif)
        AICostGuard.checkAndNotifyIfCapReached()
        XCTAssertEqual(AICostGuardPreference.shared.lastNotifiedDay, firstNotifDay)
    }

    func testCheckAndNotify_belowCap_doesNotMarkNotified() {
        AICostGuardPreference.shared.dailyCapEUR = 100.0  // très haut
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 200)
        AICostGuard.checkAndNotifyIfCapReached()
        XCTAssertNil(AICostGuardPreference.shared.lastNotifiedDay)
    }

    func testCheckAndNotify_capDisabled_doesNothing() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1_000_000, outputTokens: 1_000_000)
        AICostGuard.checkAndNotifyIfCapReached()
        XCTAssertNil(AICostGuardPreference.shared.lastNotifiedDay)
    }
}
