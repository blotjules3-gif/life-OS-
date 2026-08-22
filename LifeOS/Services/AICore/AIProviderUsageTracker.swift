import Foundation

/// Suit la consommation par provider : nombre de requêtes, tokens I/O,
/// coût estimé — persisté par jour local.
///
/// Pourquoi : quand l'user branche une clé cloud (OpenAI/Claude/Mistral/Gemini),
/// il consomme des tokens facturés. Sans visibilité, une facture surprise en
/// fin de mois est possible. Ce tracker publie les compteurs pour affichage
/// dans l'écran Réglages Coach IA.
///
/// Ne bloque JAMAIS — c'est de la transparence, pas un cap. L'user décide.
///
/// Persistence : UserDefaults keyed par `usage.<providerID>.<yyyy-MM-dd>`.
/// Les entrées de plus de 30 jours sont purgées à chaque `record()` pour
/// éviter la croissance infinie.
@MainActor
final class AIProviderUsageTracker {
    static let shared = AIProviderUsageTracker()

    private init() {}

    // MARK: - Public API

    /// Snapshot d'usage pour un provider à un jour donné.
    struct Snapshot {
        let providerID: String
        let day: String                // "yyyy-MM-dd"
        let requestCount: Int
        let inputTokens: Int
        let outputTokens: Int
        /// Coût estimé en USD, calculé via `pricingUSDPerMillionTokens(for:)`.
        /// Retourne 0 si aucun tarif référencé pour ce provider.
        let estimatedCostUSD: Double
    }

    /// Enregistre une requête réussie. Appelé par AIModelRouter après succès.
    /// Silencieux si le provider n'est pas un cloud tarifé (Apple Intelligence,
    /// LocalCoach → gratuits, pas de suivi).
    func record(providerID: String, inputTokens: Int?, outputTokens: Int?) {
        guard Self.pricing(for: providerID) != nil else { return }

        let day = Self.today()
        let key = storageKey(providerID: providerID, day: day)
        var entry = load(key: key) ?? Entry()
        entry.requestCount += 1
        entry.inputTokens += inputTokens ?? 0
        entry.outputTokens += outputTokens ?? 0
        save(entry: entry, key: key)

        purgeOldEntries()
    }

    /// Retourne le snapshot du jour pour un provider donné.
    func todaySnapshot(providerID: String) -> Snapshot {
        let day = Self.today()
        let entry = load(key: storageKey(providerID: providerID, day: day)) ?? Entry()
        return snapshot(entry: entry, providerID: providerID, day: day)
    }

    /// Retourne les snapshots des N derniers jours (utile pour un graphe).
    func recentSnapshots(providerID: String, days: Int = 7) -> [Snapshot] {
        (0..<days).map { offset in
            let day = Self.day(offset: -offset)
            let entry = load(key: storageKey(providerID: providerID, day: day)) ?? Entry()
            return snapshot(entry: entry, providerID: providerID, day: day)
        }
    }

    /// Vide tous les compteurs (utilisé par DataEraser + debug).
    func resetAll() {
        let all = UserDefaults.standard.dictionaryRepresentation()
        for (k, _) in all where k.hasPrefix(storagePrefix) {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    // MARK: - Pricing (USD par million de tokens, approximatif 2026)

    struct Pricing {
        let inputUSDPerMillion: Double
        let outputUSDPerMillion: Double
    }

    /// Barème approximatif — à revoir périodiquement selon publications
    /// providers. Retourne `nil` pour les providers gratuits (Apple, Local).
    static func pricing(for providerID: String) -> Pricing? {
        switch providerID {
        case "openai.gpt":       return Pricing(inputUSDPerMillion: 0.15,  outputUSDPerMillion: 0.60)
        case "anthropic.claude": return Pricing(inputUSDPerMillion: 1.00,  outputUSDPerMillion: 5.00)
        case "mistral.direct":   return Pricing(inputUSDPerMillion: 0.10,  outputUSDPerMillion: 0.30)
        case "google.gemini":    return Pricing(inputUSDPerMillion: 0.075, outputUSDPerMillion: 0.30)
        default: return nil
        }
    }

    // MARK: - Internals

    /// Entrée persistée par jour (JSON compact dans UserDefaults).
    private struct Entry: Codable {
        var requestCount: Int = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
    }

    private let storagePrefix = "ai.usage."

    private func storageKey(providerID: String, day: String) -> String {
        "\(storagePrefix)\(providerID).\(day)"
    }

    private func load(key: String) -> Entry? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private func save(entry: Entry, key: String) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func snapshot(entry: Entry, providerID: String, day: String) -> Snapshot {
        let cost: Double
        if let p = Self.pricing(for: providerID) {
            cost = Double(entry.inputTokens) / 1_000_000 * p.inputUSDPerMillion
                 + Double(entry.outputTokens) / 1_000_000 * p.outputUSDPerMillion
        } else {
            cost = 0
        }
        return Snapshot(
            providerID: providerID,
            day: day,
            requestCount: entry.requestCount,
            inputTokens: entry.inputTokens,
            outputTokens: entry.outputTokens,
            estimatedCostUSD: cost
        )
    }

    /// Supprime les entrées > 30 jours. Appelé à chaque record() — coût O(N)
    /// négligeable (~quelques centaines de clés max).
    private func purgeOldEntries() {
        let cutoff = Self.day(offset: -30)
        let all = UserDefaults.standard.dictionaryRepresentation()
        for (key, _) in all where key.hasPrefix(storagePrefix) {
            // Extrait "yyyy-MM-dd" en fin de clé.
            guard let dayStart = key.range(of: ".", options: .backwards) else { continue }
            let day = String(key[dayStart.upperBound...])
            if day < cutoff {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Date helpers

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func today() -> String { dayFormatter.string(from: .now) }

    static func day(offset: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
        return dayFormatter.string(from: d)
    }
}
