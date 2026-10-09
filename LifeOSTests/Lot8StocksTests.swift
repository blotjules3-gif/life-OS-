import XCTest
import SwiftData
@testable import LifeOS

/// Lot 8, bourse : lecture Yahoo, regles d'etat, instantane widgets, listes suivies.
/// Les reponses ci-dessous sont de VRAIES reponses du point "chart" (AAPL et MC.PA,
/// capturees le 4 oct 2026), recopiees telles quelles.
final class Lot8StocksTests: XCTestCase {

    static let aapl1d = #"{"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL","exchangeName":"NMS","fullExchangeName":"NasdaqGS","instrumentType":"EQUITY","firstTradeDate":345479400,"regularMarketTime":1790971201,"hasPrePostMarketData":true,"gmtoffset":-14400,"timezone":"EDT","exchangeTimezoneName":"America/New_York","regularMarketPrice":333.69,"regularMarketChangePercent":1.02,"fulldayPrice":333.54,"fulldayChange":3.37,"fulldayChangePercent":1.02,"fiftyTwoWeekHigh":345.34,"fiftyTwoWeekLow":243.42,"regularMarketDayHigh":334.54,"regularMarketDayLow":330.61,"regularMarketVolume":33278552,"longName":"Apple Inc.","shortName":"Apple Inc.","chartPreviousClose":330.32,"previousClose":330.32,"scale":3,"priceHint":2,"currentTradingPeriod":{"pre":{"timezone":"EDT","start":1790928000,"end":1790947800,"gmtoffset":-14400},"regular":{"timezone":"EDT","start":1790947800,"end":1790971200,"gmtoffset":-14400},"post":{"timezone":"EDT","start":1790971200,"end":1790985600,"gmtoffset":-14400}},"tradingPeriods":[[{"timezone":"EDT","start":1790947800,"end":1790971200,"gmtoffset":-14400}]],"dataGranularity":"30m","range":"1d","validRanges":["1d","5d","1mo","3mo","6mo","1y","2y","5y","10y","ytd","max"]},"timestamp":[1790947800,1790949600,1790951400,1790953200,1790955000,1790956800,1790958600,1790960400,1790962200,1790964000,1790965800,1790967600,1790969400,1790971200],"indicators":{"quote":[{"low":[330.6099853515625,332.010009765625,332.8500061035156,331.0799865722656,331.6199951171875,332.260009765625,332.83099365234375,333.2401123046875,333.17999267578125,332.7200012207031,332.95001220703125,333.1099853515625,332.7099914550781,333.69000244140625],"volume":[4121357,2712019,2156672,2932863,1425647,1125661,1685206,906938,828742,859679,1044927,935562,2764289,0],"close":[332.20001220703125,334.3099060058594,332.9599914550781,332.34930419921875,332.3999938964844,332.864990234375,333.375,333.4136047363281,333.32501220703125,332.989990234375,333.70001220703125,333.2699890136719,333.7900085449219,333.69000244140625],"high":[333.4200134277344,334.5400085449219,334.45001220703125,333.0862121582031,332.5150146484375,333.45001220703125,333.739990234375,333.8900146484375,333.70001220703125,333.5,334.1300048828125,333.8699951171875,334.0799865722656,333.69000244140625],"open":[333.2049865722656,332.2300109863281,334.2850036621094,332.9700012207031,332.3349914550781,332.44500732421875,332.864990234375,333.3949890136719,333.4100036621094,333.3500061035156,333.0,333.7099914550781,333.260009765625,333.69000244140625]}]}}],"error":null}}"#
    static let mcpa1d = #"{"chart":{"result":[{"meta":{"currency":"EUR","symbol":"MC.PA","exchangeName":"PAR","fullExchangeName":"Paris","instrumentType":"EQUITY","firstTradeDate":946886400,"regularMarketTime":1790955314,"hasPrePostMarketData":false,"gmtoffset":7200,"timezone":"CEST","exchangeTimezoneName":"Europe/Paris","regularMarketPrice":378.55,"regularMarketChangePercent":-0.25,"fulldayPrice":378.55,"fulldayChange":-0.95,"fulldayChangePercent":-0.25,"fiftyTwoWeekHigh":654.7,"fiftyTwoWeekLow":376.0,"regularMarketDayHigh":383.6,"regularMarketDayLow":376.0,"regularMarketVolume":609051,"longName":"LVMH Mo\u00ebt Hennessy - Louis Vuitton, Soci\u00e9t\u00e9 Europ\u00e9enne","shortName":"LVMH","chartPreviousClose":379.5,"previousClose":379.5,"scale":3,"priceHint":2,"currentTradingPeriod":{"pre":{"timezone":"CEST","start":1790924400,"end":1790924400,"gmtoffset":7200},"regular":{"timezone":"CEST","start":1790924400,"end":1790955000,"gmtoffset":7200},"post":{"timezone":"CEST","start":1790955000,"end":1790955000,"gmtoffset":7200}},"tradingPeriods":[[{"timezone":"CEST","start":1790924400,"end":1790955000,"gmtoffset":7200}]],"dataGranularity":"30m","range":"1d","validRanges":["1d","5d","1mo","3mo","6mo","1y","2y","5y","10y","ytd","max"]},"timestamp":[1790924400,1790926200,1790928000,1790929800,1790931600,1790933400,1790935200,1790937000,1790938800,1790940600,1790942400,1790944200,1790946000,1790947800,1790949600,1790951400,1790953200,1790955000],"indicators":{"quote":[{"open":[377.0,379.8999938964844,381.8500061035156,382.3500061035156,382.25,381.3500061035156,381.0,380.25,381.8500061035156,381.6000061035156,380.70001220703125,381.6000061035156,382.25,382.25,379.6499938964844,380.5,380.20001220703125,378.54998779296875],"close":[379.8500061035156,381.79998779296875,382.3500061035156,382.25,381.45001220703125,380.95001220703125,380.20001220703125,381.95001220703125,381.6499938964844,380.79998779296875,381.45001220703125,382.1000061035156,382.20001220703125,379.54998779296875,380.45001220703125,380.1000061035156,378.79998779296875,378.54998779296875],"high":[383.6000061035156,382.79998779296875,383.04998779296875,383.45001220703125,382.25,381.3500061035156,381.1499938964844,382.1000061035156,382.25,381.79998779296875,381.45001220703125,382.70001220703125,383.3999938964844,382.25,380.8500061035156,381.6499938964844,380.5,378.54998779296875],"low":[376.0,379.3999938964844,380.6000061035156,381.79998779296875,381.1000061035156,379.29998779296875,379.125,379.8999938964844,381.0,380.54998779296875,380.25,381.20001220703125,381.25,378.79998779296875,378.8999938964844,379.79998779296875,378.45001220703125,378.54998779296875],"volume":[32136,15472,14445,12307,8823,18122,21872,10974,8609,5783,11558,12653,7193,19868,10890,13641,29549,0]}]}}],"error":null}}"#
    static let mcpa1mo = #"{"chart":{"result":[{"meta":{"currency":"EUR","symbol":"MC.PA","exchangeName":"PAR","fullExchangeName":"Paris","instrumentType":"EQUITY","firstTradeDate":946886400,"regularMarketTime":1790955314,"hasPrePostMarketData":false,"gmtoffset":7200,"timezone":"CEST","exchangeTimezoneName":"Europe/Paris","regularMarketPrice":378.55,"regularMarketChangePercent":-0.25,"fulldayPrice":378.55,"fulldayChange":-0.95,"fulldayChangePercent":-0.25,"fiftyTwoWeekHigh":654.7,"fiftyTwoWeekLow":376.0,"regularMarketDayHigh":383.6,"regularMarketDayLow":376.0,"regularMarketVolume":609051,"longName":"LVMH Mo\u00ebt Hennessy - Louis Vuitton, Soci\u00e9t\u00e9 Europ\u00e9enne","shortName":"LVMH","chartPreviousClose":439.0,"priceHint":2,"currentTradingPeriod":{"pre":{"timezone":"CEST","start":1791183600,"end":1791183600,"gmtoffset":7200},"regular":{"timezone":"CEST","start":1791183600,"end":1791214200,"gmtoffset":7200},"post":{"timezone":"CEST","start":1791214200,"end":1791214200,"gmtoffset":7200}},"dataGranularity":"1d","range":"1mo","validRanges":["1d","5d","1mo","3mo","6mo","1y","2y","5y","10y","ytd","max"]},"timestamp":[1788332400,1788418800,1788505200,1788764400,1788850800,1788937200,1789023600,1789110000,1789369200,1789455600,1789542000,1789628400,1789714800,1789974000,1790060400,1790146800,1790233200,1790319600,1790578800,1790665200,1790751600,1790838000,1790924400],"indicators":{"quote":[{"low":[435.6000061035156,425.3500061035156,427.5,423.75,425.6499938964844,408.75,405.25,407.6000061035156,407.8500061035156,404.54998779296875,403.1499938964844,409.5,401.3999938964844,400.0,401.1000061035156,396.3500061035156,395.6499938964844,395.1499938964844,392.25,394.29998779296875,390.0,379.1000061035156,376.0],"close":[439.0,431.04998779296875,429.1000061035156,431.20001220703125,426.54998779296875,411.25,406.5,415.29998779296875,417.45001220703125,406.45001220703125,410.95001220703125,412.29998779296875,402.79998779296875,405.5,401.95001220703125,396.8999938964844,397.1000061035156,396.8500061035156,398.79998779296875,394.6000061035156,390.0,379.5,378.54998779296875],"high":[444.45001220703125,437.54998779296875,433.75,432.8500061035156,433.3500061035156,422.8999938964844,412.25,420.04998779296875,417.8999938964844,414.3500061035156,411.70001220703125,416.0,410.25,409.1499938964844,409.6000061035156,409.20001220703125,401.8500061035156,401.79998779296875,401.25,400.0,398.2749938964844,389.25,383.6000061035156],"volume":[525931,727463,478454,288174,337658,1029072,851589,732113,547272,665584,613823,470837,1227232,514255,676725,634527,667597,508148,499958,372219,829329,773338,609051],"open":[443.29998779296875,436.25,431.25,427.75,429.1499938964844,421.20001220703125,409.0,408.0,410.45001220703125,413.1499938964844,406.0,412.79998779296875,410.0,401.75,404.79998779296875,403.04998779296875,398.1000061035156,401.45001220703125,399.95001220703125,399.5,395.04998779296875,387.0,377.0]}],"adjclose":[{"adjclose":[439.0,431.04998779296875,429.1000061035156,431.20001220703125,426.54998779296875,411.25,406.5,415.29998779296875,417.45001220703125,406.45001220703125,410.95001220703125,412.29998779296875,402.79998779296875,405.5,401.95001220703125,396.8999938964844,397.1000061035156,396.8500061035156,398.79998779296875,394.6000061035156,390.0,379.5,378.54998779296875]}]}}],"error":null}}"#
    static let notFound = #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}"#
    static let londonPence = #"{"chart":{"result":[{"meta":{"currency":"GBp","symbol":"VOD.L","exchangeName":"LSE","fullExchangeName":"LSE","instrumentType":"EQUITY","regularMarketTime":1790955300,"exchangeTimezoneName":"Europe/London","regularMarketPrice":126.8,"previousClose":124.1,"shortName":"VODAFONE GROUP PLC"},"timestamp":[1790949600,1790953200],"indicators":{"quote":[{"close":[125.0,126.8]}]}}],"error":null}}"#

    private var tmp: URL!

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lot8stocks-\(UUID().uuidString)")
        StockFiles.directoryOverride = tmp
    }

    override func tearDown() {
        StockFiles.directoryOverride = nil
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    private func parse(_ json: String, _ symbol: String, _ period: StockPeriod, now: Date = Date(timeIntervalSince1970: 1_790_960_000)) -> Result<StockQuote, StockFetchError> {
        StockChartParser.parse(Data(json.utf8), symbol: symbol, range: period.range, interval: period.interval, now: now)
    }

    private func quote(_ json: String, _ symbol: String, _ period: StockPeriod = .day1, now: Date = Date(timeIntervalSince1970: 1_790_960_000)) throws -> StockQuote {
        switch parse(json, symbol, period, now: now) {
        case .success(let q): return q
        case .failure(let e): XCTFail("parse failed: \(e)"); throw e
        }
    }

    private var paris: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Paris")!; return c }

    // MARK: Lecture

    func testParsesRealAppleIntradayResponse() throws {
        let q = try quote(Self.aapl1d, "aapl")
        XCTAssertEqual(q.symbol, "AAPL")
        XCTAssertEqual(q.name, "Apple Inc.")
        XCTAssertEqual(q.price, 333.69, accuracy: 0.0001)
        XCTAssertEqual(q.previousClose ?? 0, 330.32, accuracy: 0.0001)
        XCTAssertEqual(q.currency, "USD")
        XCTAssertEqual(q.exchange, "NMS")
        XCTAssertEqual(q.exchangeFullName, "NasdaqGS")
        XCTAssertEqual(q.exchangeTimeZone, "America/New_York")
        XCTAssertEqual(q.marketTime, Date(timeIntervalSince1970: 1_790_971_201))
        XCTAssertEqual(q.sessionStart, Date(timeIntervalSince1970: 1_790_947_800))
        XCTAssertEqual(q.sessionEnd, Date(timeIntervalSince1970: 1_790_971_200))
        XCTAssertNil(q.marketState, "le point chart ne donne pas marketState : on ne l'invente pas")
        XCTAssertEqual(q.series["1d"]?.count, 14)
        XCTAssertEqual(q.change ?? 0, 3.37, accuracy: 0.0001)
        XCTAssertEqual(q.changePercent ?? 0, 3.37 / 330.32 * 100, accuracy: 0.0001)
    }

    func testParsesRealParisResponse() throws {
        let q = try quote(Self.mcpa1d, "MC.PA")
        XCTAssertEqual(q.currency, "EUR")
        XCTAssertEqual(q.exchangeFullName, "Paris")
        XCTAssertEqual(q.name, "LVMH")
        XCTAssertEqual(q.price, 378.55, accuracy: 0.0001)
        XCTAssertEqual(q.previousClose ?? 0, 379.5, accuracy: 0.0001)
        XCTAssertEqual(q.changePercent ?? 0, -0.2503, accuracy: 0.001)
    }

    func testDailySeriesGivesPreviousCloseWhenMetaHasNone() throws {
        // range=1mo : ni previousClose ni chartPreviousClose utilisable (celui-ci date d'il y a un mois).
        let q = try quote(Self.mcpa1mo, "MC.PA", .month1)
        XCTAssertEqual(q.previousClose ?? 0, 379.5, accuracy: 0.0001)
        XCTAssertNotNil(q.series["1mo"])
        XCTAssertNil(q.series["1d"])
    }

    func testUnknownSymbolAndGarbage() {
        XCTAssertEqual(parse(Self.notFound, "ZZZZ", .day1), .failure(.notFound))
        XCTAssertEqual(parse("<html>refus</html>", "AAPL", .day1), .failure(.decoding))
        XCTAssertEqual(StockFetcher.classify(status: 404), .notFound)
        XCTAssertEqual(StockFetcher.classify(status: 429), .rateLimited)
        XCTAssertNil(StockFetcher.classify(status: 200))
        XCTAssertEqual(StockFetcher.classify(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(StockFetcher.classify(URLError(.badServerResponse)), .network)
    }

    func testSubUnitNormalization() throws {
        let q = try quote(Self.londonPence, "VOD.L")
        XCTAssertEqual(q.currency, "GBP")
        XCTAssertEqual(q.price, 1.268, accuracy: 0.00001)
        XCTAssertEqual(q.previousClose ?? 0, 1.241, accuracy: 0.00001)
        XCTAssertEqual(q.series["1d"] ?? [], [1.25, 1.268])
        XCTAssertEqual(StockService.normalized(price: 2500, currency: "GBp").price, 25)
        XCTAssertEqual(StockMath.normalizedCurrency("ZAc").code, "ZAR")
        XCTAssertEqual(StockMath.normalizedCurrency("usd").code, "USD")
    }

    func testChangePercentMath() {
        XCTAssertEqual(StockMath.changePercent(price: 110, previousClose: 100) ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(StockMath.changePercent(price: 90, previousClose: 100) ?? 0, -10, accuracy: 1e-9)
        XCTAssertNil(StockMath.changePercent(price: 90, previousClose: 0))
        XCTAssertNil(StockMath.changePercent(price: 90, previousClose: nil))
        XCTAssertEqual(StockFormat.percent(1.0202), "+1,02 %")
        XCTAssertEqual(StockFormat.percent(-0.25), "-0,25 %")
        XCTAssertEqual(StockMath.convert(10, from: "USD", to: .eur, eurPerUnit: ["USD": 0.9])?.value ?? 0, 9, accuracy: 1e-9)
        XCTAssertNil(StockMath.convert(10, from: "JPY", to: .eur, eurPerUnit: ["USD": 0.9]), "pas de taux : on n'invente pas")
        XCTAssertEqual(StockMath.convert(10, from: "JPY", to: .original, eurPerUnit: [:])?.currency, "JPY")
    }

    // MARK: Etat

    func testOpenStaleClosedRules() throws {
        let fetched = Date(timeIntervalSince1970: 1_790_960_000)          // pendant la seance AAPL
        let q = try quote(Self.aapl1d, "AAPL", now: fetched)
        XCTAssertEqual(StockFreshness.isOpen(q, now: fetched), true)
        XCTAssertEqual(StockFreshness.status(q, now: fetched.addingTimeInterval(10 * 60)), .delayed)
        XCTAssertEqual(StockFreshness.status(q, now: fetched.addingTimeInterval(31 * 60)), .stale)
        let afterClose = Date(timeIntervalSince1970: 1_790_971_200 + 60)
        XCTAssertEqual(StockFreshness.status(q, now: afterClose), .closed)
        XCTAssertTrue(StockFreshness.needsRefresh(q, now: afterClose), "lu pendant la seance : la cloture reste a lire")

        var regular = q; regular.marketState = "REGULAR"
        XCTAssertEqual(StockFreshness.status(regular, now: afterClose), .closed, "apres la fin connue, ferme quoi que dise l'etat")

        var unknown = q; unknown.sessionStart = nil; unknown.sessionEnd = nil
        XCTAssertNil(StockFreshness.isOpen(unknown, now: fetched))
        XCTAssertEqual(StockFreshness.status(unknown, now: fetched), .delayed)
        XCTAssertEqual(StockFreshness.status(unknown, now: fetched.addingTimeInterval(3600)), .stale)

        // Lu apres la cloture, marche ferme : pas besoin de relire tout de suite.
        let lateRead = try quote(Self.aapl1d, "AAPL", now: afterClose)
        XCTAssertEqual(StockFreshness.status(lateRead, now: afterClose.addingTimeInterval(3600)), .closed)
        XCTAssertFalse(StockFreshness.needsRefresh(lateRead, now: afterClose.addingTimeInterval(3600)))
    }

    func testStatusTextsNeverClaimRealTime() throws {
        let fetched = Date(timeIntervalSince1970: 1_790_960_000)
        let q = try quote(Self.aapl1d, "AAPL", now: fetched)
        let open = StockFormat.statusLine(q, now: fetched, calendar: paris)
        XCTAssertTrue(open.hasPrefix("Différé · Yahoo Finance · "), open)
        let closed = StockFormat.statusLine(q, now: Date(timeIntervalSince1970: 1_790_972_000), calendar: paris)
        XCTAssertTrue(closed.hasPrefix("Marché fermé · dernier cours "), closed)
        XCTAssertTrue(StockFormat.statusLine(q, offline: true, now: fetched, calendar: paris).hasPrefix("Hors ligne · "))
        XCTAssertTrue(StockFormat.statusSpoken(q, now: fetched, calendar: paris).contains("différé"))
        XCTAssertTrue(StockFormat.compactStatus(q, now: Date(timeIntervalSince1970: 1_790_972_000), calendar: paris).hasPrefix("Fermé"))
        for s in [open, closed] {
            XCTAssertFalse(s.lowercased().contains("temps réel"))
            XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), "pas de tiret long")
        }
        // 22:00 a Paris le jour meme -> heure seule.
        XCTAssertEqual(StockFormat.timeLabel(Date(timeIntervalSince1970: 1_790_971_201), now: Date(timeIntervalSince1970: 1_790_972_000), calendar: paris), "22:00")
    }

    func testWidgetReloadPolicy() throws {
        let fetched = Date(timeIntervalSince1970: 1_790_960_000)
        let open = try quote(Self.aapl1d, "AAPL", now: fetched)
        XCTAssertEqual(StockWidgetPolicy.nextReload(quotes: [open], now: fetched), fetched.addingTimeInterval(1800))
        var closed = open; closed.sessionStart = fetched.addingTimeInterval(3 * 3600); closed.sessionEnd = fetched.addingTimeInterval(9 * 3600)
        XCTAssertEqual(StockWidgetPolicy.nextReload(quotes: [closed], now: fetched), fetched.addingTimeInterval(3 * 3600))
        closed.sessionStart = fetched.addingTimeInterval(40 * 3600); closed.sessionEnd = fetched.addingTimeInterval(46 * 3600)
        XCTAssertEqual(StockWidgetPolicy.nextReload(quotes: [closed], now: fetched), fetched.addingTimeInterval(6 * 3600))
        XCTAssertEqual(StockWidgetPolicy.nextReload(quotes: [], now: fetched), fetched.addingTimeInterval(2 * 3600))
    }

    // MARK: Budget, cache, hors ligne

    func testRefreshBudget() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let attempts = ["AAPL|1d": now.addingTimeInterval(-60), "MC.PA|1d": now.addingTimeInterval(-600)]
        let keys = ["AAPL|1d", "MC.PA|1d", "VOD.L|1d", "VOD.L|1d"]
        XCTAssertEqual(StockRefreshBudget.due(keys, attempts: attempts, now: now, minInterval: 300, maxRequests: 10, backoffUntil: nil),
                       ["MC.PA|1d", "VOD.L|1d"])
        XCTAssertEqual(StockRefreshBudget.due(keys, attempts: attempts, now: now, minInterval: 300, maxRequests: 1, backoffUntil: nil), ["MC.PA|1d"])
        XCTAssertEqual(StockRefreshBudget.due(keys, attempts: [:], now: now, minInterval: 300, maxRequests: 10,
                                              backoffUntil: now.addingTimeInterval(60)), [], "rien pendant un refus")
        var c = StockQuoteCache()
        c.record(.rateLimited, for: "AAPL", at: now)
        XCTAssertEqual(c.backoffUntil, now.addingTimeInterval(StockQuoteCache.backoff))
    }

    func testOfflineKeepsCacheAndUnknownSymbolKeepsItsRow() throws {
        let q = try quote(Self.mcpa1d, "MC.PA")
        // Heure entiere: le fichier garde les dates a la seconde, Date() aurait des
        // fractions perdues a la relecture.
        let now = Date(timeIntervalSince1970: 1_790_960_100)
        var c = StockQuoteCache()
        c.record(q)
        c.record(.offline, for: "MC.PA", at: now)
        XCTAssertNotNil(c.quotes["MC.PA"], "hors ligne : le dernier cours reste affiche")
        XCTAssertNotNil(c.offlineSince)
        XCTAssertNil(c.failures["MC.PA"], "hors ligne n'est pas une erreur du titre")
        c.record(.notFound, for: "zzzz", at: now)
        XCTAssertEqual(c.failures["ZZZZ"]?.error, .notFound)
        c.record(q)
        XCTAssertNil(c.offlineSince, "une lecture reussie efface l'etat hors ligne")

        try c.save()
        XCTAssertEqual(StockQuoteCache.load(), c)

        // Le widget ne relit pas un symbole introuvable, mais relit un titre sans cours.
        XCTAssertEqual(StockWidgetPolicy.symbolsToRefresh(["ZZZZ", "AAPL"], period: .day1, cache: c), ["AAPL"])
        XCTAssertEqual(StockWidgetPolicy.symbolsToRefresh(["MC.PA"], period: .month1, cache: c), ["MC.PA"], "pas de graphique 1 mois en cache")
    }

    func testMergeKeepsNewestReadingAndOtherPeriods() throws {
        let t0 = Date(timeIntervalSince1970: 1_790_960_000)
        let intraday = try quote(Self.mcpa1d, "MC.PA", .day1, now: t0)
        var monthly = try quote(Self.mcpa1mo, "MC.PA", .month1, now: t0.addingTimeInterval(60))
        monthly.previousClose = nil
        let m = monthly.merged(into: intraday)
        XCTAssertNotNil(m.series["1d"]); XCTAssertNotNil(m.series["1mo"])
        XCTAssertEqual(m.previousClose ?? 0, 379.5, accuracy: 0.001, "meme seance : la cloture de la veille est gardee")

        var a = StockQuoteCache(); a.record(intraday)
        var b = StockQuoteCache(); b.record(monthly)
        XCTAssertEqual(a.merging(b).quotes["MC.PA"]?.fetchedAt, monthly.fetchedAt)
        XCTAssertEqual(b.merging(a).quotes["MC.PA"]?.fetchedAt, monthly.fetchedAt, "la plus recente gagne dans les deux sens")
    }

    // MARK: Instantane, listes, choix des widgets

    private func sampleSnapshot() -> StockWidgetSnapshot {
        StockWidgetPublisher.makeSnapshot(
            lists: [.init(id: "L2", name: "Tech US", order: 1, currency: .eur, period: .month6, showSparkline: false),
                    .init(id: "L1", name: "Favoris", order: 0, currency: .original, period: .day1, showSparkline: true)],
            items: [.init(symbol: "aapl", displayName: "Apple", exchangeLabel: "NasdaqGS", listName: "Tech US", order: 1),
                    .init(symbol: "MSFT", displayName: "Microsoft", exchangeLabel: "NasdaqGS", listName: "Tech US", order: 0),
                    .init(symbol: "MC.PA", displayName: "LVMH", exchangeLabel: "Paris", listName: "Favoris", order: 0),
                    .init(symbol: "AAPL", displayName: "Apple", exchangeLabel: "NasdaqGS", listName: "Favoris", order: 1)],
            holdings: [.init(symbol: "CW8.PA", kind: "ETF", valueEUR: 1100, dayChangePct: 10, priceAt: nil)],
            now: Date(timeIntervalSince1970: 1_790_960_000))
    }

    func testSnapshotRoundtripAndOrdering() throws {
        let s = sampleSnapshot()
        XCTAssertEqual(s.list(id: "L2")?.items.map(\.symbol), ["MSFT", "AAPL"], "ordre de l'app, symboles en majuscules")
        XCTAssertEqual(s.orderedLists.map(\.name), ["Favoris", "Tech US"])
        XCTAssertEqual(s.allItems.map(\.symbol), ["MC.PA", "AAPL", "MSFT"], "chaque titre une fois")
        XCTAssertEqual(s.settings(for: "aapl")?.id, "L1", "reglages de la premiere liste qui contient le titre")
        try s.write()
        XCTAssertEqual(StockWidgetSnapshot.read(), s)
    }

    func testEntityQueriesReadTheSnapshot() {
        let s = sampleSnapshot()
        XCTAssertEqual(s.listChoices.map(\.id), ["L1", "L2"])
        XCTAssertEqual(s.listChoices.map(\.subtitle), ["2 titres", "2 titres"])
        XCTAssertEqual(s.symbolChoices.map(\.id), ["MC.PA", "AAPL", "MSFT"])
        XCTAssertEqual(s.symbolChoices.first?.subtitle, "LVMH · Paris")
        XCTAssertEqual(s.defaultList?.id, "L1")
        XCTAssertNil(s.item(symbol: "TSLA"), "titre retire : le widget le signale")
        // Renommage : meme id, nouveau nom ; un widget configure garde sa liste.
        let renamed = StockWidgetPublisher.makeSnapshot(
            lists: [.init(id: "L2", name: "Amérique", order: 1, currency: .eur, period: .month6, showSparkline: false)],
            items: [], holdings: [])
        XCTAssertEqual(renamed.list(id: "L2")?.name, "Amérique")
        XCTAssertEqual(renamed.list(id: "L2")?.items, [], "liste vide : etat vide")
    }

    func testReorderMath() {
        let a = ["A", "B", "C", "D"]
        XCTAssertEqual(WatchlistOps.moved(a, from: [0], to: 3), ["B", "C", "A", "D"])
        XCTAssertEqual(WatchlistOps.moved(a, from: [3], to: 0), ["D", "A", "B", "C"])
        XCTAssertEqual(WatchlistOps.moved(a, from: [1, 2], to: 4), ["A", "D", "B", "C"])
        XCTAssertEqual(WatchlistOps.moved(a, from: [2], to: 2), a)
    }

    func testSymbolAndListNameRules() {
        XCTAssertEqual(WatchlistOps.normalizedSymbol(" mc ", place: .paris), "MC.PA")
        XCTAssertEqual(WatchlistOps.normalizedSymbol("vod.l", place: .paris), "VOD.L", "suffixe deja present : garde")
        XCTAssertEqual(WatchlistOps.normalizedSymbol("aapl"), "AAPL")
        XCTAssertTrue(WatchlistOps.isPlausibleSymbol("EURUSD=X"))
        XCTAssertFalse(WatchlistOps.isPlausibleSymbol("AA PL"))
        XCTAssertFalse(WatchlistOps.isPlausibleSymbol(""))
        XCTAssertNil(WatchlistOps.validListName("favoris", existing: ["Favoris"]))
        XCTAssertEqual(WatchlistOps.validListName(" Favoris ", existing: ["Favoris"], current: "Favoris"), "Favoris")
        XCTAssertNil(WatchlistOps.validListName("   ", existing: []))
    }

    @MainActor
    func testWatchlistOpsOnContext() throws {
        let container = try ModelContainer(for: WatchlistGroup.self, WatchlistItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        XCTAssertTrue(WatchlistOps.migrate(ctx))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<WatchlistGroup>()).map(\.name), ["Favoris"])
        XCTAssertFalse(WatchlistOps.migrate(ctx), "une seule fois")
        XCTAssertEqual(WatchlistOps.add(symbol: "mc.pa", displayName: "LVMH", exchangeLabel: "Paris", to: "Favoris", in: ctx), .added)
        XCTAssertEqual(WatchlistOps.add(symbol: "MC.PA", displayName: "LVMH", exchangeLabel: "Paris", to: "Favoris", in: ctx), .duplicate)
        XCTAssertEqual(WatchlistOps.add(symbol: "AAPL", displayName: "Apple", exchangeLabel: "", to: "Favoris", in: ctx), .added)
        XCTAssertEqual(WatchlistOps.add(symbol: "A A", displayName: "", exchangeLabel: "", to: "Favoris", in: ctx), .invalid)
        let items = try ctx.fetch(FetchDescriptor<WatchlistItem>(sortBy: [SortDescriptor(\.order)]))
        XCTAssertEqual(items.map(\.symbol), ["MC.PA", "AAPL"])
        XCTAssertTrue(items.allSatisfy { $0.uid != nil })

        let g = try XCTUnwrap(ctx.fetch(FetchDescriptor<WatchlistGroup>()).first)
        WatchlistOps.rename(g, to: "Mes titres", in: ctx)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<WatchlistItem>()).allSatisfy { $0.listName == "Mes titres" })

        WatchlistOps.applyOrder(["AAPL", "MC.PA"], to: items)
        XCTAssertEqual(items.first { $0.symbol == "AAPL" }?.order, 0)

        WatchlistOps.delete(g, in: ctx)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<WatchlistItem>()), 0)
    }

    // MARK: Portefeuille, liens, courbe

    func testPortfolioSummary() {
        let p = PortfolioSummary.make([
            .init(symbol: "A", kind: "ETF", valueEUR: 1100, dayChangePct: 10, priceAt: Date(timeIntervalSince1970: 10)),
            .init(symbol: "B", kind: "Action", valueEUR: 500, dayChangePct: nil, priceAt: nil),
            .init(symbol: "C", kind: "Crypto", valueEUR: 95, dayChangePct: -5, priceAt: Date(timeIntervalSince1970: 20)),
        ])
        XCTAssertEqual(p.total, 1695, accuracy: 1e-9)
        XCTAssertEqual(p.dayChange, 100 - 5, accuracy: 1e-9)
        XCTAssertEqual(p.dayChangePct ?? 0, 95.0 / 1100.0 * 100, accuracy: 1e-9)
        XCTAssertEqual(p.withoutChange, 1)
        XCTAssertEqual(p.movers.map(\.symbol), ["A", "C"])
        XCTAssertEqual(p.latestPriceAt, Date(timeIntervalSince1970: 20))
        XCTAssertNil(PortfolioSummary.make([]).dayChangePct)
    }

    func testDeepLinks() {
        let u = StockDeepLink.url(symbol: "MC.PA", list: "Tech US")
        XCTAssertEqual(u.scheme, "lifeos"); XCTAssertEqual(u.host, "stocks")
        XCTAssertEqual(StockDeepLink.parse(u), .init(symbol: "MC.PA", list: "Tech US", portfolio: false))
        XCTAssertEqual(StockDeepLink.parse(StockDeepLink.portfolioURL)?.portfolio, true)
        XCTAssertNil(StockDeepLink.parse(URL(string: "lifeos://water")!))
        XCTAssertEqual(StockDeepLink.parse(URL(string: "lifeos://stocks?symbol=aapl")!)?.symbol, "AAPL")
    }

    func testSparklinePoints() {
        let pts = StockSparkline.points([1, 3, 2], in: CGSize(width: 100, height: 10), baseline: nil)
        XCTAssertEqual(pts.line.count, 3)
        XCTAssertEqual(pts.line[1].y, 0, accuracy: 1e-9, "maximum en haut")
        XCTAssertEqual(pts.line[0].y, 10, accuracy: 1e-9)
        XCTAssertEqual(pts.line[2].x, 100, accuracy: 1e-9)
        XCTAssertTrue(StockSparkline.points([1], in: CGSize(width: 100, height: 10), baseline: nil).line.isEmpty)
        XCTAssertEqual(StockMath.downsample(Array(0..<200).map(Double.init), maxPoints: 80).count, 80)
        XCTAssertEqual(StockMath.downsample(Array(0..<200).map(Double.init), maxPoints: 80).last, 199)
    }
}
