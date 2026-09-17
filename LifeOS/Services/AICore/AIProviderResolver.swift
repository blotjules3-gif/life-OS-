import Foundation

/// Résout un `providerID` interne (ex: "openai.gpt") en nom affichable court
/// pour l'UI ("GPT-4o mini"). Utilisé sous chaque bulle coach pour que
/// l'utilisateur sache quelle IA vient de lui répondre.
///
/// Transparence : le user doit voir si Apple Intelligence, Claude, GPT ou
/// le coach local a répondu, sans devoir ouvrir un debug view.
enum AIProviderResolver {

    /// Nom court, en français, prêt à afficher sous une bulle.
    /// Retourne `nil` pour un providerID inconnu (masque la mention plutôt
    /// que d'afficher "inconnu").
    ///
    /// Marqué `@MainActor` pour pouvoir résoudre les providerIDs custom via
    /// `CustomProviderStore.shared` (isolated to MainActor). Tous les callers
    /// UI (SwiftUI Text/Label) tournent déjà sur MainActor donc pas d'impact.
    @MainActor
    static func displayName(for providerID: String?) -> String? {
        guard let providerID, !providerID.isEmpty else { return nil }
        switch providerID {
        case "apple.intelligence.on-device":
            return "Apple Intelligence"
        case "openai.gpt":
            return "GPT-4o mini"
        case "anthropic.claude":
            return "Claude Haiku"
        case "mistral.direct":
            return "Mistral Small"
        case "google.gemini":
            return "Gemini Flash"
        case "openrouter.universal":
            return "OpenRouter"
        case "deepseek.chat":
            return "DeepSeek"
        case "groq.llama":
            return "Groq (Llama)"
        case "xai.grok":
            return "Grok"
        case "local.rules.coach":
            return "Coach local"
        case "none":
            return nil
        default:
            // Providers custom : providerID = "custom.openai.<UUID>" ou
            // "custom.anthropic.<UUID>". On récupère le nom convivial défini
            // par l'user dans le CustomProviderStore.
            if providerID.hasPrefix("custom.") {
                let uuid = String(providerID.split(separator: ".").last ?? "")
                if let uuidObj = UUID(uuidString: uuid),
                   let config = CustomProviderStore.shared.configs.first(where: { $0.id == uuidObj }) {
                    return config.name
                }
                return "Custom"
            }
            return providerID
        }
    }

    /// Icône SF Symbol associée — cohérence visuelle par famille.
    static func iconName(for providerID: String?) -> String {
        guard let providerID else { return "cpu" }
        switch providerID {
        case "apple.intelligence.on-device": return "sparkles"
        case "local.rules.coach":            return "gearshape"
        default:                              return "cloud"
        }
    }
}
