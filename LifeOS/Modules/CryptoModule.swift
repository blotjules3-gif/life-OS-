import SwiftUI

// MARK: - Modèles

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

fileprivate struct PortfolioPosition: Identifiable {
    let id: String
    var buyPrice: Double
    var quantity: Double
}

private struct PriceAlert: Identifiable {
    var id: String { "\(assetId):\(direction):\(threshold)" }
    let assetId: String
    let direction: String   // "above" ou "below"
    let threshold: Double
}

// MARK: - Scores (source : App.js §SC)

private let scores: [String: (r: Int, p: Int)] = [
    "bitcoin": (28, 72), "ethereum": (42, 68), "tether": (12, 18),
    "binancecoin": (48, 55), "ripple": (68, 58), "usd-coin": (10, 16),
    "solana": (55, 88), "tron": (58, 48), "figure-heloc": (18, 22),
    "dogecoin": (88, 45), "whitebit": (55, 40), "usds": (10, 14),
    "hyperliquid": (55, 72), "leo-token": (45, 38), "cardano": (38, 52),
    "bitcoin-cash": (55, 42), "chainlink": (50, 72), "monero": (65, 45),
    "zcash": (65, 50), "ethena-usde": (32, 22), "canton-network": (65, 52),
    "stellar": (50, 48), "memecore": (90, 35), "dai": (14, 15),
    "litecoin": (48, 40), "usd1-wlfi": (25, 15), "paypal-usd": (12, 14),
    "avalanche-2": (58, 62), "rain": (68, 55), "hedera-hashgraph": (52, 60),
    "sui": (60, 82), "the-open-network": (58, 68), "shiba-inu": (90, 35),
    "crypto-com-chain": (55, 45), "hashnote-usyc": (12, 18), "tether-gold": (18, 30),
    "ravedao": (82, 40), "world-liberty-financial": (78, 42), "bittensor": (72, 80),
    "blackrock-usd-institutional-digital-liquidity-fund": (10, 16),
    "pax-gold": (16, 30), "mantle": (60, 65), "global-dollar": (15, 14),
    "uniswap": (52, 62), "polkadot": (52, 60), "near": (58, 65),
    "falcon-finance": (28, 18), "okb": (52, 42), "sky": (52, 55),
    "pi-network": (82, 48), "matic-network": (55, 65), "aptos": (65, 70),
    "cosmos": (55, 58), "arbitrum": (55, 72), "optimism": (55, 68),
    "injective": (62, 78), "kaspa": (68, 70), "render-token": (62, 78),
    "bonk": (88, 40), "wif": (90, 42), "usdd": (38, 18), "pepe": (90, 38),
    "aave": (52, 65), "internet-computer": (62, 55), "ripple-usd": (15, 16),
    "bitget-token": (55, 42), "ethereum-classic": (62, 42),
]

// MARK: - Catégories (source : App.js §CATS)

private let categories: [String: String] = [
    "bitcoin": "Layer 1", "ethereum": "Layer 1", "tether": "Stablecoin",
    "binancecoin": "Exchange", "ripple": "Layer 1", "usd-coin": "Stablecoin",
    "solana": "Layer 1", "tron": "Layer 1", "figure-heloc": "RWA",
    "dogecoin": "Meme", "whitebit": "Exchange", "usds": "Stablecoin",
    "hyperliquid": "DeFi", "leo-token": "Exchange", "cardano": "Layer 1",
    "bitcoin-cash": "Layer 1", "chainlink": "DeFi", "monero": "Privacy",
    "zcash": "Privacy", "ethena-usde": "Stablecoin", "canton-network": "Layer 1",
    "stellar": "Layer 1", "memecore": "Meme", "dai": "Stablecoin",
    "litecoin": "Layer 1", "usd1-wlfi": "Stablecoin", "paypal-usd": "Stablecoin",
    "avalanche-2": "Layer 1", "rain": "DeFi", "hedera-hashgraph": "Layer 1",
    "sui": "Layer 1", "the-open-network": "Layer 1", "shiba-inu": "Meme",
    "crypto-com-chain": "Exchange",
    "hashnote-usyc": "RWA", "tether-gold": "Commodity",
    "ravedao": "Meme", "world-liberty-financial": "DeFi", "bittensor": "AI/GPU",
    "blackrock-usd-institutional-digital-liquidity-fund": "RWA",
    "pax-gold": "Commodity", "mantle": "Layer 2", "global-dollar": "Stablecoin",
    "uniswap": "DeFi", "polkadot": "Layer 1", "near": "Layer 1",
    "falcon-finance": "Stablecoin", "okb": "Exchange", "sky": "DeFi",
    "pi-network": "Layer 1", "matic-network": "Layer 2", "aptos": "Layer 1",
    "cosmos": "Layer 1", "arbitrum": "Layer 2", "optimism": "Layer 2",
    "injective": "DeFi", "kaspa": "Layer 1", "render-token": "AI/GPU",
    "bonk": "Meme", "wif": "Meme", "usdd": "Stablecoin", "pepe": "Meme",
    "aave": "DeFi", "internet-computer": "Layer 1", "ripple-usd": "Stablecoin",
    "bitget-token": "Exchange", "ethereum-classic": "Layer 1",
]

private let catColors: [String: Color] = [
    "Layer 1": Color(hex: 0x3CB2E0), "Layer 2": Color(hex: 0x6C7BF1),
    "DeFi": Color(hex: 0x9B6CF1), "Stablecoin": Color(hex: 0x4CC38A),
    "Meme": Color(hex: 0xE0A23C), "Exchange": Color(hex: 0xE07B3C),
    "Privacy": Color(hex: 0x8A93A8), "AI/GPU": Color(hex: 0x9B6CF1),
    "Commodity": Color(hex: 0xE0A23C), "RWA": Color(hex: 0x4CC38A),
]

// MARK: - Helpers catégorie

private func guessCategory(_ id: String) -> String {
    let s = id.lowercased()
    let stables = ["usdt","usdc","usde","usdd","dai","busd","frax","pyusd","fdusd","usds",
                   "usdb","usdtb","usdb","nusd","gusd","rlusd","crvusd","ageur","eurs"]
    if stables.contains(s) || s.hasSuffix("-usd") || s.hasSuffix("usd") || s.contains("stable") { return "Stablecoin" }
    let rwa = ["buidl","heloc","hashnote","blackrock","anemoy","spiko","fidelity","superstate","ondo-us"]
    if rwa.contains(where: { s.contains($0) }) || s.hasSuffix("rwa") { return "RWA" }
    if s.contains("gold") || s.contains("silver") || s.contains("paxg") { return "Commodity" }
    let meme = ["dogecoin","shiba-inu","pepe","bonk","wif","memecore","ravedao","floki","brett",
                "fartcoin","turbo","neiro","bome","andy","popcat"]
    if meme.contains(s) || s.hasSuffix("inu") || s.contains("meme") { return "Meme" }
    let ai = ["bittensor","render-token","fetch-ai","ocean-protocol","virtuals-protocol","grass"]
    if ai.contains(s) { return "AI/GPU" }
    let l2 = ["arbitrum","optimism","mantle","matic-network","polygon","starknet","zksync","scroll"]
    if l2.contains(s) { return "Layer 2" }
    let defi = ["uniswap","aave","hyperliquid","injective","sky","compound","sushi","1inch",
                "gmx","dydx","maker","pancake","morpho","aerodrome","lido","pendle","raydium"]
    if defi.contains(s) || s.contains("swap") || s.contains("defi") { return "DeFi" }
    if ["monero","zcash","dash","decred","beldex"].contains(s) { return "Privacy" }
    let exc = ["binancecoin","okb","leo-token","crypto-com-chain","whitebit","bitget-token","gatechain"]
    if exc.contains(s) { return "Exchange" }
    return "Layer 1"
}

private func getCat(_ id: String) -> String { categories[id] ?? guessCategory(id) }
private func getCatColor(_ id: String) -> Color { catColors[getCat(id)] ?? Color(hex: 0x3CB2E0) }

// MARK: - Helpers scores

private let PROXY = "https://riskcrypto-proxy.httpsrisckcryptoproxyworkersdev.workers.dev/market"

private func sc(_ id: String) -> (r: Int, p: Int) { scores[id] ?? (r: 50, p: 50) }
private func rC(_ r: Int) -> Color { r >= 70 ? .red : r >= 45 ? .orange : Color(hex: 0x008F6C) }
private func pC(_ p: Int) -> Color { p >= 65 ? Color(hex: 0x008F6C) : p >= 35 ? .orange : .secondary }
private func rL(_ r: Int) -> String { r >= 70 ? "ÉLEVÉ" : r >= 45 ? "MOYEN" : "FAIBLE" }
private func pL(_ p: Int) -> String { p >= 65 ? "FORT" : p >= 35 ? "MOYEN" : "FAIBLE" }

private func fmtPrice(_ p: Double) -> String {
    guard p > 0 else { return "···" }
    let a = abs(p)
    if a >= 10_000 { return "$\(Int(a).formatted())" }
    if a >= 100    { return "$\(Int(a).formatted())" }
    if a >= 1      { return String(format: "$%.2f", a) }
    if a >= 0.01   { return String(format: "$%.4f", a) }
    return String(format: "$%.6f", a)
}
private func fmtCap(_ n: Double) -> String {
    if n <= 0    { return "--" }
    if n >= 1e12 { return String(format: "$%.2fT", n / 1e12) }
    if n >= 1e9  { return String(format: "$%.1fB", n / 1e9) }
    return String(format: "$%.0fM", n / 1e6)
}

// MARK: - Fetch marché

private func fetchMarket() async throws -> [CryptoAsset] {
    guard let url = URL(string: PROXY) else { throw URLError(.badURL) }
    let (data, _) = try await URLSession.shared.data(from: url)
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let arr = json["data"] as? [[String: Any]] {
        return arr.compactMap { d -> CryptoAsset? in
            guard let slug = (d["slug"] as? String) ?? (d["id"] as? String),
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
        return arr.compactMap { d -> CryptoAsset? in
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
    let found = assets.first { a in
        q.contains(a.symbol.lowercased()) || q.contains(a.name.lowercased())
    }
    if let a = found {
        let s = sc(a.id)
        let change = String(format: "%+.2f%%", a.change24h)
        if q.contains("risque") || q.contains("risk") || q.contains("dangereux") || q.contains("safe") {
            return "\(a.symbol) — Risque \(s.r)/100 (\(rL(s.r))). \(s.r < 40 ? "Actif établi." : s.r < 70 ? "Volatilité à surveiller." : "Profil spéculatif, ne pas surpondérer.")"
        }
        if q.contains("potentiel") || q.contains("hausse") || q.contains("upside") {
            return "\(a.symbol) — Potentiel \(s.p)/100 (\(pL(s.p))). \(s.p >= 65 ? "Fort potentiel selon l'analyse." : s.p >= 35 ? "Potentiel modéré." : "Potentiel limité.")"
        }
        if q.contains("prix") || q.contains("price") || q.contains("vaut") || q.contains("coûte") {
            return "\(a.symbol) · \(fmtPrice(a.price)) · \(change) 24h · Cap. \(fmtCap(a.marketCap))"
        }
        if q.contains("acheter") || q.contains("investir") || q.contains("buy") {
            return "\(a.symbol) — R:\(s.r)/100 P:\(s.p)/100. \(s.r < 40 && s.p >= 60 ? "Profil intéressant : faible risque, bon potentiel." : s.r >= 70 ? "Risque élevé — petite position si conviction." : "À analyser avec ton propre contexte.")"
        }
        return "\(a.symbol) · \(fmtPrice(a.price)) · \(change) 24h\nRisque : \(s.r)/100 (\(rL(s.r))) · Potentiel : \(s.p)/100 (\(pL(s.p)))\nCatégorie : \(getCat(a.id))"
    }
    if q.contains("meilleur") || q.contains("top") || q.contains("performer") || q.contains("hausse") {
        let top = assets.sorted { $0.change24h > $1.change24h }.prefix(3)
        return "Top 3 en 24h : " + top.map { "\($0.symbol) \(String(format: "%+.1f%%", $0.change24h))" }.joined(separator: " · ")
    }
    if q.contains("pire") || q.contains("baisse") || q.contains("chute") {
        let bot = assets.sorted { $0.change24h < $1.change24h }.prefix(3)
        return "Plus fortes baisses 24h : " + bot.map { "\($0.symbol) \(String(format: "%+.1f%%", $0.change24h))" }.joined(separator: " · ")
    }
    if q.contains("faible risque") || q.contains("safe") || q.contains("stable") {
        let safe = assets.filter { sc($0.id).r < 35 }.prefix(4)
        return "Faible risque : " + (safe.isEmpty ? "BTC, ETH, DAI" : safe.map { $0.symbol }.joined(separator: ", "))
    }
    if q.contains("fort potentiel") || q.contains("meilleur potentiel") {
        let high = assets.filter { sc($0.id).p >= 70 }.sorted { sc($0.id).p > sc($1.id).p }.prefix(4)
        return "Fort potentiel : " + (high.isEmpty ? "SOL, SUI, TAO" : high.map { "\($0.symbol)(P\(sc($0.id).p))" }.joined(separator: ", "))
    }
    if q.contains("marché") || q.contains("market") || q.contains("global") {
        let up = assets.filter { $0.change24h > 0 }.count
        let avg = assets.isEmpty ? 0 : assets.reduce(0.0) { $0 + $1.change24h } / Double(assets.count)
        return "Marché global : \(up)/\(assets.count) en hausse · Variation moyenne : \(String(format: "%+.2f%%", avg))"
    }
    if q.contains("bonjour") || q.contains("salut") || q.contains("hello") {
        return "Salut ! Je connais les prix en temps réel et les scores R/P de toutes les cryptos du top 50. Demande par ex. : « risque de Solana » ou « meilleurs performers »."
    }
    if q.contains("merci") { return "Avec plaisir !" }
    return "Je réponds sur : prix, risque, potentiel, meilleurs/pires 24h, marché global. Cite le nom d'une crypto ou pose une question générale."
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
    case market, suivi, alertes, info
    var label: String {
        switch self {
        case .market:  return "Marché"
        case .suivi:   return "Suivi"
        case .alertes: return "Alertes"
        case .info:    return "Info"
        }
    }
    var icon: String {
        switch self {
        case .market:  return "chart.bar.xaxis"
        case .suivi:   return "eye"
        case .alertes: return "bell"
        case .info:    return "info.circle"
        }
    }
    var iconFill: String {
        switch self {
        case .market:  return "chart.bar.xaxis.ascending"
        case .suivi:   return "eye.fill"
        case .alertes: return "bell.fill"
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
    private static let tint  = Color(hex: 0x46C9A8)

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
                    .foregroundStyle(Self.tint)

                TextField("Question sur le marché…", text: $chatInput)
                    .font(.system(size: 14))
                    .focused($chatFocused)
                    .onSubmit { sendChat() }
                    .submitLabel(.send)

                if !chatInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { sendChat() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Self.tint, in: Circle())
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
                .foregroundStyle(Self.tint)
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
        .background(Self.tint.opacity(0.07))
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
                                .foregroundStyle(tab == t ? Self.tint : Color(white: 0.55))
                                .animation(.spring(duration: 0.25), value: tab)
                            Text(t.label)
                                .font(.system(size: 9, weight: tab == t ? .semibold : .regular))
                                .foregroundStyle(tab == t ? Self.tint : Color(white: 0.55))
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
            list = list.filter { getCat($0.id) == cat }
        }
        switch sortBy {
        case .rank:      list = list.sorted { $0.rank < $1.rank }
        case .change:    list = list.sorted { $0.change24h > $1.change24h }
        case .potential: list = list.sorted { sc($0.id).p > sc($1.id).p }
        case .risk:      list = list.sorted { sc($0.id).r < sc($1.id).r }
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
                            ProgressView().controlSize(.large).tint(Color(hex: 0x46C9A8))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .white : Color(hex: 0x46C9A8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color(hex: 0x46C9A8) : Color(hex: 0x46C9A8).opacity(0.1),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ligne crypto

struct CryptoCellRow: View {
    let asset: CryptoAsset
    private var s: (r: Int, p: Int) { sc(asset.id) }
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
                Text(getCat(asset.id))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(getCatColor(asset.id))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(getCatColor(asset.id).opacity(0.1), in: Capsule())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtPrice(asset.price))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Label(String(format: "%.2f%%", abs(asset.change24h)),
                      systemImage: up ? "arrow.up" : "arrow.down")
                    .font(.caption.bold())
                    .foregroundStyle(up ? Color(hex: 0x008F6C) : .red)
                    .monospacedDigit()
                HStack(spacing: 4) {
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
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x46C9A8))
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
                            Text(fmtCap(totalValue)).font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("P&L").font(.caption).foregroundStyle(.secondary)
                            Text(fmtCap(abs(totalPnl)))
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
                Text("\(String(format: "%.4f", pos.quantity)) · achat \(fmtPrice(pos.buyPrice))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtCap(currentValue))
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
                        LabeledContent("Prix actuel", value: fmtPrice(a.price))
                        LabeledContent("Valeur actuelle", value: fmtCap(currentVal))
                        LabeledContent("P&L") {
                            Text(fmtCap(abs(pnl)))
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
                    Text("\(al.direction == "above" ? "Au-dessus de" : "En dessous de") \(fmtPrice(al.threshold))")
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
                    Text(fmtPrice(a.price)).font(.caption.bold()).foregroundStyle(Theme.textPrimary).monospacedDigit()
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
    let onAdd: (PriceAlert) -> Void

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
                        LabeledContent("Prix actuel", value: fmtPrice(a.price))
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
                        LabeledContent("Cryptos scorées", value: "\(scores.count)")
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
    private var s: (r: Int, p: Int) { sc(asset.id) }
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
                                    Text(getCat(asset.id))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(getCatColor(asset.id))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(getCatColor(asset.id).opacity(0.1), in: Capsule())
                                    Text("#\(asset.rank)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(fmtPrice(asset.price))
                                    .font(.title2.bold()).foregroundStyle(Theme.textPrimary).monospacedDigit()
                                Label(String(format: "%.2f%%", abs(asset.change24h)),
                                      systemImage: up ? "arrow.up" : "arrow.down")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(up ? Color(hex: 0x008F6C) : .red)
                            }
                        }
                        .padding(Theme.pad)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                        // Scores
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Analyse").font(.headline).foregroundStyle(Theme.textPrimary)
                            detailScoreBar("Risque — \(rL(s.r))", value: s.r, color: rC(s.r))
                            detailScoreBar("Potentiel — \(pL(s.p))", value: s.p, color: pC(s.p))
                            Text(s.r < 40 ? "Profil conservateur. Actif établi avec bonne liquidité." :
                                 s.r < 70 ? "Profil modéré. Volatilité significative à surveiller." :
                                 "Profil spéculatif. Position à limiter en % de portefeuille.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(Theme.pad)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

                        // Stats marché
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Marché").font(.headline).foregroundStyle(Theme.textPrimary).padding(.bottom, 8)
                            detailStatRow("Cap. marché", fmtCap(asset.marketCap))
                            Divider()
                            detailStatRow("Volume 24h", fmtCap(asset.volume24h))
                            Divider()
                            detailStatRow("Variation 24h", String(format: "%+.2f%%", asset.change24h))
                        }
                        .padding(Theme.pad)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
