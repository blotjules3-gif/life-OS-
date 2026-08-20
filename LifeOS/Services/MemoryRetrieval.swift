import Foundation
import SwiftData

/// Retrieval intelligent des `MemoryEntry` pour injection dans le prompt coach.
///
/// Ranking par score composite :
///   `score = relevance × recency × retentionWeight × confirmationBoost`
///
/// - `relevance` : match keyword sur le message + catégorie (0.0 - 1.0)
/// - `recency` : décroit avec l'âge (< 7j = 1.0, > 6 mois = 0.1)
/// - `retentionWeight` : long > episodic > short > session
/// - `confirmationBoost` : 1 + 0.1 × confirmationCount (max 2.0)
///
/// Résultat : les mémoires les plus pertinentes en tête, budget contrôlé.
@MainActor
enum MemoryRetrieval {

    struct RankedMemory {
        let entry: MemoryEntry
        let score: Double
    }

    /// Sélectionne les `limit` mémoires les plus pertinentes pour le message donné.
    /// Filtres : pinnées d'abord (priorité), puis top score.
    static func retrieve(
        for message: String,
        context: ModelContext,
        limit: Int = 10
    ) -> [RankedMemory] {
        let all = (try? context.fetch(FetchDescriptor<MemoryEntry>())) ?? []
        guard !all.isEmpty else { return [] }

        let queryTokens = tokenize(message)

        let ranked = all.map { entry -> RankedMemory in
            let score = computeScore(entry: entry, queryTokens: queryTokens)
            return RankedMemory(entry: entry, score: score)
        }

        // Pinned toujours en tête, puis top score
        let pinned = ranked.filter { $0.entry.isPinned }.sorted { $0.score > $1.score }
        let unpinned = ranked.filter { !$0.entry.isPinned }.sorted { $0.score > $1.score }

        let combined = pinned + unpinned
        let selected = Array(combined.prefix(limit))

        // Marque les mémoires accédées (pour tracking usage future)
        for m in selected {
            m.entry.lastAccessedAt = .now
        }
        try? context.save()

        return selected
    }

    // MARK: - Scoring

    private static func computeScore(entry: MemoryEntry, queryTokens: Set<String>) -> Double {
        let relevance = computeRelevance(content: entry.content, category: entry.category, queryTokens: queryTokens)
        let recency = computeRecency(created: entry.created)
        let retentionWeight = MemoryRetention(rawValue: entry.retentionType)?.weight ?? 1.0
        let confirmationBoost = min(2.0, 1.0 + Double(entry.confirmationCount) * 0.1)
        return relevance * recency * retentionWeight * confirmationBoost
    }

    private static func computeRelevance(content: String, category: String, queryTokens: Set<String>) -> Double {
        guard !queryTokens.isEmpty else { return 0.5 } // baseline sans query
        let contentTokens = tokenize(content)
        let categoryTokens = tokenize(category)
        let allTokens = contentTokens.union(categoryTokens)
        let intersection = allTokens.intersection(queryTokens)
        guard !allTokens.isEmpty else { return 0.1 }
        let jaccard = Double(intersection.count) / Double(min(allTokens.count, queryTokens.count))
        // Boost si au moins 1 token match (baseline 0.3 pour ne pas exclure sans match)
        return max(0.3, jaccard)
    }

    private static func computeRecency(created: Date) -> Double {
        let daysOld = Date().timeIntervalSince(created) / 86400
        switch daysOld {
        case ..<7:    return 1.0
        case ..<30:   return 0.8
        case ..<90:   return 0.6
        case ..<180:  return 0.4
        default:      return 0.1
        }
    }

    /// Tokenize simple : split + normalization + stopwords fr.
    private static let stopwords: Set<String> = [
        "le", "la", "les", "de", "du", "des", "un", "une", "et", "ou", "à", "au", "aux",
        "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "mon", "ton", "son", "ma", "ta", "sa", "mes", "tes", "ses",
        "c'est", "est", "sont", "avoir", "être", "pas", "ne", "que", "qui", "quoi",
        "pour", "avec", "dans", "sur", "par", "en"
    ]

    private static func tokenize(_ text: String) -> Set<String> {
        let normalized = text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        let raw = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
        return Set(raw)
    }
}
