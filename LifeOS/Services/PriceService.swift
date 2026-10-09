import Foundation

/// Cours en direct pour le portefeuille.
///
/// CoinGecko, endpoint public: pas de cle API, pas de compte. C'est le seul
/// fournisseur serieux utilisable sans credentials, donc c'est celui-la.
///
/// Les actions et ETF passent par `StockService` (Yahoo Finance, differe), plus bas.
enum PriceService {

    enum Failure: Error, CustomStringConvertible {
        case rateLimited            // CoinGecko: ~30 appels/minute en gratuit
        case network(String)
        case decoding

        var description: String {
            switch self {
            case .rateLimited: return "Trop d'appels, réessaie dans une minute"
            case .network(let m): return m
            case .decoding: return "Réponse illisible"
            }
        }
    }

    private struct MarketRow: Decodable {
        let symbol: String
        let current_price: Double?
        let price_change_percentage_24h: Double?
    }

    /// Cours et variation sur 24 h (une crypto n'a pas de cloture : c'est la seule
    /// variation honnete).
    struct CryptoQuote: Equatable { let priceEUR: Double; let change24hPct: Double? }
    private static var changeCache: [String: Double] = [:]

    /// Dernier appel, pour ne pas marteler l'API quand la vue se recharge.
    private static var lastFetch: Date = .distantPast
    private static var cache: [String: Double] = [:]

    /// Cours en euros, par symbole en MINUSCULES (btc, eth...).
    ///
    /// `force` ignore le cache de 60 s. Sans ca, revenir sur l'ecran trois fois
    /// de suite consommait trois appels pour rien et declenchait le 429.
    static func cryptoPrices(symbols: [String], force: Bool = false) async -> Result<[String: Double], Failure> {
        let wanted = Set(symbols.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
            .filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return .success([:]) }

        if !force, Date().timeIntervalSince(lastFetch) < 60, !cache.isEmpty {
            return .success(cache.filter { wanted.contains($0.key) })
        }

        var c = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        c.queryItems = [
            .init(name: "vs_currency", value: "eur"),
            .init(name: "symbols", value: wanted.sorted().joined(separator: ",")),
            .init(name: "per_page", value: "250"),
        ]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                if http.statusCode == 429 { return .failure(.rateLimited) }
                guard (200..<300).contains(http.statusCode) else {
                    return .failure(.network("HTTP \(http.statusCode)"))
                }
            }
            guard let rows = try? JSONDecoder().decode([MarketRow].self, from: data) else {
                return .failure(.decoding)
            }
            var out: [String: Double] = [:]
            for r in rows where r.current_price != nil {
                out[r.symbol.lowercased()] = r.current_price!
                if let c = r.price_change_percentage_24h { changeCache[r.symbol.lowercased()] = c }
            }
            lastFetch = .now
            cache.merge(out) { _, new in new }
            return .success(out)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// Meme appel que `cryptoPrices`, avec la variation sur 24 h quand CoinGecko la donne.
    static func cryptoQuotes(symbols: [String], force: Bool = false) async -> Result<[String: CryptoQuote], Failure> {
        switch await cryptoPrices(symbols: symbols, force: force) {
        case .failure(let e): return .failure(e)
        case .success(let prices):
            var out: [String: CryptoQuote] = [:]
            for (k, p) in prices { out[k] = CryptoQuote(priceEUR: p, change24hPct: changeCache[k]) }
            return .success(out)
        }
    }
}

// MARK: - Actions et ETF

/// Cours des actions et ETF, sans cle.
///
/// Source: le point de graphique public de Yahoo Finance. Il n'est pas
/// documente comme une API publique, donc il peut changer sans preavis. C'est
/// assume et isole ici: si un jour il tombe, seul ce fichier est a remplacer,
/// et l'ecran retombe proprement sur la saisie manuelle.
///
/// Les cours sont DIFFERES selon la place, et l'ecran le dit. On ne pretend
/// pas donner du temps reel.
enum StockService {

    struct Quote {
        let price: Double
        let currency: String
    }

    /// Cours converti en euros, avec ce qu'il faut pour l'afficher honnetement.
    struct EURQuote: Equatable {
        let priceEUR: Double
        let currency: String
        let changePct: Double?
        let marketTime: Date?
        let quote: StockQuote
    }

    /// Cours convertis en EUROS, par symbole tel que saisi par l'utilisateur.
    ///
    /// Les symboles europeens (MC.PA, CW8.PA) rendent deja des euros. Les
    /// symboles americains rendent des dollars: on convertit, sinon on
    /// additionnerait des devises differentes dans le total du portefeuille,
    /// ce qui donnerait un chiffre faux sans que rien ne le signale.
    ///
    /// Passe par le cache partage (`QuoteStore`) : au plus une demande par titre toutes
    /// les 5 minutes, meme quand `force` est vrai.
    @MainActor
    static func pricesInEUR(symbols: [String], force: Bool = false) async -> Result<[String: Double], PriceService.Failure> {
        switch await quotesInEUR(symbols: symbols) {
        case .success(let q): return .success(q.mapValues(\.priceEUR))
        case .failure(let e): return .failure(e)
        }
    }

    /// Cours en euros + variation du jour + heure du cours. Un symbole introuvable ou sans
    /// taux de change connu est absent du resultat (on n'invente pas).
    @MainActor
    static func quotesInEUR(symbols: [String]) async -> Result<[String: EURQuote], PriceService.Failure> {
        let wanted = Array(Set(symbols.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty })).sorted()
        guard !wanted.isEmpty else { return .success([:]) }
        let store = QuoteStore.shared
        let report = await store.refresh(symbols: wanted, period: .day1, convertToEUR: true)
        var out: [String: EURQuote] = [:]
        let rates = store.cache.eurRates
        for s in wanted {
            guard let q = store.cache.quotes[s],
                  let eur = StockMath.convert(q.price, from: q.currency, to: .eur, eurPerUnit: rates) else { continue }
            out[s] = EURQuote(priceEUR: eur.value, currency: q.currency, changePct: q.changePercent, marketTime: q.marketTime, quote: q)
        }
        if out.isEmpty {
            if report.offline { return .failure(.network("Hors ligne")) }
            if report.rateLimited { return .failure(.rateLimited) }
            return .failure(.network("aucun cours trouvé"))
        }
        return .success(out)
    }

    /// Yahoo cote certaines places en sous-unites : "GBp" (pence, titres .L de Londres),
    /// "ZAc" (cents sud-africains), "ILA" (agorot). `uppercased()` faisait de "GBp" des
    /// livres, donc une action de Londres valait 100 fois trop.
    static func normalized(price: Double, currency: String) -> Quote {
        let n = StockMath.normalizedCurrency(currency)
        return Quote(price: price / n.divisor, currency: n.code)
    }
}
