import Foundation

/// Client du comparateur de vols LifeOS (`apps/lifeos/flights-api`).
///
/// L'app ne parle JAMAIS a un fournisseur de vols: elle parle a notre Worker, qui
/// garde les cles des fournisseurs et fait la recherche multi-sources. Ici: le
/// modele (miroir exact du JSON du Worker), la requete validee, l'appel, et le
/// stockage local de l'historique, des favoris et des alertes.
enum FlightSearch {

    // MARK: - Modele (miroir de flights-api/core.js)

    struct Place: Codable, Hashable { var iata: String; var name: String?; var timeZone: String? }
    struct Carrier: Codable, Hashable { var code: String?; var name: String? }

    struct Segment: Codable, Hashable {
        var origin: Place; var destination: Place
        var departingAt: String; var arrivingAt: String
        var marketingCarrier: Carrier; var operatingCarrier: Carrier
        var flightNumber: String?; var cabin: String?; var fareBrand: String?

        var departure: Date? { FlightSearch.localDate(departingAt, tz: origin.timeZone) }
        var arrival: Date? { FlightSearch.localDate(arrivingAt, tz: destination.timeZone) }
        var flightLabel: String { "\(marketingCarrier.code ?? "?")\(flightNumber ?? "")" }
        /// Vol vendu par une compagnie et opere par une autre (partage de code).
        var codeshare: Bool {
            guard let m = marketingCarrier.code, let o = operatingCarrier.code else { return false }
            return m != o
        }
    }

    struct Slice: Codable, Hashable { var origin: Place; var destination: Place; var durationMinutes: Int?; var segments: [Segment] }
    struct Seller: Codable, Hashable { var code: String?; var name: String; var kind: String? }
    struct Price: Codable, Hashable {
        var total: Double; var currency: String; var taxesKnown: Bool; var feesNote: String?
        /// Prix reellement facture, quand `total` est une conversion.
        var original: Billed?; var conversion: Conversion?
        struct Billed: Codable, Hashable { var total: Double; var currency: String }
        struct Conversion: Codable, Hashable { var rate: Double; var source: String; var date: String }
    }
    /// `checked`/`carryOn` = franchise GARANTIE a chaque voyageur (la plus petite).
    struct Baggage: Codable, Hashable {
        var checked: Int?; var carryOn: Int?
        var varies: Bool?; var perPassenger: [PaxBaggage]?
        struct PaxBaggage: Codable, Hashable { var label: String; var checked: Int?; var carryOn: Int? }
    }
    struct Conditions: Codable, Hashable { var refundable: Bool?; var changeable: Bool? }

    struct Offer: Codable, Hashable, Identifiable {
        var id: String; var provider: String; var providerRef: String
        var demo: Bool; var seller: Seller; var slices: [Slice]
        var passengers: Passengers; var price: Price; var baggage: Baggage
        var conditions: Conditions; var selfTransfer: Bool
        var fetchedAt: String; var expiresAt: String?

        var expiry: Date? { expiresAt.flatMap { ISO8601DateFormatter.lenient.date(from: $0) } }
    }

    struct Layover: Codable, Hashable { var at: String; var minutes: Int?; var airportChange: Bool; var overnight: Bool }
    struct SliceAnalysis: Codable, Hashable { var stops: Int; var layovers: [Layover]; var durationMinutes: Int? }
    struct Analysis: Codable, Hashable { var slices: [SliceAnalysis]; var totalMinutes: Int?; var warnings: [String] }

    /// Un itineraire (les memes vols) et TOUTES ses offres, triees par prix.
    struct Group: Codable, Hashable, Identifiable {
        var key: String; var sources: [String]; var analysis: Analysis; var offers: [Offer]
        var explanation: String?
        var id: String { key }
        var cheapest: Offer? { offers.first }
        var isDemo: Bool { offers.allSatisfy(\.demo) }
        var maxStops: Int { analysis.slices.map(\.stops).max() ?? 0 }
    }

    struct SourceStatus: Codable, Hashable { var status: String; var count: Int?; var ms: Int?; var message: String?; var code: String? }

    struct Result: Codable {
        var at: String; var cached: Bool; var cachedAgeMs: Int?
        var partial: Bool; var statuses: [String: SourceStatus]
        var count: Int; var cheapest: [Group]; var fastest: [Group]; var best: [Group]
        /// Offres dans une autre devise, sans taux pour les convertir: jamais classees.
        var setAside: SetAside?; var ratesDate: String?
        struct SetAside: Codable, Hashable { var count: Int; var currencies: [String] }
    }

    struct Confirmation: Codable {
        var status: String            // same_price | price_changed | unavailable | error
        var offer: Offer?; var previousTotal: Double?; var previousCurrency: String?; var delta: Double?; var reason: String?
    }

    // MARK: - Requete

    struct Passengers: Codable, Hashable {
        var adults = 1; var children = 0; var infants = 0
        /// Age de chaque enfant, exige par les compagnies. 0 = pas encore indique.
        var childAges: [Int] = []
        init(adults: Int = 1, children: Int = 0, infants: Int = 0, childAges: [Int] = []) {
            self.adults = adults; self.children = children; self.infants = infants; self.childAges = childAges
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            adults = try c.decode(Int.self, forKey: .adults)
            children = try c.decode(Int.self, forKey: .children)
            infants = try c.decode(Int.self, forKey: .infants)
            childAges = try c.decodeIfPresent([Int].self, forKey: .childAges) ?? []
        }
    }

    struct Leg: Codable, Hashable, Identifiable {
        var id = UUID()
        var origin = ""; var destination = ""; var date = Date()
        enum CodingKeys: String, CodingKey { case origin, destination, date }
        init(origin: String = "", destination: String = "", date: Date = Date()) { self.origin = origin; self.destination = destination; self.date = date }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            origin = try c.decode(String.self, forKey: .origin); destination = try c.decode(String.self, forKey: .destination)
            date = try c.decode(Date.self, forKey: .date)
        }
        func encode(to e: Encoder) throws {
            var c = e.container(keyedBy: CodingKeys.self)
            try c.encode(origin, forKey: .origin); try c.encode(destination, forKey: .destination); try c.encode(date, forKey: .date)
        }
    }

    enum TripKind: String, Codable, CaseIterable, Identifiable { case oneWay, roundTrip, multiCity
        var id: String { rawValue }
        var label: String { switch self { case .oneWay: "Aller simple"; case .roundTrip: "Aller-retour"; case .multiCity: "Multi-villes" } }
    }

    enum Cabin: String, Codable, CaseIterable, Identifiable { case economy, premium_economy, business, first
        var id: String { rawValue }
        var label: String { switch self { case .economy: "Éco"; case .premium_economy: "Premium"; case .business: "Affaires"; case .first: "Première" } }
    }

    struct Query: Codable, Hashable {
        var kind: TripKind = .roundTrip
        var legs: [Leg] = [Leg()]
        var returnDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        var passengers = Passengers()
        var cabin: Cabin = .economy
        var currency = "EUR"
        var maxConnections = 2

        /// Trajets reels envoyes au moteur (le retour est deduit de l'aller).
        var slices: [Leg] {
            switch kind {
            case .oneWay: return Array(legs.prefix(1))
            case .roundTrip:
                guard let out = legs.first else { return [] }
                return [out, Leg(origin: out.destination, destination: out.origin, date: returnDate)]
            case .multiCity: return legs
            }
        }

        /// Erreurs a montrer AVANT d'appeler le serveur. Les memes regles que le Worker.
        func problems(now: Date = .now) -> [String] {
            var out: [String] = []
            let today = Calendar.current.startOfDay(for: now)
            for (i, s) in slices.enumerated() {
                let n = slices.count > 1 ? " (trajet \(i + 1))" : ""
                if !FlightSearch.isIATA(s.origin) { out.append("Départ\(n) : code aéroport à 3 lettres, par exemple LIS.") }
                if !FlightSearch.isIATA(s.destination) { out.append("Arrivée\(n) : code aéroport à 3 lettres, par exemple CDG.") }
                if FlightSearch.isIATA(s.origin), s.origin.uppercased() == s.destination.uppercased() { out.append("Départ et arrivée identiques\(n).") }
                if Calendar.current.startOfDay(for: s.date) < today { out.append("Date passée\(n).") }
                if i > 0, Calendar.current.startOfDay(for: s.date) < Calendar.current.startOfDay(for: slices[i - 1].date) {
                    out.append("Le trajet \(i + 1) part avant le trajet précédent.")
                }
            }
            if passengers.adults < 1 { out.append("Au moins un adulte.") }
            if passengers.infants > passengers.adults { out.append("Un bébé par adulte au maximum.") }
            if passengers.adults + passengers.children + passengers.infants > 9 { out.append("9 voyageurs au maximum.") }
            if passengers.children > 0,
               passengers.childAges.count != passengers.children || passengers.childAges.contains(where: { !(2...17).contains($0) }) {
                out.append("Indique l'âge de chaque enfant.")
            }
            return out
        }

        func body(filters: Filters) -> [String: Any] {
            [
                "slices": slices.map { ["origin": $0.origin.uppercased(), "destination": $0.destination.uppercased(), "date": FlightSearch.day($0.date)] },
                "passengers": ["adults": passengers.adults, "children": passengers.children, "infants": passengers.infants,
                               "childAges": Array(passengers.childAges.prefix(passengers.children))],
                "cabin": cabin.rawValue, "currency": currency, "maxConnections": maxConnections,
                "filters": filters.json,
            ]
        }

        var summary: String {
            let route = slices.map { "\($0.origin.uppercased())→\($0.destination.uppercased())" }.joined(separator: ", ")
            let n = passengers.adults + passengers.children + passengers.infants
            return "\(route) · \(slices.first.map { FlightSearch.shortDay($0.date) } ?? "") · \(n) voyageur\(n > 1 ? "s" : "")"
        }
    }

    struct Filters: Codable, Hashable {
        var maxStops: Int? = nil
        var checkedBagRequired = false
        var noSelfTransfer = false
        var noAirportChange = false
        var maxPrice: Double? = nil

        var json: [String: Any] {
            var d: [String: Any] = ["checkedBagRequired": checkedBagRequired, "noSelfTransfer": noSelfTransfer, "noAirportChange": noAirportChange]
            if let maxStops { d["maxStops"] = maxStops }
            if let maxPrice { d["maxPrice"] = maxPrice }
            return d
        }
    }

    // MARK: - Configuration

    struct Endpoint: Equatable { var base: URL; var key: String }

    /// Adresse et cle du Worker. Info.plist (`FLIGHTS_API_URL`, `FLIGHTS_APP_KEY`),
    /// ou en DEBUG `-flightsAPI http://127.0.0.1:8787` pour le serveur local.
    static var endpoint: Endpoint? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-flightsAPI"), i + 1 < args.count, let u = URL(string: args[i + 1]) {
            return Endpoint(base: u, key: "dev-key")
        }
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        guard let raw = info["FLIGHTS_API_URL"] as? String, !raw.isEmpty, !raw.contains("$("),
              let url = URL(string: raw), url.scheme == "https",
              let key = info["FLIGHTS_APP_KEY"] as? String, !key.isEmpty, !key.contains("$(") else { return nil }
        return Endpoint(base: url, key: key)
    }

    // MARK: - Appels

    enum Failure: LocalizedError {
        case notConfigured, invalid([String]), server(String), network(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Le moteur de vols n'est pas encore branché."
            case .invalid(let list): list.joined(separator: "\n")
            case .server(let m): m
            case .network(let m): "Réseau : \(m)"
            }
        }
    }

    static func search(_ q: Query, filters: Filters, endpoint: Endpoint? = endpoint, session: URLSession = .shared) async throws -> Result {
        let problems = q.problems()
        guard problems.isEmpty else { throw Failure.invalid(problems) }
        return try await post("v1/search", q.body(filters: filters), endpoint: endpoint, session: session)
    }

    /// Recherche progressive: un resultat partiel complet (regroupe, classe par le
    /// serveur) a chaque source qui repond, puis le resultat final.
    static func searchStream(_ q: Query, filters: Filters, endpoint: Endpoint? = endpoint, session: URLSession = .shared,
                             onPartial: @MainActor @escaping (Result) -> Void) async throws -> Result {
        let problems = q.problems()
        guard problems.isEmpty else { throw Failure.invalid(problems) }
        guard let endpoint else { throw Failure.notConfigured }
        var c = URLComponents(url: endpoint.base.appendingPathComponent("v1/search"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "stream", value: "1")]
        var req = URLRequest(url: c.url!)
        req.httpMethod = "POST"; req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(endpoint.key, forHTTPHeaderField: "X-LifeOS-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: q.body(filters: filters))
        let bytes: URLSession.AsyncBytes, resp: URLResponse
        do { (bytes, resp) = try await session.bytes(for: req) }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw Failure.network(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            var data = Data(); for try await b in bytes { data.append(b) }
            throw Failure.server(serverMessage(data) ?? "Erreur du moteur (\(code)).")
        }
        var final: Result?
        for try await line in bytes.lines {
            let (kind, result, message) = try parseStreamLine(Data(line.utf8))
            switch kind {
            case "partial": if let result { await onPartial(result) }
            case "done": final = result
            case "error": throw Failure.server(message ?? "Erreur du moteur.")
            default: continue
            }
        }
        guard let final else { throw Failure.server("Réponse du moteur incomplète.") }
        return final
    }

    /// Une ligne NDJSON du moteur -> (type, resultat, message d'erreur).
    static func parseStreamLine(_ data: Data) throws -> (String, Result?, String?) {
        struct Head: Decodable { var type: String; var message: String? }
        guard let head = try? JSONDecoder().decode(Head.self, from: data) else { return ("", nil, nil) }
        if head.type == "error" { return ("error", nil, head.message) }
        do { return (head.type, try JSONDecoder().decode(Result.self, from: data), nil) }
        catch { throw Failure.server("Réponse du moteur illisible.") }
    }

    /// Ce que le serveur sait faire aujourd'hui: sources, budget, alertes.
    struct Info: Codable {
        var multiSource: Bool
        var budget: Budget; var alerts: Alerts
        struct Budget: Codable { var configured: Bool }
        struct Alerts: Codable { var serverChecks: Bool }
    }

    static func info(endpoint: Endpoint? = endpoint, session: URLSession = .shared) async throws -> Info {
        guard let endpoint else { throw Failure.notConfigured }
        var req = URLRequest(url: endpoint.base.appendingPathComponent("v1/providers"))
        req.setValue(endpoint.key, forHTTPHeaderField: "X-LifeOS-Key")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.server(serverMessage(data) ?? "Serveur injoignable.") }
        return try JSONDecoder().decode(Info.self, from: data)
    }

    static func confirm(_ offer: Offer, query: Query, endpoint: Endpoint? = endpoint, session: URLSession = .shared) async throws -> Confirmation {
        let offerJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(offer))
        let body: [String: Any] = ["offer": offerJSON, "query": q(query)]
        return try await post("v1/confirm", body, endpoint: endpoint, session: session)
    }

    struct AlertTicket: Codable, Hashable { var id: String; var token: String }

    static func createAlert(_ query: Query, maxPrice: Double, endpoint: Endpoint? = endpoint, session: URLSession = .shared) async throws -> AlertTicket {
        try await post("v1/alerts", ["query": q(query), "maxPrice": maxPrice], endpoint: endpoint, session: session)
    }

    static func deleteAlert(_ ticket: AlertTicket, endpoint: Endpoint? = endpoint, session: URLSession = .shared) async throws {
        guard let endpoint else { throw Failure.notConfigured }
        var c = URLComponents(url: endpoint.base.appendingPathComponent("v1/alerts/\(ticket.id)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "token", value: ticket.token)]
        var req = URLRequest(url: c.url!); req.httpMethod = "DELETE"
        req.setValue(endpoint.key, forHTTPHeaderField: "X-LifeOS-Key")
        let (_, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // 404: deja desinscrite cote serveur, ce qui est le resultat voulu.
        guard code == 200 || code == 404 else { throw Failure.server("Désinscription refusée (\(code)).") }
    }

    struct AlertState: Codable, Hashable {
        var id: String; var maxPrice: Double; var triggered: Bool; var lastPrice: LastPrice?; var lastCheck: String?
        var triggeredAt: String?; var lastError: String?
        struct LastPrice: Codable, Hashable { var total: Double; var currency: String }
    }

    /// Etat vu par la tache serveur. nil = l'alerte n'existe plus cote serveur.
    static func fetchAlert(_ ticket: AlertTicket, endpoint: Endpoint? = endpoint, session: URLSession = .shared) async throws -> AlertState? {
        guard let endpoint else { throw Failure.notConfigured }
        var c = URLComponents(url: endpoint.base.appendingPathComponent("v1/alerts/\(ticket.id)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "token", value: ticket.token)]
        var req = URLRequest(url: c.url!)
        req.setValue(endpoint.key, forHTTPHeaderField: "X-LifeOS-Key")
        let (data, resp) = try await session.data(for: req)
        switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return try JSONDecoder().decode(AlertState.self, from: data)
        case 404: return nil
        case let code: throw Failure.server(serverMessage(data) ?? "Alerte illisible (\(code)).")
        }
    }

    private static func q(_ query: Query) -> [String: Any] {
        var b = query.body(filters: Filters()); b["filters"] = nil; return b
    }

    private static func post<T: Decodable>(_ path: String, _ body: [String: Any], endpoint: Endpoint?, session: URLSession) async throws -> T {
        guard let endpoint else { throw Failure.notConfigured }
        var req = URLRequest(url: endpoint.base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(endpoint.key, forHTTPHeaderField: "X-LifeOS-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw Failure.network(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.server(serverMessage(data) ?? "Erreur du moteur (\(code)).") }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Failure.server("Réponse du moteur illisible.") }
    }

    static func serverMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let list = obj["error"] as? [String] { return list.joined(separator: "\n") }
        return obj["error"] as? String ?? obj["reason"] as? String
    }

    // MARK: - Comparaison d'offres

    /// Deux offres ne se comparent au prix que si elles donnent la meme chose.
    static func differences(_ a: Offer, _ b: Offer) -> [String] {
        var out: [String] = []
        if a.baggage.checked != b.baggage.checked { out.append("bagage soute") }
        if a.conditions.refundable != b.conditions.refundable || a.conditions.changeable != b.conditions.changeable { out.append("conditions") }
        let fa = a.slices.flatMap(\.segments).map { "\($0.cabin ?? "")/\($0.fareBrand ?? "")" }
        let fb = b.slices.flatMap(\.segments).map { "\($0.cabin ?? "")/\($0.fareBrand ?? "")" }
        if fa != fb { out.append("classe ou tarif") }
        if a.price.taxesKnown != b.price.taxesKnown { out.append("frais connus") }
        if a.price.original?.currency != b.price.original?.currency { out.append("devise facturée") }
        return out
    }

    // MARK: - Outils

    static func isIATA(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count == 3 && t.allSatisfy { $0.isASCII && $0.isLetter }
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    static func shortDay(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }

    /// "2026-10-20T08:00:00" a l'heure locale de l'aeroport -> instant exact.
    static func localDate(_ s: String, tz: String?) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(s.prefix(19)))
    }

    /// Heure locale de l'aeroport telle qu'ecrite sur le billet ("08:00").
    static func clock(_ s: String) -> String { s.count >= 16 ? String(s.dropFirst(11).prefix(5)) : s }

    static func duration(_ minutes: Int?) -> String {
        guard let m = minutes else { return "durée inconnue" }
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
    }

    static func money(_ p: Price) -> String {
        p.total.formatted(.currency(code: p.currency).precision(.fractionLength(p.total.rounded() == p.total ? 0 : 2)))
    }

    /// Prix affiche: converti = approximatif, et le montant facture est dit.
    static func priceLabel(_ p: Price) -> String { (p.original == nil ? "" : "≈ ") + money(p) }

    static func billedNote(_ p: Price) -> String? {
        guard let o = p.original, let c = p.conversion else { return nil }
        let billed = o.total.formatted(.currency(code: o.currency))
        return "Facturé \(billed) par le vendeur. Converti au taux \(c.source) du \(c.date), indicatif : ta banque appliquera le sien."
    }

    static func stopsLabel(_ n: Int) -> String { n == 0 ? "Direct" : n == 1 ? "1 escale" : "\(n) escales" }

    static func statusLabel(_ s: SourceStatus) -> String {
        switch s.status {
        case "ok": "\(s.count ?? 0) offre\((s.count ?? 0) > 1 ? "s" : "")"
        case "timeout": "trop lente, coupée"
        case "skipped_budget": s.message ?? "budget du jour atteint"
        case "no_source": "aucune source active"
        default: s.message ?? "en erreur"
        }
    }

    /// Texte ajoute a un voyage LifeOS. Dit clairement que RIEN n'est reserve.
    static func tripNote(group g: Group, offer o: Offer, checkedAt: Date = .now) -> String {
        var lines = ["✈︎ Vol envisagé, NON réservé (vu le \(checkedAt.formatted(.dateTime.day().month().hour().minute())))"]
        for s in o.slices {
            for seg in s.segments {
                var l = "• \(seg.flightLabel) \(seg.origin.iata) \(clock(seg.departingAt)) → \(seg.destination.iata) \(clock(seg.arrivingAt)), le \(String(seg.departingAt.prefix(10)))"
                if seg.codeshare, let op = seg.operatingCarrier.name ?? seg.operatingCarrier.code { l += ", opéré par \(op)" }
                lines.append(l)
            }
        }
        lines.append("Prix vu : \(priceLabel(o.price)) chez \(o.seller.name)\(o.price.taxesKnown ? "" : " (frais pas tous connus)")")
        if let note = billedNote(o.price) { lines.append(note) }
        if o.demo { lines.append("DONNÉES FICTIVES (démo), ne pas réserver sur cette base.") }
        lines.append("Bagage soute : \(o.baggage.checked.map { $0 == 0 ? "non inclus" : "\($0) inclus" } ?? "inconnu")\(o.baggage.varies == true ? " (varie selon le voyageur)" : "")")
        return lines.joined(separator: "\n")
    }
}

extension ISO8601DateFormatter {
    static let lenient: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
}

// MARK: - Historique, favoris, alertes (local, JSON)

/// Ce que l'utilisateur garde: recherches recentes, itineraires favoris, alertes.
/// Un fichier JSON dans Documents: entre dans la sauvegarde complete, sort a
/// l'effacement des donnees, jamais melange au SwiftData.
@MainActor final class FlightLibrary: ObservableObject {
    struct Favorite: Codable, Identifiable, Hashable {
        var id: String { group.key }
        var group: FlightSearch.Group; var query: FlightSearch.Query; var savedAt: Date
    }
    struct Alert: Codable, Identifiable, Hashable {
        var id: String { ticket.id }
        var ticket: FlightSearch.AlertTicket; var query: FlightSearch.Query; var maxPrice: Double; var createdAt: Date
    }
    struct Saved: Codable {
        var history: [FlightSearch.Query] = []; var favorites: [Favorite] = []; var alerts: [Alert] = []
        /// Alerte -> declenchement deja signale (triggeredAt), pour ne prevenir qu'une fois.
        var notified: [String: String] = [:]
        init() {}
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            history = try c.decodeIfPresent([FlightSearch.Query].self, forKey: .history) ?? []
            favorites = try c.decodeIfPresent([Favorite].self, forKey: .favorites) ?? []
            alerts = try c.decodeIfPresent([Alert].self, forKey: .alerts) ?? []
            notified = try c.decodeIfPresent([String: String].self, forKey: .notified) ?? [:]
        }
    }

    @Published private(set) var saved = Saved()
    /// Derniere ecriture ratee, montree a l'ecran plutot que perdue.
    @Published var writeError: String?
    let url: URL

    nonisolated static let fileName = "flights.json"
    init(url: URL = AppPaths.documents.appendingPathComponent(FlightLibrary.fileName)) {
        self.url = url
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: data) { saved = s }
    }

    func remember(_ q: FlightSearch.Query) {
        saved.history.removeAll { $0.summary == q.summary && $0.cabin == q.cabin }
        saved.history.insert(q, at: 0)
        saved.history = Array(saved.history.prefix(20))
        persist()
    }
    func clearHistory() { saved.history = []; persist() }

    func isFavorite(_ g: FlightSearch.Group) -> Bool { saved.favorites.contains { $0.group.key == g.key } }
    func toggleFavorite(_ g: FlightSearch.Group, query: FlightSearch.Query) {
        if isFavorite(g) { saved.favorites.removeAll { $0.group.key == g.key } }
        else { saved.favorites.insert(Favorite(group: g, query: query, savedAt: .now), at: 0) }
        persist()
    }
    func removeFavorite(_ f: Favorite) { saved.favorites.removeAll { $0.id == f.id }; persist() }

    func add(_ a: Alert) { saved.alerts.insert(a, at: 0); persist() }
    func removeAlert(_ a: Alert) { saved.alerts.removeAll { $0.id == a.id }; saved.notified[a.id] = nil; persist() }

    /// Declenchements pas encore signales. La verification tourne sur le serveur; le
    /// signalement se fait ici, dans l'app, une seule fois par baisse.
    func newTriggers(_ states: [String: FlightSearch.AlertState]) -> [(Alert, FlightSearch.AlertState)] {
        saved.alerts.compactMap { a in
            guard let s = states[a.id], s.triggered, let at = s.triggeredAt, saved.notified[a.id] != at else { return nil }
            return (a, s)
        }
    }

    func markNotified(_ id: String, triggeredAt: String) { saved.notified[id] = triggeredAt; persist() }

    private func persist() {
        do { try JSONEncoder().encode(saved).write(to: url, options: .atomic); writeError = nil }
        catch { writeError = "Enregistrement impossible : \(error.localizedDescription)" }
    }
}
