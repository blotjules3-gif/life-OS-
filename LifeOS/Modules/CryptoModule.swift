import SwiftUI

// Modèles → CryptoModels.swift
// Données statiques & helpers → CryptoData.swift

// MARK: - Portfolio codec (privé à ce fichier)

private struct PortfolioPosition: Identifiable {
    let id: String
    var buyPrice: Double
    var quantity: Double
}

// MARK: - Portfolio codec

private func decodePortfolio(_ raw: String) -> [PortfolioPosition] {
    guard !raw.isEmpty else { return [] }
    return raw.split(separator: "|").compactMap { seg -> PortfolioPosition? in
        let p = seg.split(separator: ":")
        guard p.count == 3, let bp = Double(p[1]), let qty = Double(p[2]) else { return nil }
        return PortfolioPosition(id: String(p[0]), buyPrice: bp, quantity: qty)
    }
}
private func encodePortfolio(_ positions: [PortfolioPosition]) -> String {
    positions.map { "\($0.id):\($0.buyPrice):\($0.quantity)" }.joined(separator: "|")
}

// MARK: - Alertes codec

private func decodeAlerts(_ raw: String) -> [PriceAlert] {
    guard !raw.isEmpty else { return [] }
    return raw.split(separator: "|").compactMap { seg -> PriceAlert? in
        let p = seg.split(separator: ":")
        guard p.count == 3, let thr = Double(p[2]) else { return nil }
        return PriceAlert(assetId: String(p[0]), direction: String(p[1]), threshold: thr)
    }
}
private func encodeAlerts(_ alerts: [PriceAlert]) -> String {
    alerts.map { "\($0.assetId):\($0.direction):\($0.threshold)" }.joined(separator: "|")
}

// MARK: - Onglets

enum CryptoTab: String, CaseIterable {
    case market, suivi, alertes, learn, info
    var label: String {
        switch self {
        case .market:  return "Marché"
        case .suivi:   return "Suivi"
        case .alertes: return "Alertes"
        case .learn:   return "Apprendre"
        case .info:    return "Info"
        }
    }
    var icon: String {
        switch self {
        case .market:  return "chart.bar.xaxis"
        case .suivi:   return "eye"
        case .alertes: return "bell"
        case .learn:   return "book.closed"
        case .info:    return "info.circle"
        }
    }
    var iconFill: String {
        switch self {
        case .market:  return "chart.bar.xaxis.ascending"
        case .suivi:   return "eye.fill"
        case .alertes: return "bell.fill"
        case .learn:   return "book.closed.fill"
        case .info:    return "info.circle.fill"
        }
    }
}

// MARK: - App Crypto (plein écran)

struct CryptoAppView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: CryptoTab = .market
    @State private var assets: [CryptoAsset] = []
    @State private var loading = true
    @State private var chatInput = ""
    @State private var chatResponse: String? = nil
    @State private var chatMessages: [CryptoMessage] = [
        CryptoMessage(fromUser: false, text: "Salut ! Je connais les prix en temps réel et les scores R/P de toutes les cryptos. Demande-moi quelque chose.")
    ]
    @FocusState private var chatFocused: Bool
    @Namespace private var ns

    private static let barBg = Color.white
    private static let selBg = Color(white: 0.92)
    private static let accentColor = Theme.invest

    var body: some View {
        VStack(spacing: 0) {
            // ─── En-tête persistant ───
            headerBar

            // ─── Bannière réponse chatbot ───
            if let resp = chatResponse {
                chatBanner(resp)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ─── Contenu onglet ───
            Group {
                switch tab {
                case .market:  CryptoMarketTab(assets: assets, loading: loading)
                case .suivi:   CryptoSuiviTab(assets: assets)
                case .alertes: CryptoAlertesTab(assets: assets)
                case .learn:   CryptoLearnTab()
                case .info:    CryptoInfoTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.none, value: tab)
        }
        .safeAreaInset(edge: .bottom) { cryptoTabBar }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(duration: 0.25), value: chatResponse != nil)
        .task { await loadData() }
    }

    // MARK: En-tête (quitter + chat)

    private var headerBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.93), in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Self.accentColor)

                TextField("Question sur le marché…", text: $chatInput)
                    .font(.system(size: 14))
                    .focused($chatFocused)
                    .onSubmit { sendChat() }
                    .submitLabel(.send)

                if !chatInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { sendChat() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 26, height: 26)
                            .background(Self.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.95), in: Capsule())
            .animation(.spring(duration: 0.2), value: chatInput.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func chatBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.accentColor)
                .frame(width: 20, height: 20)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation { chatResponse = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Self.accentColor.opacity(0.07))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: Barre d'onglets

    private var cryptoTabBar: some View {
        HStack(spacing: 0) {
            ForEach(CryptoTab.allCases, id: \.rawValue) { t in
                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.3)) { tab = t }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        if tab == t {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Self.selBg)
                                .frame(width: 54, height: 44)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                        VStack(spacing: 3) {
                            Image(systemName: tab == t ? t.iconFill : t.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(tab == t ? Self.accentColor : Color(white: 0.55))
                                .animation(.spring(duration: 0.25), value: tab)
                            Text(t.label)
                                .font(.system(size: 9, weight: tab == t ? .semibold : .regular))
                                .foregroundStyle(tab == t ? Self.accentColor : Color(white: 0.55))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .background(Self.barBg, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 4)
        .overlay(Capsule().stroke(Color(white: 0.88), lineWidth: 1))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    // MARK: Actions

    private func sendChat() {
        let q = chatInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        chatMessages.append(CryptoMessage(fromUser: true, text: q))
        chatInput = ""
        chatFocused = false
        let response = cryptoAnswer(query: q, assets: assets)
        chatMessages.append(CryptoMessage(fromUser: false, text: response))
        withAnimation { chatResponse = response }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            withAnimation { chatResponse = nil }
        }
    }

    private func loadData() async {
        do {
            let data = try await fetchCryptoMarket()
            await MainActor.run { assets = data; loading = false }
        } catch {
            await MainActor.run { loading = false }
        }
    }
}

// MARK: - Onglet Marché

struct CryptoMarketTab: View {
    let assets: [CryptoAsset]
    let loading: Bool
    @State private var query = ""
    @State private var selectedCat: String? = nil
    @State private var sortBy = SortMode.rank
    @State private var selected: CryptoAsset? = nil

    enum SortMode: String, CaseIterable {
        case rank = "Rang"
        case change = "Variation 24h"
        case potential = "Potentiel"
        case risk = "Risque faible"
    }

    private let allCats = ["Layer 1","Layer 2","DeFi","Stablecoin","Meme","Exchange","AI/GPU","Privacy","RWA","Commodity"]

    private var filtered: [CryptoAsset] {
        var list = assets
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter { $0.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q) }
        }
        if let cat = selectedCat {
            list = list.filter { cryptoGetCat($0.id) == cat }
        }
        switch sortBy {
        case .rank:      list = list.sorted { $0.rank < $1.rank }
        case .change:    list = list.sorted { $0.change24h > $1.change24h }
        case .potential: list = list.sorted { cryptoSc($0.id).p > cryptoSc($1.id).p }
        case .risk:      list = list.sorted { cryptoSc($0.id).r < cryptoSc($1.id).r }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    // Chips catégorie
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            catChip("Tous", cat: nil)
                            ForEach(allCats, id: \.self) { catChip($0, cat: $0) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))

                    Divider()

                    if loading {
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large).tint(Color.accentColor)
                            Text("Chargement du marché…").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(filtered) { a in
                                CryptoCellRow(asset: a)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selected = a }
                                    .listRowBackground(Theme.card)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Marché")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "BTC, Solana…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(SortMode.allCases, id: \.self) { mode in
                            Button {
                                withAnimation { sortBy = mode }
                            } label: {
                                if sortBy == mode {
                                    Label(mode.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(mode.rawValue)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
            .sheet(item: $selected) { CryptoDetailSheet(asset: $0) }
        }
    }

    private func catChip(_ label: String, cat: String?) -> some View {
        let isSelected = selectedCat == cat
        return Button {
            withAnimation(.spring(duration: 0.2)) {
                selectedCat = (selectedCat == cat && cat != nil) ? nil : cat
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor : Theme.bg2,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ligne crypto

struct CryptoCellRow: View {
    let asset: CryptoAsset
    private var s: (r: Int, p: Int) { cryptoSc(asset.id) }
    private var up: Bool { asset.change24h >= 0 }

    var body: some View {
        HStack(spacing: 12) {
            cryptoIcon(symbol: asset.symbol, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.symbol)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(asset.name) · #\(asset.rank)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(cryptoGetCat(asset.id))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(cryptoGetCatColor(asset.id))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cryptoGetCatColor(asset.id).opacity(0.1), in: Capsule())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(cryptoFmtPrice(asset.price))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Label(String(format: "%.2f%%", abs(asset.change24h)),
                      systemImage: up ? "arrow.up" : "arrow.down")
                    .font(.caption.bold())
                    .foregroundStyle(up ? Color(hex: 0x008F6C) : .red)
                    .monospacedDigit()
                HStack(spacing: 4) {
                    scoreBadge("R\(s.r)", cryptoRiskColor(s.r))
                    scoreBadge("P\(s.p)", cryptoPotColor(s.p))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Onglet Suivi

struct CryptoSuiviTab: View {
    let assets: [CryptoAsset]
    @AppStorage("crypto_watchlist") private var watchlistRaw = "bitcoin,ethereum,solana"
    @AppStorage("crypto_portfolio") private var portfolioRaw = ""
    @State private var mode = 0  // 0 = Watchlist, 1 = Portfolio
    @State private var showAddWatch = false
    @State private var showAddPos = false

    private var watchlist: [String] { watchlistRaw.split(separator: ",").map(String.init) }
    private var watchedAssets: [CryptoAsset] { watchlist.compactMap { id in assets.first { $0.id == id } } }
    private var portfolio: [PortfolioPosition] { decodePortfolio(portfolioRaw) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $mode) {
                        Text("Watchlist").tag(0)
                        Text("Portfolio").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if mode == 0 {
                        watchlistContent
                    } else {
                        portfolioContent
                    }
                }
            }
            .navigationTitle("Suivi")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mode == 0 ? (showAddWatch = true) : (showAddPos = true) } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddWatch) { addWatchSheet }
            .sheet(isPresented: $showAddPos)  { addPositionSheet }
        }
    }

    // MARK: Watchlist

    private var watchlistContent: some View {
        List {
            if watchedAssets.isEmpty {
                ContentUnavailableView("Watchlist vide", systemImage: "eye",
                    description: Text("Appuie sur + pour ajouter des cryptos."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(watchedAssets) { a in
                        CryptoCellRow(asset: a)
                            .listRowBackground(Theme.card)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { removeWatch(a.id) }
                                label: { Label("Retirer", systemImage: "minus.circle") }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func removeWatch(_ id: String) {
        watchlistRaw = watchlist.filter { $0 != id }.joined(separator: ",")
    }
    private func addWatch(_ id: String) {
        var list = watchlist
        if !list.contains(id) { list.append(id) }
        watchlistRaw = list.joined(separator: ",")
    }

    private var addWatchSheet: some View {
        NavigationStack {
            List {
                ForEach(assets.prefix(50)) { a in
                    Button { addWatch(a.id) } label: {
                        HStack {
                            cryptoIcon(symbol: a.symbol, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.symbol).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                                Text(a.name).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if watchlist.contains(a.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Ajouter à la watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showAddWatch = false } } }
        }
    }

    // MARK: Portfolio

    private var portfolioContent: some View {
        List {
            if portfolio.isEmpty {
                ContentUnavailableView("Portfolio vide", systemImage: "chart.pie",
                    description: Text("Appuie sur + pour ajouter une position."))
                    .listRowBackground(Color.clear)
            } else {
                let totalValue = portfolio.compactMap { pos -> Double? in
                    guard let a = assets.first(where: { $0.id == pos.id }) else { return nil }
                    return a.price * pos.quantity
                }.reduce(0, +)
                let totalCost = portfolio.reduce(0.0) { $0 + $1.buyPrice * $1.quantity }
                let totalPnl = totalValue - totalCost

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Valeur totale").font(.caption).foregroundStyle(.secondary)
                            Text(cryptoFmtCap(totalValue)).font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("P&L").font(.caption).foregroundStyle(.secondary)
                            Text(cryptoFmtCap(abs(totalPnl)))
                                .font(.subheadline.bold())
                                .foregroundStyle(totalPnl >= 0 ? Color(hex: 0x008F6C) : .red)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Theme.card)
                }

                Section("Positions") {
                    ForEach(portfolio) { pos in
                        if let a = assets.first(where: { $0.id == pos.id }) {
                            positionRow(a, pos)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func positionRow(_ a: CryptoAsset, _ pos: PortfolioPosition) -> some View {
        let currentValue = a.price * pos.quantity
        let cost = pos.buyPrice * pos.quantity
        let pnl = currentValue - cost
        let pct = cost > 0 ? pnl / cost * 100 : 0
        return HStack(spacing: 12) {
            cryptoIcon(symbol: a.symbol, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.symbol).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text("\(String(format: "%.4f", pos.quantity)) · achat \(cryptoFmtPrice(pos.buyPrice))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(cryptoFmtCap(currentValue))
                    .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(String(format: "%+.1f%%", pct))
                    .font(.caption.bold())
                    .foregroundStyle(pnl >= 0 ? Color(hex: 0x008F6C) : .red)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.card)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { removePosition(pos.id) }
            label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func removePosition(_ id: String) {
        var positions = portfolio
        positions.removeAll { $0.id == id }
        portfolioRaw = encodePortfolio(positions)
    }

    private var addPositionSheet: some View {
        AddPositionSheet(assets: assets) { id, bp, qty in
            var positions = portfolio
            positions.removeAll { $0.id == id }
            positions.append(PortfolioPosition(id: id, buyPrice: bp, quantity: qty))
            portfolioRaw = encodePortfolio(positions)
            showAddPos = false
        }
    }
}

// MARK: - Sheet ajout position

struct AddPositionSheet: View {
    let assets: [CryptoAsset]
    let onAdd: (String, Double, Double) -> Void

    @State private var selectedId: String = "bitcoin"
    @State private var buyPriceStr = ""
    @State private var qtyStr = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Crypto") {
                    Picker("Sélectionner", selection: $selectedId) {
                        ForEach(assets.prefix(50)) { a in
                            Text("\(a.symbol) · \(a.name)").tag(a.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("Position") {
                    TextField("Prix d'achat (USD)", text: $buyPriceStr)
                        .keyboardType(.decimalPad)
                    TextField("Quantité", text: $qtyStr)
                        .keyboardType(.decimalPad)
                }
                if let a = assets.first(where: { $0.id == selectedId }),
                   let bp = Double(buyPriceStr), let qty = Double(qtyStr), bp > 0, qty > 0 {
                    Section("Aperçu") {
                        let currentVal = a.price * qty
                        let cost = bp * qty
                        let pnl = currentVal - cost
                        LabeledContent("Prix actuel", value: cryptoFmtPrice(a.price))
                        LabeledContent("Valeur actuelle", value: cryptoFmtCap(currentVal))
                        LabeledContent("P&L") {
                            Text(cryptoFmtCap(abs(pnl)))
                                .foregroundStyle(pnl >= 0 ? Color(hex: 0x008F6C) : .red)
                        }
                    }
                }
            }
            .navigationTitle("Ajouter une position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        guard let bp = Double(buyPriceStr), let qty = Double(qtyStr), bp > 0, qty > 0 else { return }
                        onAdd(selectedId, bp, qty)
                    }
                    .disabled(Double(buyPriceStr) == nil || Double(qtyStr) == nil)
                }
            }
        }
    }
}

// MARK: - Onglet Alertes

struct CryptoAlertesTab: View {
    let assets: [CryptoAsset]
    @AppStorage("crypto_alerts") private var alertsRaw = ""
    @State private var showAdd = false

    private var alerts: [PriceAlert] { decodeAlerts(alertsRaw) }

    private func isTriggered(_ alert: PriceAlert) -> Bool {
        guard let a = assets.first(where: { $0.id == alert.assetId }) else { return false }
        return alert.direction == "above" ? a.price >= alert.threshold : a.price <= alert.threshold
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                if alerts.isEmpty {
                    ContentUnavailableView(
                        "Aucune alerte",
                        systemImage: "bell.slash",
                        description: Text("Crée une alerte pour être notifié quand un prix atteint ton seuil.")
                    )
                } else {
                    List {
                        ForEach(alerts) { al in
                            alertRow(al)
                                .listRowBackground(isTriggered(al) ? Color(hex: 0x008F6C).opacity(0.08) : Theme.card)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { removeAlert(al) }
                                    label: { Label("Supprimer", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Alertes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddAlertSheet(assets: assets) { onAdd($0) } }
        }
    }

    private func alertRow(_ al: PriceAlert) -> some View {
        let asset = assets.first(where: { $0.id == al.assetId })
        let triggered = isTriggered(al)
        return HStack(spacing: 12) {
            cryptoIcon(symbol: asset?.symbol ?? String(al.assetId.prefix(3)).uppercased(), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset?.symbol ?? al.assetId.uppercased())
                    .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: al.direction == "above" ? "arrow.up" : "arrow.down")
                        .font(.caption.bold())
                        .foregroundStyle(al.direction == "above" ? Color(hex: 0x008F6C) : .red)
                    Text("\(al.direction == "above" ? "Au-dessus de" : "En dessous de") \(cryptoFmtPrice(al.threshold))")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if triggered {
                VStack(spacing: 2) {
                    Image(systemName: "bell.fill").font(.system(size: 14)).foregroundStyle(Color(hex: 0x008F6C))
                    Text("Déclenché").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color(hex: 0x008F6C))
                }
            } else if let a = asset {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(cryptoFmtPrice(a.price)).font(.caption.bold()).foregroundStyle(Theme.textPrimary).monospacedDigit()
                    Text("actuel").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func onAdd(_ al: PriceAlert) {
        var list = alerts
        list.append(al)
        alertsRaw = encodeAlerts(list)
        showAdd = false
    }

    private func removeAlert(_ al: PriceAlert) {
        var list = alerts
        list.removeAll { $0.id == al.id }
        alertsRaw = encodeAlerts(list)
    }
}

// MARK: - Sheet ajout alerte

struct AddAlertSheet: View {
    let assets: [CryptoAsset]
    fileprivate let onAdd: (PriceAlert) -> Void

    @State private var selectedId = "bitcoin"
    @State private var direction = "above"
    @State private var thresholdStr = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Crypto") {
                    Picker("Sélectionner", selection: $selectedId) {
                        ForEach(assets.prefix(50)) { a in
                            Text("\(a.symbol) · \(a.name)").tag(a.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("Condition") {
                    Picker("Sens", selection: $direction) {
                        Text("Au-dessus de").tag("above")
                        Text("En dessous de").tag("below")
                    }
                    .pickerStyle(.segmented)
                    TextField("Seuil en USD", text: $thresholdStr)
                        .keyboardType(.decimalPad)
                    if let a = assets.first(where: { $0.id == selectedId }) {
                        LabeledContent("Prix actuel", value: cryptoFmtPrice(a.price))
                    }
                }
            }
            .navigationTitle("Nouvelle alerte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        guard let thr = Double(thresholdStr), thr > 0 else { return }
                        onAdd(PriceAlert(assetId: selectedId, direction: direction, threshold: thr))
                    }
                    .disabled(Double(thresholdStr) == nil)
                }
            }
        }
    }
}

// MARK: - Onglet Apprendre

private struct CryptoLesson: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let body: String
    let duration: String
    let color: Color
}

private struct CryptoNotion: Identifiable {
    let id = UUID()
    let term: String
    let definition: String
    let color: Color
}

private let cryptoLessons: [CryptoLesson] = [
    CryptoLesson(
        icon: "bitcoinsign.circle.fill",
        title: "Bitcoin — L'or numérique",
        subtitle: "La première crypto-monnaie décentralisée",
        body: "Bitcoin (BTC) a été créé en 2009 par Satoshi Nakamoto. C'est la première monnaie numérique décentralisée : personne ne la contrôle. Il n'en existera jamais plus de 21 millions. Cette rareté programmée la distingue des monnaies traditionnelles.\n\nBitcoin fonctionne grâce à la blockchain : un registre public et immuable tenu par des milliers d'ordinateurs dans le monde. Chaque transaction est vérifiée par ce réseau, rendant la fraude pratiquement impossible.",
        duration: "3 min",
        color: Color(hex: 0xF7931A)
    ),
    CryptoLesson(
        icon: "link.circle.fill",
        title: "La Blockchain expliquée",
        subtitle: "Comment fonctionne le registre décentralisé",
        body: "Une blockchain est une base de données partagée entre des milliers d'ordinateurs. Les données sont regroupées en « blocs » chainés ensemble de façon cryptographique.\n\nUne fois validé, un bloc ne peut pas être modifié sans invalider tous les blocs suivants — c'est ce qui rend la blockchain infalsifiable. C'est la technologie sous-jacente à Bitcoin, Ethereum et la majorité des cryptos.",
        duration: "4 min",
        color: Color(hex: 0x627EEA)
    ),
    CryptoLesson(
        icon: "building.columns.fill",
        title: "DeFi — Finance sans banques",
        subtitle: "Les protocoles financiers décentralisés",
        body: "La finance décentralisée (DeFi) regroupe des services financiers (prêt, emprunt, trading) fonctionnant via des smart contracts — sans intermédiaire bancaire.\n\nExemples : Uniswap permet d'échanger des tokens sans bourse centralisée. Aave permet d'emprunter et de prêter des cryptos. Les fonds restent dans ton wallet : tu gardes le contrôle.\n\nLe risque : les bugs dans les smart contracts peuvent mener à des pertes importantes (« hacks »).",
        duration: "5 min",
        color: Color(hex: 0x9B6CF1)
    ),
    CryptoLesson(
        icon: "exclamationmark.triangle.fill",
        title: "Risque crypto — Lire un score R/P",
        subtitle: "Comment interpréter Risque et Potentiel",
        body: "Dans cette app, chaque crypto reçoit deux scores :\n\n• Risque (R/100) — Plus le score est élevé, plus la volatilité est importante. Un score >70 signifie un actif spéculatif qui peut perdre 80%+ de sa valeur rapidement.\n\n• Potentiel (P/100) — Évalue le potentiel de croissance à moyen terme basé sur la technologie, l'adoption et l'écosystème.\n\nUn bon profil d'investissement : R faible et P élevé. Exemple : BTC (R28, P72).",
        duration: "3 min",
        color: Color(hex: 0x008F6C)
    ),
    CryptoLesson(
        icon: "chart.line.uptrend.xyaxis",
        title: "Layer 1, Layer 2, DeFi",
        subtitle: "Comprendre les catégories",
        body: "• Layer 1 : blockchains de base (Bitcoin, Ethereum, Solana). Elles sécurisent et exécutent les transactions directement.\n\n• Layer 2 : solutions construites au-dessus d'un Layer 1 pour le rendre plus rapide et moins cher (Arbitrum, Optimism sur Ethereum).\n\n• DeFi : protocoles financiers décentralisés construits sur ces blockchains.\n\n• Stablecoins : cryptos dont la valeur est ancrée au dollar (USDT, USDC). Score risque très faible, potentiel faible aussi.",
        duration: "4 min",
        color: Color(hex: 0x3CB2E0)
    ),
    CryptoLesson(
        icon: "wallet.pass.fill",
        title: "Sécuriser son wallet",
        subtitle: "Les bonnes pratiques indispensables",
        body: "Ton wallet contient les clés d'accès à tes cryptos. Si tu perds ces clés, tu perds tout.\n\n• Seed phrase (12-24 mots) : note-la sur papier, jamais sur téléphone ni cloud.\n• Hardware wallet : la solution la plus sûre pour de grandes sommes (Ledger, Trezor).\n• Jamais partager ta clé privée, même avec le « support ».\n• Activer la 2FA sur les exchanges.\n\nRègle d'or : Not your keys, not your coins.",
        duration: "3 min",
        color: Color(hex: 0xE07B3C)
    ),
]

private let cryptoNotions: [CryptoNotion] = [
    CryptoNotion(term: "Blockchain", definition: "Registre décentralisé et immuable, partagé entre des milliers de nœuds.", color: Color(hex: 0x627EEA)),
    CryptoNotion(term: "Smart Contract", definition: "Programme auto-exécutable sur blockchain qui remplace les intermédiaires.", color: Color(hex: 0x9B6CF1)),
    CryptoNotion(term: "Wallet", definition: "Portefeuille numérique stockant tes clés privées pour accéder à tes cryptos.", color: Color(hex: 0x008F6C)),
    CryptoNotion(term: "Seed Phrase", definition: "Suite de 12-24 mots permettant de restaurer ton wallet. Ne jamais partager.", color: Color(hex: 0xE84142)),
    CryptoNotion(term: "Market Cap", definition: "Capitalisation = prix × offre en circulation. Indicateur de taille d'un actif.", color: Color(hex: 0x3CB2E0)),
    CryptoNotion(term: "Halving", definition: "Division par 2 de la récompense des mineurs Bitcoin, tous les ~4 ans.", color: Color(hex: 0xF7931A)),
    CryptoNotion(term: "DEX", definition: "Bourse décentralisée (Uniswap, Raydium). Trading pair à pair sans intermédiaire.", color: Color(hex: 0x9B6CF1)),
    CryptoNotion(term: "CEX", definition: "Bourse centralisée (Binance, Coinbase). Pratique mais tu ne gardes pas les clés.", color: Color(hex: 0xE07B3C)),
    CryptoNotion(term: "Gas Fee", definition: "Frais payés au réseau pour exécuter une transaction (élevés sur Ethereum en période chargée).", color: Color(hex: 0x627EEA)),
    CryptoNotion(term: "Staking", definition: "Bloquer ses cryptos pour valider le réseau et recevoir des récompenses.", color: Color(hex: 0x008F6C)),
    CryptoNotion(term: "HODL", definition: "Stratégie consistant à conserver ses cryptos à long terme malgré la volatilité.", color: Color(hex: 0x3CB2E0)),
    CryptoNotion(term: "FUD", definition: "Fear, Uncertainty, Doubt — informations négatives (vraies ou fausses) qui font baisser les prix.", color: Color(hex: 0xE84142)),
    CryptoNotion(term: "FOMO", definition: "Fear Of Missing Out — peur de rater une hausse. Pousse souvent à acheter au mauvais moment.", color: Color(hex: 0xE07B3C)),
    CryptoNotion(term: "Whale", definition: "Investisseur détenant assez de cryptos pour influencer le marché par ses transactions.", color: Color(hex: 0x627EEA)),
    CryptoNotion(term: "Airdrop", definition: "Distribution gratuite de tokens, souvent pour récompenser les premiers utilisateurs.", color: Color(hex: 0x9B6CF1)),
    CryptoNotion(term: "Bull / Bear", definition: "Bull market = tendance haussière. Bear market = tendance baissière (baisse >20%).", color: Color(hex: 0x008F6C)),
]

struct CryptoLearnTab: View {
    @State private var mode = 0
    @State private var expandedId: UUID? = nil

    private let tint = Color(hex: 0x46C9A8)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $mode) {
                        Text("Leçons").tag(0)
                        Text("Notions").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if mode == 0 {
                        lessonsContent
                    } else {
                        notionsContent
                    }
                }
            }
            .navigationTitle("Apprendre")
            .navigationBarTitleDisplayMode(.large)
        }
        .animation(.spring(duration: 0.28), value: mode)
    }

    private var lessonsContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(cryptoLessons) { lesson in
                    lessonCard(lesson)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func lessonCard(_ lesson: CryptoLesson) -> some View {
        let isExpanded = expandedId == lesson.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    expandedId = isExpanded ? nil : lesson.id
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 14) {
                    IconBadge(icon: lesson.icon, size: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(lesson.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text(lesson.subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(lesson.duration)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 14)
                Text(lesson.body)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(5)
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isExpanded ? Theme.line : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(duration: 0.3), value: isExpanded)
    }

    private var notionsContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(cryptoNotions) { notion in
                    notionCard(notion)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func notionCard(_ notion: CryptoNotion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notion.term)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(notion.definition)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Onglet Info

struct CryptoInfoTab: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                List {
                    Section("Sources") {
                        Label("Prix : CoinMarketCap via proxy sécurisé", systemImage: "server.rack")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        Label("Scores R/P : analyse statique + dynamique", systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        Label("Chatbot : règles basées sur données live", systemImage: "brain")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    Section("Score Risque") {
                        scoreInfoRow("0–44", "Risque FAIBLE", Color(hex: 0x008F6C))
                        scoreInfoRow("45–69", "Risque MOYEN", .orange)
                        scoreInfoRow("70–100", "Risque ÉLEVÉ", .red)
                    }
                    Section("Score Potentiel") {
                        scoreInfoRow("0–34", "Potentiel FAIBLE", .secondary)
                        scoreInfoRow("35–64", "Potentiel MOYEN", .orange)
                        scoreInfoRow("65–100", "Potentiel FORT", Color(hex: 0x008F6C))
                    }
                    Section("À propos") {
                        LabeledContent("Version", value: "LifeOS Crypto Module 1.0")
                        LabeledContent("Cryptos scorées", value: "\(cryptoScores.count)")
                        LabeledContent("Données", value: "Temps réel")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func scoreInfoRow(_ range: String, _ label: String, _ color: Color) -> some View {
        HStack {
            Text(range).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(label).font(.subheadline).foregroundStyle(color)
        }
    }
}

// MARK: - Détail crypto (sheet)

struct CryptoDetailSheet: View {
    let asset: CryptoAsset
    @Environment(\.dismiss) private var dismiss
    private var s: (r: Int, p: Int) { cryptoSc(asset.id) }
    private var up: Bool { asset.change24h >= 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        // Prix
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(asset.symbol).font(.system(size: 28, weight: .black)).foregroundStyle(Theme.textPrimary)
                                Text(asset.name).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                HStack(spacing: 4) {
                                    Text(cryptoGetCat(asset.id))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(cryptoGetCatColor(asset.id))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(cryptoGetCatColor(asset.id).opacity(0.1), in: Capsule())
                                    Text("#\(asset.rank)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(cryptoFmtPrice(asset.price))
                                    .font(.title2.bold()).foregroundStyle(Theme.textPrimary).monospacedDigit()
                                Label(String(format: "%.2f%%", abs(asset.change24h)),
                                      systemImage: up ? "arrow.up" : "arrow.down")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(up ? Color(hex: 0x008F6C) : .red)
                            }
                        }
                        .padding(Theme.pad)
                        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                        // Scores
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Analyse").font(.headline).foregroundStyle(Theme.textPrimary)
                            detailScoreBar("Risque — \(cryptoRiskLabel(s.r))", value: s.r, color: cryptoRiskColor(s.r))
                            detailScoreBar("Potentiel — \(cryptoPotLabel(s.p))", value: s.p, color: cryptoPotColor(s.p))
                            Text(s.r < 40 ? "Profil conservateur. Actif établi avec bonne liquidité." :
                                 s.r < 70 ? "Profil modéré. Volatilité significative à surveiller." :
                                 "Profil spéculatif. Position à limiter en % de portefeuille.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(Theme.pad)
                        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                        // Stats marché
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Marché").font(.headline).foregroundStyle(Theme.textPrimary).padding(.bottom, 8)
                            detailStatRow("Cap. marché", cryptoFmtCap(asset.marketCap))
                            Divider()
                            detailStatRow("Volume 24h", cryptoFmtCap(asset.volume24h))
                            Divider()
                            detailStatRow("Variation 24h", String(format: "%+.2f%%", asset.change24h))
                        }
                        .padding(Theme.pad)
                        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }
                    .padding(Theme.pad)
                }
            }
            .navigationTitle(asset.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }

    private func detailScoreBar(_ label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(value)/100").font(.subheadline.bold()).foregroundStyle(color).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stroke).frame(height: 6)
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(value) / 100, height: 6)
                }
            }.frame(height: 6)
        }
    }

    private func detailStatRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }.padding(.vertical, 10)
    }
}

// MARK: - Composants partagés

private func cryptoIcon(symbol: String, size: CGFloat) -> some View {
    let sym = String(symbol.prefix(2))
    let palette: [Color] = [
        Color(hex: 0xF7931A), Color(hex: 0x627EEA), Color(hex: 0x9945FF),
        Color(hex: 0xE84142), Color(hex: 0x26A17B), Color(hex: 0x0033AD),
        Color(hex: 0xE6007A), Color(hex: 0x2775CA), Color(hex: 0xFF6B35),
    ]
    let col = palette[Int(symbol.unicodeScalars.first?.value ?? 65) % palette.count]
    return ZStack {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(col.opacity(0.15)).frame(width: size, height: size)
        Text(sym).font(.system(size: size * 0.32, weight: .black)).foregroundStyle(col)
    }
}

private func scoreBadge(_ label: String, _ color: Color) -> some View {
    Text(label)
        .font(.system(size: 10, weight: .black)).foregroundStyle(color)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
}

// MARK: - Point d'entrée depuis InvestModule

struct CryptoMarketView: View {
    @State private var showApp = false
    var body: some View {
        Button { showApp = true } label: {
            Label("Ouvrir Crypto", systemImage: "bitcoinsign.circle.fill")
        }
        .fullScreenCover(isPresented: $showApp) {
            CryptoAppView()
        }
    }
}
