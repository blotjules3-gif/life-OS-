import SwiftUI

// MARK: - Modèle

struct CryptoAsset: Identifiable, Hashable {
    let id: String
    let symbol: String
    let name: String
    let price: Double
    let change24h: Double
    let marketCap: Double
    let volume24h: Double
    let rank: Int
}

struct CryptoMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}

// MARK: - Scores

private let scores: [String: (r: Int, p: Int)] = [
    "bitcoin": (28,72), "ethereum": (42,68), "tether": (12,18),
    "binancecoin": (48,55), "ripple": (68,58), "usd-coin": (10,16),
    "solana": (55,88), "tron": (58,48), "dogecoin": (88,45),
    "hyperliquid": (55,72), "cardano": (38,52), "bitcoin-cash": (55,42),
    "chainlink": (50,72), "monero": (65,45), "stellar": (50,48),
    "avalanche-2": (58,62), "sui": (60,82), "the-open-network": (58,68),
    "shiba-inu": (90,35), "bittensor": (72,80), "uniswap": (52,62),
    "polkadot": (52,60), "near": (58,65), "mantle": (60,65),
    "hedera-hashgraph": (52,60), "litecoin": (48,40),
    "matic-network": (55,65), "arbitrum": (55,72),
    "injective-protocol": (62,78), "kaspa": (68,70),
    "pepe": (90,38), "aave": (52,65), "dai": (14,15),
    "cosmos": (55,58), "optimism": (55,68), "aptos": (65,70),
]

private let categories: [String: String] = [
    "bitcoin":"Layer 1","ethereum":"Layer 1","tether":"Stablecoin",
    "binancecoin":"Exchange","ripple":"Layer 1","usd-coin":"Stablecoin",
    "solana":"Layer 1","tron":"Layer 1","dogecoin":"Meme",
    "hyperliquid":"DeFi","cardano":"Layer 1","bitcoin-cash":"Layer 1",
    "chainlink":"DeFi","monero":"Privacy","stellar":"Layer 1",
    "avalanche-2":"Layer 1","sui":"Layer 1","the-open-network":"Layer 1",
    "shiba-inu":"Meme","bittensor":"AI/GPU","uniswap":"DeFi",
    "polkadot":"Layer 1","near":"Layer 1","mantle":"Layer 2",
    "hedera-hashgraph":"Layer 1","litecoin":"Layer 1",
    "matic-network":"Layer 2","arbitrum":"Layer 2",
    "injective-protocol":"DeFi","kaspa":"Layer 1",
    "pepe":"Meme","aave":"DeFi","dai":"Stablecoin",
    "cosmos":"Layer 1","optimism":"Layer 2","aptos":"Layer 1",
]

private func sc(_ id: String) -> (r: Int, p: Int) { scores[id] ?? (r:50, p:50) }
private func rC(_ r: Int) -> Color { r >= 70 ? .red : r >= 45 ? .orange : Color(hex:0x008F6C) }
private func pC(_ p: Int) -> Color { p >= 65 ? Color(hex:0x008F6C) : p >= 35 ? .orange : .secondary }
private func rL(_ r: Int) -> String { r >= 70 ? "ÉLEVÉ" : r >= 45 ? "MOYEN" : "FAIBLE" }
private func pL(_ p: Int) -> String { p >= 65 ? "FORT" : p >= 35 ? "MOYEN" : "FAIBLE" }

private let PROXY = "https://riskcrypto-proxy.httpsrisckcryptoproxyworkersdev.workers.dev/market"

// MARK: - Formatters

private func fmtPrice(_ p: Double) -> String {
    guard p > 0 else { return "···" }
    let a = abs(p)
    if a >= 10_000 { return "$\(Int(a).formatted())" }
    if a >= 100    { return "$\(Int(a).formatted())" }
    if a >= 1      { return String(format:"$%.2f", a) }
    if a >= 0.01   { return String(format:"$%.4f", a) }
    return String(format:"$%.6f", a)
}
private func fmtCap(_ n: Double) -> String {
    if n <= 0    { return "--" }
    if n >= 1e12 { return String(format:"$%.2fT", n/1e12) }
    if n >= 1e9  { return String(format:"$%.1fB", n/1e9) }
    return String(format:"$%.0fM", n/1e6)
}

// MARK: - Fetch

private func fetchMarket() async throws -> [CryptoAsset] {
    guard let url = URL(string: PROXY) else { throw URLError(.badURL) }
    let (data, _) = try await URLSession.shared.data(from: url)
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let arr = json["data"] as? [[String: Any]] {
        return arr.compactMap { d in
            guard let slug = d["slug"] as? String ?? d["id"] as? String,
                  let q = (d["quote"] as? [String: Any])?["USD"] as? [String: Any]
            else { return nil }
            return CryptoAsset(
                id: slug.lowercased(), symbol: (d["symbol"] as? String ?? "").uppercased(),
                name: d["name"] as? String ?? "", price: q["price"] as? Double ?? 0,
                change24h: q["percent_change_24h"] as? Double ?? 0,
                marketCap: q["market_cap"] as? Double ?? 0,
                volume24h: q["volume_24h"] as? Double ?? 0,
                rank: d["cmc_rank"] as? Int ?? 0)
        }
    }
    if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
        return arr.compactMap { d in
            guard let id = d["id"] as? String else { return nil }
            return CryptoAsset(
                id: id, symbol: (d["symbol"] as? String ?? "").uppercased(),
                name: d["name"] as? String ?? "", price: d["current_price"] as? Double ?? 0,
                change24h: d["price_change_percentage_24h"] as? Double ?? 0,
                marketCap: d["market_cap"] as? Double ?? 0,
                volume24h: d["total_volume"] as? Double ?? 0,
                rank: d["market_cap_rank"] as? Int ?? 0)
        }
    }
    return []
}

// MARK: - Chatbot

private func cryptoAnswer(query: String, assets: [CryptoAsset]) -> String {
    let q = query.lowercased()

    // Cherche une crypto mentionnée
    let found = assets.first { a in
        q.contains(a.symbol.lowercased()) || q.contains(a.name.lowercased())
    }

    if let a = found {
        let s = sc(a.id)
        let up = a.change24h >= 0
        let change = String(format: "%+.2f%%", a.change24h)
        if q.contains("risque") || q.contains("risk") || q.contains("dangereux") || q.contains("safe") {
            return "\(a.symbol) a un score de risque de \(s.r)/100 — \(rL(s.r)). \(s.r < 40 ? "C'est un actif relativement établi." : s.r < 70 ? "Volatilité significative à surveiller." : "Profil spéculatif, ne pas surpondérer.")"
        }
        if q.contains("potentiel") || q.contains("hausse") || q.contains("upside") {
            return "\(a.symbol) a un potentiel de \(s.p)/100 — \(pL(s.p)). \(s.p >= 65 ? "Fort potentiel de croissance selon l'analyse." : s.p >= 35 ? "Potentiel modéré." : "Potentiel limité à ce stade.")"
        }
        if q.contains("prix") || q.contains("price") || q.contains("vaut") || q.contains("coûte") {
            return "\(a.symbol) vaut actuellement \(fmtPrice(a.price)) (\(change) en 24h). Cap. marché : \(fmtCap(a.marketCap))."
        }
        if q.contains("acheter") || q.contains("investir") || q.contains("buy") {
            return "\(a.symbol) — Risque \(s.r)/100, Potentiel \(s.p)/100. \(s.r < 40 && s.p >= 60 ? "Profil intéressant : faible risque, bon potentiel." : s.r >= 70 ? "Risque élevé — réserve une petite position si tu y crois." : "Analyse à compléter avec ton propre suivi.")"
        }
        return "\(a.symbol) · \(fmtPrice(a.price)) · \(change) 24h\nRisque : \(s.r)/100 (\(rL(s.r))) · Potentiel : \(s.p)/100 (\(pL(s.p)))\nCatégorie : \(categories[a.id] ?? "Crypto")"
    }

    // Questions générales
    if q.contains("meilleur") || q.contains("top") || q.contains("plus haut") || q.contains("performer") {
        let top = assets.sorted { $0.change24h > $1.change24h }.prefix(3)
        let list = top.map { "\($0.symbol) \(String(format:"%+.1f%%", $0.change24h))" }.joined(separator: " · ")
        return "Top 3 performances 24h : \(list)"
    }
    if q.contains("pire") || q.contains("baisse") || q.contains("chute") {
        let bot = assets.sorted { $0.change24h < $1.change24h }.prefix(3)
        let list = bot.map { "\($0.symbol) \(String(format:"%+.1f%%", $0.change24h))" }.joined(separator: " · ")
        return "Plus fortes baisses 24h : \(list)"
    }
    if q.contains("bitcoin") || q.contains("btc") {
        if let btc = assets.first(where: { $0.id == "bitcoin" }) {
            return "Bitcoin · \(fmtPrice(btc.price)) · \(String(format:"%+.2f%%", btc.change24h)) 24h\nRisque : 28/100 (FAIBLE) · Potentiel : 72/100 (FORT)"
        }
    }
    if q.contains("faible risque") || q.contains("safe") || q.contains("stable") {
        let safe = assets.filter { sc($0.id).r < 35 }.prefix(4)
        let list = safe.map { $0.symbol }.joined(separator: ", ")
        return "Cryptos à faible risque dans le top 50 : \(list.isEmpty ? "BTC, ETH, DAI" : list)"
    }
    if q.contains("fort potentiel") || q.contains("meilleur potentiel") {
        let high = assets.filter { sc($0.id).p >= 70 }.sorted { sc($0.id).p > sc($1.id).p }.prefix(4)
        let list = high.map { "\($0.symbol) (P\(sc($0.id).p))" }.joined(separator: ", ")
        return "Cryptos à fort potentiel : \(list.isEmpty ? "SOL, SUI, TAO" : list)"
    }
    if q.contains("marché") || q.contains("market") || q.contains("global") {
        let up = assets.filter { $0.change24h > 0 }.count
        let avg = assets.isEmpty ? 0 : assets.reduce(0.0) { $0 + $1.change24h } / Double(assets.count)
        return "Marché global : \(up)/\(assets.count) cryptos en hausse. Variation moyenne 24h : \(String(format:"%+.2f%%", avg))."
    }
    if q.contains("bonjour") || q.contains("salut") || q.contains("hello") {
        return "Salut ! Je connais les prix en temps réel et les scores Risque/Potentiel de toutes les cryptos du top 50. Demande-moi par ex. : « quel est le risque de Solana ? » ou « meilleurs performers du jour »."
    }
    if q.contains("merci") { return "Avec plaisir !" }
    return "Je peux t'aider sur : prix d'une crypto, son risque, son potentiel, les meilleurs/pires performers du jour, ou le sentiment de marché. Reformule avec un de ces mots."
}

// MARK: - App Crypto (full-screen)

enum CryptoTab: String, CaseIterable {
    case market, suivi, chat, profil
    var label: String {
        switch self {
        case .market: return "Marché"
        case .suivi:  return "Suivi"
        case .chat:   return "Chat"
        case .profil: return "Profil"
        }
    }
    var icon: String {
        switch self {
        case .market: return "chart.bar.xaxis"
        case .suivi:  return "eye"
        case .chat:   return "bubble.left.and.bubble.right"
        case .profil: return "person"
        }
    }
    var iconFill: String {
        switch self {
        case .market: return "chart.bar.xaxis.ascending.badge.clock"
        case .suivi:  return "eye.fill"
        case .chat:   return "bubble.left.and.bubble.right.fill"
        case .profil: return "person.fill"
        }
    }
}

struct CryptoAppView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: CryptoTab = .market
    @State private var assets: [CryptoAsset] = []
    @State private var loading = true
    @State private var chatMessages: [CryptoMessage] = [
        CryptoMessage(fromUser: false, text: "Salut ! Je connais les prix en temps réel et les scores Risque/Potentiel de toutes les cryptos. Pose-moi une question.")
    ]
    @Namespace private var ns

    private static let barBg  = Color.white
    private static let selBg  = Color(white:0.92)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Contenu
            Group {
                switch tab {
                case .market: CryptoMarketTab(assets: assets, loading: loading)
                case .suivi:  CryptoSuiviTab(assets: assets)
                case .chat:   CryptoChatTab(assets: assets, messages: $chatMessages)
                case .profil: CryptoProfilTab(onClose: { dismiss() })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }

            // Barre d'onglets style dark pill
            cryptoTabBar
        }
        .ignoresSafeArea(.keyboard)
        .task { await loadData() }
    }

    // MARK: Barre dark pill

    private var cryptoTabBar: some View {
        HStack(spacing: 0) {
            ForEach(CryptoTab.allCases, id: \.rawValue) { t in
                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.35)) { tab = t }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        if tab == t {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Self.selBg)
                                .frame(width: 58, height: 44)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                        VStack(spacing: 3) {
                            Image(systemName: tab == t ? t.iconFill : t.icon)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .animation(.spring(duration: 0.28), value: tab)
                            Text(t.label)
                                .font(.system(size: 9, weight: tab == t ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(tab == t ? 1 : 0.55))
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
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 10)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func loadData() async {
        do {
            let data = try await fetchMarket()
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
    @State private var selected: CryptoAsset? = nil

    private var filtered: [CryptoAsset] {
        guard !query.isEmpty else { return assets }
        let q = query.lowercased()
        return assets.filter { $0.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                if loading {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(AppCategory.invest.tint)
                        Text("Chargement du marché…").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(filtered) { a in
                            CryptoRow(asset: a)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = a }
                                .listRowBackground(Theme.card)
                                .listRowInsets(EdgeInsets(top:6, leading:16, bottom:6, trailing:16))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Marché")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Rechercher…")
            .sheet(item: $selected) { CryptoDetailSheet(asset: $0) }
        }
    }
}

// MARK: - Ligne crypto

struct CryptoRow: View {
    let asset: CryptoAsset
    private var s: (r:Int,p:Int) { sc(asset.id) }
    private var up: Bool { asset.change24h >= 0 }

    var body: some View {
        HStack(spacing: 12) {
            cryptoIcon(symbol: asset.symbol, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.symbol).font(.system(.subheadline, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("\(asset.name) · #\(asset.rank)").font(.caption).foregroundStyle(Theme.textSecondary)
                Text(categories[asset.id] ?? "Crypto").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtPrice(asset.price))
                    .font(.system(.subheadline, weight: .bold)).foregroundStyle(Theme.textPrimary).monospacedDigit()
                Label(String(format:"%.2f%%", abs(asset.change24h)),
                      systemImage: up ? "arrow.up" : "arrow.down")
                    .font(.caption.bold()).foregroundStyle(up ? Color(hex:0x008F6C) : .red).monospacedDigit()
                HStack(spacing:4) {
                    scoreBadge("R\(s.r)", rC(s.r))
                    scoreBadge("P\(s.p)", pC(s.p))
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
    @State private var showAdd = false

    private var watchlist: [String] {
        watchlistRaw.split(separator: ",").map(String.init)
    }
    private var watchedAssets: [CryptoAsset] {
        watchlist.compactMap { id in assets.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                List {
                    if watchedAssets.isEmpty {
                        ContentUnavailableView("Watchlist vide",
                            systemImage: "eye", description: Text("Ajoute des cryptos à surveiller."))
                            .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(watchedAssets) { a in
                                CryptoRow(asset: a)
                                    .listRowBackground(Theme.card)
                                    .listRowInsets(EdgeInsets(top:6, leading:16, bottom:6, trailing:16))
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { remove(a.id) }
                                        label: { Label("Retirer", systemImage: "minus.circle") }
                                    }
                            }
                        } header: {
                            Text("MA WATCHLIST").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Suivi")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            List {
                ForEach(assets.prefix(50)) { a in
                    Button {
                        add(a.id)
                    } label: {
                        HStack {
                            cryptoIcon(symbol: a.symbol, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.symbol).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                                Text(a.name).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if watchlist.contains(a.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppCategory.invest.tint)
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { showAdd = false }
                }
            }
        }
    }

    private func add(_ id: String) {
        var list = watchlist
        if !list.contains(id) { list.append(id) }
        watchlistRaw = list.joined(separator: ",")
    }
    private func remove(_ id: String) {
        watchlistRaw = watchlist.filter { $0 != id }.joined(separator: ",")
    }
}

// MARK: - Onglet Chat

struct CryptoChatTab: View {
    let assets: [CryptoAsset]
    @Binding var messages: [CryptoMessage]
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(messages) { m in
                                    chatBubble(m)
                                        .id(m.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: messages.count) { _, _ in
                            withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                        }
                    }

                    // Chips de suggestions rapides
                    if messages.count <= 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button {
                                        input = s; send()
                                    } label: {
                                        Text(s)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(AppCategory.invest.tint)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(AppCategory.invest.tint.opacity(0.1),
                                                        in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    }

                    // Barre de saisie
                    HStack(spacing: 10) {
                        TextField("Demande-moi quelque chose…", text: $input, axis: .vertical)
                            .font(.system(size: 15))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .focused($focused)
                            .lineLimit(4)
                            .onSubmit { send() }
                            .submitLabel(.send)

                        if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(action: send) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(AppCategory.invest.tint, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .animation(.spring(duration: 0.2), value: input.isEmpty)
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func chatBubble(_ m: CryptoMessage) -> some View {
        HStack {
            if m.fromUser { Spacer(minLength: 60) }
            Text(m.text)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    m.fromUser ? AppCategory.invest.tint : Theme.card,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .foregroundStyle(m.fromUser ? .white : Theme.textPrimary)
            if !m.fromUser { Spacer(minLength: 60) }
        }
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        withAnimation {
            messages.append(CryptoMessage(fromUser: true, text: q))
            input = ""
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                messages.append(CryptoMessage(fromUser: false, text: cryptoAnswer(query: q, assets: assets)))
            }
        }
    }

    private let suggestions = [
        "Meilleurs performers ?", "Risque de Solana", "Prix de Bitcoin",
        "Cryptos à faible risque", "Fort potentiel ?", "Marché global"
    ]
}

// MARK: - Onglet Profil

struct CryptoProfilTab: View {
    let onClose: () -> Void
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                List {
                    Section {
                        Label("Données : CoinMarketCap via proxy", systemImage: "server.rack")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        Label("Scores Risque/Potentiel : analyse statique", systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    } header: { Text("Sources") }

                    Section {
                        Button(role: .destructive) { onClose() } label: {
                            Label("Quitter Crypto", systemImage: "xmark.circle")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Détail (sheet)

struct CryptoDetailSheet: View {
    let asset: CryptoAsset
    @Environment(\.dismiss) private var dismiss
    private var s: (r:Int,p:Int) { sc(asset.id) }
    private var up: Bool { asset.change24h >= 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Prix
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(asset.symbol).font(.system(size: 28, weight: .black)).foregroundStyle(Theme.textPrimary)
                                Text(asset.name).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                Text(categories[asset.id] ?? "Crypto").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(fmtPrice(asset.price)).font(.title2.bold()).foregroundStyle(Theme.textPrimary).monospacedDigit()
                                Label(String(format:"%.2f%%", abs(asset.change24h)),
                                      systemImage: up ? "arrow.up" : "arrow.down")
                                    .font(.subheadline.bold()).foregroundStyle(up ? Color(hex:0x008F6C) : .red)
                            }
                        }.card()

                        // Scores
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Analyse").font(.headline).foregroundStyle(Theme.textPrimary)
                            scoreBar("Risque — \(rL(s.r))", value: s.r, color: rC(s.r))
                            scoreBar("Potentiel — \(pL(s.p))", value: s.p, color: pC(s.p))
                            Text(s.r < 40 ? "Profil conservateur. Actif établi." : s.r < 70 ? "Profil modéré. Surveiller les supports." : "Profil spéculatif. Ne pas surpondérer.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }.card()

                        // Stats
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Marché").font(.headline).foregroundStyle(Theme.textPrimary).padding(.bottom, 10)
                            statRow("Cap. marché", fmtCap(asset.marketCap))
                            Divider()
                            statRow("Volume 24h", fmtCap(asset.volume24h))
                            Divider()
                            statRow("Rang", "#\(asset.rank)")
                        }.card()
                    }.padding(Theme.pad)
                }
            }
            .navigationTitle(asset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }

    private func scoreBar(_ label: String, value: Int, color: Color) -> some View {
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

    private func statRow(_ label: String, _ value: String) -> some View {
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
        Color(hex:0xF7931A), Color(hex:0x627EEA), Color(hex:0x9945FF),
        Color(hex:0xE84142), Color(hex:0x26A17B), Color(hex:0x0033AD),
        Color(hex:0xE6007A), Color(hex:0x2775CA), Color(hex:0xFF6B35),
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
