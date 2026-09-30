import XCTest
@testable import LifeOS

final class ExchangeRatesTests: XCTestCase {

    override func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        ExchangeRates.session = URLSession(configuration: c)
        ExchangeRates.cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("fx-\(UUID()).json")
        StubURLProtocol.routes = []; StubURLProtocol.failWith = nil; StubURLProtocol.requested = []
    }
    override func tearDown() { try? FileManager.default.removeItem(at: ExchangeRates.cacheURL) }

    private let ecb = Data("""
    <gesmes:Envelope><Cube><Cube time='2026-09-28'>
    <Cube currency='USD' rate='1.1378'/><Cube currency='JPY' rate='178.50'/><Cube currency='GBP' rate='0.8611'/>
    </Cube></Cube></gesmes:Envelope>
    """.utf8)
    private let er = Data(#"{"result":"success","time_last_update_unix":1790553600,"rates":{"USD":1.1385,"MAD":10.947,"AED":4.1828}}"#.utf8)

    func testParsesECBWithItsDate() {
        let r = ExchangeRates.parseECB(ecb)
        XCTAssertEqual(r["USD"]?.perEUR, 1.1378)
        XCTAssertEqual(r["JPY"]?.source, .ecb)
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Europe/Berlin")!, from: r["USD"]!.date)
        XCTAssertEqual([comps.year, comps.month, comps.day], [2026, 9, 28])
    }

    /// La BCE d'abord; l'autre source seulement pour ce que la BCE ne publie pas.
    func testECBFirstThenSecondarySourceForMissingCurrencies() async {
        StubURLProtocol.routes = [("ecb.europa.eu", 200, ecb), ("open.er-api.com", 200, er)]
        let (t, f, err) = await ExchangeRates.load(wanted: ["EUR", "USD", "MAD", "AED"])
        XCTAssertEqual(f, .live); XCTAssertNil(err)
        XCTAssertEqual(t.rate("USD")?.source, .ecb, "pas remplacé par la source secondaire")
        XCTAssertEqual(t.rate("MAD")?.source, .erapi)
        XCTAssertEqual(t.convert(100, from: "EUR", to: "USD")!, 113.78, accuracy: 0.001)
        XCTAssertEqual(t.convert(113.78, from: "USD", to: "EUR")!, 100, accuracy: 0.001)
    }

    func testOfflineUsesTheCacheWithItsAge() async {
        StubURLProtocol.routes = [("ecb.europa.eu", 200, ecb), ("open.er-api.com", 200, er)]
        _ = await ExchangeRates.load(wanted: ["USD", "MAD"])
        StubURLProtocol.failWith = URLError(.notConnectedToInternet)
        let (t, f, err) = await ExchangeRates.load(wanted: ["USD", "MAD"])
        guard case .cached = f else { return XCTFail("\(f)") }
        XCTAssertNotNil(err)
        XCTAssertEqual(t.rate("MAD")?.perEUR, 10.947)
    }

    func testOfflineWithoutCacheSaysTheRatesAreOld() async {
        StubURLProtocol.failWith = URLError(.notConnectedToInternet)
        let (t, f, err) = await ExchangeRates.load(wanted: ["USD"])
        XCTAssertEqual(f, .builtin)
        XCTAssertTrue(err?.contains("intégrés") == true)
        XCTAssertEqual(t.rate("USD")?.source, .builtin)
    }

    func testUnknownCurrencyHasNoRateInsteadOfAFakeOne() {
        XCTAssertNil(ExchangeRates.builtinTable.convert(10, from: "EUR", to: "XYZ"))
    }
}
