import XCTest
@testable import LifeOS

/// Vérifie que `AIProviderUsageTracker` :
///   1. Enregistre correctement les requêtes cloud + tokens I/O
///   2. Skip silencieusement les providers gratuits (Apple, Local)
///   3. Skip les requêtes avec tokens manquants (fix B3 audit — ne pas
///      afficher $0 pour un appel qui a réellement coûté)
///   4. Calcule un coût USD cohérent avec le barème (test formule, pas valeur)
///   5. Cap sanitaire sur tokens absurdes (fix M5 audit)
///   6. Accumule sur la même journée, distingue par (provider, jour)
///   7. Snapshot mensuel = somme des 30 derniers jours (fix T2 audit)
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

    /// Fix B3 audit : tokens manquants → skip la requête ENTIÈRE. Sinon on
    /// afficherait "$0 pour 1 requête" alors que le vrai coût est non-nul.
    func testRecord_nilTokens_skipsEntireRequest() {
        AIProviderUsageTracker.shared.record(providerID: "mistral.direct", inputTokens: nil, outputTokens: nil)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "mistral.direct")
        XCTAssertEqual(snap.requestCount, 0, "Une requête sans tokens ne doit pas être comptée comme 'gratuite'")
    }

    func testRecord_onlyInputTokensMissing_skipsRequest() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: nil, outputTokens: 100)
        XCTAssertEqual(AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt").requestCount, 0)
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

    // MARK: - Cost — test FORMULE pas valeur (M1 audit fix)

    func testCost_formula_matchesPricingCatalog() {
        // 1M input + 1M output — coût = pricing.input + pricing.output
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1_000_000, outputTokens: 1_000_000)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        guard let p = AIProviderUsageTracker.pricing(for: "openai.gpt") else { return XCTFail("pricing manquant") }
        XCTAssertEqual(snap.estimatedCostUSD, p.inputUSDPerMillion + p.outputUSDPerMillion, accuracy: 0.0001)
    }

    /// Vérifie que 0 tokens = 0 coût, indépendamment du barème.
    func testCost_zeroTokens_isZero() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 0, outputTokens: 0)
        XCTAssertEqual(AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt").estimatedCostUSD, 0)
    }

    // MARK: - Cap sanitaire (M5 audit fix)

    func testRecord_absurdlyLargeTokens_areCapped() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: Int.max, outputTokens: Int.max)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(snap.inputTokens, 10_000_000, "Cap sanitaire à 10M pour éviter chiffres absurdes")
        XCTAssertEqual(snap.outputTokens, 10_000_000)
    }

    func testRecord_negativeTokens_areClampedToZero() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: -100, outputTokens: -50)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(snap.inputTokens, 0)
        XCTAssertEqual(snap.outputTokens, 0)
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

    /// Fix m6 audit : Anthropic Haiku 4.5 corrigé à $0.80/$4.
    func testPricing_anthropic_reflectsCorrectedRates() {
        guard let p = AIProviderUsageTracker.pricing(for: "anthropic.claude") else { return XCTFail() }
        XCTAssertEqual(p.inputUSDPerMillion, 0.80, accuracy: 0.001)
        XCTAssertEqual(p.outputUSDPerMillion, 4.00, accuracy: 0.001)
    }

    func testPricingCatalogVersion_isDefinedAndNonEmpty() {
        XCTAssertFalse(AIProviderUsageTracker.pricingCatalogVersion.isEmpty)
    }

    // MARK: - Conversion EUR (B2 audit fix)

    func testUsdToEUR_appliesRate() {
        XCTAssertEqual(AIProviderUsageTracker.usdToEUR(1.0), 0.92, accuracy: 0.001)
        XCTAssertEqual(AIProviderUsageTracker.usdToEUR(0.0), 0)
        XCTAssertEqual(AIProviderUsageTracker.usdToEUR(10.0), 9.2, accuracy: 0.001)
    }

    // MARK: - Formatter

    func testFormatter_microCost_showsThreshold() {
        // 0.0001 USD ≈ 0.0000092 EUR → doit afficher "< 0,01 €"
        XCTAssertEqual(UsageFormatter.costEUR(usd: 0.0001), "< 0,01 €")
    }

    func testFormatter_zeroCost_isZeroEUR() {
        XCTAssertTrue(UsageFormatter.costEUR(usd: 0).contains("0,00"))
    }

    func testFormatter_normalCost_formatsAsEUR() {
        // 1 USD → 0.92 EUR
        let s = UsageFormatter.costEUR(usd: 1.0)
        XCTAssertTrue(s.contains("0,92"), "Attendu format EUR '0,92 €', obtenu : \(s)")
    }

    func testFormatter_requestCount_pluralization() {
        XCTAssertEqual(UsageFormatter.requestCount(0), "0 requête")
        XCTAssertEqual(UsageFormatter.requestCount(1), "1 requête")
        XCTAssertEqual(UsageFormatter.requestCount(2), "2 requêtes")
        XCTAssertEqual(UsageFormatter.requestCount(100), "100 requêtes")
    }

    func testFormatter_averageTokens_compactsThousands() {
        XCTAssertEqual(UsageFormatter.averageTokens(500), "500 tok/req")
        XCTAssertEqual(UsageFormatter.averageTokens(1500), "1.5k tok/req")
    }

    // MARK: - Snapshot mensuel (T2 audit)

    func testMonthlySnapshot_sumsLast30Days() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 200)
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 500, outputTokens: 100)
        let month = AIProviderUsageTracker.shared.monthlySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(month.requestCount, 2)
        XCTAssertEqual(month.inputTokens, 1500)
        XCTAssertEqual(month.outputTokens, 300)
    }

    func testMonthlySnapshot_noActivity_isZero() {
        let month = AIProviderUsageTracker.shared.monthlySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(month.requestCount, 0)
        XCTAssertEqual(month.estimatedCostUSD, 0)
    }

    // MARK: - Average tokens per request (T3 audit)

    func testAverageTokensPerRequest_computedCorrectly() {
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 1000, outputTokens: 500)
        AIProviderUsageTracker.shared.record(providerID: "openai.gpt", inputTokens: 2000, outputTokens: 500)
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        // (1000+500 + 2000+500) / 2 = 2000
        XCTAssertEqual(snap.averageTokensPerRequest, 2000)
    }

    func testAverageTokensPerRequest_noRequests_isZero() {
        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(snap.averageTokensPerRequest, 0)
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
