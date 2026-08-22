import XCTest
@testable import LifeOS

/// Vérifie que `AIProviderResolver.displayName(for:)` mappe correctement les
/// `providerID` internes en noms affichables sous les bulles chat.
///
/// Le mapping DOIT rester aligné avec les `.id` déclarés dans les providers
/// concrets — sinon l'user voit "openai.gpt" au lieu de "GPT-4o mini".
final class AIProviderResolverTests: XCTestCase {

    func testDisplayName_appleIntelligence() {
        XCTAssertEqual(
            AIProviderResolver.displayName(for: "apple.intelligence.on-device"),
            "Apple Intelligence"
        )
    }

    func testDisplayName_openai() {
        XCTAssertEqual(AIProviderResolver.displayName(for: "openai.gpt"), "GPT-4o mini")
    }

    func testDisplayName_anthropic() {
        XCTAssertEqual(AIProviderResolver.displayName(for: "anthropic.claude"), "Claude Haiku")
    }

    func testDisplayName_mistral() {
        XCTAssertEqual(AIProviderResolver.displayName(for: "mistral.direct"), "Mistral Small")
    }

    func testDisplayName_gemini() {
        XCTAssertEqual(AIProviderResolver.displayName(for: "google.gemini"), "Gemini Flash")
    }

    func testDisplayName_localRules() {
        XCTAssertEqual(AIProviderResolver.displayName(for: "local.rules.coach"), "Coach local")
    }

    func testDisplayName_nilProviderID_returnsNil() {
        XCTAssertNil(AIProviderResolver.displayName(for: nil))
    }

    func testDisplayName_emptyString_returnsNil() {
        XCTAssertNil(AIProviderResolver.displayName(for: ""))
    }

    func testDisplayName_noneSpecial_returnsNil() {
        XCTAssertNil(AIProviderResolver.displayName(for: "none"))
    }

    /// Régression : si les IDs concrets bougent, ce test casse et pointe le bug.
    @MainActor
    func testMappingAlignedWithConcreteProviderIDs() {
        XCTAssertNotNil(AIProviderResolver.displayName(for: AppleIntelligenceProvider().id))
        XCTAssertNotNil(AIProviderResolver.displayName(for: OpenAIProvider().id))
        XCTAssertNotNil(AIProviderResolver.displayName(for: AnthropicProvider().id))
        XCTAssertNotNil(AIProviderResolver.displayName(for: MistralProvider().id))
        XCTAssertNotNil(AIProviderResolver.displayName(for: GeminiProvider().id))
    }

    func testIconName_appleIntelligence_usesSparkles() {
        XCTAssertEqual(AIProviderResolver.iconName(for: "apple.intelligence.on-device"), "sparkles")
    }

    func testIconName_cloudProviders_useCloudIcon() {
        XCTAssertEqual(AIProviderResolver.iconName(for: "openai.gpt"), "cloud")
        XCTAssertEqual(AIProviderResolver.iconName(for: "anthropic.claude"), "cloud")
    }

    func testIconName_localCoach_usesGear() {
        XCTAssertEqual(AIProviderResolver.iconName(for: "local.rules.coach"), "gearshape")
    }
}
