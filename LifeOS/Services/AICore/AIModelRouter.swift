import Foundation

/// Aiguille une `AIRequest` vers le meilleur provider disponible.
///
/// Stratégie :
/// 1. Filtrer les providers dont les capabilities matchent le besoin de la requête.
/// 2. Filtrer ceux dont l'availability est OK (async check).
/// 3. Trier par préférence utilisateur / coût / latence.
/// 4. Tenter le premier. Si échec runtime, retenter avec le suivant (fallback chain).
///
/// Utilisation :
///   let router = AIModelRouter.shared
///   let response = await router.execute(request)
///
/// Le router NE mémorise PAS l'historique conversationnel — ce n'est pas son rôle.
/// C'est `AIContextManager` qui gère ça et fournit les messages à la requête.
@MainActor
final class AIModelRouter {
    static let shared = AIModelRouter()

    /// Ordre par défaut de préférence — surcharge possible en runtime.
    private var providers: [AIProvider] = [
        AppleIntelligenceProvider()
        // Extensible : MistralProvider(), ClaudeProvider(), OpenAIProvider()
    ]

    /// Vrai si les tools coach ont déjà été enregistrés dans le ToolRegistry.
    /// On boot lazy = pas besoin de toucher au LifeOSApp.onAppear.
    private var toolsBootstrapped = false

    private init() {}

    /// Bootstrap idempotent — enregistre les tools coach au premier appel.
    /// Appelé automatiquement par `execute()`.
    private func bootstrapToolsIfNeeded() {
        guard !toolsBootstrapped else { return }
        CoachToolsBootstrap.registerAll()
        toolsBootstrapped = true
    }

    // MARK: - Registry API

    func register(_ provider: AIProvider) {
        // Insert au début = plus prioritaire
        providers.insert(provider, at: 0)
    }

    /// Retourne les providers actuellement enregistrés (ordre de priorité).
    var registered: [AIProvider] { providers }

    // MARK: - Exécution

    /// Exécute la requête sur le premier provider éligible + disponible.
    /// Si le premier échoue à runtime, tente le suivant (fallback).
    func execute(_ request: AIRequest) async -> AIResponse {
        let requiredCaps = requiredCapabilities(for: request)
        let eligible = providers.filter { $0.capabilities.isSuperset(of: requiredCaps) }

        var lastError: AIError = .unavailable(.unknown)
        for provider in eligible {
            let avail = provider.availability
            guard avail.isAvailable else {
                if case .unavailable(let reason) = avail {
                    lastError = .unavailable(reason)
                }
                continue
            }
            let response = await provider.complete(request)
            if response.isSuccess { return response }
            lastError = response.error ?? .providerError("unknown")
        }

        // Aucun provider n'a réussi. Réponse d'erreur avec le dernier error observé.
        return AIResponse(
            providerID: "none",
            correlationID: request.correlationID,
            duration: 0,
            error: lastError
        )
    }

    /// Détermine les capacités requises minimum pour la requête.
    private func requiredCapabilities(for request: AIRequest) -> AICapabilities {
        var caps: AICapabilities = [.textGeneration]
        if request.responseSchema != nil { caps.insert(.structuredOutput) }
        if !request.tools.isEmpty { caps.insert(.toolCalling) }
        return caps
    }

    // MARK: - Debug / observability

    /// Snapshot de l'état actuel des providers — utilisé par le debug view.
    struct RouterSnapshot {
        let providers: [ProviderInfo]

        struct ProviderInfo {
            let id: String
            let displayName: String
            let capabilities: AICapabilities
            let availability: AIAvailability
        }
    }

    func snapshot() -> RouterSnapshot {
        RouterSnapshot(providers: providers.map { p in
            .init(
                id: p.id,
                displayName: p.displayName,
                capabilities: p.capabilities,
                availability: p.availability
            )
        })
    }
}
