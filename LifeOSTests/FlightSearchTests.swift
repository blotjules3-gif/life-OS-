import XCTest
@testable import LifeOS

/// Comparateur de vols, cote app. La reponse ci-dessous a ete produite par le
/// vrai moteur (flights-api, sources demo fictives) : si le JSON du Worker change,
/// ce test casse avant l'ecran.
@MainActor
final class FlightSearchTests: XCTestCase {

    static let engineResponse = #"{"at":"2026-09-28T19:12:19.410Z","cached":false,"cachedAgeMs":0,"partial":false,"statuses":{"demo-a":{"status":"ok","count":3,"ms":1},"demo-b":{"status":"ok","count":3,"ms":1}},"count":2,"cheapest":[{"key":"ZZ118@LIS2099-11-20T18:00","sources":["demo-a","demo-b"],"analysis":{"slices":[{"stops":0,"layovers":[],"durationMinutes":180}],"totalMinutes":180,"warnings":[]},"offers":[{"id":"demo-a:c","provider":"demo-a","providerRef":"c","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":180,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T18:00:00","arrivingAt":"2099-11-20T21:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"118","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":130,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:c","provider":"demo-b","providerRef":"c","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":180,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T18:00:00","arrivingAt":"2099-11-20T21:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"118","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":151,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null}]},{"key":"ZZ107@LIS2099-11-20T07:00","sources":["demo-a","demo-b"],"analysis":{"slices":[{"stops":0,"layovers":[],"durationMinutes":120}],"totalMinutes":120,"warnings":[]},"offers":[{"id":"demo-a:a","provider":"demo-a","providerRef":"a","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":140,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:a","provider":"demo-b","providerRef":"a","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":161,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null},{"id":"demo-a:b","provider":"demo-a","providerRef":"b","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Plus"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":175,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":1,"carryOn":1},"conditions":{"refundable":false,"changeable":true},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:b","provider":"demo-b","providerRef":"b","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Plus"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":196,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":1,"carryOn":1},"conditions":{"refundable":false,"changeable":true},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null}]}],"fastest":[{"key":"ZZ107@LIS2099-11-20T07:00","sources":["demo-a","demo-b"],"analysis":{"slices":[{"stops":0,"layovers":[],"durationMinutes":120}],"totalMinutes":120,"warnings":[]},"offers":[{"id":"demo-a:a","provider":"demo-a","providerRef":"a","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":140,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:a","provider":"demo-b","providerRef":"a","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":161,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null},{"id":"demo-a:b","provider":"demo-a","providerRef":"b","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Plus"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":175,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":1,"carryOn":1},"conditions":{"refundable":false,"changeable":true},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:b","provider":"demo-b","providerRef":"b","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Plus"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":196,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":1,"carryOn":1},"conditions":{"refundable":false,"changeable":true},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null}]},{"key":"ZZ118@LIS2099-11-20T18:00","sources":["demo-a","demo-b"],"analysis":{"slices":[{"stops":0,"layovers":[],"durationMinutes":180}],"totalMinutes":180,"warnings":[]},"offers":[{"id":"demo-a:c","provider":"demo-a","providerRef":"c","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":180,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T18:00:00","arrivingAt":"2099-11-20T21:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"118","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":130,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:c","provider":"demo-b","providerRef":"c","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":180,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T18:00:00","arrivingAt":"2099-11-20T21:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"118","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":151,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null}]}],"best":[{"key":"ZZ118@LIS2099-11-20T18:00","sources":["demo-a","demo-b"],"analysis":{"slices":[{"stops":0,"layovers":[],"durationMinutes":180}],"totalMinutes":180,"warnings":[]},"offers":[{"id":"demo-a:c","provider":"demo-a","providerRef":"c","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":180,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T18:00:00","arrivingAt":"2099-11-20T21:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"118","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":130,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:c","provider":"demo-b","providerRef":"c","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":180,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T18:00:00","arrivingAt":"2099-11-20T21:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"118","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":151,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null}],"explanation":"Le moins cher, 1 h 00 de plus que le plus rapide."},{"key":"ZZ107@LIS2099-11-20T07:00","sources":["demo-a","demo-b"],"analysis":{"slices":[{"stops":0,"layovers":[],"durationMinutes":120}],"totalMinutes":120,"warnings":[]},"offers":[{"id":"demo-a:a","provider":"demo-a","providerRef":"a","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":140,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:a","provider":"demo-b","providerRef":"a","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Light"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":161,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":0,"carryOn":1},"conditions":{"refundable":false,"changeable":false},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null},{"id":"demo-a:b","provider":"demo-a","providerRef":"b","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Plus"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":175,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":1,"carryOn":1},"conditions":{"refundable":false,"changeable":true},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.408Z","expiresAt":null},{"id":"demo-b:b","provider":"demo-b","providerRef":"b","demo":true,"seller":{"code":null,"name":"Démo LifeOS (fictif)","kind":"agency"},"slices":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"durationMinutes":120,"segments":[{"origin":{"iata":"LIS","timeZone":"Europe/Paris"},"destination":{"iata":"CDG","timeZone":"Europe/Paris"},"departingAt":"2099-11-20T07:00:00","arrivingAt":"2099-11-20T09:00:00","marketingCarrier":{"code":"ZZ","name":"Démo Air"},"operatingCarrier":{"code":"ZZ","name":"Démo Air"},"flightNumber":"107","cabin":"economy","fareBrand":"Plus"}]}],"passengers":{"adults":1,"children":0,"infants":0},"price":{"total":196,"currency":"EUR","taxesKnown":true,"feesNote":"Fictif."},"baggage":{"checked":1,"carryOn":1},"conditions":{"refundable":false,"changeable":true},"selfTransfer":false,"fetchedAt":"2026-09-28T19:12:19.409Z","expiresAt":null}],"explanation":"10 EUR de plus que le moins cher, le plus rapide."}]}"#

    private var session: URLSession!
    private let endpoint = FlightSearch.Endpoint(base: URL(string: "https://flights.test")!, key: "k")

    override func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: c)
        StubURLProtocol.routes = []; StubURLProtocol.failWith = nil; StubURLProtocol.requested = []
    }

    private func future(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: .now)! }

    func testDecodesRealEngineResponse() throws {
        let r = try JSONDecoder().decode(FlightSearch.Result.self, from: Data(Self.engineResponse.utf8))
        XCTAssertFalse(r.partial)
        XCTAssertEqual(Set(r.statuses.keys), ["demo-a", "demo-b"])
        let g = try XCTUnwrap(r.cheapest.first)
        XCTAssertTrue(g.isDemo)
        XCTAssertEqual(g.sources.count, 2, "le même vol vu chez deux sources reste un seul itinéraire")
        XCTAssertEqual(g.offers.map(\.price.total), g.offers.map(\.price.total).sorted(), "offres triées par prix")
        XCTAssertNotNil(r.best.first?.explanation)
    }

    func testValidationBeforeAnyCall() {
        var q = FlightSearch.Query()
        q.legs = [.init(origin: "LI", destination: "CDG", date: future(10))]
        XCTAssertTrue(q.problems().contains { $0.contains("Départ") })
        q.legs = [.init(origin: "LIS", destination: "lis", date: future(10))]
        XCTAssertTrue(q.problems().contains { $0.contains("identiques") })
        q.legs = [.init(origin: "LIS", destination: "CDG", date: future(10))]
        q.returnDate = future(3)
        XCTAssertTrue(q.problems().contains { $0.contains("avant le trajet précédent") }, "retour avant l'aller")
        q.returnDate = future(17)
        q.passengers = .init(adults: 1, children: 0, infants: 2)
        XCTAssertTrue(q.problems().contains { $0.contains("bébé") })
        q.passengers = .init()
        XCTAssertEqual(q.problems(), [])
        XCTAssertEqual(q.slices.count, 2)
        XCTAssertEqual(q.slices[1].origin, "CDG", "le retour est déduit de l'aller")
    }

    func testSearchSendsKeyAndBodyAndDecodes() async throws {
        StubURLProtocol.routes = [("/v1/search", 200, Data(Self.engineResponse.utf8))]
        var q = FlightSearch.Query(); q.kind = .oneWay
        q.legs = [.init(origin: "lis", destination: "cdg", date: future(20))]
        let r = try await FlightSearch.search(q, filters: .init(), endpoint: endpoint, session: session)
        XCTAssertGreaterThan(r.count, 0)
        XCTAssertEqual(StubURLProtocol.requested.first?.path, "/v1/search")
    }

    func testInvalidQueryNeverReachesServer() async {
        var q = FlightSearch.Query(); q.legs = [.init(origin: "", destination: "CDG", date: future(5))]
        do { _ = try await FlightSearch.search(q, filters: .init(), endpoint: endpoint, session: session); XCTFail("devait refuser") }
        catch { XCTAssertTrue(StubURLProtocol.requested.isEmpty) }
    }

    func testNotConfiguredIsSaidNotFaked() async {
        var q = FlightSearch.Query(); q.legs = [.init(origin: "LIS", destination: "CDG", date: future(5))]
        do { _ = try await FlightSearch.search(q, filters: .init(), endpoint: nil, session: session); XCTFail("devait refuser") }
        catch { XCTAssertEqual(error.localizedDescription, "Le moteur de vols n'est pas encore branché.") }
    }

    func testServerErrorMessageIsShown() async {
        StubURLProtocol.routes = [("/v1/search", 400, Data(#"{"error":["Date passée."]}"#.utf8))]
        var q = FlightSearch.Query(); q.legs = [.init(origin: "LIS", destination: "CDG", date: future(5))]
        do { _ = try await FlightSearch.search(q, filters: .init(), endpoint: endpoint, session: session); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, "Date passée.") }
    }

    func testChildAgesRequiredAndSent() throws {
        var q = FlightSearch.Query(); q.kind = .oneWay
        q.legs = [.init(origin: "LIS", destination: "CDG", date: future(12))]
        q.passengers = .init(adults: 1, children: 2, childAges: [7, 0])
        XCTAssertTrue(q.problems().contains { $0.contains("âge de chaque enfant") }, "un âge non choisi bloque la recherche")
        q.passengers.childAges = [7, 13]
        XCTAssertEqual(q.problems(), [])
        let pax = try XCTUnwrap(q.body(filters: .init())["passengers"] as? [String: Any])
        XCTAssertEqual(pax["childAges"] as? [Int], [7, 13])
    }

    func testOldSavedPassengersStillDecode() throws {
        let old = Data(#"{"adults":2,"children":0,"infants":1}"#.utf8)
        let p = try JSONDecoder().decode(FlightSearch.Passengers.self, from: old)
        XCTAssertEqual(p.adults, 2); XCTAssertEqual(p.childAges, [])
    }

    func testStreamLinesPartialDoneError() throws {
        let partial = Data(Self.engineResponse.replacingOccurrences(of: #"{"at""#, with: #"{"type":"partial","provider":"demo-a","at""#).utf8)
        let (kind, result, _) = try FlightSearch.parseStreamLine(partial)
        XCTAssertEqual(kind, "partial"); XCTAssertNotNil(result)
        let (ek, er, msg) = try FlightSearch.parseStreamLine(Data(#"{"type":"error","message":"Source en panne"}"#.utf8))
        XCTAssertEqual(ek, "error"); XCTAssertNil(er); XCTAssertEqual(msg, "Source en panne")
    }

    func testConvertedPriceShowsBilledAmount() throws {
        let json = #"{"total":100,"currency":"EUR","taxesKnown":true,"original":{"total":117.12,"currency":"USD"},"conversion":{"rate":0.8538,"source":"BCE","date":"2026-09-28"}}"#
        let p = try JSONDecoder().decode(FlightSearch.Price.self, from: Data(json.utf8))
        XCTAssertTrue(FlightSearch.priceLabel(p).hasPrefix("≈ "))
        let note = try XCTUnwrap(FlightSearch.billedNote(p))
        XCTAssertTrue(note.contains("BCE du 2026-09-28"))
        let plain = try JSONDecoder().decode(FlightSearch.Price.self, from: Data(#"{"total":90,"currency":"EUR","taxesKnown":true}"#.utf8))
        XCTAssertFalse(FlightSearch.priceLabel(plain).hasPrefix("≈"))
        XCTAssertNil(FlightSearch.billedNote(plain))
    }

    func testAlertTriggerSignalledOncePerDrop() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("flights-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var q = FlightSearch.Query(); q.legs = [.init(origin: "LIS", destination: "CDG", date: future(9))]
        let lib = FlightLibrary(url: url)
        lib.add(.init(ticket: .init(id: "a1", token: "t"), query: q, maxPrice: 120, createdAt: .now))
        let s = FlightSearch.AlertState(id: "a1", maxPrice: 120, triggered: true, lastPrice: .init(total: 99, currency: "EUR"), lastCheck: nil, triggeredAt: "2026-10-01T06:00:00Z", lastError: nil)
        XCTAssertEqual(lib.newTriggers(["a1": s]).count, 1)
        lib.markNotified("a1", triggeredAt: "2026-10-01T06:00:00Z")
        XCTAssertEqual(FlightLibrary(url: url).newTriggers(["a1": s]).count, 0, "déjà signalé, même après relance")
        var again = s; again.triggeredAt = "2026-10-05T06:00:00Z"
        XCTAssertEqual(lib.newTriggers(["a1": again]).count, 1, "nouvelle baisse après remontée: signalée")
    }

    func testDifferencesExplainUnequalOffers() throws {
        let r = try JSONDecoder().decode(FlightSearch.Result.self, from: Data(Self.engineResponse.utf8))
        let g = try XCTUnwrap(r.cheapest.first { $0.offers.count >= 4 } ?? r.best.first { $0.offers.count >= 4 })
        let light = try XCTUnwrap(g.offers.first { $0.baggage.checked == 0 })
        let plus = try XCTUnwrap(g.offers.first { $0.baggage.checked == 1 })
        XCTAssertTrue(FlightSearch.differences(light, plus).contains("bagage soute"))
        let twin = try XCTUnwrap(g.offers.first { $0.id != light.id && $0.baggage.checked == 0 })
        XCTAssertEqual(FlightSearch.differences(light, twin), [], "même tarif chez deux sources : comparables")
    }

    func testTripNoteSaysNotBookedAndDemo() throws {
        let r = try JSONDecoder().decode(FlightSearch.Result.self, from: Data(Self.engineResponse.utf8))
        let g = try XCTUnwrap(r.cheapest.first), o = try XCTUnwrap(g.cheapest)
        let note = FlightSearch.tripNote(group: g, offer: o)
        XCTAssertTrue(note.contains("NON réservé"))
        XCTAssertTrue(note.contains("DONNÉES FICTIVES"))
        XCTAssertTrue(note.contains("LIS"))
    }

    func testLocalTimeUsesAirportZone() {
        let lis = FlightSearch.localDate("2026-10-20T08:00:00", tz: "Europe/Lisbon")!
        let cdg = FlightSearch.localDate("2026-10-20T11:40:00", tz: "Europe/Paris")!
        XCTAssertEqual(cdg.timeIntervalSince(lis) / 60, 160)
        XCTAssertEqual(FlightSearch.clock("2026-10-20T08:05:00"), "08:05")
        XCTAssertEqual(FlightSearch.duration(155), "2 h 35")
        XCTAssertEqual(FlightSearch.duration(nil), "durée inconnue")
    }

    func testLibraryPersistsHistoryFavoritesAlerts() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("flights-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try JSONDecoder().decode(FlightSearch.Result.self, from: Data(Self.engineResponse.utf8))
        var q = FlightSearch.Query(); q.legs = [.init(origin: "LIS", destination: "CDG", date: future(9))]
        let lib = FlightLibrary(url: url)
        lib.remember(q); lib.remember(q)
        XCTAssertEqual(lib.saved.history.count, 1, "même recherche gardée une fois")
        lib.toggleFavorite(r.cheapest[0], query: q)
        lib.add(.init(ticket: .init(id: "a1", token: "t"), query: q, maxPrice: 120, createdAt: .now))
        let reopened = FlightLibrary(url: url)
        XCTAssertEqual(reopened.saved.history.count, 1)
        XCTAssertTrue(reopened.isFavorite(r.cheapest[0]))
        XCTAssertEqual(reopened.saved.alerts.first?.maxPrice, 120)
        reopened.toggleFavorite(r.cheapest[0], query: q)
        XCTAssertFalse(FlightLibrary(url: url).isFavorite(r.cheapest[0]))
    }

    func testUnsubscribeTreatsGoneAlertAsDone() async throws {
        StubURLProtocol.routes = [("/v1/alerts/a1", 404, Data(#"{"error":"Alerte inconnue."}"#.utf8))]
        try await FlightSearch.deleteAlert(.init(id: "a1", token: "t"), endpoint: endpoint, session: session)
        let state = try await FlightSearch.fetchAlert(.init(id: "a1", token: "t"), endpoint: endpoint, session: session)
        XCTAssertNil(state)
    }
}
