import Foundation

// Partage app + widgets. Deux fichiers JSON dans le groupe d'apps, dossier "Stocks" :
//  - quotes.json   : le cache des cours (ecrit par l'app ET par les widgets qui
//                    rafraichissent eux-memes), avec l'heure de chaque demande pour
//                    respecter le budget d'appels.
//  - snapshot.json : ce que l'utilisateur suit (listes, ordre, options, positions du
//                    portefeuille). Ecrit par l'app seule. Il affiche, il ne sauvegarde
//                    rien : la verite reste dans la base de l'app.

enum StockFiles {
    /// Remplacable dans les tests.
    nonisolated(unsafe) static var directoryOverride: URL?

    static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        return LifeOSGroup.container?.appendingPathComponent("Stocks", isDirectory: true)
    }

    static func url(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    static func write<T: Encodable>(_ value: T, to name: String) throws {
        guard let dir = directory, let url = url(name) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        try enc.encode(value).write(to: url, options: .atomic)
    }

    static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(T.self, from: data)
    }
}

// MARK: - Cache des cours

struct StockQuoteCache: Codable, Equatable, Sendable {
    struct Failure: Codable, Equatable, Sendable { var error: StockFetchError; var at: Date }
    struct FXRate: Codable, Equatable, Sendable { var eurPerUnit: Double; var fetchedAt: Date }

    static let fileName = "quotes.json"
    /// Apres un refus "trop de demandes", plus aucun appel pendant ce delai.
    static let backoff: TimeInterval = 10 * 60

    var version = 1
    var quotes: [String: StockQuote] = [:]
    /// Dernier echec par symbole. Un symbole introuvable reste affiche avec son erreur.
    var failures: [String: Failure] = [:]
    /// Euros pour 1 unite de devise.
    var fx: [String: FXRate] = [:]
    /// Heure de la derniere DEMANDE par cle ("MC.PA|1d", "FX|USD").
    var attempts: [String: Date] = [:]
    var backoffUntil: Date?
    /// Dernier echec reseau (pas de connexion) : l'ecran dit "Hors ligne".
    var offlineSince: Date?

    static func load() -> StockQuoteCache { StockFiles.read(StockQuoteCache.self, from: fileName) ?? StockQuoteCache() }
    func save() throws { try StockFiles.write(self, to: Self.fileName) }

    var eurRates: [String: Double] { fx.mapValues(\.eurPerUnit).merging(["EUR": 1]) { a, _ in a } }

    static func quoteKey(_ symbol: String, _ period: StockPeriod) -> String { "\(symbol.uppercased())|\(period.range)" }
    static func fxKey(_ currency: String) -> String { "FX|\(currency.uppercased())" }

    mutating func record(_ quote: StockQuote) {
        quotes[quote.symbol] = quote.merged(into: quotes[quote.symbol])
        failures[quote.symbol] = nil
        offlineSince = nil
    }

    mutating func record(_ error: StockFetchError, for symbol: String, at now: Date) {
        let s = symbol.uppercased()
        switch error {
        case .offline:
            if offlineSince == nil { offlineSince = now }
        case .rateLimited:
            backoffUntil = now.addingTimeInterval(Self.backoff)
        case .notFound, .network, .decoding:
            failures[s] = Failure(error: error, at: now)
        }
    }

    /// Oublie un symbole qui n'est plus suivi nulle part.
    mutating func prune(keeping symbols: Set<String>) {
        quotes = quotes.filter { symbols.contains($0.key) }
        failures = failures.filter { symbols.contains($0.key) }
        attempts = attempts.filter { k, _ in
            k.hasPrefix("FX|") || symbols.contains(String(k.split(separator: "|").first ?? ""))
        }
    }

    /// Fusion avant ecriture : l'app et un widget peuvent ecrire presque en meme temps.
    /// Pour chaque symbole, la lecture la plus recente gagne.
    func merging(_ other: StockQuoteCache) -> StockQuoteCache {
        var out = self
        for (k, q) in other.quotes {
            if let mine = out.quotes[k], mine.fetchedAt >= q.fetchedAt { continue }
            out.quotes[k] = q.merged(into: out.quotes[k])
        }
        for (k, f) in other.failures where (out.failures[k]?.at ?? .distantPast) < f.at {
            if let q = out.quotes[k], q.fetchedAt > f.at { continue }
            out.failures[k] = f
        }
        for (k, r) in other.fx where (out.fx[k]?.fetchedAt ?? .distantPast) < r.fetchedAt { out.fx[k] = r }
        for (k, d) in other.attempts where (out.attempts[k] ?? .distantPast) < d { out.attempts[k] = d }
        if let b = other.backoffUntil, b > (out.backoffUntil ?? .distantPast) { out.backoffUntil = b }
        return out
    }
}

/// Budget d'appels : une demande par cle au plus toutes les `minInterval` secondes,
/// `maxRequests` par passage, rien pendant un refus "trop de demandes".
enum StockRefreshBudget {
    /// L'app : au plus une demande par titre et par periode toutes les 5 minutes.
    static let appMinInterval: TimeInterval = 5 * 60
    /// Les widgets : toutes les 15 minutes, et peu de titres par passage.
    static let widgetMinInterval: TimeInterval = 15 * 60
    static let widgetMaxRequests = 6

    static func due(_ keys: [String], attempts: [String: Date], now: Date, minInterval: TimeInterval,
                    maxRequests: Int, backoffUntil: Date?) -> [String] {
        if let b = backoffUntil, now < b { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for k in keys where !seen.contains(k) {
            seen.insert(k)
            if let last = attempts[k], now.timeIntervalSince(last) < minInterval { continue }
            out.append(k)
            if out.count >= maxRequests { break }
        }
        return out
    }
}

// MARK: - Instantane pour les widgets

struct StockWidgetSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Identifiable, Sendable {
        var symbol: String
        var displayName: String
        var exchangeLabel: String
        var id: String { symbol }
    }

    struct List: Codable, Equatable, Identifiable, Sendable {
        /// Identifiant stable de la liste (uid), jamais le nom : un renommage ne doit pas
        /// casser un widget configure.
        var id: String
        var name: String
        var order: Int
        var displayCurrency: StockDisplayCurrency
        var period: StockPeriod
        var showSparkline: Bool
        var items: [Item]
    }

    struct HoldingRow: Codable, Equatable, Sendable {
        var symbol: String
        var kind: String
        var valueEUR: Double
        /// Variation du jour (24 h pour une crypto), nil si inconnue.
        var dayChangePct: Double?
        var priceAt: Date?
    }

    static let fileName = "snapshot.json"

    var version = 1
    var generatedAt: Date
    var lists: [List]
    var holdings: [HoldingRow]

    static func read() -> StockWidgetSnapshot? { StockFiles.read(StockWidgetSnapshot.self, from: fileName) }
    func write() throws { try StockFiles.write(self, to: Self.fileName) }

    var orderedLists: [List] { lists.sorted { $0.order != $1.order ? $0.order < $1.order : $0.name < $1.name } }

    func list(id: String) -> List? { lists.first { $0.id == id } }

    /// Liste par defaut d'un widget sans choix : "Favoris", sinon la premiere.
    var defaultList: List? { orderedLists.first { $0.name == WatchlistDefaults.listName } ?? orderedLists.first }

    /// Tous les titres suivis, chacun une fois, dans l'ordre des listes.
    var allItems: [Item] {
        var seen = Set<String>()
        var out: [Item] = []
        for l in orderedLists { for i in l.items where !seen.contains(i.symbol) { seen.insert(i.symbol); out.append(i) } }
        return out
    }

    func item(symbol: String) -> Item? { allItems.first { $0.symbol == symbol.uppercased() } }

    /// Reglages d'affichage d'un titre : ceux de la premiere liste qui le contient.
    func settings(for symbol: String) -> List? {
        orderedLists.first { $0.items.contains { $0.symbol == symbol.uppercased() } }
    }

    var portfolio: PortfolioSummary { PortfolioSummary.make(holdings) }
}

enum WatchlistDefaults {
    static let listName = "Favoris"
}

struct PortfolioSummary: Equatable, Sendable {
    struct Mover: Equatable, Sendable { var symbol: String; var pct: Double }
    var total: Double
    /// Variation du jour en euros, sur les positions dont la variation est connue.
    var dayChange: Double
    var dayChangePct: Double?
    /// Positions sans variation connue (prix saisi a la main, cours introuvable).
    var withoutChange: Int
    var movers: [Mover]
    var latestPriceAt: Date?

    static func make(_ rows: [StockWidgetSnapshot.HoldingRow], maxMovers: Int = 3) -> PortfolioSummary {
        var total = 0.0, change = 0.0, prevKnown = 0.0, without = 0
        var movers: [Mover] = []
        for r in rows {
            total += r.valueEUR
            guard let p = r.dayChangePct, p > -100 else { without += 1; continue }
            let prev = r.valueEUR / (1 + p / 100)
            change += r.valueEUR - prev
            prevKnown += prev
            movers.append(Mover(symbol: r.symbol, pct: p))
        }
        movers.sort { abs($0.pct) != abs($1.pct) ? abs($0.pct) > abs($1.pct) : $0.symbol < $1.symbol }
        return PortfolioSummary(total: total, dayChange: change,
                                dayChangePct: prevKnown > 0 ? change / prevKnown * 100 : nil,
                                withoutChange: without, movers: Array(movers.prefix(maxMovers)),
                                latestPriceAt: rows.compactMap(\.priceAt).max())
    }
}

// MARK: - Choix proposes dans la configuration des widgets

struct StockChoice: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String
}

extension StockWidgetSnapshot {
    /// Listes dans l'ordre de l'app.
    var listChoices: [StockChoice] {
        orderedLists.map { StockChoice(id: $0.id, title: $0.name, subtitle: "\($0.items.count) titre\($0.items.count > 1 ? "s" : "")") }
    }

    /// Titres suivis, chacun une fois.
    var symbolChoices: [StockChoice] {
        allItems.map { StockChoice(id: $0.symbol, title: $0.symbol,
                                   subtitle: [$0.displayName, $0.exchangeLabel].filter { !$0.isEmpty }.joined(separator: " · ")) }
    }
}

// MARK: - Rafraichissement des widgets

enum StockWidgetPolicy {
    /// Prochain rechargement : 30 min si une place est en seance, sinon a l'ouverture
    /// connue la plus proche (entre 30 min et 6 h), sinon dans 2 h.
    static func nextReload(quotes: [StockQuote], now: Date = Date()) -> Date {
        if quotes.contains(where: { StockFreshness.isOpen($0, now: now) == true }) {
            return now.addingTimeInterval(30 * 60)
        }
        let nextOpen = quotes.compactMap(\.sessionStart).filter { $0 > now }.min()
        if let o = nextOpen {
            return min(max(o, now.addingTimeInterval(30 * 60)), now.addingTimeInterval(6 * 3600))
        }
        return now.addingTimeInterval(2 * 3600)
    }

    /// Titres a relire par le widget : sans cours, sans graphique pour la periode, ou a relire.
    static func symbolsToRefresh(_ symbols: [String], period: StockPeriod, cache: StockQuoteCache, now: Date = Date()) -> [String] {
        symbols.filter { s in
            guard let q = cache.quotes[s.uppercased()] else { return cache.failures[s.uppercased()]?.error != .notFound }
            return q.series[period.range] == nil || StockFreshness.needsRefresh(q, now: now)
        }
    }
}
