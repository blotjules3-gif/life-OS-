import Foundation

/// Cours en direct pour le portefeuille.
///
/// CoinGecko, endpoint public: pas de cle API, pas de compte. C'est le seul
/// fournisseur serieux utilisable sans credentials, donc c'est celui-la.
///
/// Les ACTIONS ne sont pas couvertes: aucune API boursiere gratuite ne donne de
/// cours sans cle. Elles restent en saisie manuelle, et l'ecran le dit au lieu
/// d'afficher un chiffre faux.
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
    }

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
            }
            lastFetch = .now
            cache.merge(out) { _, new in new }
            return .success(out)
        } catch {
            return .failure(.network(error.localizedDescription))
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

    private static var lastFetch: Date = .distantPast
    private static var cache: [String: Double] = [:]

    /// Cours convertis en EUROS, par symbole tel que saisi par l'utilisateur.
    ///
    /// Les symboles europeens (MC.PA, CW8.PA) rendent deja des euros. Les
    /// symboles americains rendent des dollars: on convertit, sinon on
    /// additionnerait des devises differentes dans le total du portefeuille,
    /// ce qui donnerait un chiffre faux sans que rien ne le signale.
    static func pricesInEUR(symbols: [String], force: Bool = false) async -> Result<[String: Double], PriceService.Failure> {
        let wanted = Set(symbols.map { $0.trimmingCharacters(in: .whitespaces).uppercased() })
            .filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return .success([:]) }

        if !force, Date().timeIntervalSince(lastFetch) < 60, !cache.isEmpty {
            return .success(cache.filter { wanted.contains($0.key) })
        }

        var raw: [String: Quote] = [:]
        for sym in wanted.sorted() {
            if let q = await quote(sym) { raw[sym] = q }
        }
        guard !raw.isEmpty else { return .failure(.network("aucun cours trouvé")) }

        // Un seul appel de change par devise rencontree.
        var rates: [String: Double] = ["EUR": 1]
        for cur in Set(raw.values.map(\.currency)) where cur != "EUR" {
            if let r = await eurRate(for: cur) { rates[cur] = r }
        }

        var out: [String: Double] = [:]
        for (sym, q) in raw {
            guard let rate = rates[q.currency] else { continue }   // devise inconnue: on n'invente pas
            out[sym] = q.price * rate
        }
        lastFetch = .now
        cache.merge(out) { _, new in new }
        return .success(out)
    }

    private static func quote(_ symbol: String) async -> Quote? {
        guard let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=1d&range=1d")
        else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        // Sans en-tete d'agent, le point renvoie une page de refus.
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let meta = results.first?["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double,
              let cur = meta["currency"] as? String
        else { return nil }
        return Quote(price: price, currency: cur.uppercased())
    }

    /// Combien vaut 1 unite de `currency` en euros.
    private static func eurRate(for currency: String) async -> Double? {
        // EURUSD=X donne des dollars par euro: on inverse.
        guard let q = await quote("EUR\(currency)=X"), q.price > 0 else { return nil }
        return 1 / q.price
    }
}
