import SwiftUI
import SwiftData

// MARK: - Bourse : titres suivis

/// Listes de titres suivis : ajout avec verification du symbole, ordre au glisser,
/// suppression, renommage, devise et periode par liste. Toute modification reecrit
/// l'instantane des widgets bourse (`StockWidgetPublisher.publish`).
///
/// Ouvert aussi par lifeos://stocks?symbol=X&list=Y (liste choisie, titre mis en avant).
struct WatchlistView: View {
    var initialList: String? = nil
    var focusSymbol: String? = nil

    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WatchlistGroup.order) private var groups: [WatchlistGroup]
    @Query(sort: \WatchlistItem.order) private var allItems: [WatchlistItem]
    @ObservedObject private var store = QuoteStore.shared

    @State private var selected: String = ""
    @State private var showAdd = false
    @State private var showOptions = false
    @State private var showNewList = false
    @State private var confirmDelete = false
    @State private var editMode: EditMode = .inactive
    @State private var highlighted: String?
    @State private var now = Date()

    private var group: WatchlistGroup? { groups.first { $0.name == selected } ?? groups.first }
    private var items: [WatchlistItem] {
        guard let g = group else { return [] }
        return allItems.filter { $0.listName == g.name }.sorted { $0.order != $1.order ? $0.order < $1.order : $0.symbol < $1.symbol }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    listPicker
                    if let g = group { periodPicker(g) }
                    statusBanner
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    if items.isEmpty {
                        EmptyState(icon: "chart.line.uptrend.xyaxis", title: "Aucun titre",
                                   message: "Ajoute un symbole (MC.PA, AAPL, CW8.PA) pour suivre son cours ici et dans les widgets.",
                                   tint: AppCategory.invest.tint, actionTitle: "Ajouter un titre") { showAdd = true }
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(items) { item in
                            WatchlistRow(item: item, quote: store.quote(item.symbol), failure: store.failure(item.symbol),
                                         currency: group?.currency ?? .original, period: group?.chartPeriod ?? .day1,
                                         showSparkline: group?.showSparkline ?? true, rates: store.cache.eurRates,
                                         offline: store.isOffline, highlighted: highlighted == item.symbol, now: now)
                                .id(item.symbol)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: Theme.pad, bottom: 4, trailing: Theme.pad))
                        }
                        .onMove(perform: move)
                        .onDelete(perform: delete)
                    }
                } footer: {
                    if !items.isEmpty {
                        Text("Cours différés de Yahoo Finance (source non officielle, sans garantie). Jamais du temps réel.")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .environment(\.editMode, $editMode)
            .onAppear {
                if let s = focusSymbol, items.contains(where: { $0.symbol == s }) {
                    highlighted = s
                    DispatchQueue.main.async {
                        if reduceMotion { proxy.scrollTo(s, anchor: .center) }
                        else { withAnimation { proxy.scrollTo(s, anchor: .center) } }
                    }
                }
            }
        }
        .navigationTitle("Suivis").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Ajouter un titre")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showOptions = true } label: { Label("Options de la liste", systemImage: "slider.horizontal.3") }
                    Button { showNewList = true } label: { Label("Nouvelle liste", systemImage: "plus.rectangle.on.rectangle") }
                    if !items.isEmpty {
                        Button { editMode = editMode == .active ? .inactive : .active } label: {
                            Label(editMode == .active ? "Terminer l'ordre" : "Changer l'ordre", systemImage: "arrow.up.arrow.down")
                        }
                    }
                    if groups.count > 1 {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer la liste", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Options")
            }
        }
        .sheet(isPresented: $showAdd) {
            WatchlistAddSheet(listNames: groups.map(\.name), defaultList: group?.name ?? WatchlistDefaults.listName) { added in
                if let added { selected = added }
                StockWidgetPublisher.publish(ctx)
                Task { await refresh() }
            }
        }
        .sheet(isPresented: $showOptions) {
            if let g = group {
                WatchlistOptionsSheet(group: g, otherNames: groups.map(\.name)) { newName in
                    selected = newName
                    StockWidgetPublisher.publish(ctx)
                    Task { await refresh() }
                }
            }
        }
        .sheet(isPresented: $showNewList) {
            WatchlistNewListSheet(existing: groups.map(\.name), nextOrder: (groups.map(\.order).max() ?? -1) + 1) { name in
                selected = name
                StockWidgetPublisher.publish(ctx)
            }
        }
        .confirmationDialog("Supprimer la liste « \(group?.name ?? "") » et ses titres ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { deleteList() }
            Button("Annuler", role: .cancel) {}
        }
        .task {
            WatchlistOps.migrate(ctx)
            if selected.isEmpty {
                // Le lien donne le nom de la liste (ou son identifiant) ; liste disparue = la premiere.
                selected = initialList.flatMap { n in groups.first { $0.name == n || $0.uid?.uuidString == n }?.name }
                    ?? groups.first?.name ?? ""
            }
            StockWidgetPublisher.publish(ctx)
            await refresh()
        }
        .refreshable { await refresh() }
        .onChange(of: selected) { _, _ in Task { await refresh() } }
    }

    // MARK: Morceaux

    private var listPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups) { g in
                    Button { selected = g.name } label: {
                        Text(g.name).font(.subheadline.weight(g.name == group?.name ? .semibold : .regular))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .modifier(WatchlistChipSurface(selected: g.name == group?.name))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(g.name == group?.name ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func periodPicker(_ g: WatchlistGroup) -> some View {
        Picker("Période du graphique", selection: Binding(
            get: { g.chartPeriod },
            set: { p in
                g.period = p.rawValue
                try? ctx.save()
                StockWidgetPublisher.publish(ctx)
                Task { await refresh() }
            })) {
            ForEach(StockPeriod.allCases) { p in Text(p.rawValue).tag(p).accessibilityLabel(p.spoken) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var statusBanner: some View {
        if store.isOffline {
            Label("Hors ligne : derniers cours connus affichés.", systemImage: "wifi.slash")
                .font(.caption).foregroundStyle(Theme.warning)
        } else if let r = store.lastReport, r.rateLimited {
            Label("La source limite les demandes : nouvel essai dans quelques minutes.", systemImage: "hourglass")
                .font(.caption).foregroundStyle(Theme.warning)
        }
    }

    // MARK: Actions

    private func refresh() async {
        guard let g = group else { return }
        let syms = items.map(\.symbol)
        guard !syms.isEmpty else { return }
        let r = await store.refresh(symbols: syms, period: g.chartPeriod, convertToEUR: g.currency == .eur)
        now = Date()
        if r.updated > 0 { StockWidgetPublisher.publish(ctx, quotesChanged: true) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let order = WatchlistOps.moved(items.map(\.symbol), from: source, to: destination)
        WatchlistOps.applyOrder(order, to: items)
        try? ctx.save()
        StockWidgetPublisher.publish(ctx)
    }

    private func delete(at offsets: IndexSet) {
        let current = items
        for i in offsets { ctx.delete(current[i]) }
        try? ctx.save()
        StockWidgetPublisher.publish(ctx)
    }

    private func deleteList() {
        guard let g = group, groups.count > 1 else { return }
        WatchlistOps.delete(g, in: ctx)
        try? ctx.save()
        selected = groups.first { $0.name != g.name }?.name ?? ""
        StockWidgetPublisher.publish(ctx)
    }
}

// MARK: - Ligne

struct WatchlistRow: View {
    let item: WatchlistItem
    let quote: StockQuote?
    let failure: StockQuoteCache.Failure?
    let currency: StockDisplayCurrency
    let period: StockPeriod
    let showSparkline: Bool
    let rates: [String: Double]
    let offline: Bool
    let highlighted: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.symbol).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(item.displayName.isEmpty ? (quote?.name ?? "") : item.displayName)
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                if let q = quote {
                    Text(StockFormat.statusLine(q, offline: offline, now: now))
                        .font(.caption2).foregroundStyle(statusColor(q)).lineLimit(2)
                } else if let f = failure {
                    Label(f.error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(Theme.warning)
                } else {
                    Text(offline ? "Hors ligne, pas encore de cours" : "Cours en attente")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 6)
            if showSparkline, let q = quote, let pts = q.series[period.range], pts.count >= 2 {
                StockSparkline(values: pts, baseline: period == .day1 ? q.previousClose : nil, color: trendColor(q))
                    .frame(width: 64, height: 30)
            }
            VStack(alignment: .trailing, spacing: 3) {
                if let q = quote {
                    let shown = StockMath.convert(q.price, from: q.currency, to: currency, eurPerUnit: rates)
                    Text(StockFormat.price(shown?.value ?? q.price, currency: shown?.currency ?? q.currency))
                        .font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    if currency == .eur && shown == nil {
                        Text("Taux EUR indisponible").font(.caption2).foregroundStyle(Theme.warning)
                    } else if currency == .eur && q.currency != "EUR" {
                        Text("Cotée en \(q.currency)").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    if let pct = q.changePercent {
                        Label(StockFormat.percent(pct), systemImage: pct > 0 ? "arrow.up.right" : (pct < 0 ? "arrow.down.right" : "equal"))
                            .font(.caption.bold().monospacedDigit()).foregroundStyle(trendColor(q))
                            .labelStyle(.titleAndIcon)
                    }
                } else {
                    Text("…").font(.subheadline).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
                }
            }
        }
        .padding(12)
        .frame(minHeight: 44)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .raised,
                       tint: highlighted ? AppCategory.invest.tint : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func trendColor(_ q: StockQuote) -> Color {
        guard let p = q.changePercent else { return Theme.textSecondary }
        return p > 0 ? Theme.success : (p < 0 ? Theme.danger : Theme.textSecondary)
    }

    private func statusColor(_ q: StockQuote) -> Color {
        StockFreshness.status(q, now: now) == .stale || offline ? Theme.warning : Theme.textSecondary
    }

    private var spoken: String {
        var parts = [item.symbol]
        if !item.displayName.isEmpty { parts.append(item.displayName) }
        if let q = quote {
            let shown = StockMath.convert(q.price, from: q.currency, to: currency, eurPerUnit: rates)
            parts.append(StockFormat.price(shown?.value ?? q.price, currency: shown?.currency ?? q.currency))
            if let p = q.changePercent { parts.append(StockFormat.spokenPercent(p) + " sur la journée") }
            parts.append(StockFormat.statusSpoken(q, offline: offline, now: now))
        } else if let f = failure {
            parts.append(f.error.message)
        } else {
            parts.append("cours en attente")
        }
        return parts.joined(separator: ", ")
    }
}

/// Pastille de liste : verre simple, teinte de la categorie quand elle est choisie.
private struct WatchlistChipSurface: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        if selected {
            content.raisedSurface(Capsule(), .raised, tint: AppCategory.invest.tint)
        } else {
            content.glassControl(Capsule())
        }
    }
}
