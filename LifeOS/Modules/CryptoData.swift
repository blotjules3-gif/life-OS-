import SwiftUI

// MARK: - Données statiques & helpers (source : App.js §SC / §CATS)

let cryptoProxyURL = "https://riskcrypto-proxy.httpsrisckcryptoproxyworkersdev.workers.dev/market"

// MARK: - Scores R/P

let cryptoScores: [String: (r: Int, p: Int)] = [
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

// MARK: - Catégories

let cryptoCategories: [String: String] = [
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

let cryptoCatColors: [String: Color] = [
    "Layer 1": Color(hex: 0x3CB2E0), "Layer 2": Color(hex: 0x6C7BF1),
    "DeFi": Color(hex: 0x9B6CF1), "Stablecoin": Color(hex: 0x4CC38A),
    "Meme": Color(hex: 0xE0A23C), "Exchange": Color(hex: 0xE07B3C),
    "Privacy": Color(hex: 0x8A93A8), "AI/GPU": Color(hex: 0x9B6CF1),
    "Commodity": Color(hex: 0xE0A23C), "RWA": Color(hex: 0x4CC38A),
]

// MARK: - Helpers catégorie

func cryptoGuessCategory(_ id: String) -> String {
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

func cryptoGetCat(_ id: String) -> String { cryptoCategories[id] ?? cryptoGuessCategory(id) }
func cryptoGetCatColor(_ id: String) -> Color { cryptoCatColors[cryptoGetCat(id)] ?? Color(hex: 0x3CB2E0) }

// MARK: - Helpers scores

func cryptoSc(_ id: String) -> (r: Int, p: Int) { cryptoScores[id] ?? (r: 50, p: 50) }
func cryptoRiskColor(_ r: Int) -> Color { r >= 70 ? .red : r >= 45 ? .orange : Color(hex: 0x008F6C) }
func cryptoPotColor(_ p: Int) -> Color { p >= 65 ? Color(hex: 0x008F6C) : p >= 35 ? .orange : .secondary }
func cryptoRiskLabel(_ r: Int) -> String { r >= 70 ? "ÉLEVÉ" : r >= 45 ? "MOYEN" : "FAIBLE" }
func cryptoPotLabel(_ p: Int) -> String { p >= 65 ? "FORT" : p >= 35 ? "MOYEN" : "FAIBLE" }

// MARK: - Formatage prix

func cryptoFmtPrice(_ p: Double) -> String {
    guard p > 0 else { return "···" }
    let a = abs(p)
    if a >= 10_000 { return "$\(Int(a).formatted())" }
    if a >= 100    { return "$\(Int(a).formatted())" }
    if a >= 1      { return String(format: "$%.2f", a) }
    if a >= 0.01   { return String(format: "$%.4f", a) }
    return String(format: "$%.6f", a)
}

func cryptoFmtCap(_ n: Double) -> String {
    if n <= 0    { return "--" }
    if n >= 1e12 { return String(format: "$%.2fT", n / 1e12) }
    if n >= 1e9  { return String(format: "$%.1fB", n / 1e9) }
    return String(format: "$%.0fM", n / 1e6)
}

// MARK: - Fetch marché

func fetchCryptoMarket() async throws -> [CryptoAsset] {
    guard let url = URL(string: cryptoProxyURL) else { throw URLError(.badURL) }
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

// MARK: - Chatbot réponses

func cryptoAnswer(query: String, assets: [CryptoAsset]) -> String {
    let q = query.lowercased()
    let found = assets.first { a in
        q.contains(a.symbol.lowercased()) || q.contains(a.name.lowercased())
    }
    if let a = found {
        let s = cryptoSc(a.id)
        let change = String(format: "%+.2f%%", a.change24h)
        if q.contains("risque") || q.contains("risk") || q.contains("dangereux") || q.contains("safe") {
            return "\(a.symbol) — Risque \(s.r)/100 (\(cryptoRiskLabel(s.r))). \(s.r < 40 ? "Actif établi." : s.r < 70 ? "Volatilité à surveiller." : "Profil spéculatif, ne pas surpondérer.")"
        }
        if q.contains("potentiel") || q.contains("hausse") || q.contains("upside") {
            return "\(a.symbol) — Potentiel \(s.p)/100 (\(cryptoPotLabel(s.p))). \(s.p >= 65 ? "Fort potentiel selon l'analyse." : s.p >= 35 ? "Potentiel modéré." : "Potentiel limité.")"
        }
        if q.contains("prix") || q.contains("price") || q.contains("vaut") || q.contains("coûte") {
            return "\(a.symbol) · \(cryptoFmtPrice(a.price)) · \(change) 24h · Cap. \(cryptoFmtCap(a.marketCap))"
        }
        if q.contains("acheter") || q.contains("investir") || q.contains("buy") {
            return "\(a.symbol) — R:\(s.r)/100 P:\(s.p)/100. \(s.r < 40 && s.p >= 60 ? "Profil intéressant : faible risque, bon potentiel." : s.r >= 70 ? "Risque élevé — petite position si conviction." : "À analyser avec ton propre contexte.")"
        }
        return "\(a.symbol) · \(cryptoFmtPrice(a.price)) · \(change) 24h\nRisque : \(s.r)/100 (\(cryptoRiskLabel(s.r))) · Potentiel : \(s.p)/100 (\(cryptoPotLabel(s.p)))\nCatégorie : \(cryptoGetCat(a.id))"
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
        let safe = assets.filter { cryptoSc($0.id).r < 35 }.prefix(4)
        return "Faible risque : " + (safe.isEmpty ? "BTC, ETH, DAI" : safe.map { $0.symbol }.joined(separator: ", "))
    }
    if q.contains("fort potentiel") || q.contains("meilleur potentiel") {
        let high = assets.filter { cryptoSc($0.id).p >= 70 }.sorted { cryptoSc($0.id).p > cryptoSc($1.id).p }.prefix(4)
        return "Fort potentiel : " + (high.isEmpty ? "SOL, SUI, TAO" : high.map { "\($0.symbol)(P\(cryptoSc($0.id).p))" }.joined(separator: ", "))
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
