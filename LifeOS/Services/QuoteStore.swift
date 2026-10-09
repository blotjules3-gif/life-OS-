import Foundation
import SwiftData
import WidgetKit

/// Cache des cours cote app : une seule instance, lue par le portefeuille et les listes
/// suivies, ecrite dans le groupe d'apps pour que les widgets la lisent aussi.
///
/// Budget : au plus une demande par titre et par periode toutes les 5 minutes, meme sur
/// "Actualiser" (le point Yahoo n'est pas une API publique et refuse les rafales).
@MainActor
final class QuoteStore: ObservableObject {
    static let shared = QuoteStore()

    @Published private(set) var cache: StockQuoteCache
    @Published private(set) var refreshing = false
    @Published private(set) var lastReport: StockRefreshReport?

    private init() {
        cache = StockQuoteCache.load()
    }

    /// Relit le fichier (un widget a peut-etre rafraichi entre-temps).
    func reloadFromDisk() {
        cache = cache.merging(StockQuoteCache.load())
    }

    func quote(_ symbol: String) -> StockQuote? { cache.quotes[symbol.uppercased()] }
    func failure(_ symbol: String) -> StockQuoteCache.Failure? { cache.failures[symbol.uppercased()] }

    /// Hors ligne depuis le dernier essai.
    var isOffline: Bool { cache.offlineSince != nil }

    /// Rafraichit sous budget. `convertToEUR` : demande aussi les taux des devises vues.
    @discardableResult
    func refresh(symbols: [String], period: StockPeriod, convertToEUR: Bool) async -> StockRefreshReport {
        guard !refreshing else { return lastReport ?? StockRefreshReport() }
        refreshing = true
        defer { refreshing = false }
        reloadFromDisk()
        let wanted = symbols.map { $0.uppercased() }
        var currencies: Set<String> = []
        if convertToEUR { currencies = Set(wanted.compactMap { cache.quotes[$0]?.currency }) }
        let (first, report) = await StockFetcher.refresh(
            symbols: wanted, period: period, eurFor: currencies, cache: cache,
            minInterval: StockRefreshBudget.appMinInterval, maxRequests: 40)
        var updated = first
        // Devises decouvertes a cette lecture (nouveau titre) : un second passage, cache seul
        // pour les cours deja lus.
        if convertToEUR {
            let seen = Set(wanted.compactMap { updated.quotes[$0]?.currency }).subtracting(currencies)
            if !seen.isEmpty && !report.offline && !report.rateLimited {
                let (u2, _) = await StockFetcher.refresh(
                    symbols: [], period: period, eurFor: seen, cache: updated,
                    minInterval: StockRefreshBudget.appMinInterval, maxRequests: 10)
                updated = u2
            }
        }
        cache = StockQuoteCache.load().merging(updated)
        save()
        lastReport = report
        return report
    }

    /// Verifie un symbole avant de l'ajouter : une seule demande, ou le cache s'il est
    /// recent (moins de 5 minutes).
    func validate(_ symbol: String, period: StockPeriod = .day1) async -> Result<StockQuote, StockFetchError> {
        let s = symbol.uppercased()
        let key = StockQuoteCache.quoteKey(s, period)
        if let q = cache.quotes[s], let last = cache.attempts[key],
           Date().timeIntervalSince(last) < StockRefreshBudget.appMinInterval {
            return .success(q)
        }
        if let b = cache.backoffUntil, Date() < b { return .failure(.rateLimited) }
        cache.attempts[key] = Date()
        let r = await StockFetcher.fetch(symbol: s, period: period)
        switch r {
        case .success(let q): cache.record(q)
        case .failure(let e): cache.record(e, for: s, at: Date())
        }
        save()
        return r
    }

    /// Oublie les symboles qui ne sont plus suivis ni detenus.
    func prune(keeping symbols: Set<String>) {
        cache.prune(keeping: symbols)
        save()
    }

    private func save() {
        do { try cache.save() } catch {
            AppLog.data.error("cache des cours non ecrit: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Ecrit l'instantane des listes et du portefeuille pour les widgets, puis recharge les
/// widgets bourse. Appele apres CHAQUE modification (ajout, ordre, renommage, options,
/// suppression, mise a jour des cours).
enum StockWidgetPublisher {
    static let kinds = ["StockSingleWidget", "StockListWidget", "PortfolioWidget"]

    struct ListInput {
        var id: String; var name: String; var order: Int
        var currency: StockDisplayCurrency; var period: StockPeriod; var showSparkline: Bool
    }
    struct ItemInput { var symbol: String; var displayName: String; var exchangeLabel: String; var listName: String; var order: Int }
    struct HoldingInput { var symbol: String; var kind: String; var valueEUR: Double; var dayChangePct: Double?; var priceAt: Date? }

    /// Instantane pur, teste sans base.
    static func makeSnapshot(lists: [ListInput], items: [ItemInput], holdings: [HoldingInput], now: Date = Date()) -> StockWidgetSnapshot {
        let out = lists.map { l -> StockWidgetSnapshot.List in
            let its = items.filter { $0.listName == l.name }
                .sorted { $0.order != $1.order ? $0.order < $1.order : $0.symbol < $1.symbol }
                .map { StockWidgetSnapshot.Item(symbol: $0.symbol.uppercased(), displayName: $0.displayName, exchangeLabel: $0.exchangeLabel) }
            return .init(id: l.id, name: l.name, order: l.order, displayCurrency: l.currency, period: l.period,
                         showSparkline: l.showSparkline, items: its)
        }
        let rows = holdings.map { StockWidgetSnapshot.HoldingRow(symbol: $0.symbol, kind: $0.kind, valueEUR: $0.valueEUR,
                                                                  dayChangePct: $0.dayChangePct, priceAt: $0.priceAt) }
        return StockWidgetSnapshot(generatedAt: now, lists: out, holdings: rows)
    }

    /// `quotesChanged` : les cours ont ete relus, les widgets doivent se redessiner meme si
    /// les listes n'ont pas bouge.
    @MainActor
    static func publish(_ ctx: ModelContext, quotesChanged: Bool = false) {
        let groups = (try? ctx.fetch(FetchDescriptor<WatchlistGroup>())) ?? []
        let items = (try? ctx.fetch(FetchDescriptor<WatchlistItem>())) ?? []
        let holdings = (try? ctx.fetch(FetchDescriptor<Holding>())) ?? []
        let snap = makeSnapshot(
            lists: groups.map { ListInput(id: ($0.uid ?? UUID()).uuidString, name: $0.name, order: $0.order,
                                          currency: $0.currency, period: $0.chartPeriod, showSparkline: $0.showSparkline) },
            items: items.map { ItemInput(symbol: $0.symbol, displayName: $0.displayName, exchangeLabel: $0.exchangeLabel,
                                         listName: $0.listName, order: $0.order) },
            holdings: holdings.map { HoldingInput(symbol: $0.symbol, kind: $0.kind, valueEUR: $0.value,
                                                  dayChangePct: $0.dayChangePct, priceAt: $0.priceAt) })
        if !quotesChanged, var old = StockWidgetSnapshot.read() {
            old.generatedAt = snap.generatedAt
            if old == snap { return }
        }
        do { try snap.write() } catch {
            AppLog.data.error("instantane bourse non ecrit: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Les titres retires ne restent pas dans le cache.
        let keep = Set(items.map { $0.symbol.uppercased() } + holdings.filter { $0.kind != "Crypto" }.map { $0.symbol.uppercased() })
        QuoteStore.shared.prune(keeping: keep)
        reloadWidgets()
    }

    static func reloadWidgets() {
        for k in kinds { WidgetCenter.shared.reloadTimelines(ofKind: k) }
    }

}
