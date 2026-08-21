import XCTest
@testable import LifeOS

/// Vérifie que la préférence provider :
///   1. Persiste dans UserDefaults sur setPreferredProviderID
///   2. Renvoie `nil` si jamais définie ou clearPreference
///   3. Match EXACT (pas `contains`) via isPreferred(providerID:)
///
/// Point sensible : Loop 3a stockait un slug custom ("openai") matché via
/// `contains()` — source de bugs silencieux si un providerID était renommé.
/// Loop 3 audit fix : match strict sur providerID complet ("openai.gpt").
@MainActor
final class AIProviderPreferenceTests: XCTestCase {

    private let storageKey = "ai.provider.preference"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    // MARK: - Basic setter / getter

    func testPreferred_isNilByDefault() {
        XCTAssertNil(AIProviderPreference.shared.preferred)
    }

    func testSetPreferredProviderID_persists() {
        AIProviderPreference.shared.setPreferredProviderID("openai.gpt")
        XCTAssertEqual(AIProviderPreference.shared.preferred, "openai.gpt")
    }

    func testClearPreference_removesValue() {
        AIProviderPreference.shared.setPreferredProviderID("anthropic.claude")
        AIProviderPreference.shared.clearPreference()
        XCTAssertNil(AIProviderPreference.shared.preferred)
    }

    // MARK: - isPreferred match STRICT

    func testIsPreferred_exactMatch_returnsTrue() {
        AIProviderPreference.shared.setPreferredProviderID("openai.gpt")
        XCTAssertTrue(AIProviderPreference.shared.isPreferred(providerID: "openai.gpt"))
    }

    func testIsPreferred_differentID_returnsFalse() {
        AIProviderPreference.shared.setPreferredProviderID("openai.gpt")
        XCTAssertFalse(AIProviderPreference.shared.isPreferred(providerID: "anthropic.claude"))
    }

    /// Régression du bug audit Loop 3 : "openai" ne doit PAS matcher "openai.gpt"
    /// via contains(). Match exact uniquement.
    func testIsPreferred_partialMatch_returnsFalse() {
        AIProviderPreference.shared.setPreferredProviderID("openai")
        XCTAssertFalse(
            AIProviderPreference.shared.isPreferred(providerID: "openai.gpt"),
            "Match doit être exact — un slug ancien 'openai' ne doit pas matcher 'openai.gpt'"
        )
    }

    func testIsPreferred_noPreference_returnsFalse() {
        XCTAssertFalse(AIProviderPreference.shared.isPreferred(providerID: "openai.gpt"))
    }
}
