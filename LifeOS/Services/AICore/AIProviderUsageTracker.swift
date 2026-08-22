import Combine
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
/// Purge des entrées > 30 jours au boot (via `purgeOldEntriesIfNeeded`) — pas
/// à chaque record pour éviter O(N) à chaque appel.
///
/// **Timezone** : les jours sont calculés en `TimeZone.current` — cohérent
/// avec la perception user. Un voyage transocéanique peut créer un "jour à
/// cheval" mais c'est acceptable (compteur reste correct globalement).
@MainActor
final class AIProviderUsageTracker: ObservableObject {
    static let shared = AIProviderUsageTracker()

    /// Publier changement à chaque record() → refresh live des vues qui
    /// observent le singleton (M6 audit fix).
    @Published private(set) var lastChange: Date = .now

    private init() {
        purgeOldEntriesIfNeeded()
    }

    // MARK: - Public API

    /// Snapshot d'usage pour un provider à un jour donné.
    struct Snapshot {
        let providerID: String
        let day: String                // "yyyy-MM-dd"
        let requestCount: Int
        let inputTokens: Int
        let outputTokens: Int
        /// Coût estimé en USD, calculé via `pricing(for:)`.
        let estimatedCostUSD: Double

        /// Moyenne (in+out) tokens par requête. Retourne 0 si aucune requête.
        var averageTokensPerRequest: Int {
            requestCount > 0 ? (inputTokens + outputTokens) / requestCount : 0
        }
    }

    /// Enregistre une requête réussie. Appelé par AIModelRouter après succès.
    /// - Skip silencieux si provider non tarifé (Apple Intelligence, LocalCoach).
    /// - Skip **avec log** si tokens manquants (fix B3 audit — ne pas
    ///   incrémenter un compteur qui prétend coût nul alors qu'il y a eu appel).
    /// - Cap sanitaire `min(tokens, 10M)` (fix M5 audit — protection contre
    ///   provider bugué qui renverrait un chiffre absurde).
    func record(providerID: String, inputTokens: Int?, outputTokens: Int?) {
        guard Self.pricing(for: providerID) != nil else { return }

        // Fix B3 : tokens manquants → skip enregistrement (ne PAS afficher $0
        // pour un appel qui a bien coûté). Log pour observabilité.
        guard let input = inputTokens, let output = outputTokens else {
            AppLog.coach.warning("AIProviderUsageTracker: tokens manquants pour \(providerID, privacy: .public) — requête non enregistrée (facture invisible)")
            return
        }

        // Fix M5 : cap raisonnable pour éviter Int.max malicieux.
        let cappedIn = min(max(input, 0), 10_000_000)
        let cappedOut = min(max(output, 0), 10_000_000)

        let day = Self.today()
        let key = storageKey(providerID: providerID, day: day)
        var entry = load(key: key) ?? Entry()
        entry.requestCount += 1
        entry.inputTokens += cappedIn
        entry.outputTokens += cappedOut
        save(entry: entry, key: key)

        lastChange = .now  // publie pour observers SwiftUI
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

    /// Somme cumulée sur les 30 derniers jours pour un provider — proxy
    /// raisonnable de la facture mensuelle (T2 audit fix).
    func monthlySnapshot(providerID: String) -> Snapshot {
        let snaps = recentSnapshots(providerID: providerID, days: 30)
        let totalReq = snaps.reduce(0) { $0 + $1.requestCount }
        let totalIn = snaps.reduce(0) { $0 + $1.inputTokens }
        let totalOut = snaps.reduce(0) { $0 + $1.outputTokens }
        let totalCost = snaps.reduce(0.0) { $0 + $1.estimatedCostUSD }
        return Snapshot(
            providerID: providerID,
            day: "30j",
            requestCount: totalReq,
            inputTokens: totalIn,
            outputTokens: totalOut,
            estimatedCostUSD: totalCost
        )
    }

    /// Vide tous les compteurs (utilisé par DataEraser + debug).
    func resetAll() {
        let all = UserDefaults.standard.dictionaryRepresentation()
        for (k, _) in all where k.hasPrefix(storagePrefix) {
            UserDefaults.standard.removeObject(forKey: k)
        }
        UserDefaults.standard.removeObject(forKey: lastPurgeKey)
        lastChange = .now
    }

    // MARK: - Pricing (barème versionné, cf. B1 audit)

    /// Version du barème — incrémenter à chaque révision. Affiché à l'user
    /// dans l'écran Réglages pour transparence.
    static let pricingCatalogVersion = "2026-08"

    struct Pricing {
        let inputUSDPerMillion: Double
        let outputUSDPerMillion: Double
    }

    /// Barème approximatif à date de `pricingCatalogVersion`. Retourne `nil`
    /// pour les providers gratuits (Apple, Local).
    ///
    /// Fix m6 : Anthropic Haiku 4.5 corrigé à $0.80/$4 (source: docs Anthropic 2026).
    static func pricing(for providerID: String) -> Pricing? {
        switch providerID {
        case "openai.gpt":       return Pricing(inputUSDPerMillion: 0.15,  outputUSDPerMillion: 0.60)
        case "anthropic.claude": return Pricing(inputUSDPerMillion: 0.80,  outputUSDPerMillion: 4.00)
        case "mistral.direct":   return Pricing(inputUSDPerMillion: 0.10,  outputUSDPerMillion: 0.30)
        case "google.gemini":    return Pricing(inputUSDPerMillion: 0.075, outputUSDPerMillion: 0.30)
        default: return nil
        }
    }

    // MARK: - Currency conversion (B2 audit fix)

    /// Taux de conversion USD → EUR — fixe (mis à jour manuellement avec
    /// `pricingCatalogVersion`). Suffisant pour un ordre de grandeur.
    static let usdToEURRate: Double = 0.92

    /// Convertit un montant USD en EUR via `usdToEURRate`.
    static func usdToEUR(_ usd: Double) -> Double { usd * usdToEURRate }

    // MARK: - Internals

    /// Entrée persistée par jour (JSON compact dans UserDefaults).
    private struct Entry: Codable {
        var requestCount: Int = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
    }

    private let storagePrefix = "ai.usage."
    private let lastPurgeKey = "ai.usage.lastPurge"

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

    /// Purge des entrées > 30 jours — appelée au boot du singleton uniquement,
    /// pas à chaque record() (fix M2 audit — évite O(N) répété).
    /// Idempotent via `lastPurgeKey` : re-purge après 24h max.
    private func purgeOldEntriesIfNeeded() {
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: lastPurgeKey) as? Date,
           now.timeIntervalSince(last) < 86400 {
            return
        }
        let cutoff = Self.day(offset: -30)
        let all = UserDefaults.standard.dictionaryRepresentation()
        for (key, _) in all where key.hasPrefix(storagePrefix) {
            guard let dayStart = key.range(of: ".", options: .backwards) else { continue }
            let day = String(key[dayStart.upperBound...])
            if day < cutoff {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set(now, forKey: lastPurgeKey)
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

// MARK: - Formatters (M7 + m3 audit fix)

/// Helpers de formatage utilisés par l'UI pour afficher les coûts et compteurs
/// de manière lisible et localisée (EUR au lieu de USD brut).
enum UsageFormatter {

    /// Formate un coût USD converti en EUR. Micro-coûts (< 0.01 €) affichés
    /// "< 0,01 €" plutôt que "0,000 €" trompeur.
    static func costEUR(usd: Double) -> String {
        let eur = AIProviderUsageTracker.usdToEUR(usd)
        if eur > 0 && eur < 0.01 {
            return "< 0,01 €"
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "fr_FR")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: eur)) ?? "0,00 €"
    }

    /// Formate un compteur de requêtes avec pluriel.
    static func requestCount(_ n: Int) -> String {
        n <= 1 ? "\(n) requête" : "\(n) requêtes"
    }

    /// Formate une moyenne tokens/req compacte : "1.2k tok/req".
    static func averageTokens(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk tok/req", Double(n) / 1000) }
        return "\(n) tok/req"
    }
}
