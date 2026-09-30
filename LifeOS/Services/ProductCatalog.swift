import Foundation

// MARK: - Catalogue produits (Open Food Facts + Open Beauty Facts)
//
// Pourquoi ce fichier (brief du 28 septembre, defaut A):
//   - l'ancien modele n'avait AUCUN champ image: la photo ne pouvait pas s'afficher;
//   - une valeur nutritionnelle absente devenait 0: "inconnu" et "vrai zero" etaient
//     indiscernables;
//   - la recherche jetait tout produit a 0 kcal: l'eau et les boissons zero
//     disparaissaient;
//   - une panne reseau s'affichait "ce code n'est pas dans la base".
// Ici chaque valeur est optionnelle, et une recherche a trois issues distinctes.
//
// Couverture reelle: Open Food Facts est tres riche pour la France et l'Europe de
// l'Ouest, plus mince pour l'Amerique du Nord et ailleurs. Open Beauty Facts
// (cosmetiques) est bien plus petit. Aucun des deux ne contient "tous les produits".

struct CatalogProduct: Codable, Hashable, Identifiable {
    /// `pet`: Open Pet Food Facts (nourriture pour animaux). `product`: Open Products
    /// Facts (entretien, maison...): montre, jamais note sans methode.
    enum Source: String, Codable { case food, beauty, local, pet, product }

    var id: String { "\(source.rawValue):\(barcode)" }
    let barcode: String
    let source: Source
    var name: String
    var brand: String?
    var quantity: String?
    var imageURL: URL?
    var imageSmallURL: URL?
    /// Vrai quand la photo de face a ete deposee par la MARQUE elle-meme (compte
    /// producteur Open Food Facts): packshot officiel. Faux = photo d'un
    /// contributeur, detouree sur fond blanc a l'affichage.
    var imageFromProducer: Bool?
    var countries: [String] = []
    var categories: [String] = []      // etiquettes "en:..."
    var ingredientsText: String?
    var additives: [String] = []       // "en:e250"...
    var allergens: [String] = []       // "en:milk"...
    var traces: [String] = []
    var labels: [String] = []
    var nutriments = Nutriments()
    var servingSize: String?
    var nutriscoreGrade: String?       // officiel, fourni par la base
    /// Points Nutri-Score 2023 officiels (calcules par Open Food Facts, estimation
    /// fruits et legumes comprise). nil = non fourni: LifeOS calcule lui-meme.
    var nutriscoreScore: Int?
    /// Constituants analytiques d'un aliment pour animaux, pour 100 g tel quel.
    var petAnalysis: PetAnalysis?
    var novaGroup: Int?
    var lastModified: Date?
    /// Quand LifeOS a lu cette fiche (affiche l'age des donnees en cache).
    var fetchedAt: Date = Date()
    /// Fiche creee sur l'appareil (produit inconnu): provenance affichee.
    var localNote: String?
    /// Fiche abregee venue d'une recherche: le moteur ne renvoie ni ingredients ni
    /// additifs. On ne la note pas: on charge la fiche complete a l'ouverture.
    var isSummary: Bool?
    /// Photos d'etiquette CHOISIES par la base (composition, valeurs, face avant) :
    /// quand le texte manque, LifeOS peut les lire sur l'appareil.
    var labelPhotos: [LabelPhoto]?
    /// Donnees animaux ajoutees sur l'appareil (etiquette lue, espece choisie),
    /// posees par `ProductStore.enriched`, jamais enregistrees dans la base.
    var petFacts: PetFacts?

    struct LabelPhoto: Codable, Hashable {
        enum Kind: String, Codable { case ingredients, nutrition, front }
        let kind: Kind
        let lang: String
        let url: URL
        let uploaded: Date?
    }

    /// Ce que l'appareil sait en plus de la base pour un aliment animal.
    struct PetFacts: Codable, Hashable {
        var userSpecies: PetLabel.Species?
        var userLifeStage: PetLabel.LifeStage?
        /// "Aliment complet pour chatons..." lu sur l'etiquette.
        var declaration: String?
        var additivesText: String?
        /// Provenance de la composition et des valeurs affichees, en clair.
        var provenance: [String] = []
        var labelDate: Date?
    }

    struct PetAnalysis: Codable, Hashable {
        var protein: Double?
        var fat: Double?
        var fibre: Double?
        var ash: Double?
        var moisture: Double?
        /// Declares sur l'etiquette (pas des teneurs totales mesurees).
        var taurine: Double?
        var calcium: Double?
        var phosphorus: Double?
        /// Valeurs saisies en fractions dans la base (0,11 pour 11 %), converties.
        var convertedFromFraction = false
    }

    var isPetFood: Bool { source == .pet }

    /// Valeurs pour 100 g ou 100 ml. nil = la base ne la donne pas. 0 = vrai zero.
    struct Nutriments: Codable, Hashable {
        var energyKcal: Double?
        var proteins: Double?
        var carbohydrates: Double?
        var sugars: Double?
        var fat: Double?
        var saturatedFat: Double?
        var fiber: Double?
        var salt: Double?
    }

    /// Fiche locale declaree cosmetique (source .local, pas Open Beauty Facts).
    static let localCosmeticTag = "lifeos:cosmetic"
    var isCosmetic: Bool { source == .beauty || categories.contains(Self.localCosmeticTag) }

    var isBeverage: Bool { categories.contains("en:beverages") || categories.contains("en:waters") }
    var isWater: Bool {
        categories.contains { ["en:waters", "en:mineral-waters", "en:spring-waters", "en:natural-mineral-waters"].contains($0) }
    }
    var isSupplement: Bool {
        let tags = ["en:dietary-supplements", "en:food-supplements", "en:protein-powders",
                    "en:bodybuilding-supplements", "en:whey-proteins", "en:vitamins"]
        return categories.contains(where: tags.contains) || name.lowercased().contains("whey")
    }
    var isOrganic: Bool {
        labels.contains { ["en:organic", "en:eu-organic", "fr:ab-agriculture-biologique"].contains($0) }
    }
    /// Allergenes et pays en francais (la base les donne en etiquettes anglaises).
    static let frenchNames: [String: String] = [
        "en:milk": "lait", "en:nuts": "fruits à coque", "en:peanuts": "arachides", "en:soybeans": "soja",
        "en:gluten": "gluten", "en:eggs": "œufs", "en:fish": "poisson", "en:crustaceans": "crustacés",
        "en:molluscs": "mollusques", "en:celery": "céleri", "en:mustard": "moutarde", "en:sesame-seeds": "sésame",
        "en:sulphur-dioxide-and-sulphites": "sulfites", "en:lupin": "lupin",
        "en:france": "France", "en:belgium": "Belgique", "en:switzerland": "Suisse", "en:germany": "Allemagne",
        "en:spain": "Espagne", "en:italy": "Italie", "en:portugal": "Portugal", "en:netherlands": "Pays-Bas",
        "en:united-kingdom": "Royaume-Uni", "en:united-states": "États-Unis", "en:canada": "Canada",
        "en:luxembourg": "Luxembourg", "en:austria": "Autriche", "en:morocco": "Maroc",
    ]
    static func french(_ tag: String) -> String { frenchNames[tag] ?? plain(tag) }

    /// Etiquette lisible: "en:milk" -> "milk".
    static func plain(_ tag: String) -> String {
        tag.split(separator: ":").last.map(String.init)?.replacingOccurrences(of: "-", with: " ") ?? tag
    }
}

enum ProductCatalog {

    enum Lookup: Equatable {
        case found(CatalogProduct)
        /// Les deux bases repondent: ce code n'y est pas.
        case notFound
        /// Pas de reponse exploitable: reseau coupe, delai, serveur en panne.
        case unavailable(String)
    }

    enum Search: Equatable {
        case results([CatalogProduct], hasMore: Bool)
        case unavailable(String)
    }

    static let pageSize = 24

    static let fields = [
        "code", "product_name", "product_name_fr", "brands", "quantity",
        "image_front_url", "image_front_small_url", "image_url", "image_small_url",
        "countries_tags", "categories_tags", "ingredients_text_fr", "ingredients_text",
        "additives_tags", "allergens_tags", "traces_tags", "labels_tags", "nutriments",
        "serving_size", "nutriscore_grade", "nutriscore_score", "nova_group", "last_modified_t"
    ].joined(separator: ",")

    /// Remplacable dans les tests (URLProtocol simule).
    nonisolated(unsafe) static var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = ["User-Agent": "LifeOS - iOS - 1.0 (contact via App Store)"]
        return URLSession(configuration: config)
    }()

    private static let foodHost = "https://world.openfoodfacts.org"
    private static let beautyHost = "https://world.openbeautyfacts.org"
    private static let petHost = "https://world.openpetfoodfacts.org"

    // MARK: Code-barres

    static func product(barcode raw: String) async -> Lookup { await lookup(barcode: raw).0 }

    /// Recherche par code, instrumentee: code brut -> formes normalisees -> base
    /// universelle (une requete trouve aliments ET cosmetiques, Open Food Facts
    /// redirige vers la bonne base) -> ancien trajet base par base si la base
    /// universelle ne repond pas -> cache de l'appareil AVANT de conclure "absent".
    static func lookup(barcode raw: String) async -> (Lookup, LookupTrace) {
        var trace = LookupTrace(raw: raw)
        guard let n = Barcode.normalize(raw) else {
            return (.unavailable("Code-barres invalide : il faut 8, 12, 13 ou 14 chiffres."), trace)
        }
        trace.normalized = n
        var failure: Lookup?
        // L'absence n'est ETABLIE que si la forme canonique a recu une vraie reponse
        // "absent" (base universelle, ou les deux bases par l'ancien trajet). Un
        // "absent" sur une forme equivalente ne masque pas une panne sur la bonne
        // forme (revue Codex du 29 sept: 503 + 404 donnait "produit absent").
        var absenceEstablished = false
        for code in n.candidates {
            let (r, status, base) = await fetchUniversal(code: code)
            trace.attempts.append(.init(code: code, base: base, status: status, outcome: outcomeName(r)))
            switch r {
            case .found(let p):
                ProductCache.put(p)
                logTrace(trace, found: true)
                return (.found(p), trace)
            case .notFound: if code == n.canonical { absenceEstablished = true }
            case .unavailable: failure = failure ?? r
            }
        }
        // Base universelle en panne pour la forme canonique: ancien trajet.
        if failure != nil && !absenceEstablished {
            trace.usedLegacy = true
            var legacyAbsent = 0
            for (host, source, base) in [(foodHost, CatalogProduct.Source.food, "Open Food Facts"), (beautyHost, .beauty, "Open Beauty Facts"),
                                         (petHost, .pet, "Open Pet Food Facts")] {
                let (r, status) = await fetchWithStatus(host: host, code: n.canonical, source: source)
                trace.attempts.append(.init(code: n.canonical, base: base, status: status, outcome: outcomeName(r)))
                if case .found(let p) = r { ProductCache.put(p); logTrace(trace, found: true); return (r, trace) }
                if r == .notFound { legacyAbsent += 1 }
            }
            if legacyAbsent == 3 { absenceEstablished = true }
        }
        // Une fiche deja lue (recherche, scan precedent) reste consultable, avec son age.
        if let cached = n.candidates.lazy.compactMap({ ProductCache.get(barcode: $0) }).first {
            trace.usedCache = true
            logTrace(trace, found: true)
            return (.found(cached), trace)
        }
        logTrace(trace, found: false)
        if !absenceEstablished {
            trace.incomplete = true
            let why: String
            if case .unavailable(let m)? = failure { why = m } else { why = "La base n'a pas répondu." }
            return (.unavailable("Recherche incomplète : l'absence du produit n'a pas pu être vérifiée. \(why) Réessaie dans un instant."), trace)
        }
        return (.notFound, trace)
    }

    private static func outcomeName(_ r: Lookup) -> String {
        switch r { case .found: "trouvé"; case .notFound: "absent"; case .unavailable(let m): m }
    }

    private static func logTrace(_ t: LookupTrace, found: Bool) {
        let steps = t.attempts.map { "\($0.base) \($0.code) \($0.status) \($0.outcome)" }.joined(separator: " | ")
        AppLog.data.info("Yuko lookup \(found ? "trouvé" : "absent", privacy: .public): \(steps, privacy: .public)\(t.usedCache ? " | cache" : "", privacy: .public)")
    }

    /// API v3 universelle (`product_type=all`): la base alimentaire repond, ou
    /// redirige vers Open Beauty Facts (suivi automatiquement). La source de la fiche
    /// vient du `product_type` rendu, pas de la base interrogee.
    static func fetchUniversal(code: String) async -> (Lookup, Int, String) {
        guard let url = URL(string: "\(foodHost)/api/v3/product/\(code)?product_type=all&fields=\(fields),images,product_type") else {
            return (.unavailable("Adresse invalide."), -1, "universelle")
        }
        do {
            let (data, response) = try await session.data(from: url)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let host = http?.url?.host ?? ""
            let base = host.contains("openbeautyfacts") ? "Open Beauty Facts"
                : host.contains("openpetfoodfacts") ? "Open Pet Food Facts"
                : host.contains("openproductsfacts") ? "Open Products Facts" : "Open Food Facts"
            if status == 429 { return (.unavailable("La base produit limite les requêtes. Réessaie dans un instant."), status, base) }
            if status >= 500 { return (.unavailable("La base produit ne répond pas (erreur \(status)). Réessaie plus tard."), status, base) }
            guard let v3 = try? JSONDecoder().decode(OFFV3.self, from: data) else {
                return (.unavailable("Réponse illisible de la base produit."), status, base)
            }
            guard let prod = v3.product else {
                // 404 "product_not_found" ou "invalid_code": absent de toutes les bases.
                return (.notFound, status, base)
            }
            let source: CatalogProduct.Source
            switch (prod.product_type, base) {
            case ("beauty", _), (_, "Open Beauty Facts"): source = .beauty
            case ("petfood", _), (_, "Open Pet Food Facts"): source = .pet
            case ("product", _), (_, "Open Products Facts"): source = .product
            default: source = .food
            }
            guard let p = prod.fields.product(fallbackCode: code, source: source, allowUnnamed: true) else {
                return (.unavailable("Fiche illisible."), status, base)
            }
            return (.found(p), status, base)
        } catch {
            return (.unavailable(networkMessage(error)), 0, "réseau")
        }
    }

    /// Fiche complete d'un produit vu en liste, par l'API produit. Un seul essai:
    /// les nouveaux essais en rafale sont exactement ce qui fait bloquer l'adresse
    /// (429 mesure le 29 sept). Le rythme est tenu par `CatalogBudget`.
    ///
    /// Une fiche peut avoir change de base: le moteur de recherche alimentaire garde
    /// des shampoings deplaces depuis vers Open Beauty Facts, et leur fiche repond
    /// 404 cote aliments (mesure le 29 sept sur 9 shampoings sur 12). Un "absent"
    /// d'une base est donc verifie dans l'autre avant d'etre cru.
    static func complete(_ p: CatalogProduct) async -> (Lookup, Int) {
        // Une seule requete universelle d'abord: elle trouve la fiche quelle que soit
        // sa base. En panne (pas un "absent"), ancien trajet base par base.
        let (u, status, _) = await fetchUniversal(code: p.barcode)
        switch u {
        case .found, .notFound: return (u, status)
        case .unavailable: if status == 429 { return (u, status) }
        }
        if p.source == .pet { return await fetchWithStatus(host: petHost, code: p.barcode, source: .pet) }
        let first = await fetchWithStatus(host: p.source == .beauty ? beautyHost : foodHost, code: p.barcode, source: p.source)
        guard first.0 == .notFound else { return first }
        // Deuxieme requete: elle compte dans le budget. Hors budget, statut 0 =
        // "reessayer plus tard", sans bloquer toute la file comme un 429.
        guard await CatalogBudget.shared.take() else { return (.unavailable("Réessai plus tard."), 0) }
        let other: CatalogProduct.Source = p.source == .beauty ? .food : .beauty
        return await fetchWithStatus(host: other == .beauty ? beautyHost : foodHost, code: p.barcode, source: other)
    }

    private static func fetch(host: String, code: String, source: CatalogProduct.Source) async -> Lookup {
        await fetchWithStatus(host: host, code: code, source: source).0
    }

    private static func fetchWithStatus(host: String, code: String, source: CatalogProduct.Source) async -> (Lookup, Int) {
        guard let url = URL(string: "\(host)/api/v2/product/\(code).json?fields=\(fields),images") else {
            return (.unavailable("Adresse invalide."), -1)
        }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // La base repond 404 avec {"status":0} pour un code absent.
            if status < 400, let single = try? JSONDecoder().decode(OFFSingle.self, from: data) {
                if single.status == 1, let p = single.product?.product(fallbackCode: code, source: source, allowUnnamed: true) { return (.found(p), status) }
                if single.status == 0 { return (.notFound, status) }
            }
            if status == 404, let single = try? JSONDecoder().decode(OFFSingle.self, from: data), single.status == 0 { return (.notFound, status) }
            if status == 429 { return (.unavailable("La base produit limite les requêtes. Réessaie dans un instant."), status) }
            if status >= 500 { return (.unavailable("La base produit ne répond pas (erreur \(status)). Réessaie plus tard."), status) }
            return (.unavailable("Réponse illisible de la base produit."), status)
        } catch {
            return (.unavailable(networkMessage(error)), 0)
        }
    }

    // MARK: Recherche par nom

    enum Kind: String, CaseIterable, Identifiable {
        case all, food, beauty, pet
        var id: String { rawValue }
        var label: String { switch self { case .all: "Tout"; case .food: "Aliments"; case .beauty: "Cosmétiques"; case .pet: "Animaux" } }
    }

    static func search(_ query: String, page: Int = 1, kind: Kind = .food) async -> Search {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return .results([], hasMore: false) }
        switch kind {
        case .beauty:
            return rankByQuery(await searchLegacy(q, page: page, host: beautyHost, source: .beauty), q)
        case .pet:
            return rankByQuery(await searchLegacy(q, page: page, host: petHost, source: .pet), q)
        case .food:
            return rankByQuery(await searchFood(q, page: page), q)
        case .all:
            // Aliments ET cosmetiques en meme temps: l'utilisateur n'a pas a savoir dans
            // quelle base chercher un shampoing ou un yaourt.
            async let food = searchFood(q, page: page)
            async let beauty = searchLegacy(q, page: page, host: beautyHost, source: .beauty)
            async let pets = searchLegacy(q, page: page, host: petHost, source: .pet)
            let (f, b, pt) = await (food, beauty, pets)
            // Nourriture pour animaux: ajoutee quand la base repond, jamais bloquante.
            var petItems: [CatalogProduct] = []
            var petMore = false
            if case .results(let items, let more) = pt { petItems = items; petMore = more }
            switch (f, b) {
            case let (.results(a, ma), .results(c, mc)):
                // Des cosmetiques deposes par erreur dans la base ALIMENTAIRE ne se
                // notent pas comme aliments: quand la base cosmetique repond, ils sortent.
                let food = (c.isEmpty && petItems.isEmpty) ? a : a.filter { !$0.categories.contains(where: nonFoodTags.contains) }
                return rankByQuery(.results(food + c + petItems, hasMore: ma || mc || petMore), q)
            case (.results, _): return rankByQuery(f, q)
            case (_, .results): return rankByQuery(b, q)
            default: return f
            }
        }
    }

    static let nonFoodTags: Set<String> = ["en:non-food-products", "en:open-beauty-facts", "en:cosmetics", "en:hygiene",
                                           "en:pet-food", "en:cat-food", "en:dog-food", "en:open-pet-food-facts"]

    /// Aliments: produits vendus en France d'abord, puis le reste du monde une fois
    /// la France epuisee. Chaque page de resultats est completee par la fiche
    /// entiere (additifs compris) en UNE requete, pour que la liste montre une note.
    private static func searchFood(_ q: String, page: Int) async -> Search {
        let france = await searchALicious(q + " countries_tags:\"en:france\"", page: page)
        guard case .results(let fr, let frMore) = france else {
            // Moteur actuel en panne: l'ancien moteur en repli.
            let world = await searchALicious(q, page: page)
            if case .results = world { return await enrich(world, host: foodHost, source: .food) }
            let legacy = await searchLegacy(q, page: page, host: foodHost, source: .food)
            if case .results = legacy { return legacy }
            return france
        }
        if !fr.isEmpty || page == 1 && frMore {
            // Page francaise; il restera ensuite le reste du monde.
            let merged: Search
            if fr.count < pageSize / 2, page == 1 {
                // Peu de produits francais: on complete tout de suite avec le monde.
                if case .results(let w, let wMore) = await searchALicious(q, page: 1) {
                    let seen = Set(fr.map(\.barcode))
                    merged = .results(fr + w.filter { !seen.contains($0.barcode) }, hasMore: frMore || wMore)
                } else { merged = .results(fr, hasMore: frMore) }
            } else {
                merged = .results(fr, hasMore: true)
            }
            return await enrich(merged, host: foodHost, source: .food)
        }
        // France epuisee: pages du monde, sans repeter les produits francais deja vus.
        // La page 1 a deja pris la page 1 du monde quand la France etait maigre.
        let franceCount = await frenchCount(q)
        let francePages = Int((Double(franceCount) / Double(pageSize)).rounded(.up))
        let worldPage = max(1, page - francePages + (franceCount > 0 && franceCount < pageSize / 2 ? 1 : 0))
        guard case .results(let w, let wMore) = await searchALicious(q, page: worldPage) else { return .results([], hasMore: false) }
        return await enrich(.results(w.filter { !$0.countries.contains("en:france") }, hasMore: wMore), host: foodHost, source: .food)
    }

    private static func frenchCount(_ q: String) async -> Int {
        var comps = URLComponents(string: "https://search.openfoodfacts.org/search")!
        comps.queryItems = [.init(name: "q", value: q + " countries_tags:\"en:france\""), .init(name: "page_size", value: "1"), .init(name: "fields", value: "code")]
        guard let url = comps.url, let (data, _) = try? await session.data(from: url),
              let r = try? JSONDecoder().decode(SearchALiciousResponse.self, from: data) else { return 0 }
        return r.count ?? 0
    }

    /// Remplace les fiches abregees par les fiches completes, pour que la liste
    /// montre une note. Dans l'ordre: fiches deja lues (moins d'une semaine), puis
    /// UNE requete pour toute la page, puis, si la base la refuse (limite de debit
    /// de la recherche), les premieres fiches une par une par l'API produit, dont
    /// la limite est dix fois plus haute. Ce qui reste abrege s'affiche quand meme,
    /// sans note, et se complete a l'ouverture.
    static func enrich(_ search: Search, host: String, source: CatalogProduct.Source) async -> Search {
        guard case .results(let items, let more) = search else { return search }
        let summaries = items.filter { $0.isSummary == true }.map(\.barcode)
        guard !summaries.isEmpty else { return search }
        var full = ProductCache.get(barcodes: summaries, maxAge: 7 * 86_400)
        let missing = summaries.filter { full[$0] == nil }
        var fetched: [CatalogProduct] = []
        if !missing.isEmpty {
            // Requete groupee, courte: elle echoue une fois sur deux (503 mesure le
            // 29 sept). Ce qu'elle ne rend pas est complete ligne par ligne par
            // `ProductEnricher`, qui passe par l'API produit, fiable.
            var comps = URLComponents(string: "\(host)/api/v2/search")!
            comps.queryItems = [.init(name: "code", value: missing.joined(separator: ",")),
                                .init(name: "page_size", value: String(missing.count)), .init(name: "fields", value: fields)]
            if let url = comps.url, await CatalogBudget.shared.groupAllowed() {
                // Trois essais espaces: cette requete complete TOUTE la page en une
                // fois, c'est de loin la moins couteuse pour la limite de debit.
                for delay in [0.0, 1.5, 3.0] {
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    var req = URLRequest(url: url); req.timeoutInterval = 6
                    guard let (data, response) = try? await session.data(for: req) else { continue }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 429 { await CatalogBudget.shared.groupBlocked(); break }
                    guard status < 400, let r = try? JSONDecoder().decode(OFFSearch.self, from: data) else { continue }
                    for item in r.products { if let p = item.product(fallbackCode: "", source: source) { full[p.barcode] = p; fetched.append(p) } }
                    break
                }
            }
        }
        ProductCache.put(fetched)
        return .results(items.map { full[$0.barcode] ?? $0 }, hasMore: more)
    }

    /// Les produits dont le nom ou la marque contiennent les mots tapes passent
    /// devant; a egalite, l'ordre du moteur est garde.
    static func rankByQuery(_ search: Search, _ q: String) -> Search {
        guard case .results(let items, let more) = search else { return search }
        let fold = { (s: String) in s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "fr_FR")) }
        let words = fold(q).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }
        guard !words.isEmpty else { return search }
        func score(_ p: CatalogProduct) -> Int {
            let hay = fold(p.name + " " + (p.brand ?? ""))
            return words.filter { hay.contains($0) }.count
        }
        // A pertinence egale: fiche complete (notable) d'abord, puis fiche abregee
        // (elle peut encore se completer), et en dernier une fiche complete SANS
        // liste d'ingredients, qui ne pourra jamais etre notee.
        func tier(_ p: CatalogProduct) -> Int {
            if p.isSummary == true { return 1 }
            return (p.ingredientsText ?? "").isEmpty ? 2 : 0
        }
        let ranked = items.enumerated().sorted { a, b in
            let (sa, sb) = (score(a.element), score(b.element))
            if sa != sb { return sa > sb }
            let (ta, tb) = (tier(a.element), tier(b.element))
            if ta != tb { return ta < tb }
            return a.offset < b.offset
        }.map(\.element)
        var seen = Set<String>()
        return .results(ranked.filter { seen.insert($0.id).inserted }, hasMore: more)
    }

    private static func searchALicious(_ q: String, page: Int, pageSize size: Int = pageSize, sortBy: String? = nil) async -> Search {
        var comps = URLComponents(string: "https://search.openfoodfacts.org/search")!
        comps.queryItems = [
            .init(name: "q", value: q), .init(name: "langs", value: "fr,en"),
            .init(name: "page_size", value: String(size)), .init(name: "page", value: String(page)),
            .init(name: "fields", value: fields)
        ]
        if let sortBy { comps.queryItems?.append(.init(name: "sort_by", value: sortBy)) }
        guard let url = comps.url else { return .unavailable("Recherche invalide.") }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status < 400, let r = try? JSONDecoder().decode(SearchALiciousResponse.self, from: data) else {
                return .unavailable(status >= 500 ? "La base produit ne répond pas (erreur \(status))." : "Réponse illisible de la base produit.")
            }
            // Plus AUCUN filtre sur les calories: l'eau et le zero restent.
            let items = r.hits.compactMap { $0.product(fallbackCode: "", source: .food) }
                .filter { !$0.barcode.isEmpty }
                .map { p -> CatalogProduct in var p = p; p.isSummary = true; return p }
            return .results(items, hasMore: page < (r.page_count ?? 0))
        } catch {
            return .unavailable(networkMessage(error))
        }
    }

    private static func searchLegacy(_ q: String, page: Int, host: String, source: CatalogProduct.Source) async -> Search {
        var comps = URLComponents(string: "\(host)/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms", value: q), .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "page_size", value: String(pageSize)), .init(name: "page", value: String(page)),
            .init(name: "fields", value: fields)
        ]
        guard let url = comps.url else { return .unavailable("Recherche invalide.") }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status < 400, let r = try? JSONDecoder().decode(OFFSearch.self, from: data) else {
                return .unavailable(status >= 500 ? "La base produit ne répond pas (erreur \(status))." : "Réponse illisible de la base produit.")
            }
            let items = r.products.compactMap { $0.product(fallbackCode: "", source: source) }.filter { !$0.barcode.isEmpty }
            let total = Int(r.count?.value ?? 0)
            return .results(items, hasMore: page * pageSize < total)
        } catch {
            return .unavailable(networkMessage(error))
        }
    }

    // MARK: Alternatives reellement presentes dans la base

    /// Alternatives REELLEMENT presentes dans la base: meme categorie la plus
    /// precise, meme methode de note, et note LifeOS strictement superieure.
    /// Aliments (grade officiel A/B en prefiltre), cosmetiques (Open Beauty Facts)
    /// et proteines en poudre. Un produit non note n'a pas de base de comparaison:
    /// liste vide.
    /// "Aucune alternative" et "la base n'a pas repondu" sont deux choses: avant,
    /// un 503 de la recherche s'affichait comme "aucune alternative mieux notée".
    enum Alternatives: Equatable {
        case found([CatalogProduct])
        case none(String)
        case unavailable(String)
    }

    /// Produits de la MEME categorie, mieux notes par la meme methode.
    /// Aliments: moteur de recherche actuel (France d'abord), candidats tries sur la
    /// seule nutrition (connue sur les fiches abregees), puis les meilleurs sont
    /// completes par l'API produit (dans le budget de requetes) et gardes seulement
    /// si leur VRAIE note depasse celle du produit. Plus de filtre Nutri-Score A/B:
    /// il excluait toute une categorie (aucune pate a tartiner n'est A ou B).
    static func alternatives(to product: CatalogProduct) async -> Alternatives {
        guard product.source != .local else { return .none("Fiche créée sur l'appareil : pas de catégorie pour chercher.") }
        let current = ProductScore.evaluate(product)
        guard let currentValue = current.value else { return .none("Pas de comparaison possible : ce produit n'a pas de note LifeOS.") }
        let generic: Set<String> = ["en:non-food-products", "en:open-beauty-facts", "en:beverages", "en:plant-based-foods-and-beverages",
                                    "en:open-pet-food-facts"]
        // Seulement une etiquette bien formee: la base contient aussi des etiquettes
        // mal ecrites ("en:Pâtes à tartiner" sur Nutella), qui ne trouvent rien.
        var categories = Array(product.categories
            .filter { $0.range(of: #"^en:[a-z0-9-]+$"#, options: .regularExpression) != nil && !generic.contains($0) }
            .reversed())
        // Aliment animal mal classe dans la base ("one junior") : la categorie vient de
        // l'identite reconnue (espece, format). Les candidats doivent de toute facon avoir
        // la meme methode, donc la meme espece et le meme stade de vie.
        if categories.isEmpty, product.isPetFood, let sp = ProductScore.petIdentity(product).species {
            let dry = ProductScore.petIdentity(product).format == .dry
            categories = sp == .cat ? (dry ? ["en:dry-cat-food", "en:cat-food"] : ["en:cat-food"])
                                    : (dry ? ["en:dry-dog-food", "en:dog-food"] : ["en:dog-food"])
        }
        guard let category = categories.first else {
            return .none("La fiche n'a pas de catégorie précise : pas d'alternative cherchée.")
        }
        if product.isCosmetic { return await categoryAlternatives(product, host: beautyHost, source: .beauty, category: category, currentValue: currentValue, method: current.method) }
        if product.isPetFood { return await categoryAlternatives(product, host: petHost, source: .pet, category: category, currentValue: currentValue, method: current.method) }

        // Du plus precis au plus large: l'index du moteur ne connait pas toujours la
        // categorie la plus fine de la fiche (Nutella: "confectionary-based-spreads"
        // y donne 0 produit, "sweet-spreads" des centaines). 3 essais au plus.
        var candidates: [CatalogProduct] = []
        var lastError: String?
        var answered = false
        search: for cat in categories.prefix(3) {
            for q in ["categories_tags:\"\(cat)\" countries_tags:\"en:france\"", "categories_tags:\"\(cat)\""] {
                switch await searchALicious(q, page: 1, pageSize: 60, sortBy: "-unique_scans_n") {
                case .results(let items, _): answered = true; candidates += items
                case .unavailable(let m): lastError = m
                }
                if candidates.count >= 20 { break search }
            }
        }
        if !answered, let lastError { return .unavailable(lastError) }
        guard !candidates.isEmpty else { return .none("Aucun autre produit de cette catégorie dans la base.") }
        // Borne haute d'une fiche abregee: nutrition connue + additifs 30 + bio 10.
        func nutrition(_ p: CatalogProduct) -> Double? { ProductScore.food(p).components.first?.points }
        var seen: Set<String> = [product.barcode]
        var seenNames = Set<String>()
        let mine = categoryKeys(product.categories)
        var scored: [(product: CatalogProduct, shared: Int, nutrition: Double)] = []
        for p in candidates {
            guard seen.insert(p.barcode).inserted else { continue }
            let key = (p.name + "|" + (p.brand ?? "")).lowercased()
            guard seenNames.insert(key).inserted, let n = nutrition(p) else { continue }
            let ceiling = n + 30 + (p.isOrganic ? 10 : 0)
            if ceiling > Double(currentValue) { scored.append((p, categoryKeys(p.categories).intersection(mine).count, n)) }
        }
        // Le plus proche d'abord (categories communes: une pate a tartiner avant une
        // confiture), puis la meilleure nutrition.
        scored.sort { $0.shared != $1.shared ? $0.shared > $1.shared : $0.nutrition > $1.nutrition }
        let ranked = scored.prefix(8).map { $0.product }
        guard !ranked.isEmpty else { return .none("Aucun produit de cette catégorie ne peut dépasser \(currentValue)/100 d'après sa nutrition.") }
        var better: [CatalogProduct] = []
        var failures = 0
        for p in ranked {
            guard await CatalogBudget.shared.take() else { failures += 1; continue }
            let (r, _) = await complete(p)
            guard case .found(let full) = r else { if case .unavailable = r { failures += 1 }; continue }
            ProductCache.put(full)
            let v = ProductScore.evaluate(full)
            if v.method == current.method, let value = v.value, value > currentValue { better.append(full) }
        }
        if better.isEmpty && failures == ranked.count { return .unavailable("La base produit n'a pas répondu pour les candidats. Réessaie dans un instant.") }
        guard !better.isEmpty else { return .none("Aucune alternative mieux notée trouvée dans la même catégorie de la base.") }
        return .found(better.sorted { (ProductScore.evaluate($0).value ?? 0) > (ProductScore.evaluate($1).value ?? 0) }.prefix(6).map { $0 })
    }

    /// Etiquettes ramenees a une cle comparable: "en:Pâtes à tartiner" et
    /// "fr:pates-a-tartiner" donnent toutes deux "pates-a-tartiner".
    static func categoryKeys(_ tags: [String]) -> Set<String> {
        Set(tags.map { tag -> String in
            let body = tag.split(separator: ":", maxSplits: 1).last.map(String.init) ?? tag
            return body.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "fr_FR"))
                .lowercased().replacingOccurrences(of: " ", with: "-")
        })
    }

    private static func categoryAlternatives(_ product: CatalogProduct, host: String, source: CatalogProduct.Source,
                                             category: String, currentValue: Int, method: String) async -> Alternatives {
        var comps = URLComponents(string: "\(host)/api/v2/search")!
        comps.queryItems = [.init(name: "categories_tags", value: category),
                            .init(name: "page_size", value: "24"), .init(name: "fields", value: fields)]
        guard let url = comps.url else { return .unavailable("Recherche invalide.") }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status < 400, let r = try? JSONDecoder().decode(OFFSearch.self, from: data) else {
                return .unavailable(status >= 500 ? "La base ne répond pas (erreur \(status)). Réessaie plus tard." : "Réponse illisible de la base.")
            }
            let better = r.products
                .compactMap { $0.product(fallbackCode: "", source: source) }
                .filter { $0.barcode != product.barcode && !$0.barcode.isEmpty }
                .map { ($0, ProductScore.evaluate($0)) }
                .filter { $0.1.method == method && ($0.1.value ?? -1) > currentValue }
                .sorted { ($0.1.value ?? 0) > ($1.1.value ?? 0) }
                .prefix(6).map(\.0)
            return better.isEmpty ? .none("Aucune alternative mieux notée trouvée dans la même catégorie de la base.") : .found(Array(better))
        } catch {
            return .unavailable(networkMessage(error))
        }
    }

    static func networkMessage(_ error: Error) -> String {
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Pas de connexion internet. La recherche reprendra quand tu seras en ligne."
            case .timedOut: return "La base produit met trop de temps à répondre. Réessaie."
            default: break
            }
        }
        return "La base produit est injoignable (\(error.localizedDescription))."
    }
}

// MARK: - Decodage (tolerant, sans jamais inventer de zero)

/// Reponse de l'API v3: `product` absent quand le code n'est dans aucune base.
struct OFFV3: Decodable {
    struct Product: Decodable {
        let product_type: String?
        let fields: OFFItem
        init(from decoder: Decoder) throws {
            fields = try OFFItem(from: decoder)
            product_type = try decoder.container(keyedBy: K.self).decodeIfPresent(String.self, forKey: .product_type)
        }
        enum K: String, CodingKey { case product_type }
    }
    let product: Product?
}

struct FlexNumber: Decodable, Hashable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s.replacingOccurrences(of: ",", with: ".")) }
        else { value = nil }
    }
    init(_ v: Double?) { value = v }
}

/// Texte ou liste de textes: l'API produit donne "Ferrero,Nutella", la recherche
/// ["Ferrero", "Nutella"].
struct FlexStrings: Decodable, Hashable {
    let values: [String]
    var first: String? { values.first }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let list = try? c.decode([String].self) { values = list }
        else if let s = try? c.decode(String.self) { values = s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        else { values = [] }
    }
}

/// Reponse de search.openfoodfacts.org (moteur de recherche officiel actuel).
struct SearchALiciousResponse: Decodable { let hits: [OFFItem]; let page_count: Int?; let count: Int? }

/// Une entree de la carte `images` d'Open Food Facts: photo brute (uploader) ou
/// photo choisie "front_fr" (imgid).
struct OFFImageMeta: Decodable {
    let imgid: FlexNumber?
    let uploader: String?
    /// Revision d'une photo CHOISIE (front_fr, ingredients_fr...) : fait partie du lien.
    let rev: FlexNumber?
    /// Date de depot d'une photo brute ("1", "2"...).
    let uploaded_t: FlexNumber?
}

/// Carte des images, lue sans jamais faire echouer la fiche: une entree
/// inattendue est ignoree, pas fatale.
struct OFFImages: Decodable {
    let map: [String: OFFImageMeta]
    private struct Key: CodingKey {
        var stringValue: String; var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }
    init(from decoder: Decoder) throws {
        var out: [String: OFFImageMeta] = [:]
        if let c = try? decoder.container(keyedBy: Key.self) {
            for k in c.allKeys { if let v = try? c.decode(OFFImageMeta.self, forKey: k) { out[k.stringValue] = v } }
        }
        map = out
    }
}

struct OFFSingle: Decodable { let status: Int; let product: OFFItem? }
struct OFFSearch: Decodable { let products: [OFFItem]; let count: FlexNumber? }

struct OFFItem: Decodable {
    let code: String?
    let product_name: String?
    let product_name_fr: String?
    let brands: FlexStrings?
    let quantity: String?
    let image_front_url: String?
    let image_front_small_url: String?
    let image_url: String?
    let image_small_url: String?
    let countries_tags: [String]?
    let categories_tags: [String]?
    let ingredients_text_fr: String?
    let ingredients_text: String?
    let additives_tags: [String]?
    let allergens_tags: [String]?
    let traces_tags: [String]?
    let labels_tags: [String]?
    let nutriments: [String: FlexNumber]?
    let serving_size: String?
    let nutriscore_grade: String?
    let nutriscore_score: FlexNumber?
    let nova_group: FlexNumber?
    let last_modified_t: FlexNumber?
    let images: OFFImages?

    /// La photo de face choisie a-t-elle ete deposee par un compte producteur
    /// ("org-...")? nil = on ne sait pas (la recherche ne renvoie pas les images).
    var frontFromProducer: Bool? {
        guard let images = images?.map else { return nil }
        let front = images["front_fr"] ?? images["front_en"] ?? images.first(where: { $0.key.hasPrefix("front") })?.value
        guard let id = front?.imgid?.value else { return false }
        return images[String(Int(id))]?.uploader?.hasPrefix("org-") == true
    }

    /// `allowUnnamed`: un code scanne dont la fiche n'a pas de nom reste un produit
    /// trouve (incomplet), pas un produit absent. Une recherche, elle, ignore les
    /// fiches sans nom: impossibles a reconnaitre dans une liste.
    func product(fallbackCode: String, source: CatalogProduct.Source, allowUnnamed: Bool = false) -> CatalogProduct? {
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        guard let name = clean(product_name_fr) ?? clean(product_name) ?? (allowUnnamed ? "Produit sans nom" : nil) else { return nil }
        let n = nutriments ?? [:]
        func v(_ k: String) -> Double? { n[k]?.value }
        var nut = CatalogProduct.Nutriments()
        nut.energyKcal = v("energy-kcal_100g") ?? v("energy_100g").map { $0 / 4.184 }
        nut.proteins = v("proteins_100g")
        nut.carbohydrates = v("carbohydrates_100g")
        nut.sugars = v("sugars_100g")
        nut.fat = v("fat_100g")
        nut.saturatedFat = v("saturated-fat_100g")
        nut.fiber = v("fiber_100g")
        nut.salt = v("salt_100g") ?? v("sodium_100g").map { $0 * 2.5 }

        var pet: CatalogProduct.PetAnalysis?
        if source == .pet {
            var a = CatalogProduct.PetAnalysis(protein: v("crude-protein_100g") ?? v("proteins_100g"),
                                               fat: v("crude-fat_100g") ?? v("fat_100g"),
                                               fibre: v("crude-fibre_100g") ?? v("fiber_100g"),
                                               ash: v("crude-ash_100g"), moisture: v("moisture_100g"))
            // Saisie en fraction (proteines 0,11 et lipides 0,07 pour 11 % et 7 %):
            // aucune croquette ni patee ne contient moins de 1 % de proteines.
            if let pr = a.protein, pr > 0, pr < 1, (a.fat ?? 0) < 1 {
                a.protein = pr * 100; a.fat = a.fat.map { $0 * 100 }; a.fibre = a.fibre.map { $0 < 1 ? $0 * 100 : $0 }
                a.convertedFromFraction = true
            }
            if a.protein != nil || a.fat != nil || a.moisture != nil { pet = a }
        }
        let grade = nutriscore_grade?.lowercased()
        let url: (String?) -> URL? = { $0.flatMap { clean($0) }.flatMap(URL.init(string:)) }
        let photos = labelPhotos(code: clean(code) ?? fallbackCode, source: source)
        return CatalogProduct(
            barcode: clean(code) ?? fallbackCode,
            source: source,
            name: name,
            brand: clean(brands?.first),
            quantity: clean(quantity),
            imageURL: url(image_front_url) ?? url(image_url),
            imageSmallURL: url(image_front_small_url) ?? url(image_small_url) ?? url(image_front_url),
            imageFromProducer: frontFromProducer,
            countries: countries_tags ?? [],
            categories: categories_tags ?? [],
            ingredientsText: clean(ingredients_text_fr) ?? clean(ingredients_text),
            additives: additives_tags ?? [],
            allergens: allergens_tags ?? [],
            traces: traces_tags ?? [],
            labels: labels_tags ?? [],
            nutriments: nut,
            servingSize: clean(serving_size),
            nutriscoreGrade: ["a", "b", "c", "d", "e"].contains(grade ?? "") ? grade : nil,
            nutriscoreScore: ["a", "b", "c", "d", "e"].contains(grade ?? "") ? nutriscore_score?.value.map { Int($0.rounded()) } : nil,
            petAnalysis: pet,
            novaGroup: nova_group?.value.map { Int($0) },
            lastModified: last_modified_t?.value.map { Date(timeIntervalSince1970: $0) },
            labelPhotos: photos.isEmpty ? nil : photos
        )
    }

    /// Liens des photos CHOISIES (ingredients_xx, nutrition_xx, front_xx), au format
    /// public des bases Open * Facts. Francais d'abord, puis anglais, puis le reste.
    func labelPhotos(code: String, source: CatalogProduct.Source) -> [CatalogProduct.LabelPhoto] {
        guard let map = images?.map, !map.isEmpty else { return [] }
        let host: String
        switch source {
        case .pet: host = "https://images.openpetfoodfacts.org"
        case .beauty: host = "https://images.openbeautyfacts.org"
        case .product: host = "https://images.openproductsfacts.org"
        default: host = "https://images.openfoodfacts.org"
        }
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return [] }
        var path = digits
        if digits.count > 8 {
            let padded = String(repeating: "0", count: max(0, 13 - digits.count)) + digits
            let c = Array(padded)
            path = [String(c[0..<3]), String(c[3..<6]), String(c[6..<9]), String(c[9...])].joined(separator: "/")
        }
        var out: [CatalogProduct.LabelPhoto] = []
        for kind in [CatalogProduct.LabelPhoto.Kind.ingredients, .nutrition, .front] {
            let keys = map.keys.filter { $0.hasPrefix(kind.rawValue + "_") }
                .sorted { a, b in
                    func rank(_ k: String) -> Int { k.hasSuffix("_fr") ? 0 : k.hasSuffix("_en") ? 1 : 2 }
                    return (rank(a), a) < (rank(b), b)
                }
            guard let key = keys.first, let rev = map[key]?.rev?.value, let u = URL(string: "\(host)/images/products/\(path)/\(key).\(Int(rev)).full.jpg") else { continue }
            let raw = map[key]?.imgid?.value.map { String(Int($0)) }
            let uploaded = raw.flatMap { map[$0]?.uploaded_t?.value }.map { Date(timeIntervalSince1970: $0) }
            out.append(.init(kind: kind, lang: String(key.split(separator: "_").last ?? ""), url: u, uploaded: uploaded))
        }
        return out
    }
}

// MARK: - Rythme des requetes vers Open Food Facts

/// Budget commun des lectures fiche par fiche: 20 par minute au plus, et arret
/// complet d'une minute des qu'un 429 arrive. Open Food Facts bloque l'adresse
/// entiere quand on insiste; mieux vaut une note qui arrive plus tard qu'aucune.
actor CatalogBudget {
    static let shared = CatalogBudget()
    private var stamps: [Date] = []
    private var pausedUntil = Date.distantPast
    /// La requete groupee passe par la RECHERCHE, dont la limite est a part (~10/min):
    /// un refus la met en pause elle seule, sans arreter les lectures fiche par fiche.
    private var groupPausedUntil = Date.distantPast
    /// Lectures fiche par fiche: Open Food Facts en autorise 100 par minute; on en
    /// garde de la marge pour les autres ecrans (scanner, fiche ouverte).
    var perMinute = 60

    /// Vrai si une lecture peut partir maintenant (et la compte).
    func take(now: Date = Date()) -> Bool {
        guard now >= pausedUntil else { return false }
        stamps = stamps.filter { now.timeIntervalSince($0) < 60 }
        guard stamps.count < perMinute else { return false }
        stamps.append(now)
        return true
    }

    func blocked(now: Date = Date()) { pausedUntil = now.addingTimeInterval(60) }
    func groupBlocked(now: Date = Date()) { groupPausedUntil = now.addingTimeInterval(60) }
    func groupAllowed(now: Date = Date()) -> Bool { now >= groupPausedUntil }
    func reset() { stamps = []; pausedUntil = .distantPast; groupPausedUntil = .distantPast }
}

// MARK: - Completement des lignes de resultat

/// Complete en arriere-plan un produit de liste encore abrege quand la requete
/// groupee n'a pas suffi. Deux a la fois, dans le budget commun; hors budget, la
/// ligne dit "note a l'ouverture" au lieu d'une roue qui tourne sans fin.
@MainActor final class ProductEnricher: ObservableObject {
    static let shared = ProductEnricher()
    @Published private(set) var full: [String: CatalogProduct] = [:]
    @Published private(set) var failed: Set<String> = []
    /// Derniere reponse par produit (statut HTTP, 0 = reseau), pour le diagnostic.
    private(set) var lastStatus: [String: Int] = [:]
    private var queue: [CatalogProduct] = []
    private var inFlight: Set<String> = []
    private var retryTask: Task<Void, Never>?
    var maxConcurrent = 3

    /// La meilleure fiche connue pour ce produit.
    func resolved(_ p: CatalogProduct) -> CatalogProduct {
        p.isSummary == true ? (full[p.barcode] ?? p) : p
    }

    /// En cours seulement si une requete tourne vraiment pour lui.
    func isLoading(_ p: CatalogProduct) -> Bool { inFlight.contains(p.barcode) }

    func request(_ p: CatalogProduct) {
        guard p.isSummary == true, full[p.barcode] == nil, !inFlight.contains(p.barcode), !failed.contains(p.barcode) else { return }
        if let cached = ProductCache.get(barcodes: [p.barcode], maxAge: 7 * 86_400)[p.barcode] { full[p.barcode] = cached; return }
        queue.removeAll { $0.barcode == p.barcode }
        queue.append(p)
        pump()
    }

    /// Nouvelle recherche: ce qui attendait pour l'ancienne n'est plus prioritaire.
    func dropQueued() { queue.removeAll() }

    var idle: Bool { queue.isEmpty && inFlight.isEmpty }
    var queuedCount: Int { queue.count }

    private func pump() {
        while inFlight.count < maxConcurrent, let p = queue.last {
            let barcode = p.barcode
            inFlight.insert(barcode)
            queue.removeLast()
            Task {
                guard await CatalogBudget.shared.take() else {
                    // Hors budget: on remet en file et on reessaie dans 5 s.
                    inFlight.remove(barcode); queue.insert(p, at: 0); scheduleRetry(); return
                }
                let (r, status) = await ProductCatalog.complete(p)
                inFlight.remove(barcode)
                lastStatus[barcode] = status
                switch r {
                case .found(let f): full[barcode] = f; ProductCache.put(f)
                case .notFound: failed.insert(barcode)
                case .unavailable:
                    // Refus de debit ou coupure/delai reseau: on reessaie plus tard.
                    // Seule une vraie reponse d'erreur marque la ligne en echec.
                    if status == 429 { await CatalogBudget.shared.blocked() }
                    if status == 429 || status == 0 || status >= 500 { queue.insert(p, at: 0); scheduleRetry() }
                    else { failed.insert(barcode) }
                }
                pump()
            }
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task {
            try? await Task.sleep(for: .seconds(5))
            retryTask = nil
            pump()
        }
    }
}
