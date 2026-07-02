import Foundation

// MARK: - Modèles de données Crypto

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

struct PriceAlert: Identifiable {
    var id: String { "\(assetId):\(direction):\(threshold)" }
    let assetId: String
    let direction: String   // "above" ou "below"
    let threshold: Double
}
