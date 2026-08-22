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

    /// Ordre par défaut — priorité :
    ///   1. Apple Intelligence (100% on-device, gratuit, privé, latence <1s)
    ///   2. Cloud providers dans l'ordre déclaré (chacun requiert une clé
    ///      user stockée via `AIProviderCredentials`, sinon `availability`
    ///      retourne `.invalidCredentials` et le router passe au suivant)
    ///   3. `OnDeviceLLM.respond` bascule sur `LocalCoach` (règles Swift) si
    ///      aucun provider ne répond.
    ///
    /// L'utilisateur peut surcharger via `AIProviderPreference.setPreferred(_:)` —
    /// dans ce cas, le provider choisi passe en tête de la chaîne.
    private var providers: [AIProvider] = [
        AppleIntelligenceProvider(),
        OpenAIProvider(),
        AnthropicProvider(),
        MistralProvider(),
        GeminiProvider(),
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
        bootstrapToolsIfNeeded()
        let requiredCaps = requiredCapabilities(for: request)
        let eligible = providers.filter { $0.capabilities.isSuperset(of: requiredCaps) }

        // Applique la préférence utilisateur : si un provider est marqué
        // préféré ET dans la liste éligible, il passe en tête (le reste
        // conserve son ordre → fallback naturel si le préféré échoue).
        // Match exact sur providerID — évite les bugs silencieux si un ID
        // change (ex: rename "openai.gpt" → "openai.direct").
        let ordered: [AIProvider]
        if let pref = AIProviderPreference.shared.preferred,
           let idx = eligible.firstIndex(where: { $0.id == pref }) {
            var reordered = eligible
            let chosen = reordered.remove(at: idx)
            reordered.insert(chosen, at: 0)
            ordered = reordered
        } else {
            ordered = eligible
        }

        var lastError: AIError = .unavailable(.unknown)
        for provider in ordered {
            // Cost guard — si l'user a défini un cap €/jour et qu'il est atteint,
            // les providers cloud sont skippés (Apple Intelligence + LocalCoach
            // passent toujours). Comportement transparent : le router bascule sur
            // le suivant, l'user voit son coach répondre via un provider gratuit.
            if AICostGuard.isBlocked(providerID: provider.id) {
                lastError = .rateLimited  // sémantique "temporairement indisponible"
                continue
            }
            let avail = provider.availability
            guard avail.isAvailable else {
                if case .unavailable(let reason) = avail {
                    lastError = .unavailable(reason)
                }
                continue
            }
            let response = await provider.complete(request)
            if response.isSuccess {
                // Track cloud usage — transparence coûts pour l'user. Silencieux
                // pour Apple Intelligence / LocalCoach (pricing nil).
                AIProviderUsageTracker.shared.record(
                    providerID: response.providerID,
                    inputTokens: response.inputTokens,
                    outputTokens: response.outputTokens
                )
                // Vérifie si le cap vient d'être franchi → notif unique/jour.
                AICostGuard.checkAndNotifyIfCapReached()
                return response
            }
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
