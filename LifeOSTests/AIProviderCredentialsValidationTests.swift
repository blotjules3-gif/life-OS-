import XCTest
@testable import LifeOS

/// Vérifie la validation format de `AIProviderCredentials.validate(_:for:)` —
/// ajoutée en Loop 3 audit fix (B4) pour éviter qu'un user colle une clé
/// tronquée ou mise dans le mauvais slot sans feedback immédiat.
///
/// Ne touche PAS au Keychain — teste juste la logique pure de validation.
@MainActor
final class AIProviderCredentialsValidationTests: XCTestCase {

    // MARK: - OpenAI (prefix "sk-", min 40)

    func testOpenAI_validKey_returnsNil() {
        // clé plausible (48 chars, prefix ok)
        let key = "sk-" + String(repeating: "a", count: 45)
        XCTAssertNil(AIProviderCredentials.shared.validate(key, for: .openai))
    }

    func testOpenAI_wrongPrefix_returnsError() {
        let key = "ant-" + String(repeating: "x", count: 45)
        guard let err = AIProviderCredentials.shared.validate(key, for: .openai) else {
            return XCTFail("Erreur attendue pour prefix invalide")
        }
        if case .wrongPrefix(let expected) = err {
            XCTAssertEqual(expected, "sk-")
        } else {
            XCTFail("Type d'erreur inattendu : \(err)")
        }
    }

    func testOpenAI_tooShort_returnsError() {
        let key = "sk-abc"
        guard let err = AIProviderCredentials.shared.validate(key, for: .openai) else {
            return XCTFail("Erreur attendue pour clé courte")
        }
        if case .tooShort(let min) = err {
            XCTAssertEqual(min, 40)
        } else {
            XCTFail("Type d'erreur inattendu : \(err)")
        }
    }

    // MARK: - Anthropic (prefix "sk-ant-", min 40)

    func testAnthropic_validKey_returnsNil() {
        let key = "sk-ant-" + String(repeating: "b", count: 40)
        XCTAssertNil(AIProviderCredentials.shared.validate(key, for: .anthropic))
    }

    /// Régression B4 : ne pas confondre clé OpenAI et Anthropic.
    /// Un user qui colle sa clé OpenAI dans le slot Anthropic doit être averti.
    func testAnthropic_openAIKey_returnsWrongPrefixError() {
        let openaiKey = "sk-" + String(repeating: "a", count: 45)
        guard let err = AIProviderCredentials.shared.validate(openaiKey, for: .anthropic) else {
            return XCTFail("Devrait refuser une clé OpenAI dans le slot Anthropic")
        }
        if case .wrongPrefix(let expected) = err {
            XCTAssertEqual(expected, "sk-ant-")
        } else {
            XCTFail("Type d'erreur inattendu : \(err)")
        }
    }

    // MARK: - Mistral / Gemini (pas de prefix imposé)

    func testMistral_noPrefixRequired_acceptsAnyLongEnoughKey() {
        let key = String(repeating: "m", count: 30)
        XCTAssertNil(AIProviderCredentials.shared.validate(key, for: .mistral))
    }

    func testMistral_tooShort_returnsError() {
        let key = "abc"
        XCTAssertNotNil(AIProviderCredentials.shared.validate(key, for: .mistral))
    }

    // MARK: - Trim whitespace

    func testValidate_trimsWhitespace() {
        let key = "  sk-" + String(repeating: "a", count: 45) + "  "
        XCTAssertNil(AIProviderCredentials.shared.validate(key, for: .openai))
    }

    // MARK: - providerID mapping

    func testProviderID_mapping_matchesConcreteProviders() {
        XCTAssertEqual(AIProviderCredentials.Slot.openai.providerID, "openai.gpt")
        XCTAssertEqual(AIProviderCredentials.Slot.anthropic.providerID, "anthropic.claude")
        XCTAssertEqual(AIProviderCredentials.Slot.mistral.providerID, "mistral.direct")
        XCTAssertEqual(AIProviderCredentials.Slot.gemini.providerID, "google.gemini")

        // Les IDs doivent matcher les .id des providers concrets — sinon le
        // reordering router via AIProviderPreference casse silencieusement.
        XCTAssertEqual(OpenAIProvider().id, AIProviderCredentials.Slot.openai.providerID)
        XCTAssertEqual(AnthropicProvider().id, AIProviderCredentials.Slot.anthropic.providerID)
        XCTAssertEqual(MistralProvider().id, AIProviderCredentials.Slot.mistral.providerID)
        XCTAssertEqual(GeminiProvider().id, AIProviderCredentials.Slot.gemini.providerID)
    }
}
