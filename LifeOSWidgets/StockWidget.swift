import AppIntents
import SwiftUI
import WidgetKit

// Widgets bourse : un titre, une liste choisie, le portefeuille.
//
// Donnees : l'instantane ecrit par l'app (listes, ordre, options, positions) et le cache
// des cours partage. Le widget peut relire lui-meme les cours, sous budget : 6 titres au
// plus par passage, chacun au plus toutes les 15 minutes, rien pendant un refus de la
// source. Cours DIFFERES (Yahoo Finance, source non officielle) : chaque vue le dit.

// MARK: - Entree et chargement

struct StockEntry: TimelineEntry {
    var date: Date
    var snapshot: StockWidgetSnapshot?
    var cache: StockQuoteCache
    var listID: String? = nil
    var symbol: String? = nil
    var offline = false
    /// Exemple de la galerie ou espace reserve : jamais presente comme donnee personnelle.
    var isPreview = false

    var list: StockWidgetSnapshot.List? {
        guard let snapshot else { return nil }
        if let listID, let l = snapshot.list(id: listID) { return l }
        return listID == nil ? snapshot.defaultList : nil
    }
}

enum StockWidgetLoader {
    /// Cache a jour pour `symbols`, en relisant ce qui doit l'etre (sous budget).
    static func load(symbols: [String], period: StockPeriod, eur: Bool, now: Date = Date()) async -> (StockQuoteCache, Bool) {
        let cache = StockQuoteCache.load()
        let wanted = StockWidgetPolicy.symbolsToRefresh(symbols, period: period, cache: cache, now: now)
        var currencies: Set<String> = []
        if eur {
            currencies = Set(symbols.compactMap { cache.quotes[$0.uppercased()]?.currency })
                .filter { cur in cur != "EUR" && (cache.fx[cur].map { now.timeIntervalSince($0.fetchedAt) > 6 * 3600 } ?? true) }
        }
        guard !wanted.isEmpty || !currencies.isEmpty else { return (cache, cache.offlineSince != nil) }
        let (updated, report) = await StockFetcher.refresh(
            symbols: wanted, period: period, eurFor: currencies, cache: cache,
            minInterval: StockRefreshBudget.widgetMinInterval, maxRequests: StockRefreshBudget.widgetMaxRequests)
        let merged = StockQuoteCache.load().merging(updated)
        try? merged.save()
        return (merged, report.offline || (report.updated == 0 && merged.offlineSince != nil))
    }
}

enum StockWidgetSample {
    /// Espace reserve de la galerie, affiche avec la mention "Exemple".
    static func quote(_ symbol: String, _ name: String, _ price: Double, _ prev: Double, _ cur: String, now: Date) -> StockQuote {
        let series = (0..<20).map { i in prev + (price - prev) * Double(i) / 19 + sin(Double(i)) * price * 0.002 }
        return StockQuote(symbol: symbol, name: name, price: price, previousClose: prev, currency: cur, exchange: "",
                          exchangeFullName: "", instrumentType: "EQUITY", marketState: nil, marketTime: now,
                          sessionStart: now.addingTimeInterval(-3600), sessionEnd: now.addingTimeInterval(3600),
                          exchangeTimeZone: nil, fetchedAt: now, series: ["1d": series])
    }

    static func entry(now: Date = Date()) -> StockEntry {
        var cache = StockQuoteCache()
        for q in [quote("AAPL", "Apple", 230, 227, "USD", now: now), quote("MC.PA", "LVMH", 600, 606, "EUR", now: now),
                  quote("CW8.PA", "MSCI World", 520, 518, "EUR", now: now)] { cache.quotes[q.symbol] = q }
        let items = cache.quotes.keys.sorted().map { StockWidgetSnapshot.Item(symbol: $0, displayName: cache.quotes[$0]?.name ?? "", exchangeLabel: "") }
        let list = StockWidgetSnapshot.List(id: "sample", name: "Exemple", order: 0, displayCurrency: .original, period: .day1, showSparkline: true, items: items)
        let snap = StockWidgetSnapshot(generatedAt: now, lists: [list],
                                       holdings: [.init(symbol: "AAPL", kind: "Action", valueEUR: 2100, dayChangePct: 1.3, priceAt: now),
                                                  .init(symbol: "CW8.PA", kind: "ETF", valueEUR: 5200, dayChangePct: 0.4, priceAt: now)])
        return StockEntry(date: now, snapshot: snap, cache: cache, listID: "sample", symbol: "AAPL", isPreview: true)
    }
}

// MARK: - Fournisseurs

struct StockSingleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StockEntry { StockWidgetSample.entry() }

    func snapshot(for configuration: StockSingleWidgetIntent, in context: Context) async -> StockEntry {
        let e = makeEntry(configuration, cache: StockQuoteCache.load())
        return context.isPreview && e.snapshot?.allItems.isEmpty != false ? StockWidgetSample.entry() : e
    }

    func timeline(for configuration: StockSingleWidgetIntent, in context: Context) async -> Timeline<StockEntry> {
        var e = makeEntry(configuration, cache: StockQuoteCache.load())
        if let s = e.symbol, e.snapshot?.item(symbol: s) != nil {
            let settings = e.snapshot?.settings(for: s)
            let (cache, offline) = await StockWidgetLoader.load(symbols: [s], period: settings?.period ?? .day1,
                                                                eur: settings?.displayCurrency == .eur)
            e.cache = cache; e.offline = offline
        }
        let quotes = e.symbol.flatMap { e.cache.quotes[$0] }.map { [$0] } ?? []
        return Timeline(entries: [e], policy: .after(StockWidgetPolicy.nextReload(quotes: quotes)))
    }

    private func makeEntry(_ c: StockSingleWidgetIntent, cache: StockQuoteCache) -> StockEntry {
        let snap = StockWidgetSnapshot.read()
        let symbol = c.symbol?.id ?? snap?.allItems.first?.symbol
        return StockEntry(date: Date(), snapshot: snap, cache: cache, symbol: symbol, offline: cache.offlineSince != nil)
    }
}

struct StockListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StockEntry { StockWidgetSample.entry() }

    func snapshot(for configuration: StockListWidgetIntent, in context: Context) async -> StockEntry {
        let e = makeEntry(configuration, cache: StockQuoteCache.load())
        return context.isPreview && e.list?.items.isEmpty != false ? StockWidgetSample.entry() : e
    }

    func timeline(for configuration: StockListWidgetIntent, in context: Context) async -> Timeline<StockEntry> {
        var e = makeEntry(configuration, cache: StockQuoteCache.load())
        var quotes: [StockQuote] = []
        if let l = e.list, !l.items.isEmpty {
            let shown = Array(l.items.prefix(StockListView.maxRows(context.family)))
            let (cache, offline) = await StockWidgetLoader.load(symbols: shown.map(\.symbol), period: l.period,
                                                                eur: l.displayCurrency == .eur)
            e.cache = cache; e.offline = offline
            quotes = shown.compactMap { cache.quotes[$0.symbol] }
        }
        return Timeline(entries: [e], policy: .after(StockWidgetPolicy.nextReload(quotes: quotes)))
    }

    private func makeEntry(_ c: StockListWidgetIntent, cache: StockQuoteCache) -> StockEntry {
        StockEntry(date: Date(), snapshot: StockWidgetSnapshot.read(), cache: cache, listID: c.list?.id,
                   offline: cache.offlineSince != nil)
    }
}

/// Le portefeuille lit les valeurs ecrites par l'app (en euros) : pas d'appel reseau ici.
struct PortfolioProvider: TimelineProvider {
    func placeholder(in context: Context) -> StockEntry { StockWidgetSample.entry() }

    func getSnapshot(in context: Context, completion: @escaping (StockEntry) -> Void) {
        let e = entry()
        completion(context.isPreview && e.snapshot?.holdings.isEmpty != false ? StockWidgetSample.entry() : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StockEntry>) -> Void) {
        let e = entry()
        // L'app recharge ce widget a chaque mise a jour des cours ; ceci n'est qu'un filet.
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(2 * 3600))))
    }

    private func entry() -> StockEntry {
        let cache = StockQuoteCache.load()
        return StockEntry(date: Date(), snapshot: StockWidgetSnapshot.read(), cache: cache, offline: cache.offlineSince != nil)
    }
}

// MARK: - Couleurs et petits morceaux

private enum StockTone {
    static var up: Color { WidgetPalette.green }
    static var down: Color { WidgetPalette.tone(1.00, 0.27, 0.23) }
    static func trend(_ pct: Double?) -> Color {
        guard let pct else { return .secondary }
        return pct > 0 ? up : (pct < 0 ? down : .secondary)
    }
    static func arrow(_ pct: Double) -> String { pct > 0 ? "arrow.up.right" : (pct < 0 ? "arrow.down.right" : "equal") }
}

private struct ChangeLabel: View {
    let pct: Double?
    var font: Font = .caption.bold()
    var body: some View {
        if let pct {
            HStack(spacing: 2) {
                Image(systemName: StockTone.arrow(pct)).imageScale(.small)
                Text(StockFormat.percent(pct)).monospacedDigit()
            }
            .font(font).foregroundStyle(StockTone.trend(pct))
        } else {
            Text("Variation inconnue").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct EmptyStockView: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.title3).foregroundStyle(.secondary)
            Text(message).font(.caption).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private func displayed(_ q: StockQuote, _ currency: StockDisplayCurrency, _ cache: StockQuoteCache) -> String {
    let c = StockMath.convert(q.price, from: q.currency, to: currency, eurPerUnit: cache.eurRates)
    return StockFormat.price(c?.value ?? q.price, currency: c?.currency ?? q.currency)
}

private func spoken(_ q: StockQuote, _ currency: StockDisplayCurrency, _ cache: StockQuoteCache, offline: Bool) -> String {
    var parts = [q.symbol, q.name, displayed(q, currency, cache)]
    if let p = q.changePercent { parts.append(StockFormat.spokenPercent(p)) }
    parts.append(StockFormat.statusSpoken(q, offline: offline))
    return parts.filter { !$0.isEmpty }.joined(separator: ", ")
}

// MARK: - Un titre

struct StockSingleView: View {
    let entry: StockEntry
    @Environment(\.widgetFamily) private var family

    private var settings: StockWidgetSnapshot.List? { entry.symbol.flatMap { entry.snapshot?.settings(for: $0) } }
    private var currency: StockDisplayCurrency { settings?.displayCurrency ?? .original }
    private var period: StockPeriod { settings?.period ?? .day1 }

    var body: some View {
        content
            .containerBackground(.background, for: .widget)
            .widgetURL(StockDeepLink.url(symbol: entry.symbol, list: settings?.name))
    }

    @ViewBuilder private var content: some View {
        if entry.snapshot?.allItems.isEmpty != false {
            EmptyStockView(message: "Ajoute des titres dans LifeOS (Finario, Suivis).")
        } else if let s = entry.symbol, entry.snapshot?.item(symbol: s) == nil {
            EmptyStockView(message: "\(s) n'est plus suivi. Modifie le widget pour choisir un titre.")
        } else if let s = entry.symbol, let q = entry.cache.quotes[s] {
            quoteView(q)
        } else if let s = entry.symbol {
            let err = entry.cache.failures[s]?.error
            EmptyStockView(message: "\(s) · " + (err?.message ?? (entry.offline ? "Hors ligne, pas encore de cours" : "Cours en attente")))
        } else {
            EmptyStockView(message: "Ajoute des titres dans LifeOS (Finario, Suivis).")
        }
    }

    @ViewBuilder private func quoteView(_ q: StockQuote) -> some View {
        switch family {
        case .accessoryInline:
            Text("\(q.symbol) \(displayed(q, currency, entry.cache)) \(q.changePercent.map(StockFormat.percent) ?? "")")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(q.symbol).font(.headline).widgetAccentable()
                Text(displayed(q, currency, entry.cache)).font(.body.monospacedDigit())
                HStack(spacing: 4) {
                    if let p = q.changePercent { Image(systemName: StockTone.arrow(p)); Text(StockFormat.percent(p)) }
                    Text(StockFormat.compactStatus(q, offline: entry.offline))
                }.font(.caption2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(q, currency, entry.cache, offline: entry.offline))
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(q.symbol).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    if entry.isPreview { Text("Exemple").font(.caption2).foregroundStyle(.secondary) }
                }
                if !q.name.isEmpty {
                    Text(q.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let pts = q.series[period.range], pts.count >= 2, settings?.showSparkline ?? true {
                    StockSparkline(values: pts, baseline: period == .day1 ? q.previousClose : nil,
                                   color: StockTone.trend(q.changePercent))
                        .frame(height: family == .systemSmall ? 28 : 44)
                }
                Text(displayed(q, currency, entry.cache))
                    .font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    ChangeLabel(pct: q.changePercent)
                    if family != .systemSmall, currency == .eur, q.currency != "EUR" {
                        Text("cotée en \(q.currency)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(family == .systemSmall ? StockFormat.compactStatus(q, offline: entry.offline)
                                            : StockFormat.statusLine(q, offline: entry.offline))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(q, currency, entry.cache, offline: entry.offline))
        }
    }
}

// MARK: - Une liste

struct StockListView: View {
    let entry: StockEntry
    @Environment(\.widgetFamily) private var family

    static func maxRows(_ family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        case .systemLarge, .systemExtraLarge: return 7
        case .accessoryRectangular: return 2
        default: return 1
        }
    }

    var body: some View {
        content
            .containerBackground(.background, for: .widget)
            .widgetURL(StockDeepLink.url(list: entry.list?.name))
    }

    @ViewBuilder private var content: some View {
        if let l = entry.list {
            if l.items.isEmpty {
                EmptyStockView(message: "« \(l.name) » est vide. Ajoute des titres dans LifeOS.")
            } else {
                listView(l)
            }
        } else if entry.listID != nil {
            EmptyStockView(message: "Cette liste n'existe plus. Modifie le widget pour en choisir une.")
        } else {
            EmptyStockView(message: "Ajoute des titres dans LifeOS (Finario, Suivis).")
        }
    }

    @ViewBuilder private func listView(_ l: StockWidgetSnapshot.List) -> some View {
        let rows = Array(l.items.prefix(Self.maxRows(family)))
        if family == .accessoryRectangular || family == .accessoryInline {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(rows) { i in
                    if let q = entry.cache.quotes[i.symbol] {
                        Text("\(i.symbol) \(displayed(q, l.displayCurrency, entry.cache)) \(q.changePercent.map(StockFormat.percent) ?? "")")
                            .font(.caption).lineLimit(1)
                    } else {
                        Text(i.symbol).font(.caption)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 5) {
                HStack {
                    Text(l.name).font(.caption.bold()).lineLimit(1)
                    Spacer()
                    Text(entry.isPreview ? "Exemple" : l.period.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(rows) { i in row(i, l) }
                Spacer(minLength: 0)
                footer(rows)
            }
        }
    }

    @ViewBuilder private func row(_ i: StockWidgetSnapshot.Item, _ l: StockWidgetSnapshot.List) -> some View {
        let q = entry.cache.quotes[i.symbol]
        let content = HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(i.symbol).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                if family != .systemSmall, !i.displayName.isEmpty {
                    Text(i.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let q {
                if family != .systemSmall, l.showSparkline, let pts = q.series[l.period.range], pts.count >= 2 {
                    StockSparkline(values: pts, baseline: l.period == .day1 ? q.previousClose : nil,
                                   color: StockTone.trend(q.changePercent), lineWidth: 1.2)
                        .frame(width: 44, height: 18)
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(displayed(q, l.displayCurrency, entry.cache)).font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    ChangeLabel(pct: q.changePercent, font: .caption2.bold())
                }
            } else {
                Text(entry.cache.failures[i.symbol]?.error.message ?? (entry.offline ? "Hors ligne" : "En attente"))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(q.map { spoken($0, l.displayCurrency, entry.cache, offline: entry.offline) } ?? "\(i.symbol), cours indisponible")

        if family == .systemSmall {
            content
        } else {
            Link(destination: StockDeepLink.url(symbol: i.symbol, list: l.name)) { content }
        }
    }

    @ViewBuilder private func footer(_ rows: [StockWidgetSnapshot.Item]) -> some View {
        let quotes = rows.compactMap { entry.cache.quotes[$0.symbol] }
        if let latest = quotes.max(by: { ($0.marketTime ?? $0.fetchedAt) < ($1.marketTime ?? $1.fetchedAt) }) {
            Text(family == .systemSmall ? StockFormat.compactStatus(latest, offline: entry.offline)
                                        : StockFormat.statusLine(latest, offline: entry.offline))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel(StockFormat.statusSpoken(latest, offline: entry.offline))
        } else if entry.offline {
            Text("Hors ligne").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Portefeuille

struct PortfolioWidgetView: View {
    let entry: StockEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(.background, for: .widget)
            .widgetURL(StockDeepLink.portfolioURL)
    }

    @ViewBuilder private var content: some View {
        if let snap = entry.snapshot, !snap.holdings.isEmpty {
            let p = snap.portfolio
            switch family {
            case .accessoryInline:
                Text("Portefeuille \(p.dayChangePct.map(StockFormat.percent) ?? "")")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Portefeuille").font(.caption.bold()).widgetAccentable()
                    Text(p.total, format: .currency(code: "EUR").precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit()).privacySensitive()
                    if let pct = p.dayChangePct { Text("\(StockFormat.percent(pct)) aujourd'hui").font(.caption2) }
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Portefeuille").font(.caption.bold())
                        Spacer()
                        if entry.isPreview { Text("Exemple").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Text(p.total, format: .currency(code: "EUR").precision(.fractionLength(0)))
                        .font(.title2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                        .privacySensitive()
                    if let pct = p.dayChangePct {
                        HStack(spacing: 4) {
                            Image(systemName: StockTone.arrow(pct)).imageScale(.small)
                            Text("\(p.dayChange >= 0 ? "+" : "-")\(abs(p.dayChange), format: .currency(code: "EUR").precision(.fractionLength(0)))")
                                .privacySensitive()
                            Text(StockFormat.percent(pct))
                        }
                        .font(.caption.bold().monospacedDigit()).foregroundStyle(StockTone.trend(pct))
                    } else {
                        Text("Variation du jour inconnue").font(.caption2).foregroundStyle(.secondary)
                    }
                    if family != .systemSmall, !p.movers.isEmpty {
                        Divider().opacity(0.3)
                        ForEach(p.movers, id: \.symbol) { m in
                            HStack {
                                Text(m.symbol).font(.caption).lineLimit(1)
                                Spacer()
                                ChangeLabel(pct: m.pct, font: .caption2.bold())
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(footer(p)).font(.caption2).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8)
                }
            }
        } else {
            EmptyStockView(message: "Ajoute tes positions dans LifeOS (Finario).")
        }
    }

    private func footer(_ p: PortfolioSummary) -> String {
        var parts: [String] = []
        if let t = p.latestPriceAt { parts.append("Cours différés · \(StockFormat.timeLabel(t))") }
        if p.withoutChange > 0 { parts.append("\(p.withoutChange) sans variation") }
        if entry.offline { parts.insert("Hors ligne", at: 0) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Widgets

struct StockSingleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "StockSingleWidget", intent: StockSingleWidgetIntent.self, provider: StockSingleProvider()) { entry in
            StockSingleView(entry: entry)
        }
        .configurationDisplayName("Bourse · un titre")
        .description("Cours différé, variation et petit graphique d'un titre suivi.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct StockListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "StockListWidget", intent: StockListWidgetIntent.self, provider: StockListProvider()) { entry in
            StockListView(entry: entry)
        }
        .configurationDisplayName("Bourse · liste")
        .description("Les titres d'une de tes listes, dans ton ordre.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct PortfolioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PortfolioWidget", provider: PortfolioProvider()) { entry in
            PortfolioWidgetView(entry: entry)
        }
        .configurationDisplayName("Portefeuille")
        .description("Valeur totale, variation du jour et plus fortes variations.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
