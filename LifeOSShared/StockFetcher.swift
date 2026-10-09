import Foundation

// Partage app + widgets : les appels reseau vers le point "chart" de Yahoo Finance.
// Sequentiels, avec une petite pause entre deux, et toujours sous le budget de
// `StockRefreshBudget` : le point n'est pas une API publique et refuse (429) les
// rafales.

struct StockRefreshReport: Equatable, Sendable {
    var requested = 0
    var updated = 0
    /// Demandes evitees : lecture de moins de 5 minutes deja en cache.
    var skippedRecent = 0
    var notFound: [String] = []
    var offline = false
    var rateLimited = false
    var otherErrors = 0
}

enum StockFetcher {
    /// Pause entre deux demandes d'un meme passage.
    static let pauseNanoseconds: UInt64 = 250_000_000

    static func request(symbol: String, period: StockPeriod) -> URLRequest? {
        guard let enc = symbol.uppercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=\(period.interval)&range=\(period.range)")
        else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        // Sans en-tete d'agent, le point renvoie une page de refus.
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    static func classify(_ error: Error) -> StockFetchError {
        guard let u = error as? URLError else { return .network }
        switch u.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .timedOut:
            return .offline
        default:
            return .network
        }
    }

    static func classify(status: Int) -> StockFetchError? {
        switch status {
        case 200..<300: return nil
        case 404: return .notFound
        case 429: return .rateLimited
        default: return .network
        }
    }

    /// Une demande. Le 404 de Yahoo porte un corps JSON "Not Found" : lu aussi.
    static func fetch(symbol: String, period: StockPeriod, session: URLSession = .shared,
                      now: @escaping () -> Date = { Date() }) async -> Result<StockQuote, StockFetchError> {
        guard let req = request(symbol: symbol, period: period) else { return .failure(.notFound) }
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, let err = classify(status: http.statusCode) {
                if err == .notFound || err == .network,
                   case .failure(let parsed) = StockChartParser.parse(data, symbol: symbol, range: period.range, interval: period.interval),
                   parsed == .notFound {
                    return .failure(.notFound)
                }
                return .failure(err)
            }
            return StockChartParser.parse(data, symbol: symbol, range: period.range, interval: period.interval, now: now())
        } catch {
            return .failure(classify(error))
        }
    }

    /// Euros pour 1 unite de `currency` (paire EURXXX=X, inversee).
    static func fetchEURRate(_ currency: String, session: URLSession = .shared) async -> Result<Double, StockFetchError> {
        let cur = currency.uppercased()
        if cur == "EUR" { return .success(1) }
        switch await fetch(symbol: "EUR\(cur)=X", period: .day1, session: session) {
        case .success(let q) where q.price > 0: return .success(1 / q.price)
        case .success: return .failure(.decoding)
        case .failure(let e): return .failure(e)
        }
    }

    /// Rafraichit `symbols` pour `period`, puis les taux EUR des devises demandees.
    /// Ne demande que ce que le budget autorise ; tout le reste vient du cache.
    static func refresh(symbols: [String], period: StockPeriod, eurFor currencies: Set<String> = [],
                        cache start: StockQuoteCache, minInterval: TimeInterval, maxRequests: Int,
                        session: URLSession = .shared, now: @escaping () -> Date = { Date() }) async -> (StockQuoteCache, StockRefreshReport) {
        var cache = start
        var report = StockRefreshReport()
        let wanted = symbols.map { $0.uppercased() }.filter { !$0.isEmpty }
        let keys = wanted.map { StockQuoteCache.quoteKey($0, period) }
        let due = StockRefreshBudget.due(keys, attempts: cache.attempts, now: now(), minInterval: minInterval,
                                         maxRequests: maxRequests, backoffUntil: cache.backoffUntil)
        report.skippedRecent = Set(keys).count - due.count
        var first = true
        for key in due {
            let symbol = String(key.split(separator: "|").first ?? "")
            if !first { try? await Task.sleep(nanoseconds: pauseNanoseconds) }
            first = false
            cache.attempts[key] = now()
            report.requested += 1
            switch await fetch(symbol: symbol, period: period, session: session, now: now) {
            case .success(let q):
                cache.record(q); report.updated += 1
            case .failure(let e):
                cache.record(e, for: symbol, at: now())
                switch e {
                case .notFound: report.notFound.append(symbol)
                case .offline: report.offline = true
                case .rateLimited: report.rateLimited = true
                default: report.otherErrors += 1
                }
                // Hors ligne ou refus : inutile d'enchainer les autres demandes.
                if e == .offline || e == .rateLimited { return (cache, report) }
            }
        }

        // Devises a convertir : celles demandees, plus celles des cours en cache.
        let fxKeys = currencies.filter { $0 != "EUR" && !$0.isEmpty }.sorted().map(StockQuoteCache.fxKey)
        let fxDue = StockRefreshBudget.due(fxKeys, attempts: cache.attempts, now: now(), minInterval: minInterval,
                                           maxRequests: maxRequests, backoffUntil: cache.backoffUntil)
        for key in fxDue {
            let cur = String(key.dropFirst(3))
            if !first { try? await Task.sleep(nanoseconds: pauseNanoseconds) }
            first = false
            cache.attempts[key] = now()
            switch await fetchEURRate(cur, session: session) {
            case .success(let r): cache.fx[cur] = .init(eurPerUnit: r, fetchedAt: now())
            case .failure(let e):
                if e == .offline { report.offline = true; cache.record(e, for: key, at: now()); return (cache, report) }
                if e == .rateLimited { report.rateLimited = true; cache.record(e, for: key, at: now()); return (cache, report) }
            }
        }
        return (cache, report)
    }
}
