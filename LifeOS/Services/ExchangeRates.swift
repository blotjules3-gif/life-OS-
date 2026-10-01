import Foundation

/// Taux de change reels, dates, avec leur source.
///
/// Avant (audit V2): 12 taux ecrits en dur, "mis a jour manuellement", sans date.
/// Ici: taux de reference de la Banque centrale europeenne (publies chaque jour
/// ouvre vers 16 h, sans cle), et ExchangeRate-API (offre ouverte, sans cle,
/// attribution demandee) SEULEMENT pour les devises que la BCE ne publie pas
/// (dirham marocain, dirham des Emirats...). Cache local avec sa date; hors
/// ligne sans cache, des taux integres clairement marques anciens.
enum ExchangeRates {

    enum Source: String, Codable {
        case ecb = "BCE"
        case erapi = "ExchangeRate-API"
        case builtin = "Taux intégrés"
    }

    struct Rate: Codable, Equatable {
        let perEUR: Double
        let source: Source
        let date: Date
    }

    struct Table: Codable, Equatable {
        var rates: [String: Rate]
        var fetchedAt: Date

        func rate(_ code: String) -> Rate? { code == "EUR" ? Rate(perEUR: 1, source: .ecb, date: fetchedAt) : rates[code] }

        /// Montant converti, ou nil si une des deux devises n'a pas de taux.
        func convert(_ amount: Double, from: String, to: String) -> Double? {
            guard let f = rate(from)?.perEUR, let t = rate(to)?.perEUR, f > 0 else { return nil }
            return amount / f * t
        }
    }

    enum Freshness: Equatable {
        case live, cached(age: TimeInterval), builtin
    }

    // MARK: Taux integres (dernier recours)

    /// Releves du 28 septembre 2026 (BCE, et ExchangeRate-API pour MAD et AED).
    /// Utilises seulement sans reseau ET sans cache, et affiches comme tels.
    static let builtinDate = Date(timeIntervalSince1970: 1_790_553_600)   // 28 sept. 2026
    static let builtin: [String: Double] = [
        "USD": 1.1378, "GBP": 0.8611, "CHF": 0.9338, "JPY": 178.50, "CAD": 1.5735, "AUD": 1.7212,
        "MAD": 10.947, "AED": 4.1828, "THB": 38.053, "TRY": 47.35, "MXN": 21.05, "CNY": 8.101,
        "SEK": 10.995, "NOK": 11.62, "DKK": 7.4752, "PLN": 4.263, "CZK": 24.397, "HUF": 388.9,
        "BRL": 6.05, "INR": 100.8, "KRW": 1585.0, "SGD": 1.462, "HKD": 8.857, "NZD": 1.935,
        "ZAR": 20.12, "ILS": 3.86,
    ]

    static var builtinTable: Table {
        Table(rates: builtin.mapValues { Rate(perEUR: $0, source: .builtin, date: builtinDate) }, fetchedAt: builtinDate)
    }

    // MARK: Chargement

    nonisolated(unsafe) static var session: URLSession = .shared
    nonisolated(unsafe) static var cacheURL: URL = AppPaths.caches.appendingPathComponent("fx.json")

    static let ecbURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    static let erURL = URL(string: "https://open.er-api.com/v6/latest/EUR")!

    /// Reseau d'abord; en echec, le cache; sinon les taux integres.
    static func load(wanted: [String]) async -> (Table, Freshness, error: String?) {
        var table = Table(rates: [:], fetchedAt: Date())
        var problems: [String] = []
        do { table.rates.merge(try await fetchECB(), uniquingKeysWith: { a, _ in a }) }
        catch { problems.append("BCE : \(error.localizedDescription)") }
        let missing = wanted.filter { $0 != "EUR" && table.rates[$0] == nil }
        if !missing.isEmpty {
            do {
                let er = try await fetchER()
                for code in missing { if let r = er[code] { table.rates[code] = r } }
            } catch { problems.append("ExchangeRate-API : \(error.localizedDescription)") }
        }
        if !table.rates.isEmpty {
            // Garde du cache les devises que le reseau n'a pas donnees ce coup-ci.
            if let old = readCache() { for (k, v) in old.rates where table.rates[k] == nil { table.rates[k] = v } }
            writeCache(table)
            return (table, .live, problems.isEmpty ? nil : problems.joined(separator: " · "))
        }
        if let cached = readCache() {
            return (cached, .cached(age: Date().timeIntervalSince(cached.fetchedAt)), "Hors ligne : derniers taux enregistrés.")
        }
        return (builtinTable, .builtin, "Hors ligne et aucun taux enregistré : taux intégrés du \(builtinDate.formatted(date: .abbreviated, time: .omitted)).")
    }

    static func fetchECB() async throws -> [String: Rate] {
        let (data, response) = try await session.data(from: ecbURL)
        guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { throw URLError(.badServerResponse) }
        let parsed = parseECB(data)
        guard !parsed.isEmpty else { throw URLError(.cannotParseResponse) }
        return parsed
    }

    /// `<Cube time='2026-09-28'>` puis `<Cube currency='USD' rate='1.1378'/>`.
    static func parseECB(_ data: Data) -> [String: Rate] {
        guard let xml = String(data: data, encoding: .utf8) else { return [:] }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = TimeZone(identifier: "Europe/Berlin")
        guard let dm = xml.range(of: #"time=['"]([0-9-]{10})['"]"#, options: .regularExpression),
              let date = fmt.date(from: String(xml[dm]).filter { $0.isNumber || $0 == "-" }) else { return [:] }
        var out: [String: Rate] = [:]
        let re = try! NSRegularExpression(pattern: #"currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]"#)
        for m in re.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
            guard let c = Range(m.range(at: 1), in: xml), let r = Range(m.range(at: 2), in: xml),
                  let v = Double(xml[r]), v > 0 else { continue }
            out[String(xml[c])] = Rate(perEUR: v, source: .ecb, date: date)
        }
        return out
    }

    static func fetchER() async throws -> [String: Rate] {
        let (data, _) = try await session.data(from: erURL)
        struct R: Decodable { let result: String; let time_last_update_unix: Double; let rates: [String: Double] }
        let r = try JSONDecoder().decode(R.self, from: data)
        guard r.result == "success" else { throw URLError(.badServerResponse) }
        let date = Date(timeIntervalSince1970: r.time_last_update_unix)
        return r.rates.filter { $0.value > 0 }.mapValues { Rate(perEUR: $0, source: .erapi, date: date) }
    }

    private static let enc: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let dec: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func readCache() -> Table? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? dec.decode(Table.self, from: data)
    }

    static func writeCache(_ t: Table) {
        try? enc.encode(t).write(to: cacheURL, options: .atomic)
    }

    // MARK: Taux d'un jour passe (cout d'achat en euros)

    /// Euros pour 1 unite de `code` au jour `date` (taux de reference BCE, via Frankfurter,
    /// gratuit et sans cle). Un week-end ou jour ferie rend le dernier jour ouvre, et la
    /// date reellement utilisee est rendue pour l'afficher.
    static func historicalEURPerUnit(_ code: String, on date: Date) async throws -> (eurPerUnit: Double, day: String) {
        if code == "EUR" { return (1, isoDay(date)) }
        guard let url = URL(string: "https://api.frankfurter.dev/v1/\(isoDay(date))?base=EUR&symbols=\(code)") else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("LifeOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let r = parseHistorical(data, code: code) else { throw URLError(.cannotParseResponse) }
        return r
    }

    /// `{"base":"EUR","date":"2024-01-12","rates":{"USD":1.0942}}` -> (1/1.0942, "2024-01-12").
    static func parseHistorical(_ data: Data, code: String) -> (eurPerUnit: Double, day: String)? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = j["rates"] as? [String: Any], let perEUR = (rates[code] as? NSNumber)?.doubleValue, perEUR > 0
        else { return nil }
        return (1 / perEUR, j["date"] as? String ?? "")
    }

    static func isoDay(_ d: Date) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        let x = c.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", x.year ?? 0, x.month ?? 0, x.day ?? 0)
    }
}
