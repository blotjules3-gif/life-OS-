import SwiftUI

// MARK: - Modèle

struct CryptoAsset: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let price: Double
    let change24h: Double
    let marketCap: Double
    let volume24h: Double
    let rank: Int
}

// MARK: - Scores Risque / Potentiel

private let scores: [String: (r: Int, p: Int)] = [
    "bitcoin":            (r: 28, p: 72),
    "ethereum":           (r: 42, p: 68),
    "tether":             (r: 12, p: 18),
    "binancecoin":        (r: 48, p: 55),
    "ripple":             (r: 68, p: 58),
    "usd-coin":           (r: 10, p: 16),
    "solana":             (r: 55, p: 88),
    "tron":               (r: 58, p: 48),
    "dogecoin":           (r: 88, p: 45),
    "hyperliquid":        (r: 55, p: 72),
    "cardano":            (r: 38, p: 52),
    "bitcoin-cash":       (r: 55, p: 42),
    "chainlink":          (r: 50, p: 72),
    "monero":             (r: 65, p: 45),
    "stellar":            (r: 50, p: 48),
    "avalanche-2":        (r: 58, p: 62),
    "sui":                (r: 60, p: 82),
    "the-open-network":   (r: 58, p: 68),
    "shiba-inu":          (r: 90, p: 35),
    "bittensor":          (r: 72, p: 80),
    "uniswap":            (r: 52, p: 62),
    "polkadot":           (r: 52, p: 60),
    "near":               (r: 58, p: 65),
    "mantle":             (r: 60, p: 65),
    "hedera-hashgraph":   (r: 52, p: 60),
    "litecoin":           (r: 48, p: 40),
    "matic-network":      (r: 55, p: 65),
    "arbitrum":           (r: 55, p: 72),
    "injective-protocol": (r: 62, p: 78),
    "kaspa":              (r: 68, p: 70),
    "pepe":               (r: 90, p: 38),
    "aave":               (r: 52, p: 65),
    "dai":                (r: 14, p: 15),
    "cosmos":             (r: 55, p: 58),
    "optimism":           (r: 55, p: 68),
    "aptos":              (r: 65, p: 70),
]

private func sc(_ id: String) -> (r: Int, p: Int) {
    scores[id] ?? (r: 50, p: 50)
}

private func riskColor(_ r: Int) -> Color {
    r >= 70 ? .red : r >= 45 ? .orange : Color(hex: 0x008F6C)
}
private func potColor(_ p: Int) -> Color {
    p >= 65 ? Color(hex: 0x008F6C) : p >= 35 ? .orange : .secondary
}
private func riskLabel(_ r: Int) -> String {
    r >= 70 ? "ÉLEVÉ" : r >= 45 ? "MOYEN" : "FAIBLE"
}
private func potLabel(_ p: Int) -> String {
    p >= 65 ? "FORT" : p >= 35 ? "MOYEN" : "FAIBLE"
}

private let categories: [String: String] = [
    "bitcoin": "Layer 1", "ethereum": "Layer 1", "tether": "Stablecoin",
    "binancecoin": "Exchange", "ripple": "Layer 1", "usd-coin": "Stablecoin",
    "solana": "Layer 1", "tron": "Layer 1", "dogecoin": "Meme",
    "hyperliquid": "DeFi", "cardano": "Layer 1", "bitcoin-cash": "Layer 1",
    "chainlink": "DeFi", "monero": "Privacy", "stellar": "Layer 1",
    "avalanche-2": "Layer 1", "sui": "Layer 1", "the-open-network": "Layer 1",
    "shiba-inu": "Meme", "bittensor": "AI/GPU", "uniswap": "DeFi",
    "polkadot": "Layer 1", "near": "Layer 1", "mantle": "Layer 2",
    "hedera-hashgraph": "Layer 1", "litecoin": "Layer 1",
    "matic-network": "Layer 2", "arbitrum": "Layer 2",
    "injective-protocol": "DeFi", "kaspa": "Layer 1",
    "pepe": "Meme", "aave": "DeFi", "dai": "Stablecoin",
    "cosmos": "Layer 1", "optimism": "Layer 2", "aptos": "Layer 1",
]

// MARK: - Fetch

private let proxyURL = "https://riskcrypto-proxy.httpsrisckcryptoproxyworkersdev.workers.dev/market"

private func fetchCrypto() async throws -> [CryptoAsset] {
    guard let url = URL(string: proxyURL) else { throw URLError(.badURL) }
    let (data, _) = try await URLSession.shared.data(from: url)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    // Format CMC via proxy : { data: [...] }
    if let array = json?["data"] as? [[String: Any]] {
        return array.compactMap { parseCMC($0) }
    }
    // Format CoinGecko direct : [...]
    if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
        return array.compactMap { parseCG($0) }
    }
    return []
}

private func parseCMC(_ d: [String: Any]) -> CryptoAsset? {
    guard let name = d["name"] as? String,
          let sym  = d["symbol"] as? String,
          let slug = d["slug"] as? String ?? (d["id"] as? String),
          let q    = (d["quote"] as? [String: Any])?["USD"] as? [String: Any]
    else { return nil }
    return CryptoAsset(
        id:        slug.lowercased(),
        symbol:    sym.uppercased(),
        name:      name,
        price:     q["price"] as? Double ?? 0,
        change24h: q["percent_change_24h"] as? Double ?? 0,
        marketCap: q["market_cap"] as? Double ?? 0,
        volume24h: q["volume_24h"] as? Double ?? 0,
        rank:      d["cmc_rank"] as? Int ?? d["rank"] as? Int ?? 0
    )
}

private func parseCG(_ d: [String: Any]) -> CryptoAsset? {
    guard let id = d["id"] as? String else { return nil }
    return CryptoAsset(
        id:        id,
        symbol:    (d["symbol"] as? String ?? "").uppercased(),
        name:      d["name"] as? String ?? "",
        price:     d["current_price"] as? Double ?? 0,
        change24h: d["price_change_percentage_24h"] as? Double ?? 0,
        marketCap: d["market_cap"] as? Double ?? 0,
        volume24h: d["total_volume"] as? Double ?? 0,
        rank:      d["market_cap_rank"] as? Int ?? 0
    )
}

// MARK: - Formatters

private func fmtPrice(_ p: Double) -> String {
    guard p > 0 else { return "···" }
    let abs = Swift.abs(p)
    if abs >= 10_000 { return "$\(Int(abs).formatted())" }
    if abs >= 100    { return "$\(Int(abs).formatted())" }
    if abs >= 1      { return String(format: "$%.2f", abs) }
    if abs >= 0.01   { return String(format: "$%.4f", abs) }
    return String(format: "$%.6f", abs)
}

private func fmtCap(_ n: Double) -> String {
    if n <= 0       { return "--" }
    if n >= 1e12    { return String(format: "$%.2fT", n / 1e12) }
    if n >= 1e9     { return String(format: "$%.1fB", n / 1e9) }
    return String(format: "$%.0fM", n / 1e6)
}

// MARK: - Vue principale

struct CryptoMarketView: View {
    @State private var assets: [CryptoAsset] = []
    @State private var loading = true
    @State private var error = false
    @State private var query = ""
    @State private var selected: CryptoAsset? = nil

    private var filtered: [CryptoAsset] {
        guard !query.isEmpty else { return assets }
        let q = query.lowercased()
        return assets.filter {
            $0.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            Theme.background
            if loading {
                loadingView
            } else if error {
                errorView
            } else {
                marketList
            }
        }
        .navigationTitle("Crypto")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Rechercher…")
        .task { await load() }
        .navigationDestination(for: String.self) { _ in EmptyView() }
        .sheet(item: $selected) { asset in
            CryptoDetailView(asset: asset)
        }
    }

    // MARK: Liste

    private var marketList: some View {
        List {
            ForEach(filtered) { asset in
                CryptoAssetRow(asset: asset)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = asset }
                    .listRowBackground(Theme.card)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    // MARK: Chargement / Erreur

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(AppCategory.invest.tint)
            Text("Chargement du marché…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("Impossible de charger")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Button("Réessayer") {
                loading = true; error = false
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppCategory.invest.tint)
        }
    }

    // MARK: Fetch

    private func load() async {
        do {
            let data = try await fetchCrypto()
            await MainActor.run {
                assets = data
                loading = false
                error = false
            }
        } catch {
            await MainActor.run {
                self.error = true
                self.loading = false
            }
        }
    }
}

// MARK: - Ligne de la liste

struct CryptoAssetRow: View {
    let asset: CryptoAsset
    private var s: (r: Int, p: Int) { sc(asset.id) }
    private var up: Bool { asset.change24h >= 0 }

    var body: some View {
        HStack(spacing: 12) {
            // Initiales colorées (pas de dépendance image externe)
            cryptoInitials

            // Nom + rang
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.symbol)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(asset.name) · #\(asset.rank)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(categories[asset.id] ?? "Crypto")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            // Prix + variation + badges
            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtPrice(asset.price))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()

                Label(String(format: "%.2f%%", Swift.abs(asset.change24h)),
                      systemImage: up ? "arrow.up" : "arrow.down")
                    .font(.caption.bold())
                    .foregroundStyle(up ? Color(hex: 0x008F6C) : .red)
                    .monospacedDigit()

                HStack(spacing: 4) {
                    scoreBadge("R\(s.r)", riskColor(s.r))
                    scoreBadge("P\(s.p)", potColor(s.p))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var cryptoInitials: some View {
        let sym = String(asset.symbol.prefix(2))
        let palette: [Color] = [
            Color(hex: 0xF7931A), Color(hex: 0x627EEA), Color(hex: 0x9945FF),
            Color(hex: 0xE84142), Color(hex: 0x26A17B), Color(hex: 0x0033AD),
            Color(hex: 0xE6007A), Color(hex: 0x2775CA), Color(hex: 0xFF6B35),
        ]
        let col = palette[Int(asset.symbol.unicodeScalars.first?.value ?? 65) % palette.count]
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(col.opacity(0.15))
                .frame(width: 42, height: 42)
            Text(sym)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(col)
        }
    }

    private func scoreBadge(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Vue détail

struct CryptoDetailView: View {
    let asset: CryptoAsset
    @Environment(\.dismiss) private var dismiss
    private var s: (r: Int, p: Int) { sc(asset.id) }
    private var up: Bool { asset.change24h >= 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 16) {
                        // En-tête prix
                        priceHeader

                        // Scores
                        scoresCard

                        // Données marché
                        marketCard
                    }
                    .padding(Theme.pad)
                }
            }
            .navigationTitle(asset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: En-tête

    private var priceHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.symbol)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Theme.textPrimary)
                Text(categories[asset.id] ?? "Crypto")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("Rang #\(asset.rank)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtPrice(asset.price))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Label(String(format: "%.2f%%", Swift.abs(asset.change24h)),
                      systemImage: up ? "arrow.up" : "arrow.down")
                    .font(.subheadline.bold())
                    .foregroundStyle(up ? Color(hex: 0x008F6C) : .red)
                    .monospacedDigit()
            }
        }
        .card()
    }

    // MARK: Scores

    private var scoresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Analyse").font(.headline).foregroundStyle(Theme.textPrimary)

            scoreBar(label: "Risque — \(riskLabel(s.r))", value: s.r, color: riskColor(s.r))
            scoreBar(label: "Potentiel — \(potLabel(s.p))", value: s.p, color: potColor(s.p))

            Text(riskDescription(s.r))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func scoreBar(label: String, value: Int, color: Color) -> some View {
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
            }
            .frame(height: 6)
        }
    }

    private func riskDescription(_ r: Int) -> String {
        if r < 40 { return "Profil conservateur. Actif établi avec une volatilité historique modérée." }
        if r < 70 { return "Profil modéré. Volatilité significative — surveiller les niveaux de support." }
        return "Profil spéculatif. Risque élevé, ne pas surpondérer dans un portefeuille équilibré."
    }

    // MARK: Données marché

    private var marketCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Données marché").font(.headline).foregroundStyle(Theme.textPrimary).padding(.bottom, 12)
            dataRow("Cap. marché", fmtCap(asset.marketCap))
            Divider().overlay(Theme.stroke)
            dataRow("Volume 24h", fmtCap(asset.volume24h))
            Divider().overlay(Theme.stroke)
            dataRow("Variation 24h", String(format: "%+.2f%%", asset.change24h))
        }
        .card()
    }

    private func dataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .padding(.vertical, 10)
    }
}
