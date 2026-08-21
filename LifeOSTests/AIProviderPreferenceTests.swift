import XCTest
@testable import LifeOS

/// Vérifie que la préférence provider persiste/reset correctement dans
/// UserDefaults. Le matching côté router (égalité stricte sur providerID)
/// est vérifié indirectement via l'audit code de `AIModelRouter.execute`.
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

    func testPreferred_isNilByDefault() {
        XCTAssertNil(AIProviderPreference.shared.preferred)
    }

    func testSetPreferredProviderID_persists() {
        AIProviderPreference.shared.setPreferredProviderID("openai.gpt")
        XCTAssertEqual(AIProviderPreference.shared.preferred, "openai.gpt")
    }

    func testSetPreferredProviderID_overwritesPreviousValue() {
        AIProviderPreference.shared.setPreferredProviderID("openai.gpt")
        AIProviderPreference.shared.setPreferredProviderID("anthropic.claude")
        XCTAssertEqual(AIProviderPreference.shared.preferred, "anthropic.claude")
    }

    func testClearPreference_removesValue() {
        AIProviderPreference.shared.setPreferredProviderID("anthropic.claude")
        AIProviderPreference.shared.clearPreference()
        XCTAssertNil(AIProviderPreference.shared.preferred)
    }
}
