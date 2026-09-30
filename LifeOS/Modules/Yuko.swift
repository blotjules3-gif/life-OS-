import SwiftUI
import PhotosUI
import VisionKit

// MARK: - Yuko : scanner un produit, voir sa vraie photo et une note /100 expliquee
//
// Donnees: Open Food Facts (aliments, boissons, complements) et Open Beauty Facts
// (cosmetiques), via `ProductCatalog`. Note: `ProductScore` (methode LifeOS
// versionnee, pas le score Yuka). Historique, favoris et fiches locales:
// `ProductStore`. Aucun prix affiche: aucune source verifiee de prix n'est branchee.

struct YukoView: View {
    @StateObject private var store = ProductStore.shared
    @StateObject private var enricher = ProductEnricher.shared
    @State private var query = ""
    @State private var kind: ProductCatalog.Kind = .all
    @State private var results: [CatalogProduct] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var searching = false
    @State private var searchError: String?
    /// Jeton de la derniere recherche: une reponse d'une ancienne saisie est jetee.
    @State private var searchToken = UUID()

    @State private var code = ""
    @State private var lookingUp = false
    @State private var lookupError: String?
    @State private var unknownCode: String?
    @State private var opened: CatalogProduct?
    @State private var showScanner = false
    @State private var showGoals = false
    @State private var showAllScans = false
    /// Ce que la derniere recherche par code a essaye (affiche si le produit manque).
    @State private var lastTrace = ""
    @State private var showInfo = false
    @State private var storeError: String?

    private var scannerAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #endif
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    controls
                    if let lookupError { errorCard(lookupError) }
                    if let storeError { errorCard(storeError) }
                    ForEach(store.loadProblems, id: \.self) { errorCard($0) }
                    if query.trimmingCharacters(in: .whitespaces).count >= 2 { resultsSection } else { librarySections }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Yuko").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showGoals = true } label: { Image(systemName: "target") }
                    .accessibilityLabel("Mes objectifs")
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Méthode et couverture")
            }
        }
        .navigationDestination(item: $opened) { YukoDetailView(product: $0) }
        .sheet(isPresented: $showInfo) { YukoMethodSheet() }
        .sheet(isPresented: $showGoals) { NavigationStack { YukoGoalsEditor() } }
        .sheet(item: Binding(get: { unknownCode.map(CodeBox.init) }, set: { unknownCode = $0?.code })) { box in
            NavigationStack { UnknownProductView(barcode: box.code, trace: lastTrace) { saved in unknownCode = nil; open(saved) } }
        }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showScanner) {
            ZStack(alignment: .topTrailing) {
                BarcodeScanner { scanned in showScanner = false; lookup(scanned, via: .camera) }.ignoresSafeArea()
                Button("Fermer") { showScanner = false }
                    .buttonStyle(LifeOSGlassButtonStyle()).padding()
            }
        }
        #endif
        .onChange(of: query) { _, q in startSearch(q) }
        .onChange(of: kind) { _, _ in startSearch(query, immediate: true) }
        #if DEBUG
        // Le simulateur ne sait pas coller dans ce champ: `-yukoCode <code>` et
        // `-yukoQuery <texte>` lancent la meme action que l'utilisateur.
        .onAppear {
            if let c = DebugLaunchFlags.value("-yukoCode"), code.isEmpty { code = c; lookup(c, via: .typedCode) }
            if let q = DebugLaunchFlags.value("-yukoQuery"), query.isEmpty { query = q }
            if let list = DebugLaunchFlags.value("-yukoCheck") { Task { await runCheck(list) } }
        }
        #endif
    }

    #if DEBUG
    /// `-yukoCheck "nutella,yaourt,..."`: tape chaque recherche dans l'ecran reel,
    /// attend que chaque ligne visible ait fini de charger (max 60 s), puis ecrit
    /// dans Documents/yuko-check.txt combien de lignes ont une note. C'est la
    /// verification "ce que l'utilisateur voit", pas un test de fonction isolee.
    private func runCheck(_ list: String) async {
        var report: [String] = []
        for q in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            query = q
            let start = Date()
            try? await Task.sleep(for: .seconds(1))
            while (searching || results.isEmpty) && Date().timeIntervalSince(start) < 30 { try? await Task.sleep(for: .milliseconds(300)) }
            // Les lignes se completent a l'affichage; ici on demande les 12 premieres
            // comme si elles etaient a l'ecran.
            for p in results.prefix(12) { enricher.request(p) }
            while !enricher.idle && Date().timeIntervalSince(start) < 60 { try? await Task.sleep(for: .milliseconds(300)) }
            let top = results.prefix(12).map { enricher.resolved($0) }
            let scored = top.filter { ProductScore.evaluate($0).value != nil }.count
            let pending = top.filter { $0.isSummary == true }.count
            let reasons = top.filter { $0.isSummary != true && ProductScore.evaluate($0).value == nil }
                .map { "\($0.name.prefix(24)) [\(ProductScore.evaluate($0).missing.joined(separator: "/"))]" }
            let left = results.prefix(12).filter { enricher.resolved($0).isSummary == true }
            let why = left.map { "\($0.barcode):\(enricher.lastStatus[$0.barcode].map(String.init) ?? "pas parti")\(enricher.failed.contains($0.barcode) ? "/échec" : "")" }
            report.append("\(q): \(results.count) résultats, 12 premiers -> \(scored) notés, \(pending) restés abrégés \(why), \(top.count - scored - pending) non notés \(reasons) en \(Int(Date().timeIntervalSince(start))) s, file \(enricher.queuedCount)")
        }
        let url = AppPaths.documents.appendingPathComponent("yuko-check.txt")
        try? report.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    #endif

    private struct CodeBox: Identifiable { let code: String; var id: String { code } }

    // MARK: Recherche, code, scanner : toujours tous les trois

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Type", selection: $kind) {
                ForEach(ProductCatalog.Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Nom du produit (ex : yaourt nature)", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
            }
            .padding(12).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), .nested)

            HStack(spacing: 8) {
                TextField("Code-barres", text: $code)
                    .keyboardType(.numberPad)
                    .padding(12).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), .nested)
                Button { lookup(code, via: .typedCode) } label: {
                    if lookingUp { ProgressView() } else { Text("Chercher") }
                }
                .buttonStyle(LifeOSGlassButtonStyle()).disabled(code.filter(\.isNumber).count < 6 || lookingUp)
            }
            if scannerAvailable {
                Button { showScanner = true } label: {
                    Label("Scanner un code-barres", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.nutriTint)
            } else {
                Text("Pas de caméra de scan ici : cherche par nom ou tape le code-barres.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let searchError {
                errorCard(searchError)
                Button("Réessayer") { startSearch(query, immediate: true) }.buttonStyle(LifeOSGlassButtonStyle())
            } else if searching && results.isEmpty {
                HStack { Spacer(); ProgressView("Recherche…"); Spacer() }.padding(.vertical, 20)
            } else if results.isEmpty {
                Text("Aucun produit trouvé pour « \(query) » dans \(kind == .food ? "Open Food Facts" : kind == .beauty ? "Open Beauty Facts" : "Open Food Facts et Open Beauty Facts"). Scanne le code-barres : c'est plus sûr qu'un nom.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(results) { p in
                let shown = enricher.resolved(p)
                Button { openFull(shown) } label: { ProductRow(product: shown, loading: enricher.isLoading(p)) }.buttonStyle(.plain)
                    .disabled(lookingUp)
                    .onAppear { enricher.request(p) }
            }
            if hasMore && searchError == nil {
                Button { loadMore() } label: {
                    if searching { ProgressView() } else { Text("Plus de résultats").frame(maxWidth: .infinity) }
                }
                .buttonStyle(LifeOSGlassButtonStyle()).disabled(searching)
            }
        }
    }

    @ViewBuilder private var librarySections: some View {
        if !store.scans.isEmpty { scansSection }
        if !store.favorites.isEmpty { section("Favoris", store.favorites) }
        if !store.localProducts.isEmpty { section("Mes fiches (non vérifiées)", store.localProducts) }
        if store.history.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aucun produit consulté").font(.headline)
                Text("Scanne un code-barres, tape-le, ou cherche un produit par son nom. Tu retrouveras ici ton historique, avec l'âge de chaque fiche.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        } else {
            section("Consultés récemment", store.history, deletable: true)
        }
    }

    /// Scans reels, dates, separes des consultations (un produit ouvert depuis une
    /// recherche n'y entre pas).
    private var scansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Derniers scans").font(.headline)
                Spacer()
                Text("\(store.scans.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            ForEach(store.scans.prefix(showAllScans ? ProductStore.scanLimit : 5)) { r in
                Button { openFull(r.product) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        ProductRow(product: r.product)
                        Text("\(r.via == .camera ? "Scanné" : "Code tapé") le \(r.scannedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary).padding(.leading, 8)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        do { try store.removeScan(r) } catch { storeError = error.localizedDescription }
                    } label: { Label("Retirer ce scan", systemImage: "trash") }
                }
            }
            if store.scans.count > 5 {
                Button(showAllScans ? "Afficher moins" : "Tous les scans (\(store.scans.count))") { withAnimation { showAllScans.toggle() } }
                    .font(.subheadline)
            }
        }
    }

    private func section(_ title: String, _ items: [CatalogProduct], deletable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.leading, 4)
            ForEach(items) { p in
                Button { openFull(p) } label: { ProductRow(product: p) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if deletable { Button(role: .destructive) {
                            do { try store.removeFromHistory(p) } catch { storeError = error.localizedDescription }
                        } label: { Label("Retirer de l'historique", systemImage: "trash") } }
                    }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "wifi.exclamationmark")
            .font(.subheadline).foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(Theme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Actions

    /// La fiche s'ouvre meme si l'historique n'a pas pu etre ecrit, et l'ecran le dit.
    private func open(_ p: CatalogProduct) {
        do { try store.record(p) } catch { storeError = "Historique non enregistré : \(error.localizedDescription)" }
        opened = p
    }

    /// Un resultat de recherche est une fiche abregee: on charge la complete
    /// (ingredients, additifs) avant de l'ouvrir. En panne, on ouvre l'abregee,
    /// qui s'affiche "non evaluee" avec ce qui manque, jamais une note inventee.
    private func openFull(_ p: CatalogProduct) {
        guard p.isSummary == true else { open(p); return }
        lookingUp = true
        Task {
            let r = await ProductCatalog.product(barcode: p.barcode)
            lookingUp = false
            if case .found(let full) = r { open(full) } else { open(p) }
        }
    }

    private func lookup(_ raw: String, via: ScanRecord.Via) {
        let digits = raw.filter(\.isNumber)
        guard !lookingUp, digits.count >= 6 else { return }
        lookupError = nil
        // Une fiche creee sur l'appareil passe avant la base.
        if let local = store.local(barcode: digits) { recordScan(local, via: via); open(local); return }
        lookingUp = true
        Task {
            let (r, trace) = await ProductCatalog.lookup(barcode: raw)
            lookingUp = false
            lastTrace = trace.summary
            switch r {
            case .found(let p): Haptics.medium(); recordScan(p, via: via); open(p)
            case .notFound: Haptics.tap(); unknownCode = trace.normalized?.canonical ?? digits
            case .unavailable(let m): Haptics.warning(); lookupError = m + "\n" + trace.summary
            }
        }
    }

    /// Un scan (camera ou code) entre dans "Derniers scans"; une recherche par nom non.
    private func recordScan(_ p: CatalogProduct, via: ScanRecord.Via) {
        do { try store.recordScan(p, via: via) } catch { storeError = "Scan non enregistré : \(error.localizedDescription)" }
    }

    private func startSearch(_ q: String, immediate: Bool = false) {
        let token = UUID()
        searchToken = token
        results = []; page = 1; hasMore = false; searchError = nil
        enricher.dropQueued()
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { searching = false; return }
        searching = true
        Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(400)) }
            guard token == searchToken else { return }
            let r = await ProductCatalog.search(q, page: 1, kind: kind)
            guard token == searchToken else { return }   // saisie changee entre temps
            apply(r, append: false)
        }
    }

    private func loadMore() {
        let token = searchToken, next = page + 1, q = query, k = kind
        searching = true
        Task {
            let r = await ProductCatalog.search(q, page: next, kind: k)
            guard token == searchToken else { return }
            page = next
            apply(r, append: true)
        }
    }

    private func apply(_ r: ProductCatalog.Search, append: Bool) {
        searching = false
        switch r {
        case .results(let items, let more):
            let fresh = items.filter { i in !results.contains { $0.id == i.id } }
            results = append ? results + fresh : items
            hasMore = more
        case .unavailable(let m):
            searchError = m
        }
    }
}

// MARK: - Ligne produit

struct ProductRow: View {
    let product: CatalogProduct
    /// Fiche en cours de completement: la note arrive, on le montre.
    var loading = false
    /// Une liste d'ingredients ajoutee par photo note aussi la ligne.
    @ObservedObject private var store = ProductStore.shared
    var body: some View {
        let score = ProductScore.evaluate(store.enriched(product))
        HStack(spacing: 12) {
            ProductImage(url: product.imageURL ?? product.imageSmallURL, side: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Text([product.brand, product.quantity].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if product.source == .local { Text("Fiche locale, non vérifiée").font(.caption2).foregroundStyle(Theme.warning) }
            }
            Spacer(minLength: 6)
            if product.isSummary == true && loading {
                ProgressView().frame(width: 52).accessibilityLabel("Note en cours de calcul")
            } else if product.isSummary == true {
                ScoreChip(result: score, summary: true)
            } else {
                ScoreChip(result: score)
            }
        }
        .padding(10)
        .raisedSurface(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct ScoreChip: View {
    let result: ProductScore.Result
    var summary = false
    var body: some View {
        VStack(spacing: 1) {
            Text(result.value.map(String.init) ?? "—").font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundStyle(result.value.map(scoreColor) ?? .secondary)
            Text(result.value == nil ? (summary ? "ouvrir" : "non noté") : "/100").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(width: 52)
    }
}

/// Nombre a la francaise: "6,3", "58".
func frNumber(_ v: Double) -> String {
    // Sous 1 : jusqu'a deux decimales (taurine 0,15 %, sel 0,25 g), sinon "0,2".
    if abs(v) < 1 { return v.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "fr_FR"))) }
    return v.formatted(.number.precision(.fractionLength(v < 10 && v != v.rounded() ? 1 : 0)).locale(Locale(identifier: "fr_FR")))
}

func scoreColor(_ v: Int) -> Color {
    switch v {
    case 75...: return Color(hex: 0x1E8F4E)
    case 50...: return Color(hex: 0x5FAE3E)
    case 25...: return Color(hex: 0xE8821E)
    default: return Color(hex: 0xE03A2F)
    }
}

// MARK: - Photo produit (cache, chargement, erreur, absente)

enum ProductImageLoader {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 150 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: c)
    }()
    nonisolated(unsafe) static let memory = NSCache<NSURL, UIImage>()

    /// Photo prete a afficher: produit detoure sur fond blanc (traitee une fois,
    /// gardee sur l'appareil). Detourage impossible: la photo d'origine.
    static func load(_ url: URL) async throws -> UIImage {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let done = ProductPhoto.cached(url) { memory.setObject(done, forKey: url as NSURL); return done }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400, let img = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        let white = await Task.detached(priority: .utility) { ProductPhoto.onWhite(img) }.value
        let shown = white ?? img
        if let white { ProductPhoto.store(white, for: url) }
        memory.setObject(shown, forKey: url as NSURL)
        return shown
    }
}

struct ProductImage: View {
    let url: URL?
    var side: CGFloat? = nil
    var maxHeight: CGFloat = 260
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()   // proportions gardees
            } else if url == nil {
                placeholder("photo.badge.exclamationmark", "Pas de photo dans la base")
            } else if failed {
                placeholder("exclamationmark.triangle", "Photo indisponible")
            } else {
                ProgressView()
            }
        }
        .frame(width: side, height: side)
        .frame(maxWidth: side == nil ? .infinity : nil, maxHeight: side == nil ? maxHeight : nil)
        .padding(side == nil ? 12 : 4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: url) {
            guard let url else { return }
            image = nil; failed = false
            do { image = try await ProductImageLoader.load(url) } catch { failed = true }
        }
        .accessibilityLabel(url == nil ? "Aucune photo" : "Photo du produit")
    }

    private func placeholder(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(side == nil ? .title : .body)
            if side == nil { Text(text).font(.caption) }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: side ?? 140)
    }
}

// MARK: - Fiche produit

struct YukoDetailView: View {
    let original: CatalogProduct
    @Environment(\.modelContext) private var ctx
    @StateObject private var store = ProductStore.shared
    /// La fiche affichee: la base, completee par ce que l'utilisateur a ajoute.
    private var product: CatalogProduct { store.enriched(refreshed ?? original) }
    @State private var completing = false
    /// Lecture de la photo d'etiquette de la base (aliments animaux sans composition).
    @State private var labelState: LabelState = .idle
    @State private var editingLabel = false
    /// Fiche relue sur la base quand celle du cache n'a pas les liens des photos.
    @State private var refreshed: CatalogProduct?
    enum LabelState: Equatable { case idle, reading, failed(String) }

    init(product: CatalogProduct) { original = product }
    @AppStorage(AppStorageKeys.dietFlags) private var dietFlagsRaw = ""
    @State private var alternatives: ProductCatalog.Alternatives?
    @State private var comparing = false
    @State private var grams: Double = 100
    @State private var meal = "Déjeuner"
    @State private var added = false
    @State private var addError: String?
    @State private var favoriteError: String?
    @State private var showGoals = false
    @State private var goals = ProductGoals.load()

    private var score: ProductScore.Result { ProductScore.evaluate(product) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let favoriteError {
                    Label(favoriteError, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warning)
                }
                header
                scoreCard
                if product.isPetFood { petIdentityCard; petLabelCard }
                if !product.isPetFood && product.source != .product { personalCard }
                if product.isPetFood { petAnalysisCard }
                else if !product.isCosmetic && product.source != .product { nutritionCard }
                ingredientsCard
                if original.ingredientsText == nil && original.source != .local && !original.isPetFood { completeCard }
                if !score.flags.isEmpty { flagsCard }
                if product.source != .local { alternativesCard }
                // Jamais la gamelle du chat dans TON journal alimentaire.
                if !product.isCosmetic, !product.isPetFood, product.source != .product,
                   product.nutriments.energyKcal != nil, !product.isSupplement { journalCard }
                provenance
            }
            .padding(Theme.pad)
        }
        // La barre d'onglets flotte par-dessus : sans cette reserve, les derniers
        // boutons (Chat / Chien) passaient dessous (capture du 1er oct.).
        .floatingBarClearance()
        .background(Theme.background)
        .navigationTitle("Produit").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { comparing = true } label: { Image(systemName: "rectangle.split.2x1") }
                    .accessibilityLabel("Comparer")
                    .disabled(candidates.isEmpty)
                Button {
                    do { try store.toggleFavorite(product); favoriteError = nil }
                    catch { favoriteError = error.localizedDescription }
                } label: {
                    Image(systemName: store.isFavorite(product) ? "heart.fill" : "heart")
                }
                .accessibilityLabel(store.isFavorite(product) ? "Retirer des favoris" : "Ajouter aux favoris")
            }
        }
        .sheet(isPresented: $comparing) { ComparePicker(current: product, candidates: candidates) }
        .sheet(isPresented: $completing) { NavigationStack { IngredientPhotoSheet(product: original) } }
        .sheet(isPresented: $showGoals, onDismiss: { goals = ProductGoals.load() }) { NavigationStack { YukoGoalsEditor() } }
        .sheet(isPresented: $editingLabel) { NavigationStack { PetLabelEditor(product: refreshed ?? original, code: original.barcode) } }
        .task {
            await readLabelIfNeeded()
            #if DEBUG
            // `-yukoEditLabel` : ouvre l'editeur d'etiquette (captures, le simulateur ne tape pas bien).
            if DebugLaunchFlags.has("-yukoEditLabel"), original.isPetFood { editingLabel = true }
            #endif
        }
        // Relance quand la note change (etiquette lue, espece choisie) : sinon la carte
        // restait sur "pas de note" calcule avant la lecture.
        .task(id: score.value) { if product.source != .local { alternatives = await ProductCatalog.alternatives(to: product) } }
    }

    private var candidates: [CatalogProduct] {
        (store.favorites + store.history).reduce(into: [CatalogProduct]()) { acc, p in
            if p.id != product.id && !acc.contains(where: { $0.id == p.id }) { acc.append(p) }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ProductImage(url: product.imageURL)
            if product.imageURL != nil, let producer = product.imageFromProducer {
                Text(producer ? "Photo officielle de la marque" : "Photo d'un contributeur, détourée sur fond blanc")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(product.name).font(.title2.bold()).multilineTextAlignment(.center)
            let sub = [product.brand, product.quantity].compactMap { $0 }.joined(separator: " · ")
            if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(.secondary) }
            if !product.countries.isEmpty {
                Text("Vendu : " + product.countries.prefix(4).map { CatalogProduct.french($0).capitalized }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreCard: some View {
        let r = score
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if let v = r.value {
                    Text("\(v)").font(.system(size: 52, weight: .bold).monospacedDigit()).foregroundStyle(scoreColor(v))
                    Text("/100").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Text(r.label ?? "").font(.headline).foregroundStyle(scoreColor(v))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notScoredTitle(r)).font(.title3.bold())
                        Text(outcomeText(r)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Méthode « \(r.method) » · \(ProductScore.version)").font(.caption2).foregroundStyle(.secondary)
            if let c = r.confidence {
                Label("Confiance \(c.level.rawValue) : \(c.reason)", systemImage: c.level == .high ? "checkmark.seal" : c.level == .medium ? "seal" : "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(c.level == .low ? Theme.warning : .secondary)
            }
            ForEach(r.components) { c in componentRow(c) }
            if !r.missing.isEmpty {
                Label("Manque dans la base : " + r.missing.joined(separator: ", "), systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(Theme.warning)
            }
            HStack(spacing: 10) {
                if let g = product.nutriscoreGrade {
                    officialBadge("Nutri-Score officiel", g.uppercased(), nutriColor(g))
                }
                if let nova = product.novaGroup {
                    officialBadge("Transformation NOVA", "\(nova)", nova <= 1 ? Theme.success : nova == 4 ? Theme.danger : Theme.warning)
                }
            }
        }
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func notScoredTitle(_ r: ProductScore.Result) -> String {
        if case .notApplicable = r.outcome { return "Pas de note sur 100" }
        return "Non évalué"
    }
    private func outcomeText(_ r: ProductScore.Result) -> String {
        switch r.outcome {
        case .notEvaluated(let m), .notApplicable(let m): return m
        case .scored: return ""
        }
    }

    private func componentRow(_ c: ProductScore.Component) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c.name).font(.subheadline.weight(.semibold))
                Spacer()
                if c.max > 0 {
                    Text(c.points.map { "\(Int($0)) / \(Int(c.max))" } ?? "non évalué")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(c.points == nil ? Theme.warning : .primary)
                }
            }
            if let pts = c.points, c.max > 0 {
                ProgressView(value: pts, total: c.max).tint(.nutriTint)
            }
            ForEach(c.details, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func officialBadge(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(value).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                .frame(minWidth: 24).padding(.vertical, 3).padding(.horizontal, 6)
                .background(color, in: Capsule())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Aliments animaux

    /// Espece, stade de vie, type : detectes sur plusieurs indices, et toujours
    /// modifiables. Le choix est retenu pour le produit (GTIN canonique) et la note se
    /// recalcule tout de suite.
    private var petIdentityCard: some View {
        let id = ProductScore.petIdentity(product)
        let profile = store.petProfile(for: original.barcode)
        return VStack(alignment: .leading, spacing: 10) {
            Text("C'est pour qui ?").font(.headline)
            Text(id.species == nil
                 ? (id.ambiguous ? "La fiche parle de chat et de chien. Choisis l'espèce : les besoins ne sont pas les mêmes."
                                 : "La fiche ne dit pas l'espèce. Choisis-la pour obtenir la note.")
                 : "Reconnu : " + (ProductScore.identityComponent(id).details.first ?? ""))
                .font(.callout).foregroundStyle(.secondary)
            Picker("Espèce", selection: Binding(get: { id.species }, set: { v in try? store.setPetSpecies(v, for: original.barcode) })) {
                Text("Chat").tag(Optional(PetLabel.Species.cat))
                Text("Chien").tag(Optional(PetLabel.Species.dog))
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Espèce")
            Picker("Âge", selection: Binding(get: { id.lifeStage }, set: { v in try? store.setPetLifeStage(v, for: original.barcode) })) {
                Text(id.species == .dog ? "Chiot" : "Chaton").tag(Optional(PetLabel.LifeStage.young))
                Text("Adulte").tag(Optional(PetLabel.LifeStage.adult))
                Text("Senior").tag(Optional(PetLabel.LifeStage.senior))
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Âge de l'animal")
            if !id.evidence.isEmpty {
                Text("Indices : " + id.evidence.prefix(4).joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
            }
            if profile?.species != nil || profile?.lifeStage != nil {
                Button("Revenir à la détection automatique") {
                    try? store.setPetSpecies(nil, for: original.barcode)
                    try? store.setPetLifeStage(nil, for: original.barcode)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    /// Composition et constituants lus sur la photo de l'etiquette (base ou toi),
    /// avec leur provenance, et les etats de lecture.
    @ViewBuilder private var petLabelCard: some View {
        let label = store.petProfile(for: original.barcode)?.label
        let needsData = (refreshed ?? original).ingredientsText == nil || (refreshed ?? original).petAnalysis == nil
        if label != nil || needsData {
            VStack(alignment: .leading, spacing: 10) {
                Text("Étiquette").font(.headline)
                switch labelState {
                case .reading:
                    HStack(spacing: 8) { ProgressView(); Text("Recherche de la composition sur la photo de l'étiquette…").font(.callout) }
                case .failed(let why):
                    Label(why, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Theme.warning)
                    Button("Réessayer") { labelState = .idle; Task { await readLabelIfNeeded(force: true) } }
                        .buttonStyle(LifeOSGlassButtonStyle())
                case .idle:
                    if let label {
                        Text("Source : \(label.fromUserPhoto ? "ta photo" : label.source). Lue le \(label.readAt.formatted(date: .abbreviated, time: .omitted)). "
                             + (label.validated ? "Relue par toi." : "Lecture automatique : vérifie-la."))
                            .font(.callout).foregroundStyle(.secondary)
                        if let d = label.declaration { Text(d).font(.caption).italic() }
                    } else if (refreshed ?? original).labelPhotos?.isEmpty ?? true {
                        Text("La base n'a ni la composition ni une photo de l'étiquette. Photographie-la au dos du paquet : LifeOS la lit, tu vérifies.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button { editingLabel = true } label: {
                        Label(label == nil ? "Photographier l'étiquette" : "Relire et corriger", systemImage: "text.viewfinder")
                    }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: label == nil))
                    if label != nil {
                        Button(role: .destructive) { try? store.removeLabel(for: original.barcode) } label: { Text("Retirer") }
                    }
                }
                ForEach(product.petFacts?.provenance ?? [], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    /// Fiche animale sans composition ou sans valeurs : on lit les photos d'etiquette
    /// CHOISIES par la base, sur l'appareil. Rien n'est envoye nulle part.
    private func readLabelIfNeeded(force: Bool = false) async {
        guard original.isPetFood, original.source != .local, labelState != .reading else { return }
        guard force || store.petProfile(for: original.barcode)?.label == nil else { return }
        var base = refreshed ?? original
        guard base.ingredientsText == nil || base.petAnalysis == nil else { return }
        if base.labelPhotos == nil {
            // Fiche du cache d'avant : relue pour avoir les liens des photos.
            if case .found(let fresh) = await ProductCatalog.complete(base).0 { refreshed = fresh; base = fresh }
        }
        guard !(base.labelPhotos ?? []).isEmpty, base.ingredientsText == nil || base.petAnalysis == nil else { return }
        labelState = .reading
        switch await PetLabelReader.read(base, database: "Open Pet Food Facts") {
        case .success(let reading):
            do { try store.saveLabel(reading, for: original.barcode); labelState = .idle }
            catch { labelState = .failed(error.localizedDescription) }
        case .failure(let e):
            labelState = e == .noPhoto ? .idle : .failed(e.localizedDescription)
        }
    }

    // Preferences et objectifs: A PART de la note (brief: preference != qualite).
    private var personalCard: some View {
        let flags = Set(dietFlagsRaw.split(separator: "|").map(String.init))
        let fit = ProductFit.evaluate(product, goals: goals)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pour toi").font(.headline)
                Spacer()
                Button { showGoals = true } label: { Label("Mes objectifs", systemImage: "target").font(.subheadline) }
            }
            Text("Adéquation à tes objectifs et à ton profil. Séparée de la note : un produit peut être bien noté et mal convenir à ton objectif.")
                .font(.caption).foregroundStyle(.secondary)
            if fit.verdicts.isEmpty {
                Text(goals.isEmpty
                     ? "Aucun objectif choisi. Touche « Mes objectifs » pour en ajouter (moins de sucre, plus de protéines, sans parfum…)."
                     : "Aucun de tes objectifs ne s'applique à ce type de produit.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(fit.line).font(.subheadline.weight(.semibold))
                ForEach(fit.verdicts) { v in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: fitIcon(v.status)).foregroundStyle(fitColor(v.status))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.goal.title).font(.subheadline)
                            Text(v.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !flags.isEmpty {
                Divider()
                let issues = personalIssues(flags)
                Text("Allergènes & régimes").font(.subheadline.weight(.semibold))
                if issues.isEmpty {
                    Label(product.ingredientsText == nil && product.allergens.isEmpty
                          ? "Ingrédients inconnus : compatibilité non vérifiable."
                          : "Aucune correspondance avec tes restrictions dans les données disponibles. Ce n'est pas une garantie : vérifie l'étiquette.",
                          systemImage: product.ingredientsText == nil ? "questionmark.circle" : "checkmark.seal")
                        .font(.subheadline)
                } else {
                    ForEach(issues, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).font(.subheadline) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func fitIcon(_ s: ProductFit.Status) -> String {
        switch s { case .ok: "checkmark.circle.fill"; case .watch: "minus.circle.fill"; case .against: "xmark.circle.fill"; case .unknown: "questionmark.circle" }
    }
    private func fitColor(_ s: ProductFit.Status) -> Color {
        switch s { case .ok: Theme.success; case .watch: Theme.warning; case .against: Theme.danger; case .unknown: .secondary }
    }

    private func personalIssues(_ flags: Set<String>) -> [String] {
        var out = Set<String>()
        let map: [String: [String]] = ["en:gluten": ["Sans gluten"], "en:milk": ["Sans lactose", "Vegan"],
                                       "en:eggs": ["Vegan"], "en:nuts": ["Sans fruits à coque"],
                                       "en:fish": ["Vegan", "Végétarien"], "en:crustaceans": ["Vegan", "Végétarien"]]
        for a in product.allergens { for d in map[a] ?? [] where flags.contains(d) { out.insert("Contient \(CatalogProduct.french(a)) : incompatible avec « \(d) »") } }
        for t in product.traces { for d in map[t] ?? [] where flags.contains(d) { out.insert("Peut contenir des traces de \(CatalogProduct.french(t)) (« \(d) »)") } }
        if let text = product.ingredientsText { AllergenChecker.check(text, against: flags).forEach { out.insert($0) } }
        return out.sorted()
    }

    private var petAnalysisCard: some View {
        let a = product.petAnalysis
        return VStack(alignment: .leading, spacing: 8) {
            Text("Constituants analytiques (tel quel)").font(.headline)
            petRow("Protéines brutes", a?.protein); petRow("Matières grasses", a?.fat)
            petRow("Cellulose brute", a?.fibre); petRow("Cendres brutes", a?.ash); petRow("Humidité", a?.moisture)
            if let t = a?.taurine { petRow("Taurine (déclarée)", t) }
            if let c = a?.calcium { petRow("Calcium (déclaré)", c) }
            if let ph = a?.phosphorus { petRow("Phosphore (déclaré)", ph) }
            Text("Valeurs pour 100 g tel quel, comme sur le paquet. « — » : non déclarée ou non trouvée. Une humidité absente n'est jamais remplacée par une valeur inventée.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func petRow(_ name: String, _ v: Double?) -> some View {
        HStack { Text(name); Spacer(); Text(v.map { "\(frNumber($0)) %" } ?? "—").monospacedDigit().foregroundStyle(v == nil ? .secondary : .primary) }
            .font(.subheadline)
    }

    private var nutritionCard: some View {
        let n = product.nutriments
        let unit = product.isBeverage ? "100 ml" : "100 g"
        return VStack(alignment: .leading, spacing: 8) {
            Text("Valeurs pour \(unit)").font(.headline)
            if let s = product.servingSize { Text("Portion indiquée : \(s)").font(.caption).foregroundStyle(.secondary) }
            nutrientRow("Énergie", n.energyKcal, "kcal")
            nutrientRow("Protéines", n.proteins, "g")
            nutrientRow("Glucides", n.carbohydrates, "g")
            nutrientRow("dont sucres", n.sugars, "g")
            nutrientRow("Lipides", n.fat, "g")
            nutrientRow("dont saturés", n.saturatedFat, "g")
            nutrientRow("Fibres", n.fiber, "g")
            nutrientRow("Sel", n.salt, "g")
            Text("« — » : la base ne donne pas cette valeur. Ce n'est pas zéro.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func nutrientRow(_ name: String, _ v: Double?, _ unit: String) -> some View {
        HStack {
            Text(name).font(.subheadline)
            Spacer()
            Text(v.map { "\(frNumber($0)) \(unit)" } ?? "—")
                .font(.subheadline.monospacedDigit()).foregroundStyle(v == nil ? .secondary : .primary)
        }
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.isPetFood ? "Composition" : "Ingrédients").font(.headline)
            Text(product.ingredientsText ?? "Non renseignés dans la base.")
                .font(.subheadline).foregroundStyle(product.ingredientsText == nil ? .secondary : .primary)
                .textSelection(.enabled)
            if product.isPetFood, let add = product.petFacts?.additivesText {
                Text("Additifs").font(.subheadline.weight(.semibold))
                Text(add).font(.caption).textSelection(.enabled)
            }
            if !product.allergens.isEmpty {
                Text("Allergènes : " + product.allergens.map(CatalogProduct.french).joined(separator: ", "))
                    .font(.subheadline.weight(.semibold))
            }
            if !product.traces.isEmpty {
                Text("Traces possibles : " + product.traces.map(CatalogProduct.french).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var flagsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(product.isCosmetic ? "Ingrédients à surveiller" : "Additifs à surveiller").font(.headline)
            ForEach(score.flags) { f in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(f.code == f.name.lowercased() ? f.name : "\(f.code) \(f.name)")").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(f.level.rawValue).font(.caption.weight(.semibold))
                            .foregroundStyle(f.level == .high ? Theme.danger : f.level == .moderate ? Theme.warning : .secondary)
                    }
                    Text(f.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Classement LifeOS d'après des avis publics (EFSA, CIRC, règlements UE). « À surveiller » ne veut pas dire dangereux à toute dose.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var alternativesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alternatives mieux notées").font(.headline)
            if let alternatives {
                switch alternatives {
                case .none(let why):
                    Text(why).font(.callout).foregroundStyle(.secondary)
                case .unavailable(let why):
                    VStack(alignment: .leading, spacing: 6) {
                        Label(why, systemImage: "wifi.exclamationmark").font(.callout).foregroundStyle(Theme.warning)
                        Button("Réessayer") {
                            self.alternatives = nil
                            Task { self.alternatives = await ProductCatalog.alternatives(to: product) }
                        }.font(.subheadline)
                    }
                case .found(let list):
                ForEach(list) { alt in
                    NavigationLink { YukoDetailView(product: alt) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            ProductRow(product: alt)
                            let why = ProductFit.reasons(alternative: alt, versus: product)
                            if !why.isEmpty {
                                Text("Pourquoi : " + why.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).padding(.leading, 8)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                }
            } else {
                HStack { ProgressView(); Text("Recherche dans la même catégorie…").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var journalCard: some View {
        let kcal = product.nutriments.energyKcal ?? 0
        let f = grams / 100
        return VStack(alignment: .leading, spacing: 10) {
            Text("Ajouter au journal").font(.headline)
            HStack { Text("\(Int(grams)) g"); Slider(value: $grams, in: 10...500, step: 5) }
            Text("\(Int((kcal * f).rounded())) kcal").font(.subheadline.monospacedDigit())
            Picker("Repas", selection: $meal) { ForEach(["Petit-déj", "Déjeuner", "Dîner", "Collation"], id: \.self) { Text($0) } }
                .pickerStyle(.segmented)
            if let addError { Label(addError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).font(.caption) }
            Button {
                guard !added else { return }
                do {
                    let n = product.nutriments
                    try FoodLogService.log([.init(name: product.name, calories: Int((kcal * f).rounded()),
                                                  protein: (n.proteins ?? 0) * f, carbs: (n.carbohydrates ?? 0) * f,
                                                  fat: (n.fat ?? 0) * f, meal: meal)], in: ctx)
                    addError = nil; Haptics.medium(); withAnimation { added = true }
                } catch { Haptics.warning(); addError = error.localizedDescription }
            } label: {
                Label(added ? "Ajouté" : "Ajouter", systemImage: added ? "checkmark.circle.fill" : "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.nutriTint).disabled(added)
        }
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    /// La base n'a pas la liste d'ingredients (un tiers des cosmetiques trouves au
    /// banc d'essai du 29 sept): on propose de la photographier plutot que de
    /// laisser la fiche sans note.
    private var completeCard: some View {
        let added = store.enrichments.first { $0.barcode == original.barcode }
        return VStack(alignment: .leading, spacing: 8) {
            Text(added == nil ? "Liste d'ingrédients manquante" : "Liste d'ingrédients ajoutée par toi").font(.headline)
            Text(added == nil
                 ? "La base n'a pas la liste de ce produit, donc pas de note. Photographie la liste au dos : LifeOS la lit, tu vérifies, et la fiche est notée sur ton appareil."
                 : "Elle sert à la note sur cet appareil. Elle n'est envoyée à aucune base.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { completing = true } label: {
                    Label(added == nil ? "Photographier la liste" : "Refaire la photo", systemImage: "text.viewfinder")
                }.buttonStyle(LifeOSGlassButtonStyle(prominent: added == nil))
                if added != nil {
                    Button(role: .destructive) { try? store.removeEnrichment(barcode: original.barcode) } label: { Text("Retirer") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let note = product.localNote { Text(note).font(.caption).foregroundStyle(Theme.warning) }
            Text(sourceText).font(.caption2).foregroundStyle(.secondary)
            Text("Fiche lue le \(product.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
                 + (product.lastModified.map { " · mise à jour dans la base le \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                .font(.caption2).foregroundStyle(.secondary)
            Text("Prix : aucune source vérifiée branchée, donc aucun prix affiché.").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceText: String {
        switch product.source {
        case .food: return "Données et photo : Open Food Facts (licence ODbL), code \(product.barcode)."
        case .beauty: return "Données et photo : Open Beauty Facts (licence ODbL), code \(product.barcode)."
        case .pet: return "Données et photo : Open Pet Food Facts (licence ODbL), code \(product.barcode)."
        case .product: return "Données et photo : Open Products Facts (licence ODbL), code \(product.barcode)."
        case .local: return "Fiche créée sur cet appareil, code \(product.barcode)."
        }
    }
}

// MARK: - Comparaison

struct ComparePicker: View {
    let current: CatalogProduct
    let candidates: [CatalogProduct]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(candidates) { p in
                NavigationLink { CompareView(a: current, b: p) } label: { ProductRow(product: p) }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .navigationTitle("Comparer avec…").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct CompareView: View {
    let a: CatalogProduct
    let b: CatalogProduct
    var body: some View {
        let ra = ProductScore.evaluate(a), rb = ProductScore.evaluate(b)
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) { column(a, ra); column(b, rb) }
                if ra.method != rb.method {
                    Text("Méthodes différentes (\(ra.method) / \(rb.method)) : les notes ne se comparent pas directement.")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
                VStack(spacing: 6) {
                    row("Énergie (kcal)", a.nutriments.energyKcal, b.nutriments.energyKcal, lowerIsBetter: true)
                    row("Sucres (g)", a.nutriments.sugars, b.nutriments.sugars, lowerIsBetter: true)
                    row("Graisses saturées (g)", a.nutriments.saturatedFat, b.nutriments.saturatedFat, lowerIsBetter: true)
                    row("Sel (g)", a.nutriments.salt, b.nutriments.salt, lowerIsBetter: true)
                    row("Fibres (g)", a.nutriments.fiber, b.nutriments.fiber, lowerIsBetter: false)
                    row("Protéines (g)", a.nutriments.proteins, b.nutriments.proteins, lowerIsBetter: false)
                    row("Additifs à surveiller", Double(ra.flags.count), Double(rb.flags.count), lowerIsBetter: true)
                }
                .padding(14).raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            .padding(Theme.pad)
        }
        .background(Theme.background)
        .navigationTitle("Comparaison").navigationBarTitleDisplayMode(.inline)
    }

    private func column(_ p: CatalogProduct, _ r: ProductScore.Result) -> some View {
        VStack(spacing: 6) {
            ProductImage(url: p.imageSmallURL, side: 90)
            Text(p.name).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3)
            ScoreChip(result: r)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ name: String, _ x: Double?, _ y: Double?, lowerIsBetter: Bool) -> some View {
        let better: Int? = {
            guard let x, let y, x != y else { return nil }
            return (x < y) == lowerIsBetter ? 0 : 1
        }()
        return HStack {
            cell(x, highlight: better == 0)
            Text(name).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            cell(y, highlight: better == 1)
        }
    }

    private func cell(_ v: Double?, highlight: Bool) -> some View {
        Text(v.map(frNumber) ?? "—")
            .font(.subheadline.monospacedDigit().weight(highlight ? .bold : .regular))
            .foregroundStyle(highlight ? Theme.success : .primary)
            .frame(width: 64)
    }
}

// MARK: - Produit inconnu : photo d'etiquette, OCR, correction, provenance

struct UnknownProductView: View {
    let barcode: String
    var trace: String = ""
    var onSaved: (CatalogProduct) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Ce que la photo doit lire: la liste d'ingredients ou le tableau nutritionnel.
    enum Target: String, Identifiable { case ingredients, nutrition; var id: String { rawValue } }

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickerTarget: Target = .ingredients
    @State private var cameraTarget: Target?
    @State private var reading: Target?
    @State private var ocrText = ""
    @State private var nutritionRead = ""
    @State private var filledFromPhoto: Set<String> = []
    @State private var name = ""
    @State private var brand = ""
    @State private var isCosmetic = false
    @State private var kcal = ""; @State private var sugars = ""; @State private var sat = ""
    @State private var salt = ""; @State private var protein = ""; @State private var fiber = ""
    @State private var error: String?
    @State private var confirming: CatalogProduct?

    private var cameraAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    var body: some View {
        Form {
            Section {
                Text("Le code \(barcode) n'est ni dans Open Food Facts ni dans Open Beauty Facts. Tu peux créer une fiche sur cet appareil. Elle reste marquée « non vérifiée » et n'est envoyée nulle part.")
                    .font(.callout)
                if !trace.isEmpty {
                    Text("Recherche faite : " + trace).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Produit") {
                TextField("Nom (obligatoire)", text: $name)
                TextField("Marque", text: $brand)
                Toggle("C'est un cosmétique", isOn: $isCosmetic)
            }
            Section {
                photoButtons(.ingredients, label: "la liste d'ingrédients")
                if !ocrText.isEmpty {
                    Text("Texte lu (corrige-le si besoin) :").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $ocrText).frame(minHeight: 100)
                }
            } header: { Text("Ingrédients") }
            if !isCosmetic {
                Section {
                    photoButtons(.nutrition, label: "le tableau nutritionnel")
                    if !nutritionRead.isEmpty {
                        Text(nutritionRead).font(.caption).foregroundStyle(filledFromPhoto.isEmpty ? Theme.warning : .secondary)
                    }
                    field("Énergie (kcal)", $kcal, "kcal"); field("Sucres (g)", $sugars, "sugars"); field("Graisses saturées (g)", $sat, "sat")
                    field("Sel (g)", $salt, "salt"); field("Protéines (g)", $protein, "protein"); field("Fibres (g)", $fiber, "fiber")
                } header: { Text("Valeurs pour 100 g (vide = inconnu)") }
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) } }
        }
        .navigationTitle("Produit inconnu").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Vérifier") { review() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            let target = pickerTarget
            Task {
                defer { pickerItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
                    error = "Photo illisible."; return
                }
                await read(img, for: target)
            }
        }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(item: $cameraTarget) { target in
            CameraPicker { img in
                cameraTarget = nil
                if let img { Task { await read(img, for: target) } }
            }
            .ignoresSafeArea()
        }
        #endif
        .sheet(item: $confirming) { p in
            NavigationStack { UnknownProductConfirm(product: p, onConfirm: { commit(p) }) }
        }
    }

    @ViewBuilder private func photoButtons(_ target: Target, label: String) -> some View {
        if reading == target {
            HStack { ProgressView(); Text("Lecture du texte…").foregroundStyle(.secondary) }
        } else {
            if cameraAvailable {
                Button { cameraTarget = target } label: { Label("Photographier \(label)", systemImage: "camera") }
            }
            PhotosPicker(selection: Binding(get: { pickerItem }, set: { pickerTarget = target; pickerItem = $0 }), matching: .images) {
                Label("Choisir une photo de \(label)", systemImage: "photo.on.rectangle")
            }
        }
    }

    private func read(_ img: UIImage, for target: Target) async {
        reading = target
        defer { reading = nil }
        let text = await DocOCR.recognize(img)
        guard !text.isEmpty else { error = "Aucun texte lu sur cette photo. Essaie une photo plus nette, bien à plat."; return }
        error = nil
        switch target {
        case .ingredients: ocrText = text
        case .nutrition: applyNutrition(text)
        }
    }

    /// Ne remplace JAMAIS un champ deja tape a la main; dit ce qui a ete lu.
    private func applyNutrition(_ text: String) {
        let v = NutritionLabelParser.parse(text)
        var filled: [String] = []
        func put(_ value: Double?, _ binding: Binding<String>, _ key: String, _ label: String) {
            guard let value, binding.wrappedValue.isEmpty else { return }
            binding.wrappedValue = frNumber(value); filledFromPhoto.insert(key); filled.append(label)
        }
        put(v.kcal, $kcal, "kcal", "énergie"); put(v.sugars, $sugars, "sugars", "sucres")
        put(v.saturatedFat, $sat, "sat", "graisses saturées"); put(v.salt, $salt, "salt", "sel")
        put(v.proteins, $protein, "protein", "protéines"); put(v.fiber, $fiber, "fiber", "fibres")
        nutritionRead = filled.isEmpty
            ? "Aucune valeur reconnue sur la photo. Tape-les à la main."
            : "Lu sur la photo : \(filled.joined(separator: ", ")). Vérifie chaque valeur (colonne « pour 100 g »)."
    }

    private func field(_ title: String, _ text: Binding<String>, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                if filledFromPhoto.contains(key) { Image(systemName: "text.viewfinder").font(.caption).foregroundStyle(.secondary).accessibilityLabel("lu sur la photo") }
                Spacer()
                TextField("—", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
            if !text.wrappedValue.isEmpty, let m = AmountInput.parse(text.wrappedValue, rules: .optional).message {
                Text(m).font(.caption).foregroundStyle(Theme.warning)
            }
        }
    }

    /// Construit la fiche et ouvre l'ecran de confirmation; rien n'est ecrit avant.
    private func review() {
        let values = [kcal, sugars, sat, salt, protein, fiber].map { AmountInput.parse($0, rules: .optional) }
        if let bad = values.compactMap(\.message).first { error = bad; return }
        var p = CatalogProduct(barcode: barcode, source: .local, name: name.trimmingCharacters(in: .whitespaces))
        if isCosmetic { p.categories = [CatalogProduct.localCosmeticTag] }
        p.brand = brand.isEmpty ? nil : brand
        p.ingredientsText = ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ocrText
        if !isCosmetic {
            p.nutriments = .init(energyKcal: values[0].value, proteins: values[4].value, sugars: values[1].value,
                                 saturatedFat: values[2].value, fiber: values[5].value, salt: values[3].value)
        }
        var origin: [String] = []
        if p.ingredientsText != nil { origin.append("ingrédients lus sur une photo") }
        if !filledFromPhoto.isEmpty { origin.append("valeurs lues sur une photo puis vérifiées") }
        p.localNote = "Fiche créée par toi le \(Date().formatted(date: .abbreviated, time: .omitted))"
            + (origin.isEmpty ? "." : ", " + origin.joined(separator: ", ") + ".") + " Non vérifiée."
        error = nil
        confirming = p
    }

    /// Ecrit la fiche. Le formulaire ne se ferme qu'une fois l'ecriture reussie.
    private func commit(_ p: CatalogProduct) {
        do { try ProductStore.shared.saveLocal(p) } catch {
            confirming = nil
            self.error = error.localizedDescription; return
        }
        confirming = nil
        onSaved(p)
    }
}

/// Recapitulatif avant enregistrement: ce qui sera garde, la note que la fiche
/// obtiendra, et ce qui manque.
struct UnknownProductConfirm: View {
    let product: CatalogProduct
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = ProductScore.evaluate(product)
        Form {
            Section("Produit") {
                LabeledContent("Nom", value: product.name)
                if let b = product.brand { LabeledContent("Marque", value: b) }
                LabeledContent("Code-barres", value: product.barcode)
                LabeledContent("Type", value: product.isCosmetic ? "Cosmétique" : "Aliment")
            }
            if !product.isCosmetic {
                Section("Valeurs pour 100 g") {
                    row("Énergie", product.nutriments.energyKcal, "kcal"); row("Sucres", product.nutriments.sugars, "g")
                    row("Graisses saturées", product.nutriments.saturatedFat, "g"); row("Sel", product.nutriments.salt, "g")
                    row("Protéines", product.nutriments.proteins, "g"); row("Fibres", product.nutriments.fiber, "g")
                }
            }
            Section("Ingrédients") {
                Text(product.ingredientsText ?? "Non renseignés").font(.callout).foregroundStyle(product.ingredientsText == nil ? .secondary : .primary)
            }
            Section("Note obtenue") {
                if let v = r.value { Text("\(v)/100 · \(r.method)").font(.headline) }
                else { Text("Pas de note : " + (r.missing.isEmpty ? "données insuffisantes" : "manque " + r.missing.joined(separator: ", "))).foregroundStyle(.secondary) }
                Text("La fiche reste marquée « non vérifiée » et n'est envoyée à aucune base.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Vérifier la fiche").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Modifier") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { onConfirm() } }
        }
    }

    private func row(_ name: String, _ v: Double?, _ unit: String) -> some View {
        LabeledContent(name, value: v.map { "\(frNumber($0)) \(unit)" } ?? "inconnu")
    }
}

// MARK: - Completer une fiche de la base

struct IngredientPhotoSheet: View {
    let product: CatalogProduct
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var reading = false
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("Photographie la liste d'ingrédients de « \(product.name) », bien à plat et nette. Corrige ensuite le texte lu si besoin.")
                    .font(.callout)
                #if !targetEnvironment(macCatalyst)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label("Photographier", systemImage: "camera") }
                }
                #endif
                PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choisir une photo", systemImage: "photo.on.rectangle") }
                if reading { HStack { ProgressView(); Text("Lecture du texte…").foregroundStyle(.secondary) } }
            }
            if !text.isEmpty {
                Section("Texte lu (vérifie-le)") { TextEditor(text: $text).frame(minHeight: 140) }
                Section("Note obtenue") {
                    let preview: CatalogProduct = { var p = product; p.ingredientsText = text; return p }()
                    let r = ProductScore.evaluate(preview)
                    if let v = r.value { Text("\(v)/100 · \(r.method)").font(.headline) }
                    else { Text(r.missing.isEmpty ? "Pas encore de note." : "Pas de note : manque " + r.missing.joined(separator: ", ")).foregroundStyle(.secondary) }
                }
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) } }
        }
        .navigationTitle("Compléter la fiche").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    do { try ProductStore.shared.enrich(barcode: product.barcode, ingredientsText: text); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { error = "Photo illisible."; return }
                await read(img)
            }
        }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in showCamera = false; if let img { Task { await read(img) } } }.ignoresSafeArea()
        }
        #endif
    }

    private func read(_ img: UIImage) async {
        reading = true; defer { reading = false }
        let t = await DocOCR.recognize(img)
        if t.isEmpty { error = "Aucun texte lu. Essaie une photo plus nette, bien à plat." } else { error = nil; text = t }
    }
}

// MARK: - Etiquette d'aliment animal : lire, corriger, valider

/// Photo de l'etiquette (ou relecture de celle de la base), texte corrigeable champ par
/// champ, note recalculee en direct. Enregistre sur l'appareil pour CE produit.
struct PetLabelEditor: View {
    let product: CatalogProduct
    let code: String
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var reading = false
    @State private var error: String?
    @State private var composition = ""
    @State private var additives = ""
    @State private var declaration = ""
    @State private var values: [String: String] = [:]
    @State private var fromUserPhoto = false
    @State private var sourceText = ""
    @State private var rawText = ""
    @State private var loaded = false
    /// Valeurs lues qui n'ont pas de champ ici (omega 3 et 6, DHA) : gardees telles quelles.
    @State private var otherValues = PetLabel.Analytics()

    private let fields: [(String, WritableKeyPath<PetLabel.Analytics, Double?>)] = [
        ("Protéines", \.protein), ("Matières grasses", \.fat), ("Cendres brutes", \.ash),
        ("Cellulose brute", \.fibre), ("Humidité", \.moisture), ("Taurine", \.taurine),
        ("Calcium", \.calcium), ("Phosphore", \.phosphorus)
    ]

    var body: some View {
        Form {
            Section {
                Text("Photographie l'étiquette au dos (composition et constituants analytiques), bien à plat. Corrige ensuite ce qui a été mal lu.")
                    .font(.callout)
                #if !targetEnvironment(macCatalyst)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label("Photographier l'étiquette", systemImage: "camera") }
                }
                #endif
                PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choisir une photo", systemImage: "photo.on.rectangle") }
                if reading { HStack { ProgressView(); Text("Lecture de l'étiquette…").foregroundStyle(.secondary) } }
                if !sourceText.isEmpty { Text("Source : \(sourceText)").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Mention (aliment complet pour…)") { TextField("Aliment complet pour chatons…", text: $declaration, axis: .vertical) }
            Section("Composition") { TextEditor(text: $composition).frame(minHeight: 120) }
            Section("Additifs") { TextEditor(text: $additives).frame(minHeight: 60) }
            Section {
                ForEach(fields, id: \.0) { name, _ in
                    HStack {
                        Text(name)
                        Spacer()
                        TextField("—", text: Binding(get: { values[name] ?? "" }, set: { values[name] = $0 }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Constituants analytiques (tel quel)") } footer: {
                Text("Laisse vide ce qui n'est pas écrit sur le paquet : rien n'est inventé.")
            }
            Section("Note obtenue") {
                let r = ProductScore.evaluate(preview)
                if let v = r.value { Text("\(v)/100 · \(r.method)").font(.headline) }
                else { Text(r.missing.isEmpty ? "Pas encore de note." : "Pas de note : manque " + r.missing.joined(separator: ", ")).foregroundStyle(.secondary) }
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) } }
        }
        .navigationTitle("Étiquette").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Valider") { save() }
                    .disabled(composition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && analytics.isEmpty)
            }
        }
        .onAppear(perform: load)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { error = "Photo illisible."; return }
                await read(img)
            }
        }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in showCamera = false; if let img { Task { await read(img) } } }.ignoresSafeArea()
        }
        #endif
    }

    private var analytics: PetLabel.Analytics {
        var a = otherValues
        for (name, kp) in fields {
            if let t = values[name], let v = Double(t.replacingOccurrences(of: ",", with: ".")), (0...100).contains(v) { a[keyPath: kp] = v }
            else { a[keyPath: kp] = nil }
        }
        return a
    }

    /// La fiche telle qu'elle serait notee avec ces valeurs (la base garde la main
    /// sur ce qu'elle a deja).
    private var preview: CatalogProduct {
        let reading = PetProfile.LabelReading(text: rawText, declaration: declaration.nilIfBlank, composition: composition.nilIfBlank,
                                              additives: additives.nilIfBlank, analytics: analytics, source: sourceText,
                                              photoDate: nil, readAt: Date(), validated: true, fromUserPhoto: fromUserPhoto)
        // `product` est la fiche BRUTE de la base : on lui applique cette lecture seule.
        let prof = ProductStore.shared.petProfile(for: code)
        let p = PetProfile(gtin: PetProfile.key(code), aliases: [], species: prof?.species, lifeStage: prof?.lifeStage, label: reading, updatedAt: Date())
        return PetMerge.apply(p, to: product)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let l = ProductStore.shared.petProfile(for: code)?.label else { return }
        fill(l)
    }

    private func fill(_ l: PetProfile.LabelReading) {
        composition = l.composition ?? ""; additives = l.additives ?? ""; declaration = l.declaration ?? ""
        rawText = l.text; fromUserPhoto = l.fromUserPhoto; sourceText = l.source
        otherValues = l.analytics
        for (name, kp) in fields { values[name] = l.analytics[keyPath: kp].map { ProductScore.fmt($0) } ?? "" }
    }

    private func read(_ img: UIImage) async {
        reading = true; defer { reading = false }
        switch await PetLabelReader.read(userImage: img) {
        case .success(let l): fill(l); error = nil
        case .failure(let e): error = e.localizedDescription
        }
    }

    private func save() {
        let reading = PetProfile.LabelReading(text: rawText, declaration: declaration.nilIfBlank, composition: composition.nilIfBlank,
                                              additives: additives.nilIfBlank, analytics: analytics,
                                              source: sourceText.isEmpty ? "ta saisie" : sourceText,
                                              photoDate: ProductStore.shared.petProfile(for: code)?.label?.photoDate,
                                              readAt: Date(), validated: true, fromUserPhoto: fromUserPhoto)
        do { try ProductStore.shared.saveLabel(reading, for: code); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private extension String {
    var nilIfBlank: String? { let t = trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
}

// MARK: - Objectifs

struct YukoGoalsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var goals = ProductGoals.load()

    var body: some View {
        Form {
            Section {
                Text("Tes objectifs donnent un verdict « Pour toi » sur chaque fiche. Ils ne changent pas la note LifeOS, qui reste la même pour tout le monde.")
                    .font(.callout)
            }
            Section("Alimentation") { ForEach(ProductGoal.allCases.filter { !$0.forCosmetics }) { toggle($0) } }
            Section("Cosmétiques") { ForEach(ProductGoal.allCases.filter(\.forCosmetics)) { toggle($0) } }
            Section {
                Text("Repères utilisés : seuils « faible / élevé » des feux tricolores de la FSA pour sucres, sel et graisses saturées ; allégations nutritionnelles de l'UE pour protéines (12 et 20 % de l'énergie) et fibres (3 et 6 g) ; groupe NOVA ; liste de surveillance LifeOS pour les cosmétiques. Ce ne sont pas des conseils médicaux.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mes objectifs").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }

    private func toggle(_ g: ProductGoal) -> some View {
        Toggle(isOn: Binding(get: { goals.contains(g) }, set: { on in
            if on { goals.insert(g) } else { goals.remove(g) }
            ProductGoals.save(goals)
        })) { Label(g.title, systemImage: g.icon) }
    }
}

// MARK: - Methode et couverture

struct YukoMethodSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("La note LifeOS (\(ProductScore.version))") {
                    Text("Aliments et boissons : nutrition sur 60, additifs sur 30, label bio sur 10 (même répartition que Yuka). La nutrition vient du Nutri-Score 2023 officiel quand la base le donne, sinon d'un calcul LifeOS du même algorithme. Une lettre E vaut au plus 12/60.")
                    Text("Un additif à risque élevé plafonne la note à 49/100, comme chez Yuka. Chaque additif à risque élevé retire 15 points, chaque additif à risque modéré 6.")
                    Text("Eau : pas de nutriment à pénaliser, notée sur la nutrition et les additifs déclarés.")
                    Text("Cosmétiques : 100 moins des pénalités pour chaque ingrédient de la \(ProductScore.watchListVersion) trouvé (élevé -30, modéré -10, sensibilité -3). Seuls ces \(ProductScore.watchListCount) ingrédients sont évalués un par un ; les autres sont seulement reconnus. Sources : \(ProductScore.watchListSources)")
                    Text("Reconnaître un ingrédient n'est pas l'évaluer. Une note n'est donnée que si au moins 80 % des ingrédients sont reconnus, et elle s'accompagne d'un niveau de confiance. Concentrations et usage (rincé ou laissé sur la peau) ne sont pas connus : la note ne les prend pas en compte.")
                    Text("Ingrédients reconnus grâce à la liste officielle des noms INCI de la Commission européenne (base CosIng, licence CC BY 4.0). Elle dit qu'un nom existe, pas qu'il est sans risque : CosIng n'a qu'une valeur informative.")
                    Text("Compléments (whey, vitamines) : pas de note sur 100, la grille des aliments ne s'applique pas.")
                    Text("Animaux (chats et chiens, méthode Animaux 1.0) : composition sur 45 (viande nommée en premier, part de viande déclarée, céréales en tête, « sous-produits »), protéines sur matière sèche sur 25 (minimum FEDIAF : chat 25 %, chien 18 %), additifs et ingrédients à éviter sur 30 (sucre ajouté −15). Un ingrédient toxique pour l'espèce plafonne à 49. Pas un avis vétérinaire.")
                    Text("S'il manque un nutriment de base ou la liste des ingrédients : « non évalué », jamais un faux 0 ou 100.")
                    Text("Ce n'est pas le score Yuka : même répartition pour les aliments, mais calcul et données différents.")
                }
                Section("Couverture réelle") {
                    Text("Open Food Facts est très complet pour la France et l'Europe de l'Ouest, plus mince en Amérique du Nord et ailleurs. Open Beauty Facts (cosmétiques) est bien plus petit. Beaucoup de fiches sont incomplètes.")
                    Text("Un produit absent peut être créé sur ton appareil : il reste marqué « non vérifié » et n'est pas envoyé à la base.")
                }
                Section("Prix") {
                    Text("Aucune source de prix vérifiée n'est branchée. LifeOS n'affiche donc aucun prix plutôt que d'en inventer.")
                }
            }
            .navigationTitle("Méthode").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}
