import XCTest
@testable import LifeOS

/// Fix B4 audit : test d'intégration qui vérifie que `AIModelRouter.execute()`
/// appelle bien `AIProviderUsageTracker.record()` après un succès provider.
///
/// Sans ce test, le wire pouvait silencieusement casser lors d'un refactor
/// du router — le compteur d'usage se serait arrêté sans alerter.
///
/// Approche : on injecte un provider factice qui simule un succès avec des
/// tokens I/O connus, on route la requête via `AIModelRouter.shared`, on
/// vérifie que le tracker a bien incrémenté pour le providerID retourné.
@MainActor
final class AIModelRouterUsageWireTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AIProviderUsageTracker.shared.resetAll()
        // Retire la préférence user pour ne pas interférer avec l'ordre.
        AIProviderPreference.shared.clearPreference()
    }

    override func tearDown() {
        AIProviderUsageTracker.shared.resetAll()
        AIProviderPreference.shared.clearPreference()
        super.tearDown()
    }

    /// Enregistre un provider mock en tête, exécute une requête, vérifie
    /// que le tracker a incrémenté avec les tokens remontés par le mock.
    func testRouterExecute_onSuccess_recordsUsage() async {
        let mock = MockCloudProvider(
            id: "openai.gpt",  // même ID qu'un provider tarifé pour que record() ne skip pas
            inputTokens: 1234,
            outputTokens: 567
        )
        AIModelRouter.shared.register(mock)

        let request = AIRequest(
            messages: [.user("test")],
            correlationID: UUID()
        )
        let response = await AIModelRouter.shared.execute(request)

        XCTAssertTrue(response.isSuccess, "Le mock doit répondre avec succès")
        XCTAssertEqual(response.providerID, "openai.gpt")

        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(snap.requestCount, 1, "Le router doit avoir appelé record() une fois")
        XCTAssertEqual(snap.inputTokens, 1234, "Tokens input remontés doivent être enregistrés")
        XCTAssertEqual(snap.outputTokens, 567, "Tokens output remontés doivent être enregistrés")
    }

    /// Un provider en erreur ne doit PAS incrémenter le tracker.
    func testRouterExecute_onError_doesNotRecordUsage() async {
        let mock = MockCloudProvider(id: "openai.gpt", failWith: .rateLimited)
        AIModelRouter.shared.register(mock)

        let request = AIRequest(messages: [.user("test")], correlationID: UUID())
        _ = await AIModelRouter.shared.execute(request)

        let snap = AIProviderUsageTracker.shared.todaySnapshot(providerID: "openai.gpt")
        XCTAssertEqual(snap.requestCount, 0, "Une requête en erreur ne doit rien enregistrer")
    }
}

// MARK: - Mock provider pour tests intégration

/// Provider factice pour tester le wire router → tracker sans faire d'appel
/// réseau. Renvoie un succès (avec tokens configurables) ou une erreur choisie.
private struct MockCloudProvider: AIProvider {
    let id: String
    let displayName = "Mock"
    var capabilities: AICapabilities { [.textGeneration] }
    var availability: AIAvailability { .available }

    var inputTokens: Int?
    var outputTokens: Int?
    var failWith: AIError?

    init(id: String, inputTokens: Int? = nil, outputTokens: Int? = nil, failWith: AIError? = nil) {
        self.id = id
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.failWith = failWith
    }

    func complete(_ request: AIRequest) async -> AIResponse {
        if let err = failWith {
            return AIResponse(
                providerID: id,
                correlationID: request.correlationID,
                duration: 0.01,
                error: err
            )
        }
        return AIResponse(
            text: "mock reply",
            providerID: id,
            correlationID: request.correlationID,
            duration: 0.01,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
