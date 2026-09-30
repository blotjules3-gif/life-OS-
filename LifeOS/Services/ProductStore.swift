import Foundation

/// Historique, favoris, fiches locales et cache des produits scannes.
///
/// Historique, favoris et fiches locales vivent dans Documents/Yuko: la
/// sauvegarde complete les emporte. Le cache vit dans Caches: il se reconstruit.
/// Chaque entree garde la fiche entiere, donc l'historique s'ouvre hors ligne,
/// avec l'age des donnees.
@MainActor
final class ProductStore: ObservableObject {
    static let shared = ProductStore()

    @Published private(set) var history: [CatalogProduct] = []
    @Published private(set) var favorites: [CatalogProduct] = []
    @Published private(set) var localProducts: [CatalogProduct] = []
    /// Scans reels (camera ou code tape), distincts des simples consultations:
    /// un produit ouvert depuis une recherche n'y entre pas. Un meme produit
    /// scanne deux fois donne deux lignes datees.
    @Published private(set) var scans: [ScanRecord] = []
    /// Complements ajoutes par l'utilisateur a une fiche de la base (liste
    /// d'ingredients photographiee quand la base n'en a pas). Gardes a part: la
    /// fiche d'origine n'est jamais modifiee, et la provenance reste visible.
    @Published private(set) var enrichments: [Enrichment] = []
    /// Aliments animaux : espece / stade choisis, etiquette lue (voir PetProfile).
    @Published private(set) var petProfiles: [PetProfile] = []
    /// Fichiers illisibles au chargement: mis de cote, jamais ecrases en silence.
    @Published private(set) var loadProblems: [String] = []

    enum StoreError: LocalizedError, Equatable {
        case writeFailed(String)
        var errorDescription: String? {
            switch self { case .writeFailed(let m): return "Enregistrement impossible : \(m). Rien n'a changé." }
        }
    }

    static let historyLimit = 100
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? AppPaths.documents.appendingPathComponent("Yuko", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        history = load("history.json")
        favorites = load("favorites.json")
        localProducts = load("local.json")
        scans = load("scans.json")
        enrichments = load("enrichments.json")
        petProfiles = load("pets.json")
        migrateLegacySpecies()
    }

    // MARK: Aliments animaux

    func petProfile(for code: String) -> PetProfile? {
        let k = PetProfile.key(code)
        return petProfiles.first { $0.gtin == k }
    }

    private func updatePet(_ code: String, _ change: (inout PetProfile) -> Void) throws {
        let k = PetProfile.key(code)
        var list = petProfiles
        var prof = list.first { $0.gtin == k } ?? PetProfile(gtin: k, aliases: [], species: nil, lifeStage: nil, label: nil, updatedAt: Date())
        if !prof.aliases.contains(code) && code != k { prof.aliases.append(code) }
        change(&prof)
        prof.updatedAt = Date()
        list.removeAll { $0.gtin == k }
        list.insert(prof, at: 0)
        try commit(list, "pets.json")
        petProfiles = list
    }

    func setPetSpecies(_ s: PetLabel.Species?, for code: String) throws { try updatePet(code) { $0.species = s } }
    func setPetLifeStage(_ l: PetLabel.LifeStage?, for code: String) throws { try updatePet(code) { $0.lifeStage = l } }
    func saveLabel(_ l: PetProfile.LabelReading, for code: String) throws { try updatePet(code) { $0.label = l } }
    func removeLabel(for code: String) throws { try updatePet(code) { $0.label = nil } }

    /// Anciens choix "C'est pour : chat / chien" (UserDefaults, par code brut) repris
    /// sous le GTIN canonique, une fois.
    private func migrateLegacySpecies() {
        let defaults = UserDefaults.standard
        guard directory == AppPaths.documents.appendingPathComponent("Yuko", isDirectory: true),
              let legacy = defaults.dictionary(forKey: "yuko.petSpecies") as? [String: String], !legacy.isEmpty else { return }
        for (code, raw) in legacy {
            guard let sp = PetLabel.Species(rawValue: raw), petProfile(for: code)?.species == nil else { continue }
            try? setPetSpecies(sp, for: code)
        }
        defaults.removeObject(forKey: "yuko.petSpecies")
    }

    // MARK: Complements de fiche

    func enrich(barcode: String, ingredientsText: String, at date: Date = Date()) throws {
        let text = ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var e = enrichments.filter { $0.barcode != barcode }
        e.insert(Enrichment(barcode: barcode, ingredientsText: text, addedAt: date), at: 0)
        try commit(e, "enrichments.json")
        enrichments = e
    }

    func removeEnrichment(barcode: String) throws {
        let e = enrichments.filter { $0.barcode != barcode }
        try commit(e, "enrichments.json")
        enrichments = e
    }

    /// La fiche telle qu'affichee: la base d'abord, le complement seulement pour ce
    /// qui manque (jamais par-dessus une donnee de la base).
    func enriched(_ p: CatalogProduct) -> CatalogProduct {
        // Aliments animaux : profil de l'appareil (espece, etiquette lue) d'abord,
        // puis la liste d'ingredients photographiee si elle manque encore.
        let p = PetMerge.apply(p.isPetFood ? petProfile(for: p.barcode) : nil, to: p)
        guard p.ingredientsText == nil, let e = enrichments.first(where: { $0.barcode == p.barcode }) else { return p }
        var q = p
        q.ingredientsText = e.ingredientsText
        q.localNote = [p.localNote, "Liste d'ingrédients ajoutée par toi le \(e.addedAt.formatted(date: .abbreviated, time: .omitted)) (photo), non vérifiée."]
            .compactMap { $0 }.joined(separator: " ")
        return q
    }

    // MARK: Scans

    static let scanLimit = 200

    func recordScan(_ p: CatalogProduct, via: ScanRecord.Via, at date: Date = Date()) throws {
        var s = scans
        s.insert(ScanRecord(product: p, scannedAt: date, via: via), at: 0)
        if s.count > Self.scanLimit { s.removeLast(s.count - Self.scanLimit) }
        try commit(s, "scans.json")
        scans = s
    }

    func removeScan(_ r: ScanRecord) throws {
        let s = scans.filter { $0.id != r.id }
        try commit(s, "scans.json")
        scans = s
    }

    // MARK: Historique

    /// Chaque mutation ecrit d'ABORD, puis met a jour l'ecran. Un echec d'ecriture
    /// laisse les listes comme avant et remonte une erreur lisible.
    func record(_ p: CatalogProduct) throws {
        var h = history.filter { $0.id != p.id }
        h.insert(p, at: 0)
        if h.count > Self.historyLimit { h.removeLast(h.count - Self.historyLimit) }
        try commit(h, "history.json")
        history = h
    }

    func removeFromHistory(_ p: CatalogProduct) throws {
        let h = history.filter { $0.id != p.id }
        try commit(h, "history.json")
        history = h
    }

    // MARK: Favoris

    func isFavorite(_ p: CatalogProduct) -> Bool { favorites.contains { $0.id == p.id } }

    func toggleFavorite(_ p: CatalogProduct) throws {
        var f = favorites
        if isFavorite(p) { f.removeAll { $0.id == p.id } } else { f.insert(p, at: 0) }
        try commit(f, "favorites.json")
        favorites = f
    }

    // MARK: Fiches locales (produit inconnu)

    func saveLocal(_ p: CatalogProduct) throws {
        var l = localProducts.filter { $0.barcode != p.barcode }
        l.insert(p, at: 0)
        try commit(l, "local.json")
        localProducts = l
    }

    func local(barcode: String) -> CatalogProduct? { localProducts.first { $0.barcode == barcode } }

    func deleteLocal(_ p: CatalogProduct) throws {
        let l = localProducts.filter { $0.id != p.id }
        try commit(l, "local.json")
        localProducts = l
    }

    /// Efface tout (effacement des donnees). Rend les erreurs au lieu de les avaler.
    func eraseAll() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        history = []; favorites = []; localProducts = []; scans = []; enrichments = []; petProfiles = []; loadProblems = []
    }

    // MARK: Fichiers

    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()

    /// Un fichier present mais illisible est deplace (`<nom>.illisible-<date>`) et
    /// signale. Avant, il donnait une liste vide que la sauvegarde suivante ecrasait:
    /// l'historique disparaissait sans un mot.
    private func load<T: Decodable>(_ name: String) -> [T] {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try Self.decoder.decode([T].self, from: Data(contentsOf: url))
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = directory.appendingPathComponent("\(name).illisible-\(stamp)")
            if (try? FileManager.default.moveItem(at: url, to: aside)) != nil {
                loadProblems.append("\(name) était illisible : mis de côté dans \(aside.lastPathComponent).")
            } else {
                loadProblems.append("\(name) est illisible et n'a pas pu être mis de côté.")
            }
            AppLog.data.error("Yuko: \(name) illisible: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func commit<T: Encodable>(_ items: [T], _ name: String) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(items).write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }
}

/// Dernieres fiches lues, pour les montrer HORS LIGNE avec leur age. Appelable
/// depuis n'importe quel fil (le service reseau n'est pas sur l'acteur principal).
enum ProductCache {
    private static let queue = DispatchQueue(label: "lifeos.yuko.cache")
    nonisolated(unsafe) static var directory: URL = AppPaths.caches.appendingPathComponent("Yuko", isDirectory: true)
    static let limit = 300

    private static var file: URL { directory.appendingPathComponent("cache.json") }
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()

    static func put(_ p: CatalogProduct) {
        queue.sync {
            var all = read().filter { $0.barcode != p.barcode }
            all.insert(p, at: 0)
            if all.count > limit { all.removeLast(all.count - limit) }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? encoder.encode(all).write(to: file, options: .atomic)
        }
    }

    static func get(barcode: String) -> CatalogProduct? {
        queue.sync { read().first { $0.barcode == barcode } }
    }

    /// Fiches completes deja lues, par code, plus recentes que `maxAge`.
    static func get(barcodes: [String], maxAge: TimeInterval) -> [String: CatalogProduct] {
        let wanted = Set(barcodes), now = Date()
        return queue.sync {
            var out: [String: CatalogProduct] = [:]
            for p in read() where wanted.contains(p.barcode) && p.isSummary != true && now.timeIntervalSince(p.fetchedAt) < maxAge {
                if out[p.barcode] == nil { out[p.barcode] = p }
            }
            return out
        }
    }

    static func put(_ list: [CatalogProduct]) {
        guard !list.isEmpty else { return }
        queue.sync {
            let codes = Set(list.map(\.barcode))
            var all = list + read().filter { !codes.contains($0.barcode) }
            if all.count > limit { all.removeLast(all.count - limit) }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? encoder.encode(all).write(to: file, options: .atomic)
        }
    }

    static func clear() { queue.sync { try? FileManager.default.removeItem(at: file) } }

    private static func read() -> [CatalogProduct] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([CatalogProduct].self, from: data)) ?? []
    }
}

struct ScanRecord: Codable, Identifiable, Equatable {
    enum Via: String, Codable { case camera, typedCode }
    var id = UUID()
    let product: CatalogProduct
    let scannedAt: Date
    let via: Via
}

struct Enrichment: Codable, Equatable {
    let barcode: String
    let ingredientsText: String
    let addedAt: Date
}
