import Foundation
import SwiftData

/// Récupère les derniers échanges du chat coach pour les injecter en tant que
/// `previousMessages` dans `AIContextManager`.
///
/// Pourquoi : sans historique, chaque message = amnésie. L'user tape "et
/// pour ma taille alors ?" → le coach répond à côté car il ne sait pas ce
/// qui a été dit avant.
///
/// Fenêtre : par défaut les 3 derniers échanges (user + assistant = 6 messages
/// max). Suffisant pour la continuité, léger en tokens (~200-500 chars).
///
/// Filtre : ignore les messages "thinking" et vides.
@MainActor
enum RecentConversationFetcher {

    /// Retourne les `pairs` derniers échanges convertis en `AIChatMessage`
    /// prêts pour `AIContextManager.build(previousMessages:)`.
    /// L'ordre est chronologique (plus ancien d'abord) — attendu par le LLM.
    static func recent(context: ModelContext?, pairs: Int = 3) -> [AIChatMessage] {
        guard let context, pairs > 0 else { return [] }

        var descriptor = FetchDescriptor<AIMessage>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = pairs * 2 + 2   // marge pour les thinking filtrés
        let recent = (try? context.fetch(descriptor)) ?? []

        // Ré-inverse en ordre chronologique + filtre les entrées vides
        let filtered = recent
            .reversed()
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { $0.text != "…" }   // marker thinking transient

        // Cap final au dernier N * 2 messages (user + assistant)
        let capped = Array(filtered.suffix(pairs * 2))

        return capped.map { msg -> AIChatMessage in
            let role: AIChatMessage.Role = (msg.role == "user") ? .user : .assistant
            return AIChatMessage(role: role, content: msg.text)
        }
    }
}
