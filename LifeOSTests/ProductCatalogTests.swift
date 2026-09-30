import XCTest
@testable import LifeOS

// MARK: - Faux reseau

final class StubURLProtocol: URLProtocol {
    /// URL (contient) -> (statut, corps) ; ou une erreur.
    nonisolated(unsafe) static var routes: [(match: String, status: Int, body: Data)] = []
    nonisolated(unsafe) static var failWith: URLError?
    nonisolated(unsafe) static var requested: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requested.append(url)
        if let e = Self.failWith { client?.urlProtocol(self, didFailWithError: e); return }
        let route = Self.routes.first { url.absoluteString.contains($0.match) }
        let status = route?.status ?? 404
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route?.body ?? Data(#"{"status":0}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ProductCatalogTests: XCTestCase {

    override func setUp() {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        ProductCatalog.session = URLSession(configuration: c)
        StubURLProtocol.routes = []; StubURLProtocol.failWith = nil; StubURLProtocol.requested = []
        // Budget partage: un 429 simule dans un test ne doit pas suspendre le suivant.
        let reset = expectation(description: "budget")
        Task { await CatalogBudget.shared.reset(); reset.fulfill() }
        wait(for: [reset], timeout: 2)
        ProductCache.directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuko-\(UUID())")
    }
    override func tearDown() { ProductCache.clear() }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    private let nutella = #"""
    {"status":1,"product":{"code":"3017620422003","product_name_fr":"Nutella","brands":"Ferrero,Nutella",
     "image_front_url":"https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.jpg",
     "image_front_small_url":"https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.200.jpg",
     "categories_tags":["en:spreads","en:cocoa-and-hazelnuts-spreads","en:Pâtes à tartiner"],"countries_tags":["en:france"],
     "ingredients_text_fr":"Sucre, huile de palme, noisettes 13%, lait écrémé en poudre, cacao, lécithines (soja), vanilline.",
     "additives_tags":["en:e322"],"allergens_tags":["en:milk","en:nuts","en:soybeans"],"traces_tags":[],
     "labels_tags":[],"nutriscore_grade":"e","nova_group":4,
     "nutriments":{"energy-kcal_100g":539,"sugars_100g":56.3,"saturated-fat_100g":10.6,"salt_100g":0.107,
                   "proteins_100g":6.3,"fiber_100g":0,"fat_100g":30.9,"carbohydrates_100g":57.5}}}
    """#

    // MARK: Decodage

    func testImageAndDetailsAreDecoded() async throws {
        StubURLProtocol.routes = [("openfoodfacts.org/api/v3/product/3017620422003", 200, json(nutella))]
        guard case .found(let p) = await ProductCatalog.product(barcode: "3017620422003") else { return XCTFail() }
        XCTAssertEqual(p.imageURL?.lastPathComponent, "front_fr.jpg")
        XCTAssertEqual(p.imageSmallURL?.lastPathComponent, "front_fr.200.jpg")
        XCTAssertEqual(p.brand, "Ferrero")
        XCTAssertEqual(p.allergens, ["en:milk", "en:nuts", "en:soybeans"])
        XCTAssertEqual(p.nutriments.fiber, 0, "un vrai zero reste zero")
        XCTAssertNotNil(p.ingredientsText)
    }

    func testMissingNutrientStaysUnknown() async throws {
        StubURLProtocol.routes = [("product/123456", 200, json(#"{"status":1,"product":{"code":"123456","product_name":"Biscuit","nutriments":{"energy-kcal_100g":450}}}"#))]
        guard case .found(let p) = await ProductCatalog.product(barcode: "123456") else { return XCTFail() }
        XCTAssertEqual(p.nutriments.energyKcal, 450)
        XCTAssertNil(p.nutriments.sugars, "absent ne doit pas devenir 0")
        XCTAssertNil(p.imageURL, "aucune photo inventee")
    }

    // MARK: Trois issues distinctes

    func testNetworkFailureIsNotNotFound() async {
        StubURLProtocol.failWith = URLError(.notConnectedToInternet)
        let r = await ProductCatalog.product(barcode: "3017620422003")
        guard case .unavailable(let msg) = r else { return XCTFail("\(r)") }
        XCTAssertTrue(msg.contains("connexion"))
    }

    func testAbsentFromBothBasesIsNotFound() async {
        // Pas de route: les deux bases repondent 404 {"status":0}.
        let (r, trace) = await ProductCatalog.lookup(barcode: "0000000000017")
        XCTAssertEqual(r, .notFound)
        XCTAssertTrue(StubURLProtocol.requested.allSatisfy { $0.path.contains("/api/v3/product/") }, "une requête universelle par forme du code")
        XCTAssertEqual(StubURLProtocol.requested.count, trace.normalized?.candidates.count)
    }

    func testServerErrorIsUnavailable() async {
        StubURLProtocol.routes = [("openfoodfacts", 503, json("<html>down</html>")), ("openbeautyfacts", 503, json("x")), ("openpetfoodfacts", 503, json("x"))]
        guard case .unavailable = await ProductCatalog.product(barcode: "3017620422003") else { return XCTFail() }
    }

    func testCosmeticFoundInBeautyBase() async {
        // La base universelle redirige vers Open Beauty Facts; la fiche porte product_type "beauty".
        StubURLProtocol.routes = [("api/v3/product/3600523", 200,
            json(#"{"product":{"code":"3600523","product_type":"beauty","product_name":"Shampoing","ingredients_text":"Aqua, Sodium Laureth Sulfate, Parfum, Limonene"}}"#))]
        guard case .found(let p) = await ProductCatalog.product(barcode: "3600523") else { return XCTFail() }
        XCTAssertEqual(p.source, .beauty)
    }

    func testOfflineFallsBackToCacheWithItsDate() async {
        StubURLProtocol.routes = [("product/3017620422003", 200, json(nutella))]
        guard case .found(let first) = await ProductCatalog.product(barcode: "3017620422003") else { return XCTFail() }
        StubURLProtocol.failWith = URLError(.notConnectedToInternet)
        guard case .found(let cached) = await ProductCatalog.product(barcode: "3017620422003") else { return XCTFail("cache non utilise") }
        XCTAssertEqual(cached.fetchedAt.timeIntervalSince1970, first.fetchedAt.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: Recherche

    func testSearchKeepsWaterAndZeroDrinks() async {
        StubURLProtocol.routes = [("search.openfoodfacts.org", 200, json(#"""
        {"page_count":1,"hits":[
          {"code":"3274080005003","product_name":"Cristaline","categories_tags":["en:beverages","en:waters"],"nutriments":{"energy-kcal_100g":0,"sugars_100g":0}},
          {"code":"5449000131805","product_name":"Coca-Cola Zero","categories_tags":["en:beverages"],"nutriments":{"energy-kcal_100g":0.3}}]}
        """#))]
        guard case .results(let items, let more) = await ProductCatalog.search("eau") else { return XCTFail() }
        XCTAssertEqual(items.map(\.name), ["Cristaline", "Coca-Cola Zero"])
        XCTAssertFalse(more)
    }

    func testSearchPagination() async {
        StubURLProtocol.routes = [("search.openfoodfacts.org", 200, json(#"{"page_count":5,"hits":[{"code":"1","product_name":"A","brands":["Marque"]}]}"#))]
        guard case .results(let items, let more) = await ProductCatalog.search("pomme", page: 1) else { return XCTFail() }
        XCTAssertTrue(more)
        XCTAssertEqual(items.first?.brand, "Marque", "marques en liste dans ce moteur")
        XCTAssertTrue(StubURLProtocol.requested.filter { $0.host == "search.openfoodfacts.org" }.allSatisfy { $0.absoluteString.contains("page=1") })
    }

    /// La liste montre une note: chaque page est completee par les fiches entieres
    /// (additifs compris) en UNE requete.
    func testSearchResultsAreCompletedSoTheListShowsAScore() async {
        StubURLProtocol.routes = [
            ("api/v2/search", 200, json(#"{"count":1,"products":[{"code":"3017620422003","product_name":"Nutella","ingredients_text_fr":"Sucre, huile de palme","additives_tags":["en:e322"],"nutriments":{"energy-kcal_100g":539,"sugars_100g":56.3,"saturated-fat_100g":10.6,"salt_100g":0.107}}]}"#)),
            ("search.openfoodfacts.org", 200, json(#"{"page_count":1,"count":1,"hits":[{"code":"3017620422003","product_name":"Nutella","nutriments":{"energy-kcal_100g":539}}]}"#)),
        ]
        guard case .results(let items, _) = await ProductCatalog.search("nutella") else { return XCTFail() }
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].isSummary, "fiche complete")
        XCTAssertEqual(items[0].additives, ["en:e322"])
        XCTAssertNotNil(ProductScore.evaluate(items[0]).value, "une note dans la liste")
        let completion = StubURLProtocol.requested.filter { $0.path.contains("api/v2/search") }
        XCTAssertEqual(completion.count, 1, "une seule requete pour toute la page")
    }

    /// Completement refuse (limite de debit): la liste s'affiche quand meme, abregee.
    func testCompletionRefusedKeepsTheList() async {
        StubURLProtocol.routes = [
            ("api/v2/search", 429, json("{}")),
            ("search.openfoodfacts.org", 200, json(#"{"page_count":1,"hits":[{"code":"1","product_name":"Pomme"}]}"#)),
        ]
        guard case .results(let items, _) = await ProductCatalog.search("pomme") else { return XCTFail() }
        XCTAssertEqual(items.map(\.name), ["Pomme"])
        XCTAssertEqual(items.first?.isSummary, true)
    }

    /// Recherche groupee refusee (503, limite de debit): les fiches viennent une par
    /// une de l'API produit, et la liste garde sa note.
    func testBatchRetriedThenRowCompletesByProductAPI() async {
        StubURLProtocol.routes = [
            ("api/v2/search", 503, json("{}")),
            ("product/7610000000017", 200, json(#"{"status":1,"product":{"code":"7610000000017","product_name":"Muesli","ingredients_text":"Avoine","additives_tags":[],"nutriments":{"energy-kcal_100g":370,"sugars_100g":8,"saturated-fat_100g":1,"salt_100g":0.02}}}"#)),
            ("search.openfoodfacts.org", 200, json(#"{"page_count":1,"hits":[{"code":"7610000000017","product_name":"Muesli"}]}"#)),
        ]
        guard case .results(let items, _) = await ProductCatalog.search("muesli") else { return XCTFail() }
        XCTAssertEqual(items.first?.isSummary, true, "la recherche ne lit pas fiche par fiche")
        let groupTries = StubURLProtocol.requested.filter { $0.path.contains("api/v2/search") }.count
        XCTAssertEqual(groupTries, 3, "trois essais de la requete groupee")
        let (r, _) = await ProductCatalog.complete(items[0])
        guard case .found(let full) = r else { return XCTFail() }
        XCTAssertNotNil(ProductScore.evaluate(full).value, "la ligne se complete ensuite par l'API produit")
    }

    /// Budget des lectures fiche par fiche: 20 par minute, et arret d'une minute
    /// apres un 429 (Open Food Facts bloque l'adresse si on insiste).
    func testRequestBudgetCapsAndPausesAfter429() async {
        let b = CatalogBudget()
        let t0 = Date()
        var ok = 0
        for _ in 0..<70 { if await b.take(now: t0) { ok += 1 } }
        XCTAssertEqual(ok, 60)
        let reopened = await b.take(now: t0.addingTimeInterval(61))
        XCTAssertTrue(reopened, "la minute suivante rouvre")
        await b.blocked(now: t0.addingTimeInterval(61))
        let paused = await b.take(now: t0.addingTimeInterval(90))
        XCTAssertFalse(paused, "429: plus rien pendant une minute")
        let afterPause = await b.take(now: t0.addingTimeInterval(122))
        XCTAssertTrue(afterPause)
        // Un refus de la RECHERCHE groupee ne coupe pas les lectures fiche par fiche.
        let c = CatalogBudget()
        await c.groupBlocked(now: t0)
        let groupOK = await c.groupAllowed(now: t0.addingTimeInterval(10))
        XCTAssertFalse(groupOK)
        let readsStillOK = await c.take(now: t0.addingTimeInterval(10))
        XCTAssertTrue(readsStillOK)
    }

    /// France d'abord: la premiere requete filtre les produits vendus en France.
    func testFrenchProductsAreAskedFirst() async {
        StubURLProtocol.routes = [("search.openfoodfacts.org", 200, json(#"{"page_count":1,"hits":[]}"#))]
        _ = await ProductCatalog.search("jambon")
        let first = StubURLProtocol.requested.first?.absoluteString.removingPercentEncoding ?? ""
        XCTAssertTrue(first.contains(#"countries_tags:"en:france""#), first)
    }

    func testMatchingNamesComeFirst() {
        func p(_ code: String, _ name: String) -> CatalogProduct { CatalogProduct(barcode: code, source: .food, name: name) }
        let r = ProductCatalog.rankByQuery(.results([p("1", "Deko pâte"), p("2", "Pâte à tartiner Nutella"), p("3", "Biscuit")], hasMore: false), "nutella pate")
        guard case .results(let items, _) = r else { return XCTFail() }
        XCTAssertEqual(items.map(\.barcode), ["2", "1", "3"], "deux mots trouvés, puis un, puis aucun; accents ignorés")
    }

    /// "Tout": aliments et cosmetiques dans la meme liste.
    func testAllKindSearchesFoodAndBeauty() async {
        StubURLProtocol.routes = [
            ("openbeautyfacts.org/cgi/search.pl", 200, json(#"{"count":1,"products":[{"code":"3600551119816","product_name":"Shampoing doux"}]}"#)),
            ("search.openfoodfacts.org", 200, json(#"{"page_count":1,"hits":[{"code":"1","product_name":"Bonbon shampoing"}]}"#)),
        ]
        guard case .results(let items, _) = await ProductCatalog.search("shampoing", kind: .all) else { return XCTFail() }
        XCTAssertEqual(Set(items.map(\.source)), [.food, .beauty])
    }

    /// Photo de face deposee par la marque (compte "org-..."): packshot officiel.
    func testProducerFrontPhotoIsRecognised() async {
        StubURLProtocol.routes = [("product/3017620406003", 200, json(#"""
        {"status":1,"product":{"code":"3017620406003","product_name":"Nutella","image_front_url":"https://img/front.jpg",
         "images":{"front_fr":{"imgid":"74","rev":"203"},"74":{"uploader":"org-ferrero-france-commerciale"},"12":{"uploader":"kiliweb"}}}}
        """#))]
        guard case .found(let p) = await ProductCatalog.product(barcode: "3017620406003") else { return XCTFail() }
        XCTAssertEqual(p.imageFromProducer, true)
        StubURLProtocol.routes = [("product/3033490004743", 200, json(#"""
        {"status":1,"product":{"code":"3033490004743","product_name":"Skyr","images":{"front_fr":{"imgid":32},"32":{"uploader":"quentinbrd"}}}}
        """#))]
        guard case .found(let q) = await ProductCatalog.product(barcode: "3033490004743") else { return XCTFail() }
        XCTAssertEqual(q.imageFromProducer, false)
    }

    /// Le moteur principal en panne: l'ancien sert de repli.
    func testSearchFallsBackToLegacyEngine() async {
        StubURLProtocol.routes = [("search.openfoodfacts.org", 503, json("x")),
                                  ("search.pl", 200, json(#"{"count":1,"products":[{"code":"2","product_name":"B","brands":"X,Y"}]}"#))]
        guard case .results(let items, _) = await ProductCatalog.search("pomme") else { return XCTFail() }
        XCTAssertEqual(items.map(\.name), ["B"])
        XCTAssertEqual(items.first?.brand, "X")
    }

    func testCosmeticSearchUsesOpenBeautyFacts() async {
        StubURLProtocol.routes = [("openbeautyfacts.org/cgi/search.pl", 200,
            json(#"{"count":1,"products":[{"code":"3600551119816","product_name":"Shampoing doux","ingredients_text":"Aqua, Glycerin"}]}"#))]
        guard case .results(let items, _) = await ProductCatalog.search("shampoing", kind: .beauty) else { return XCTFail() }
        XCTAssertEqual(items.first?.source, .beauty)
        XCTAssertNil(items.first?.isSummary, "fiche complete: notable dans la liste")
        XCTAssertTrue(StubURLProtocol.requested.allSatisfy { $0.host == "world.openbeautyfacts.org" })
    }

    /// Mesure du 29 sept: le moteur alimentaire liste des shampoings dont la fiche
    /// a migre vers Open Beauty Facts (404 cote aliments). La fiche est cherchee
    /// dans l'autre base avant de marquer la ligne en echec.
    func testMovedProductIsCompletedFromTheOtherBase() async {
        StubURLProtocol.routes = [("api/v3/product/3596710536696", 200,
            json(#"{"product":{"code":"3596710536696","product_type":"beauty","product_name":"Shampoing","ingredients_text":"Aqua, Glycerin, Coco-Betaine"}}"#))]
        let summary = CatalogProduct(barcode: "3596710536696", source: .food, name: "Shampoing")
        let (r, _) = await ProductCatalog.complete(summary)
        guard case .found(let p) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(p.source, .beauty, "noté avec la méthode cosmétique")
        XCTAssertEqual(StubURLProtocol.requested.count, 1, "une seule requête universelle")
        StubURLProtocol.requested = []
        let (gone, _) = await ProductCatalog.complete(CatalogProduct(barcode: "1", source: .food, name: "X"))
        XCTAssertEqual(gone, .notFound, "absent des deux bases: vraiment absent")
    }

    /// Le haut de la liste doit etre notable: une fiche sans ingredients passe apres.
    func testProductsThatCanNeverBeRatedGoLast() {
        var empty = CatalogProduct(barcode: "1", source: .beauty, name: "Shampoing A")
        empty.ingredientsText = nil
        var full = CatalogProduct(barcode: "2", source: .beauty, name: "Shampoing B")
        full.ingredientsText = "Aqua, Glycerin, Coco-Betaine"
        var summary = CatalogProduct(barcode: "3", source: .food, name: "Shampoing C")
        summary.isSummary = true
        guard case .results(let r, _) = ProductCatalog.rankByQuery(.results([empty, summary, full], hasMore: false), "shampoing") else { return XCTFail() }
        XCTAssertEqual(r.map(\.barcode), ["2", "3", "1"])
    }

    /// Alternatives: la categorie entiere est regardee (plus de filtre Nutri-Score
    /// A/B), les candidats sont completes, et seule la VRAIE note compte.
    func testAlternativesAreCompletedAndMustReallyScoreHigher() async throws {
        let spread = #"{"code":"%@","product_name":"%@","categories_tags":["en:spreads","en:cocoa-and-hazelnuts-spreads"],"ingredients_text":"x","additives_tags":%@,"nutriments":{"energy-kcal_100g":%@,"sugars_100g":%@,"saturated-fat_100g":%@,"salt_100g":0.1,"fiber_100g":%@,"proteins_100g":7}}"#
        func hit(_ c: String, _ n: String, _ add: String, _ kcal: String, _ su: String, _ sat: String, _ fi: String) -> String {
            String(format: spread, c, n, add, kcal, su, sat, fi)
        }
        let good = hit("111", "Ouf", "[]", "400", "26", "1.8", "4.8")
        let tricky = hit("222", "Faux ami", #"["en:e951","en:e250","en:e320"]"#, "420", "20", "2", "4")
        StubURLProtocol.routes = [
            ("search.openfoodfacts.org", 200, json(#"{"page_count":1,"hits":["# + good + "," + tricky + "]}")),
            ("product/111", 200, json(#"{"status":1,"product":"# + good + "}")),
            ("product/222", 200, json(#"{"status":1,"product":"# + tricky + "}")),
        ]
        let data = try XCTUnwrap(nutella.data(using: .utf8))
        let current = try XCTUnwrap(try JSONDecoder().decode(OFFSingle.self, from: data).product?.product(fallbackCode: "3017620422003", source: .food))
        guard case .found(let list) = await ProductCatalog.alternatives(to: current) else { return XCTFail() }
        XCTAssertEqual(list.map(\.barcode).first, "111")
        XCTAssertTrue(list.allSatisfy { (ProductScore.evaluate($0).value ?? 0) > (ProductScore.evaluate(current).value ?? 0) })
    }

    func testCategoryKeysMatchMalformedAndFrenchTags() {
        XCTAssertEqual(ProductCatalog.categoryKeys(["en:Pâtes à tartiner"]), ProductCatalog.categoryKeys(["fr:pates-a-tartiner"]))
    }

    func testAlternativesSayWhenTheBaseDidNotAnswer() async throws {
        StubURLProtocol.routes = [("search.openfoodfacts.org", 503, Data())]
        defer { XCTAssertTrue(StubURLProtocol.requested.allSatisfy { !($0.query ?? "").contains("%C3%A2") }, "jamais une étiquette mal formée") }
        let data = try XCTUnwrap(nutella.data(using: .utf8))
        let current = try XCTUnwrap(try JSONDecoder().decode(OFFSingle.self, from: data).product?.product(fallbackCode: "3017620422003", source: .food))
        guard case .unavailable = await ProductCatalog.alternatives(to: current) else { return XCTFail("un 503 n'est pas « aucune alternative »") }
    }

    // MARK: Scan: meme identite que la recherche

    /// Un UPC-A scanne en 12 chiffres retrouve la fiche rangee en EAN-13.
    func testUPCAScanFindsTheEAN13Record() async {
        StubURLProtocol.routes = [("api/v3/product/0049000028911", 200, json(#"{"product":{"code":"0049000028911","product_type":"food","product_name":"Coca-Cola"}}"#))]
        let (r, trace) = await ProductCatalog.lookup(barcode: "049000028911")
        guard case .found(let p) = r else { return XCTFail(trace.summary) }
        XCTAssertEqual(p.barcode, "0049000028911")
        XCTAssertEqual(trace.normalized?.kind, "UPC-A")
    }

    /// Absent des bases aujourd'hui, mais lu hier par une recherche: la fiche en
    /// cache reste consultable (avant, "absent" etait rendu avant de regarder le cache).
    func testAbsentOnlineButCachedStaysReachable() async throws {
        var p = CatalogProduct(barcode: "3017620422003", source: .food, name: "Nutella")
        p.ingredientsText = "x"
        ProductCache.put(p)
        let (r, trace) = await ProductCatalog.lookup(barcode: "3017620422003")
        guard case .found(let cached) = r else { return XCTFail() }
        XCTAssertEqual(cached.name, "Nutella")
        XCTAssertTrue(trace.usedCache)
        XCTAssertTrue(trace.summary.contains("cache"))
    }

    /// La base universelle rend une fiche d'Open Pet Food Facts: notee avec la
    /// methode Animaux, jamais comme un aliment humain.
    func testPetFoodFromUniversalLookupIsAPetProduct() async {
        StubURLProtocol.routes = [("api/v3/product/3222270550673", 200, json(#"{"product":{"code":"3222270550673","product_type":"petfood","product_name":"Gourmet Gold","categories_tags":["en:cat-food"],"ingredients_text":"viande et sous-produits animaux (dont poulet 4%), sucres","nutriments":{"proteins_100g":0.11,"fat_100g":0.07,"moisture_100g":77}}}"#))]
        guard case .found(let p) = await ProductCatalog.product(barcode: "3222270550673") else { return XCTFail() }
        XCTAssertEqual(p.source, .pet)
        XCTAssertEqual(p.petAnalysis?.protein ?? 0, 11, accuracy: 0.001, "fraction 0,11 convertie en 11 %")
        XCTAssertTrue(p.petAnalysis?.convertedFromFraction == true)
        XCTAssertTrue(ProductScore.evaluate(p).method.contains("Animaux"))
    }

    // MARK: Reponses mixtes (revue Codex du 29 sept)

    /// Forme canonique en panne (503), forme equivalente absente (404): l'absence
    /// n'est pas etablie. Avant: "produit absent", donc une fiche a creer a tort.
    func testOutageOnCanonicalFormIsNotAbsence() async {
        StubURLProtocol.routes = [("api/v3/product/0049000028911", 503, json("down")), ("api/v2/product/0049000028911", 503, json("down"))]
        let (r, trace) = await ProductCatalog.lookup(barcode: "049000028911")
        guard case .unavailable(let m) = r else { return XCTFail("\(r) \(trace.attempts)") }
        XCTAssertTrue(m.contains("Recherche incomplète"))
        XCTAssertTrue(trace.incomplete)
        XCTAssertTrue(trace.attempts.contains { $0.outcome == "absent" }, "une forme équivalente a bien répondu absent")
    }

    func testThrottledCanonicalAndAbsentVariantIsIncomplete() async {
        StubURLProtocol.routes = [("api/v3/product/0049000028911", 429, json("{}")), ("api/v2/product/0049000028911", 429, json("{}"))]
        guard case .unavailable = await ProductCatalog.lookup(barcode: "049000028911").0 else { return XCTFail() }
    }

    /// La base universelle repond "absent" pour la forme canonique: vraiment absent.
    func testCanonicalAbsenceIsAbsence() async {
        let (r, trace) = await ProductCatalog.lookup(barcode: "3017620422004")
        XCTAssertEqual(r, .notFound)
        XCTAssertFalse(trace.incomplete)
    }

    /// Panne universelle mais les trois bases disent absent par l'ancien trajet.
    func testLegacyAbsenceOnAllBasesIsAbsence() async {
        StubURLProtocol.routes = [("api/v3/", 503, json("down"))]
        let (r, trace) = await ProductCatalog.lookup(barcode: "3017620422004")
        XCTAssertEqual(r, .notFound, "\(trace.attempts)")
        XCTAssertTrue(trace.usedLegacy)
    }

    /// Panne partout, mais la fiche est en cache: elle reste consultable.
    func testOutageWithCacheServesTheCache() async {
        var p = CatalogProduct(barcode: "3017620422003", source: .food, name: "Nutella"); p.ingredientsText = "x"
        ProductCache.put(p)
        StubURLProtocol.routes = [("openfoodfacts", 503, json("down")), ("openbeautyfacts", 503, json("down")), ("openpetfoodfacts", 503, json("down"))]
        guard case .found = await ProductCatalog.lookup(barcode: "3017620422003").0 else { return XCTFail() }
    }

    func testBarcodeNormalization() throws {
        XCTAssertTrue(Barcode.checksumOK("3017620422003"))
        XCTAssertFalse(Barcode.checksumOK("3017620422004"))
        XCTAssertEqual(Barcode.normalize("03017620422003")?.canonical, "3017620422003", "GTIN-14 de tête 0")
        XCTAssertEqual(Barcode.normalize("049000028911")?.canonical, "0049000028911", "UPC-A")
        XCTAssertEqual(Barcode.normalize("0049000028911")?.candidates.contains("049000028911"), true)
        XCTAssertEqual(Barcode.normalize("40170725")?.kind, "EAN-8")
        XCTAssertEqual(Barcode.normalize(" 3017620422003\n")?.digits, "3017620422003", "espaces de lecture caméra")
        XCTAssertNil(Barcode.normalize("12345"))
        XCTAssertNil(Barcode.normalize("٣٠١٧٦٢٠٤٢٢٠٠٣"), "chiffres non latins refusés, jamais convertis en silence")
        XCTAssertEqual(Barcode.normalize("3017620422004")?.checksumValid, false)
        // Jamais de troncature: la forme d'origine reste toujours essayée.
        XCTAssertEqual(Barcode.normalize("3017620422003")?.candidates.first, "3017620422003")
    }

    func testSearchOfflineIsAnErrorNotAnEmptyList() async {
        StubURLProtocol.failWith = URLError(.timedOut)
        guard case .unavailable = await ProductCatalog.search("yaourt") else { return XCTFail() }
    }
}

// MARK: - Note LifeOS

final class ProductScoreTests: XCTestCase {

    private func product(_ name: String = "P", source: CatalogProduct.Source = .food, categories: [String] = [],
                         ingredients: String? = "ingrédients", additives: [String] = [], labels: [String] = [],
                         kcal: Double? = 100, sugars: Double? = 1, sat: Double? = 0.5, salt: Double? = 0.1,
                         fiber: Double? = nil, protein: Double? = nil) -> CatalogProduct {
        var p = CatalogProduct(barcode: "1", source: source, name: name)
        p.categories = categories; p.ingredientsText = ingredients; p.additives = additives; p.labels = labels
        p.nutriments = .init(energyKcal: kcal, proteins: protein, sugars: sugars, saturatedFat: sat, fiber: fiber, salt: salt)
        return p
    }

    func testNutritionComesFromNutrientsNotFromTheLetter() {
        var a = product(kcal: 539, sugars: 56.3, sat: 10.6, salt: 0.107, fiber: 0, protein: 6.3)
        a.nutriscoreGrade = "a"   // lettre fausse volontairement
        var b = a; b.nutriscoreGrade = "e"
        XCTAssertEqual(ProductScore.evaluate(a), ProductScore.evaluate(b), "la lettre A-E ne doit rien changer")
        XCTAssertLessThan(ProductScore.evaluate(a).value!, 50, "une pâte à tartiner très sucrée n'est pas bonne")
    }

    func testWaterScoresHighOnItsOwnRule() {
        let w = product("Eau", categories: ["en:beverages", "en:waters"], ingredients: "Eau minérale naturelle", kcal: 0, sugars: 0, sat: 0, salt: 0.01)
        let r = ProductScore.evaluate(w)
        XCTAssertEqual(r.method, "Eau")
        XCTAssertEqual(r.value, 100)
    }

    /// Audit du 28 septembre: une eau SANS valeurs obtenait 100.
    func testWaterWithoutDataIsNotEvaluated() {
        let noValues = product("Eau", categories: ["en:beverages", "en:waters"], ingredients: nil,
                               kcal: nil, sugars: nil, sat: nil, salt: nil)
        let r = ProductScore.evaluate(noValues)
        XCTAssertEqual(r.method, "Eau")
        XCTAssertNil(r.value)
        XCTAssertEqual(Set(r.missing), ["énergie", "sucres", "liste des ingrédients"])
        let valuesNoList = product("Eau", categories: ["en:waters"], ingredients: nil, kcal: 0, sugars: 0, sat: nil, salt: nil)
        XCTAssertNil(ProductScore.evaluate(valuesNoList).value, "sans liste, les additifs ne sont pas supposés absents")
    }

    func testSugaryWaterIsNotPlainWater() {
        let w = product("Eau sucrée", categories: ["en:waters"], ingredients: "Eau", kcal: 20, sugars: 5, sat: 0, salt: 0)
        XCTAssertFalse(ProductScore.isPlainWater(w))
        XCTAssertEqual(ProductScore.evaluate(w).method, "Boissons")
    }

    /// Une eau aromatisee est rangee dans "eaux" par la base: elle ne doit pas
    /// passer par la regle de l'eau plate.
    func testFlavouredWaterIsNotPlainWater() {
        let byCategory = product("Eau citron", categories: ["en:beverages", "en:waters", "en:flavoured-waters"],
                                 ingredients: nil, kcal: nil, sugars: nil, sat: nil, salt: nil)
        XCTAssertFalse(ProductScore.isPlainWater(byCategory))
        let byIngredients = product("Eau pêche", categories: ["en:beverages", "en:waters"],
                                    ingredients: "Eau, sucre, arôme naturel", kcal: nil, sugars: nil, sat: nil, salt: nil)
        XCTAssertFalse(ProductScore.isPlainWater(byIngredients))
        XCTAssertNil(ProductScore.evaluate(byIngredients).value, "valeurs inconnues: pas de note, pas 100")
    }

    func testPerfumeWrittenTwiceCountsOnce() {
        let s = product("Gel douche", source: .beauty, ingredients: "Aqua, Sodium Laureth Sulfate, Cocamidopropyl Betaine, Glycerin, Parfum/Fragrance")
        XCTAssertEqual(ProductScore.evaluate(s).value, 97)
    }

    /// Audit du 28 septembre: une liste incomprise obtenait 100.
    func testUnrecognisedCosmeticIsNotEvaluated() {
        let s = product("X", source: .beauty, ingredients: "INGREDIENT_UNRECOGNISED_123")
        let r = ProductScore.evaluate(s)
        XCTAssertNil(r.value)
        XCTAssertTrue(r.components.first?.details.contains { $0.contains("ingredient_unrecognised_123") } == true)
    }

    func testMostlyUnrecognisedCosmeticIsNotEvaluatedButMostlyKnownIs() {
        let mixed = product("Y", source: .beauty, ingredients: "Aqua, Glycerin, Zorblax, Quintex-9, Frumple Acid")
        XCTAssertNil(ProductScore.evaluate(mixed).value, "2 inconnus sur 5 = 60 % reconnus")
        let mostly = product("Z", source: .beauty,
            ingredients: "Aqua, Glycerin, Cetearyl Alcohol, Dimethicone, Phenoxyethanol, Simmondsia Chinensis Seed Oil, Tocopherol, Xanthan Gum, Citric Acid, Zorblax")
        let r = ProductScore.evaluate(mostly)
        XCTAssertEqual(r.value, 100, "9 sur 10 reconnus, rien a surveiller")
        XCTAssertTrue(r.components[0].details.contains { $0.contains("zorblax") }, "l'inconnu reste nommé")
    }

    /// Vraie liste Open Beauty Facts (3600551119816): notee grace a CosIng, et le
    /// code de formule "(F.I.L. ...)" n'est pas compte comme ingredient inconnu.
    func testRealShampooIsScoredWithCosIng() {
        let s = product("Shampoing", source: .beauty, ingredients: "AQUA/WATER, SODIUM LAURETH SULFATE, PEG-200 HYDROGENATED GLYCERYL PALMATE, COCO-BETAINE, SODIUM CHLORIDE, SODIUM BENZOATE, SODIUM HYDROXIDE, SIMMONDSIA CHINENSIS SEED OIL/JOJOBA SEED OIL, CITRIC ACID, POLYSORBATE 20, HEXYLENE GLYCOL, POLYQUATERNIUM-10, BUTYROSPERMUM PARKII BUTTER/SHEA BUTTER, PEG-7 GLYCERYL COCOATE, CI 14700/RED 4, CI 47005/ ACID YELLOW 3, PARFUM/FRAGRANCE. (F.I.L. Z288697/2)")
        let r = ProductScore.evaluate(s)
        XCTAssertNotNil(r.value, "\(r.components.first?.details ?? [])")
        XCTAssertFalse(r.components[0].details.joined().contains("z288697"))
        XCTAssertFalse(ProductScore.inciTokens("CI 14700, (F.I.L. Z288697/2)").contains { $0.contains("z28") })
    }

    /// Audit apres build 42: reconnaitre n'est pas evaluer. La note le dit, et porte
    /// un niveau de confiance.
    func testRecognisedIsNotPresentedAsEvaluated() {
        let s = product("Crème", source: .beauty, ingredients: "Aqua, Glycerin, Cetearyl Alcohol, Dimethicone, Phenoxyethanol, Tocopherol")
        let r = ProductScore.evaluate(s)
        XCTAssertEqual(r.value, 100)
        let text = r.components[0].details.joined(separator: " ")
        XCTAssertTrue(text.contains("pas évalué"), text)
        XCTAssertTrue(text.contains("ne prouve pas"), "jamais présenté comme sans risque")
        XCTAssertEqual(r.confidence?.level, .high)
    }

    func testPartlyRecognisedListHasMediumConfidence() {
        let s = product("Z", source: .beauty,
            ingredients: "Aqua, Glycerin, Cetearyl Alcohol, Dimethicone, Phenoxyethanol, Simmondsia Chinensis Seed Oil, Tocopherol, Xanthan Gum, Citric Acid, Zorblax")
        XCTAssertEqual(ProductScore.evaluate(s).confidence?.level, .medium)
    }

    /// Une huile pure (un seul ingredient reconnu) etait exclue par le minimum de 3.
    func testVeryShortFormulaIsScoredWithLowConfidence() {
        let oil = product("Huile de jojoba", source: .beauty, ingredients: "Simmondsia Chinensis Seed Oil")
        let r = ProductScore.evaluate(oil)
        XCTAssertEqual(r.value, 100)
        XCTAssertEqual(r.confidence?.level, .low)
        let unknownShort = product("X", source: .beauty, ingredients: "Zorblax")
        XCTAssertNil(ProductScore.evaluate(unknownShort).value, "court ET inconnu: toujours pas de note")
    }

    func testEmptyIngredientListIsNotEvaluated() {
        XCTAssertNil(ProductScore.evaluate(product(source: .beauty, ingredients: "")).value)
        XCTAssertNil(ProductScore.evaluate(product(source: .beauty, ingredients: " , ; ")).value)
    }

    func testZeroDrinkIsNotTreatedAsWaterAndSweetenerCounts() {
        let base = product("Zero", categories: ["en:beverages"], additives: ["en:e338", "en:e150d"], kcal: 0.3, sugars: 0, sat: 0, salt: 0.02)
        var sweet = base; sweet.additives.append("en:e951")
        let a = ProductScore.evaluate(base), b = ProductScore.evaluate(sweet)
        XCTAssertEqual(a.method, "Boissons")
        XCTAssertLessThan(b.value!, a.value!, "un édulcorant dans une boisson coûte des points")
        XCTAssertTrue(b.flags.contains { $0.code == "E951" })
    }

    /// Whey: sa propre methode (proteines, sucres, additifs), pas la grille des aliments.
    func testWheyUsesTheProteinPowderMethod() {
        let whey = product("Whey protein vanille", categories: ["en:protein-powders"], kcal: 380, sugars: 5, sat: 1, salt: 0.5, protein: 78)
        let r = ProductScore.evaluate(whey)
        XCTAssertEqual(r.method, "Protéines en poudre")
        // Proteines (78-40)/45*50 = 42, sucres (15-5)/13*20 = 15, additifs 30.
        XCTAssertEqual(r.value, 87)
        let sweetened = product("Whey choco", categories: ["en:protein-powders"], additives: ["en:e951"], kcal: 380, sugars: 5, sat: 1, salt: 0.5, protein: 78)
        // Aspartame: risque eleve (CIRC 2B) -> plafond de 49.
        XCTAssertEqual(ProductScore.evaluate(sweetened).value, 49)
        let incomplete = product("Whey", categories: ["en:protein-powders"], ingredients: nil, protein: 78)
        XCTAssertNil(ProductScore.evaluate(incomplete).value)
        XCTAssertTrue(ProductScore.evaluate(incomplete).missing.contains("liste des ingrédients"))
    }

    func testOtherSupplementsAreNotScored() {
        let vit = product("Vitamine D3", categories: ["en:dietary-supplements", "en:vitamins"], kcal: nil, sugars: nil)
        guard case .notApplicable = ProductScore.evaluate(vit).outcome else { return XCTFail() }
    }

    func testCosmeticUsesIngredientMethod() {
        let s = product("Shampoing", source: .beauty, ingredients: "Aqua, Sodium Lauryl Sulfate, Parfum, Limonene, Propylparaben")
        let r = ProductScore.evaluate(s)
        XCTAssertEqual(r.method, "Cosmétiques")
        XCTAssertEqual(r.value, 100 - 10 - 3 - 3 - 30)
        XCTAssertTrue(r.flags.contains { $0.level == .sensitivity && $0.reason.contains("sensible") },
                      "un allergène est une sensibilité, pas un danger pour tous")
    }

    func testIncompleteProductIsNotEvaluatedNeverZeroOrHundred() {
        let r = ProductScore.evaluate(product(sugars: nil))
        guard case .notEvaluated = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertNil(r.value)
        XCTAssertTrue(r.missing.contains("sucres"))
        let noIngredients = ProductScore.evaluate(product(ingredients: nil))
        XCTAssertNil(noIngredients.value)
        XCTAssertTrue(noIngredients.missing.contains("liste des ingrédients"))
        let cosmetic = ProductScore.evaluate(product(source: .beauty, ingredients: nil))
        XCTAssertNil(cosmetic.value)
    }

    /// Des donnees inconnues ne doivent jamais faire mieux que des donnees connues.
    func testUnknownFiberOrProteinNeverImprovesTheScore() {
        let unknown = ProductScore.evaluate(product(fiber: nil, protein: nil)).value!
        let knownZero = ProductScore.evaluate(product(fiber: 0, protein: 0)).value!
        let knownGood = ProductScore.evaluate(product(fiber: 6, protein: 10)).value!
        XCTAssertEqual(unknown, knownZero)
        XCTAssertGreaterThan(knownGood, unknown)
    }

    func testAdditivesAndOrganicMoveTheScoreAsDocumented() {
        let plain = ProductScore.evaluate(product()).value!
        let nitrite = ProductScore.evaluate(product(additives: ["en:e250"])).value!
        let organic = ProductScore.evaluate(product(labels: ["en:organic"])).value!
        XCTAssertGreaterThan(plain, 49)
        XCTAssertEqual(nitrite, 49, "additif à risque élevé : plafond de 49 (règle Yuka)")
        XCTAssertTrue(ProductScore.evaluate(product(additives: ["en:e250"])).components.contains { $0.name == "Plafond" })
        let lowPlain = product(kcal: 450, sugars: 30, sat: 8, salt: 1.2)
        let lowNitrite = ProductScore.evaluate({ var p = lowPlain; p.additives = ["en:e250"]; return p }()).value!
        XCTAssertEqual(ProductScore.evaluate(lowPlain).value! - lowNitrite, 15, "sous le plafond, -15 par additif à risque élevé")
        XCTAssertEqual(organic - plain, 10)
    }

    /// Coca-Cola Original, fiche reelle du 29 sept: Nutri-Score 2023 officiel E
    /// (12 points, tableau boissons), E150d et E338. Avant: environ 50/100.
    func testRegularColaIsNowBad() {
        var cola = product("Coca-Cola Original", categories: ["en:beverages", "en:sodas", "en:colas"],
                           additives: ["en:e150d", "en:e338"], kcal: 42, sugars: 10.6, sat: 0, salt: 0)
        cola.nutriscoreGrade = "e"; cola.nutriscoreScore = 12
        let r = ProductScore.evaluate(cola)
        XCTAssertLessThanOrEqual(r.value!, 20, "\(r.components)")
        XCTAssertTrue(r.components[0].details[0].contains("boissons"))
        // Sans le score officiel, le calcul LifeOS 2023 donne le meme resultat.
        cola.nutriscoreGrade = nil; cola.nutriscoreScore = nil
        XCTAssertLessThanOrEqual(ProductScore.evaluate(cola).value!, 20)
        XCTAssertEqual(ProductScore.computeNutriScore(cola)?.score, 12, "même points que le calcul officiel")
    }

    func testNutriScoreBands() {
        XCTAssertEqual(ProductScore.grade(12, .beverage), "e")
        XCTAssertEqual(ProductScore.grade(2, .beverage), "b")
        XCTAssertEqual(ProductScore.grade(0, .general), "a")
        XCTAssertEqual(ProductScore.grade(19, .general), "e")
        XCTAssertEqual(ProductScore.grade(-6, .fats), "a")
        XCTAssertLessThanOrEqual(ProductScore.nutritionPoints(19, .general), 12, "un E vaut au plus 12/60")
        XCTAssertEqual(ProductScore.nutritionPoints(-10, .general), 60)
        // La table suit la lettre officielle: un score 12 lettre E n'est pas lu comme un aliment (D).
        var p = CatalogProduct(barcode: "1", source: .food, name: "x")
        XCTAssertEqual(ProductScore.table(for: p, official: (12, "e")), .beverage)
        p.categories = ["en:beverages"]
        XCTAssertEqual(ProductScore.table(for: p, official: (4, "c")), .beverage)
    }

    func testDeterministicAndVersioned() {
        let p = product(kcal: 250, sugars: 12, sat: 3, salt: 0.8, fiber: 2, protein: 5)
        XCTAssertEqual(ProductScore.evaluate(p), ProductScore.evaluate(p))
        XCTAssertTrue(ProductScore.version.hasPrefix("LifeOS Qualité 2.0"))
        XCTAssertFalse(ProductScore.version.lowercased().contains("yuka"))
    }

    func testThresholdSteps() {
        XCTAssertEqual(ProductScore.steps(335, [335, 670]), 0, "seuil strict")
        XCTAssertEqual(ProductScore.steps(336, [335, 670]), 1)
        XCTAssertEqual(ProductScore.steps(5000, [335, 670]), 2)
    }
}

// MARK: - Persistance Yuko

@MainActor
final class ProductStoreTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("yukostore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func item(_ code: String) -> CatalogProduct { CatalogProduct(barcode: code, source: .food, name: "P\(code)") }

    func testSurvivesAReload() throws {
        let a = ProductStore(directory: dir)
        try a.record(item("1")); try a.toggleFavorite(item("2")); try a.saveLocal(item("3"))
        let b = ProductStore(directory: dir)
        XCTAssertEqual(b.history.map(\.barcode), ["1"])
        XCTAssertEqual(b.favorites.map(\.barcode), ["2"])
        XCTAssertEqual(b.localProducts.map(\.barcode), ["3"])
    }

    /// Scans et consultations sont deux listes: une recherche n'entre pas dans les
    /// scans, et deux scans du meme produit restent deux lignes datees.
    func testScansAreSeparateFromViewsAndSurviveAReload() throws {
        let a = ProductStore(directory: dir)
        try a.record(item("1"))
        try a.recordScan(item("2"), via: .camera, at: Date(timeIntervalSince1970: 100))
        try a.recordScan(item("2"), via: .typedCode, at: Date(timeIntervalSince1970: 200))
        let b = ProductStore(directory: dir)
        XCTAssertEqual(b.scans.map(\.product.barcode), ["2", "2"])
        XCTAssertEqual(b.scans.map(\.via), [.typedCode, .camera])
        XCTAssertEqual(b.history.map(\.barcode), ["1"])
        try b.removeScan(b.scans[0])
        XCTAssertEqual(ProductStore(directory: dir).scans.count, 1)
        try b.eraseAll()
        XCTAssertTrue(ProductStore(directory: dir).scans.isEmpty)
    }

    /// Liste d'ingredients photographiee: elle complete la fiche SANS la modifier,
    /// ne passe jamais par-dessus une donnee de la base, et survit a une relance.
    func testEnrichmentFillsOnlyWhatIsMissing() throws {
        let a = ProductStore(directory: dir)
        var shampoo = CatalogProduct(barcode: "9", source: .beauty, name: "Shampoing")
        try a.enrich(barcode: "9", ingredientsText: "Aqua, Glycerin, Coco-Betaine")
        let b = ProductStore(directory: dir)
        let shown = b.enriched(shampoo)
        XCTAssertEqual(shown.ingredientsText, "Aqua, Glycerin, Coco-Betaine")
        XCTAssertTrue(shown.localNote?.contains("non vérifiée") == true)
        XCTAssertNotNil(ProductScore.evaluate(shown).value, "la fiche complétée est notée")
        shampoo.ingredientsText = "Aqua"
        XCTAssertEqual(b.enriched(shampoo).ingredientsText, "Aqua", "la base garde la main")
        try b.removeEnrichment(barcode: "9")
        XCTAssertNil(ProductStore(directory: dir).enriched(CatalogProduct(barcode: "9", source: .beauty, name: "S")).ingredientsText)
    }

    /// Ecriture impossible (dossier en lecture seule, comme un disque plein):
    /// erreur remontee, listes inchangees.
    func testFailedWriteChangesNothingAndThrows() throws {
        let s = ProductStore(directory: dir)
        try s.record(item("1"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try s.record(item("2")))
        XCTAssertThrowsError(try s.toggleFavorite(item("2")))
        XCTAssertThrowsError(try s.saveLocal(item("3")))
        XCTAssertEqual(s.history.map(\.barcode), ["1"], "rien n'est affiche comme enregistre")
        XCTAssertTrue(s.favorites.isEmpty)
        XCTAssertTrue(s.localProducts.isEmpty)
    }

    /// Fichier illisible: mis de cote et signale, jamais ecrase par la sauvegarde suivante.
    func testUnreadableFileIsSetAsideNotOverwritten() throws {
        let garbage = Data("{pas du json".utf8)
        try garbage.write(to: dir.appendingPathComponent("history.json"))
        let s = ProductStore(directory: dir)
        XCTAssertEqual(s.loadProblems.count, 1)
        try s.record(item("9"))
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("history.json.illisible-") }
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(aside[0])), garbage, "le contenu d'origine est garde")
    }
}

// MARK: - Adequation aux objectifs (separee de la note)

final class ProductFitTests: XCTestCase {
    private func food(sugars: Double? = 1, salt: Double? = 0.1, sat: Double? = 0.5, protein: Double? = 3, fiber: Double? = nil,
                      kcal: Double? = 100, additives: [String] = [], nova: Int? = nil, drink: Bool = false) -> CatalogProduct {
        var p = CatalogProduct(barcode: "1", source: .food, name: "P")
        p.ingredientsText = "ingrédients"; p.additives = additives; p.novaGroup = nova
        if drink { p.categories = ["en:beverages"] }
        p.nutriments = .init(energyKcal: kcal, proteins: protein, sugars: sugars, saturatedFat: sat, fiber: fiber, salt: salt)
        return p
    }

    func testSugarUsesPublicThresholdsAndDrinksHaveTheirOwn() {
        XCTAssertEqual(ProductFit.verdict(.lessSugar, food(sugars: 4)).status, .ok)
        XCTAssertEqual(ProductFit.verdict(.lessSugar, food(sugars: 10)).status, .watch)
        XCTAssertEqual(ProductFit.verdict(.lessSugar, food(sugars: 30)).status, .against)
        XCTAssertTrue(ProductFit.verdict(.lessSugar, food(sugars: 30)).reason.contains("22,5"), "seuil affiché sans arrondi")
        XCTAssertEqual(ProductFit.verdict(.lessSugar, food(sugars: 12, drink: true)).status, .against, "11,25 g/100 ml pour une boisson")
    }

    func testMissingValueIsUnknownNeverOk() {
        XCTAssertEqual(ProductFit.verdict(.lessSalt, food(salt: nil)).status, .unknown)
        XCTAssertEqual(ProductFit.verdict(.moreFiber, food(fiber: nil)).status, .unknown)
        XCTAssertEqual(ProductFit.verdict(.lessProcessed, food(nova: nil)).status, .unknown)
    }

    func testProteinIsJudgedAsShareOfEnergy() {
        // 25 g * 4 / 380 kcal = 26 % : riche.
        XCTAssertEqual(ProductFit.verdict(.moreProtein, food(protein: 25, kcal: 380)).status, .ok)
        XCTAssertEqual(ProductFit.verdict(.moreProtein, food(protein: 3, kcal: 400)).status, .against)
    }

    func testSweetenerGoal() {
        XCTAssertEqual(ProductFit.verdict(.noSweeteners, food(additives: ["en:e951"])).status, .against)
        XCTAssertEqual(ProductFit.verdict(.noSweeteners, food()).status, .ok)
    }

    func testCosmeticGoalsOnlyApplyToCosmetics() {
        var shampoo = CatalogProduct(barcode: "2", source: .beauty, name: "S")
        shampoo.ingredientsText = "Aqua, Sodium Laureth Sulfate, Coco-Betaine, Parfum, Limonene"
        let goals: Set<ProductGoal> = [.lessSugar, .fragranceFree, .sensitiveSkin]
        let fit = ProductFit.evaluate(shampoo, goals: goals)
        XCTAssertEqual(fit.verdicts.map(\.goal), [.fragranceFree, .sensitiveSkin], "le sucre ne s'applique pas à un shampoing")
        XCTAssertEqual(fit.verdicts.map(\.status), [.against, .against])
        XCTAssertTrue(fit.verdicts[1].reason.contains("Limonene"))
    }

    /// L'adequation ne touche jamais la note.
    func testGoalsDoNotChangeTheScore() {
        let p = food(sugars: 30)
        let before = ProductScore.evaluate(p).value
        _ = ProductFit.evaluate(p, goals: Set(ProductGoal.allCases))
        XCTAssertEqual(ProductScore.evaluate(p).value, before)
    }

    func testGoalsPersist() {
        let d = UserDefaults(suiteName: "fit-\(UUID())")!
        ProductGoals.save([.lessSalt, .moreFiber], d)
        XCTAssertEqual(ProductGoals.load(d), [.lessSalt, .moreFiber])
    }

    func testAlternativeReasonsOnlyUseValuesBothHave() {
        var better = food(sugars: 2, salt: nil, fiber: 6); better.name = "B"
        let current = food(sugars: 15, salt: 0.8, fiber: 1)
        let why = ProductFit.reasons(alternative: better, versus: current)
        XCTAssertTrue(why.contains("sucres −13 g"), "\(why)")
        XCTAssertTrue(why.contains("fibres +5 g"), "\(why)")
        XCTAssertFalse(why.joined().contains("sel"), "valeur absente d'un côté: pas de comparaison")
    }

    // MARK: Tableau nutritionnel lu par OCR

    func testFrenchLabelTakesThePer100gColumn() {
        let ocr = """
        Valeurs nutritionnelles pour 100 g par portion de 30 g
        Énergie 1650 kJ / 394 kcal 495 kJ / 118 kcal
        Matières grasses 10 g 3 g
        dont acides gras saturés 3,5 g 1,1 g
        Glucides 60 g 18 g
        dont sucres 22 g 6,6 g
        Fibres alimentaires 6,5 g 2 g
        Protéines 9 g 2,7 g
        Sel 0,45 g 0,14 g
        """
        let v = NutritionLabelParser.parse(ocr)
        XCTAssertEqual(v.kcal, 394); XCTAssertEqual(v.saturatedFat, 3.5); XCTAssertEqual(v.sugars, 22)
        XCTAssertEqual(v.fiber, 6.5); XCTAssertEqual(v.proteins, 9); XCTAssertEqual(v.salt, 0.45)
    }

    func testEnglishLabelAndLabelOnItsOwnLine() {
        let ocr = "Energy\n250 kcal\nof which saturates 0.8 g\nof which sugars <0.5 g\nProtein 12 g\nSalt 1.2 g"
        let v = NutritionLabelParser.parse(ocr)
        XCTAssertEqual(v.kcal, 250); XCTAssertEqual(v.saturatedFat, 0.8); XCTAssertEqual(v.sugars, 0.5)
        XCTAssertEqual(v.proteins, 12); XCTAssertEqual(v.salt, 1.2)
        XCTAssertNil(v.fiber, "absent: jamais inventé")
    }

    func testUnrelatedTextGivesNothing() {
        let v = NutritionLabelParser.parse("Fabriqué en France. À conserver au sec.")
        XCTAssertTrue(v.isEmpty)
    }
}
