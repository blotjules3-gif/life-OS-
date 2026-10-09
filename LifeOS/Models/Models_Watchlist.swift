import Foundation
import SwiftData

// MARK: - Bourse : titres suivis (lot 8)

/// Une liste de titres suivis ("Favoris", "Tech US"...), avec ses reglages d'affichage.
/// Les titres la designent par son NOM (`WatchlistItem.listName`) ; renommer une liste
/// renomme ses titres dans la meme sauvegarde (`WatchlistOps.rename`).
@Model final class WatchlistGroup {
    /// Identifiant stable, pose a l'init ou par `WatchlistOps.migrate` (jamais de valeur
    /// par defaut : elle serait la meme pour toutes les lignes existantes).
    var uid: UUID?
    var name: String = WatchlistDefaults.listName
    var order: Int = 0
    /// `StockDisplayCurrency.rawValue` : "original" ou "eur".
    var displayCurrency: String = StockDisplayCurrency.original.rawValue
    /// `StockPeriod.rawValue` : "1J", "5J", "1M", "6M", "1A".
    var period: String = StockPeriod.day1.rawValue
    var showSparkline: Bool = true
    var createdAt: Date = Date.now

    init(name: String = WatchlistDefaults.listName, order: Int = 0) {
        self.uid = UUID()
        self.name = name; self.order = order; self.createdAt = .now
    }

    var currency: StockDisplayCurrency { StockDisplayCurrency(rawValue: displayCurrency) ?? .original }
    var chartPeriod: StockPeriod { StockPeriod(rawValue: period) ?? .day1 }
}

@Model final class WatchlistItem {
    var uid: UUID?
    /// Symbole Yahoo, en MAJUSCULES (MC.PA, AAPL, VOD.L).
    var symbol: String = ""
    var displayName: String = ""
    /// Place telle que lue a l'ajout ("Paris", "NasdaqGS").
    var exchangeLabel: String = ""
    var listName: String = WatchlistDefaults.listName
    var order: Int = 0
    var addedAt: Date = Date.now

    init(symbol: String = "", displayName: String = "", exchangeLabel: String = "",
         listName: String = WatchlistDefaults.listName, order: Int = 0) {
        self.uid = UUID()
        self.symbol = symbol.uppercased(); self.displayName = displayName; self.exchangeLabel = exchangeLabel
        self.listName = listName; self.order = order; self.addedAt = .now
    }
}

/// Places proposees a l'ajout : suffixe Yahoo du symbole.
enum StockPlace: String, CaseIterable, Identifiable {
    case auto = "", paris = ".PA", london = ".L", frankfurt = ".DE", amsterdam = ".AS", milan = ".MI",
         madrid = ".MC", brussels = ".BR", swiss = ".SW", toronto = ".TO"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "États-Unis ou symbole complet"
        case .paris: return "Paris (.PA)"
        case .london: return "Londres (.L)"
        case .frankfurt: return "Francfort Xetra (.DE)"
        case .amsterdam: return "Amsterdam (.AS)"
        case .milan: return "Milan (.MI)"
        case .madrid: return "Madrid (.MC)"
        case .brussels: return "Bruxelles (.BR)"
        case .swiss: return "Suisse (.SW)"
        case .toronto: return "Toronto (.TO)"
        }
    }
}

/// Operations pures ou sur le contexte, testees sans interface.
enum WatchlistOps {
    /// "mc" + Paris -> "MC.PA". Un symbole qui a deja un suffixe le garde.
    static func normalizedSymbol(_ raw: String, place: StockPlace = .auto) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return "" }
        if place == .auto || s.contains(".") || s.contains("=") || s.hasPrefix("^") { return s }
        return s + place.rawValue
    }

    /// Caracteres admis par Yahoo dans un symbole.
    static func isPlausibleSymbol(_ s: String) -> Bool {
        let allowed = CharacterSet.uppercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: ".-=^"))
        return !s.isEmpty && s.count <= 20 && s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Nouvel ordre apres un glisser : rend les symboles dans l'ordre affiche.
    static func moved(_ symbols: [String], from source: IndexSet, to destination: Int) -> [String] {
        var a = symbols
        let moving = source.sorted().map { a[$0] }
        for i in source.sorted(by: >) { a.remove(at: i) }
        let shift = source.filter { $0 < destination }.count
        a.insert(contentsOf: moving, at: max(0, min(a.count, destination - shift)))
        return a
    }

    /// Nom de liste propre et libre : "" ou deja pris -> nil.
    static func validListName(_ raw: String, existing: [String], current: String? = nil) -> String? {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n.count <= 40 else { return nil }
        let taken = existing.filter { $0 != current }.map { $0.lowercased() }
        return taken.contains(n.lowercased()) ? nil : n
    }

    // MARK: Contexte

    /// Remplit les uid manquants et cree "Favoris" s'il n'y a aucune liste.
    /// Rend true si quelque chose a change.
    @discardableResult
    static func migrate(_ ctx: ModelContext) -> Bool {
        var changed = false
        let groups = (try? ctx.fetch(FetchDescriptor<WatchlistGroup>())) ?? []
        let items = (try? ctx.fetch(FetchDescriptor<WatchlistItem>())) ?? []
        for g in groups where g.uid == nil { g.uid = UUID(); changed = true }
        for i in items where i.uid == nil { i.uid = UUID(); changed = true }
        var names = Set(groups.map(\.name))
        if groups.isEmpty {
            ctx.insert(WatchlistGroup(name: WatchlistDefaults.listName, order: 0)); changed = true
            names.insert(WatchlistDefaults.listName)
        }
        // Titre dont la liste n'existe plus (ancienne donnee) : on recree la liste plutot
        // que de cacher le titre.
        var next = (groups.map(\.order).max() ?? 0) + 1
        for n in Set(items.map(\.listName)).subtracting(names).sorted() {
            ctx.insert(WatchlistGroup(name: n, order: next)); next += 1; changed = true
        }
        if changed { try? ctx.save() }
        return changed
    }

    enum AddResult: Equatable { case added, duplicate, invalid }

    static func add(symbol: String, displayName: String, exchangeLabel: String, to list: String,
                    in ctx: ModelContext) -> AddResult {
        let s = symbol.uppercased()
        guard isPlausibleSymbol(s) else { return .invalid }
        let existing = ((try? ctx.fetch(FetchDescriptor<WatchlistItem>())) ?? []).filter { $0.listName == list }
        if existing.contains(where: { $0.symbol == s }) { return .duplicate }
        let order = (existing.map(\.order).max() ?? -1) + 1
        ctx.insert(WatchlistItem(symbol: s, displayName: displayName, exchangeLabel: exchangeLabel, listName: list, order: order))
        return .added
    }

    /// Renomme une liste ET ses titres.
    static func rename(_ group: WatchlistGroup, to newName: String, in ctx: ModelContext) {
        let old = group.name
        guard old != newName else { return }
        let items = (try? ctx.fetch(FetchDescriptor<WatchlistItem>())) ?? []
        for i in items where i.listName == old { i.listName = newName }
        group.name = newName
    }

    /// Supprime une liste et ses titres.
    static func delete(_ group: WatchlistGroup, in ctx: ModelContext) {
        let items = (try? ctx.fetch(FetchDescriptor<WatchlistItem>())) ?? []
        for i in items where i.listName == group.name { ctx.delete(i) }
        ctx.delete(group)
    }

    /// Applique un ordre affiche : 0, 1, 2...
    static func applyOrder(_ symbols: [String], to items: [WatchlistItem]) {
        for (idx, s) in symbols.enumerated() { items.first { $0.symbol == s }?.order = idx }
    }
}
