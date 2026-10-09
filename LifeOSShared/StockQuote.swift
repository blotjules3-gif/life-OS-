import Foundation

// Partage entre l'app et l'extension widgets (dossier LifeOSShared, compile dans
// les deux cibles). Ici : le cours d'un titre tel que lu dans la reponse "chart"
// de Yahoo Finance, la lecture de cette reponse, et les regles d'affichage
// (marche ferme, donnees perimees, horodatage).
//
// Source : point "chart" public de Yahoo Finance. Il n'est PAS documente comme une
// API publique : il peut changer, ralentir ou refuser sans preavis. Les cours sont
// DIFFERES selon la place (souvent 15 a 20 minutes en Europe). Rien ici ne doit
// laisser croire a du temps reel.

/// Periode du petit graphique, avec les parametres Yahoo correspondants.
enum StockPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case day1 = "1J", day5 = "5J", month1 = "1M", month6 = "6M", year1 = "1A"

    var id: String { rawValue }

    var range: String {
        switch self {
        case .day1: return "1d"
        case .day5: return "5d"
        case .month1: return "1mo"
        case .month6: return "6mo"
        case .year1: return "1y"
        }
    }

    var interval: String {
        switch self {
        case .day1: return "15m"
        case .day5: return "60m"
        case .month1, .month6: return "1d"
        case .year1: return "1wk"
        }
    }

    /// Libelle long, lu par VoiceOver.
    var spoken: String {
        switch self {
        case .day1: return "1 jour"
        case .day5: return "5 jours"
        case .month1: return "1 mois"
        case .month6: return "6 mois"
        case .year1: return "1 an"
        }
    }
}

/// Devise d'affichage d'une liste : celle de la place, ou l'euro.
enum StockDisplayCurrency: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, eur
    var id: String { rawValue }
    var label: String { self == .eur ? "Euro" : "Devise d'origine" }
}

enum StockFetchError: String, Codable, Error, Equatable, Sendable {
    case notFound, network, offline, rateLimited, decoding

    var message: String {
        switch self {
        case .notFound: return "Symbole introuvable"
        case .network: return "Source indisponible"
        case .offline: return "Hors ligne"
        case .rateLimited: return "Trop de demandes, nouvel essai plus tard"
        case .decoding: return "Réponse illisible"
        }
    }
}

struct StockQuote: Codable, Equatable, Sendable {
    /// Symbole tel que demande, en MAJUSCULES (MC.PA, AAPL).
    var symbol: String
    var name: String
    /// Prix dans `currency`, toujours en unite principale (livres, pas pence).
    var price: Double
    /// Cloture de la veille, quand la reponse permet de la connaitre.
    var previousClose: Double?
    /// Devise ISO normalisee (GBP, jamais GBp).
    var currency: String
    /// Code court de la place (PAR, NMS).
    var exchange: String
    /// Nom de la place (Paris, NasdaqGS).
    var exchangeFullName: String
    var instrumentType: String
    /// Etat du marche donne par Yahoo, quand il est present (REGULAR, CLOSED, PRE, POST).
    var marketState: String?
    /// Heure du dernier cours (regularMarketTime).
    var marketTime: Date?
    /// Seance reguliere en cours ou derniere seance connue.
    var sessionStart: Date?
    var sessionEnd: Date?
    var exchangeTimeZone: String?
    /// Moment ou LifeOS a recu la reponse.
    var fetchedAt: Date
    /// Points du graphique par periode Yahoo ("1d", "5d"...), dans `currency`.
    var series: [String: [Double]] = [:]

    var change: Double? { previousClose.map { price - $0 } }
    var changePercent: Double? { StockMath.changePercent(price: price, previousClose: previousClose) }

    /// Fusionne une nouvelle lecture avec l'ancienne : garde les graphiques des autres
    /// periodes, et la cloture de la veille si la nouvelle reponse ne la donne pas
    /// (meme seance).
    func merged(into old: StockQuote?) -> StockQuote {
        guard let old, old.symbol == symbol else { return self }
        var q = self
        for (k, v) in old.series where q.series[k] == nil { q.series[k] = v }
        if q.previousClose == nil, let p = old.previousClose, old.currency == q.currency,
           StockMath.sameSession(old, q) {
            q.previousClose = p
        }
        return q
    }
}

enum StockMath {
    static func changePercent(price: Double, previousClose: Double?) -> Double? {
        guard let p = previousClose, p > 0 else { return nil }
        return (price - p) / p * 100
    }

    /// Yahoo cote certaines places en sous-unites : "GBp" (pence, titres .L de Londres),
    /// "ZAc" (cents sud-africains), "ILA" (agorot). Rend le diviseur et la devise ISO.
    static func normalizedCurrency(_ currency: String) -> (divisor: Double, code: String) {
        switch currency {
        case "GBp", "GBX": return (100, "GBP")
        case "ZAc", "ZAC": return (100, "ZAR")
        case "ILA": return (100, "ILS")
        default: return (1, currency.uppercased())
        }
    }

    /// Deux lectures de la meme seance : dernier cours le meme jour dans le fuseau de la
    /// place (a defaut, meme fin de seance).
    static func sameSession(_ a: StockQuote, _ b: StockQuote) -> Bool {
        if let ta = a.marketTime, let tb = b.marketTime,
           let name = a.exchangeTimeZone ?? b.exchangeTimeZone, let tz = TimeZone(identifier: name) {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
            return cal.isDate(ta, inSameDayAs: tb)
        }
        if let ea = a.sessionEnd, let eb = b.sessionEnd { return abs(ea.timeIntervalSince(eb)) < 60 }
        return false
    }

    /// Conversion pour l'affichage. `eurPerUnit` : euros pour 1 unite de la devise.
    /// Sans taux connu : nil (on n'invente pas de taux).
    static func convert(_ value: Double, from currency: String, to display: StockDisplayCurrency,
                        eurPerUnit: [String: Double]) -> (value: Double, currency: String)? {
        if display == .original || currency == "EUR" { return (value, currency) }
        guard let r = eurPerUnit[currency], r > 0 else { return nil }
        return (value * r, "EUR")
    }

    /// Reduit une serie a `maxPoints` points au plus, en gardant le dernier.
    static func downsample(_ values: [Double], maxPoints: Int = 80) -> [Double] {
        guard values.count > maxPoints, maxPoints > 1 else { return values }
        let step = Double(values.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { values[Int((Double($0) * step).rounded())] }
    }
}

// MARK: - Lecture de la reponse Yahoo

enum StockChartParser {
    private struct Root: Decodable { let chart: Chart }
    private struct Chart: Decodable { let result: [Result]?; let error: APIError? }
    private struct APIError: Decodable { let code: String?; let description: String? }
    private struct Result: Decodable {
        let meta: Meta
        let timestamp: [Double]?
        let indicators: Indicators?
    }
    private struct Indicators: Decodable { let quote: [QuoteSeries]? }
    private struct QuoteSeries: Decodable { let close: [Double?]? }
    private struct Period: Decodable { let start: Double?; let end: Double? }
    private struct Trading: Decodable { let regular: Period? }
    private struct Meta: Decodable {
        let currency: String?
        let symbol: String?
        let exchangeName: String?
        let fullExchangeName: String?
        let instrumentType: String?
        let regularMarketTime: Double?
        let exchangeTimezoneName: String?
        let regularMarketPrice: Double?
        let regularMarketChangePercent: Double?
        let previousClose: Double?
        let chartPreviousClose: Double?
        let longName: String?
        let shortName: String?
        let marketState: String?
        let currentTradingPeriod: Trading?
    }

    /// Lit une reponse "chart". `range`/`interval` : ceux de la requete.
    static func parse(_ data: Data, symbol requested: String, range: String, interval: String,
                      now: Date = Date()) -> Swift.Result<StockQuote, StockFetchError> {
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return .failure(.decoding) }
        if let code = root.chart.error?.code, !code.isEmpty {
            return .failure(code.lowercased().contains("not found") ? .notFound : .network)
        }
        guard let r = root.chart.result?.first else { return .failure(.notFound) }
        let m = r.meta
        guard let rawPrice = m.regularMarketPrice, let rawCurrency = m.currency, !rawCurrency.isEmpty else {
            return .failure(.notFound)
        }
        let (div, cur) = StockMath.normalizedCurrency(rawCurrency)
        let marketTime = m.regularMarketTime.map { Date(timeIntervalSince1970: $0) }

        // Points du graphique : les closes, sans les trous.
        let closes = r.indicators?.quote?.first?.close ?? []
        let stamps = r.timestamp ?? []

        // Cloture de la veille, dans l'ordre de confiance.
        var prev: Double? = m.previousClose
        if prev == nil, range == "1d" { prev = m.chartPreviousClose }
        if prev == nil, interval == "1d", let mt = marketTime,
           let tzName = m.exchangeTimezoneName, let tz = TimeZone(identifier: tzName) {
            prev = previousDailyClose(stamps: stamps, closes: closes, marketTime: mt, timeZone: tz)
        }
        if prev == nil, let pct = m.regularMarketChangePercent, pct > -100 {
            prev = rawPrice / (1 + pct / 100)
        }

        let series = closes.compactMap { $0 }.map { $0 / div }
        let name = (m.shortName?.isEmpty == false ? m.shortName : m.longName) ?? ""
        let q = StockQuote(
            symbol: requested.uppercased(),
            name: name,
            price: rawPrice / div,
            previousClose: prev.map { $0 / div },
            currency: cur,
            exchange: m.exchangeName ?? "",
            exchangeFullName: m.fullExchangeName ?? m.exchangeName ?? "",
            instrumentType: m.instrumentType ?? "",
            marketState: m.marketState,
            marketTime: marketTime,
            sessionStart: m.currentTradingPeriod?.regular?.start.map { Date(timeIntervalSince1970: $0) },
            sessionEnd: m.currentTradingPeriod?.regular?.end.map { Date(timeIntervalSince1970: $0) },
            exchangeTimeZone: m.exchangeTimezoneName,
            fetchedAt: now,
            series: series.isEmpty ? [:] : [range: StockMath.downsample(series)]
        )
        return .success(q)
    }

    /// Serie journaliere : si la derniere barre est la seance du dernier cours,
    /// l'avant-derniere est la cloture de la veille.
    static func previousDailyClose(stamps: [Double], closes: [Double?], marketTime: Date, timeZone: TimeZone) -> Double? {
        guard stamps.count == closes.count, stamps.count >= 2 else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let last = Date(timeIntervalSince1970: stamps[stamps.count - 1])
        guard cal.isDate(last, inSameDayAs: marketTime) else { return nil }
        return closes[closes.count - 2]
    }
}

// MARK: - Etat affiche

enum StockQuoteStatus: Equatable, Sendable {
    /// Marche ouvert, cours recent (mais differe).
    case delayed
    /// Marche ouvert, lecture trop ancienne.
    case stale
    /// Marche ferme : on montre le dernier cours et son heure.
    case closed
}

enum StockFreshness {
    /// Au-dela, pendant la seance, la lecture est dite perimee.
    static let staleAfter: TimeInterval = 30 * 60

    /// Le marche est-il en seance reguliere a `now` ? nil = inconnu.
    static func isOpen(_ q: StockQuote, now: Date) -> Bool? {
        if let s = q.marketState?.uppercased(), !s.isEmpty {
            // L'etat Yahoo ne vaut que pour le moment de la lecture : apres la fin de seance
            // connue, le marche est ferme quoi qu'il dise.
            if let end = q.sessionEnd, now >= end { return false }
            return s == "REGULAR"
        }
        if let start = q.sessionStart, let end = q.sessionEnd { return now >= start && now < end }
        return nil
    }

    static func status(_ q: StockQuote, now: Date = Date(), staleAfter: TimeInterval = staleAfter) -> StockQuoteStatus {
        switch isOpen(q, now: now) {
        case .some(false): return .closed
        case .some(true), .none:
            return now.timeIntervalSince(q.fetchedAt) > staleAfter ? .stale : .delayed
        }
    }

    /// A relire au prochain passage : perime, ou lu pendant une seance qui s'est terminee
    /// depuis (le dernier cours n'est peut-etre pas la cloture), ou vieux de plus de 12 h.
    static func needsRefresh(_ q: StockQuote, now: Date = Date()) -> Bool {
        if status(q, now: now) == .stale { return true }
        if let end = q.sessionEnd, now >= end, q.fetchedAt < end { return true }
        return now.timeIntervalSince(q.fetchedAt) > 12 * 3600
    }
}

// MARK: - Textes

enum StockFormat {
    static let source = "Yahoo Finance"
    static let locale = Locale(identifier: "fr_FR")

    /// "14:32" aujourd'hui, "ven. 17:35" cette semaine, "2 oct." au-dela.
    static func timeLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            f.dateFormat = "HH:mm"
        } else if abs(now.timeIntervalSince(date)) < 6 * 86_400 {
            f.dateFormat = "EEE HH:mm"
        } else {
            f.dateFormat = "d MMM"
        }
        return f.string(from: date)
    }

    /// Ligne d'etat courte, ex. "Différé · Yahoo Finance · 14:32".
    static func statusLine(_ q: StockQuote, offline: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = timeLabel(q.marketTime ?? q.fetchedAt, now: now, calendar: calendar)
        let core: String
        switch StockFreshness.status(q, now: now) {
        case .delayed: core = "Différé · \(source) · \(time)"
        case .stale: core = "Données périmées · \(source) · \(time)"
        case .closed: core = "Marché fermé · dernier cours \(time)"
        }
        return offline ? "Hors ligne · " + core : core
    }

    /// Version lue par VoiceOver, sans abreviations.
    static func statusSpoken(_ q: StockQuote, offline: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = timeLabel(q.marketTime ?? q.fetchedAt, now: now, calendar: calendar)
        var s: String
        switch StockFreshness.status(q, now: now) {
        case .delayed: s = "Cours différé, source \(source), heure du cours \(time)"
        case .stale: s = "Données périmées, source \(source), heure du cours \(time)"
        case .closed: s = "Marché fermé, dernier cours à \(time), source \(source)"
        }
        if offline { s = "Hors ligne. " + s }
        return s
    }

    /// Version courte pour les widgets : "Différé · 14:32", "Fermé · 17:35".
    static func compactStatus(_ q: StockQuote, offline: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = timeLabel(q.marketTime ?? q.fetchedAt, now: now, calendar: calendar)
        let core: String
        switch StockFreshness.status(q, now: now) {
        case .delayed: core = "Différé · \(time)"
        case .stale: core = "Périmé · \(time)"
        case .closed: core = "Fermé · \(time)"
        }
        return offline ? "Hors ligne · " + core : core
    }

    static func price(_ value: Double, currency: String) -> String {
        let digits = value >= 1000 ? 0 : (value < 1 ? 4 : 2)
        return value.formatted(.currency(code: currency).locale(locale).precision(.fractionLength(digits)))
    }

    static func percent(_ pct: Double) -> String {
        let sign = pct > 0 ? "+" : (pct < 0 ? "-" : "")
        return sign + String(format: "%.2f", abs(pct)).replacingOccurrences(of: ".", with: ",") + " %"
    }

    static func spokenPercent(_ pct: Double) -> String {
        let v = String(format: "%.2f", abs(pct)).replacingOccurrences(of: ".", with: ",")
        if pct > 0 { return "en hausse de \(v) pour cent" }
        if pct < 0 { return "en baisse de \(v) pour cent" }
        return "stable"
    }
}

// MARK: - Lien profond

/// lifeos://stocks?symbol=MC.PA&list=Favoris  ·  lifeos://stocks?view=portfolio
enum StockDeepLink {
    struct Target: Equatable {
        var symbol: String?
        var list: String?
        var portfolio = false
    }

    static func url(symbol: String? = nil, list: String? = nil) -> URL {
        build([("symbol", symbol), ("list", list)])
    }

    static var portfolioURL: URL { build([("view", "portfolio")]) }

    private static func build(_ pairs: [(String, String?)]) -> URL {
        var c = URLComponents()
        c.scheme = "lifeos"; c.host = "stocks"
        let items = pairs.compactMap { k, v in v.flatMap { $0.isEmpty ? nil : URLQueryItem(name: k, value: $0) } }
        c.queryItems = items.isEmpty ? nil : items
        return c.url ?? URL(string: "lifeos://stocks")!
    }

    /// nil si le lien ne vise pas la bourse.
    static func parse(_ url: URL) -> Target? {
        guard url.scheme == "lifeos", url.host == "stocks" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ n: String) -> String? {
            items.first { $0.name == n }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        return Target(symbol: v("symbol")?.uppercased(), list: v("list"), portfolio: v("view") == "portfolio")
    }
}
