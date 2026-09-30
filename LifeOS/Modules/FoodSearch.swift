import SwiftUI
import SwiftData
import VisionKit

// MARK: - Adaptateur pour les ecrans du journal alimentaire
//
// Les ecrans qui AJOUTENT un repas (recherche nutrition, photo, Cal AI) ont besoin
// de calories. Ils passent par ici, construit sur `ProductCatalog`. Le Yuko
// complet (photo, note /100, ingredients) est dans Yuko.swift.
//
// Corrige au passage: la recherche ne jette plus les produits a 0 kcal (l'eau et
// les boissons zero ont des calories CONNUES, egales a zero). Seuls sortent ceux
// dont l'energie est inconnue: on ne peut pas les journaliser sans inventer.

struct FoodProduct: Identifiable, Hashable {
    let id = UUID()
    let barcode: String
    let name: String
    let brand: String
    let kcal: Int          // pour 100 g
    let protein: Double
    let carbs: Double
    let fat: Double
    let nutriscore: String? // "a"..."e"
    let nova: Int?          // 1...4
    let ecoscore: String?   // "a"..."e"

    init?(_ p: CatalogProduct) {
        guard let kcal = p.nutriments.energyKcal else { return nil }
        barcode = p.barcode; name = p.name; brand = p.brand ?? ""
        self.kcal = Int(kcal.rounded())
        protein = p.nutriments.proteins ?? 0
        carbs = p.nutriments.carbohydrates ?? 0
        fat = p.nutriments.fat ?? 0
        nutriscore = p.nutriscoreGrade; nova = p.novaGroup; ecoscore = nil
    }
}

enum FoodSearchService {
    static func search(_ query: String) async -> [FoodProduct] {
        guard case .results(let items, _) = await ProductCatalog.search(query) else { return [] }
        return items.compactMap(FoodProduct.init)
    }

    static func product(barcode: String) async -> FoodProduct? {
        guard case .found(let p) = await ProductCatalog.product(barcode: barcode) else { return nil }
        return FoodProduct(p)
    }
}

// MARK: - Nutri-Score officiel (badge)

func nutriColor(_ grade: String?) -> Color {
    switch (grade ?? "").lowercased() {
    case "a": return Color(hex: 0x1E8F4E)
    case "b": return Color(hex: 0x7AC547)
    case "c": return Color(hex: 0xF1C40F)
    case "d": return Color(hex: 0xE8821E)
    case "e": return Color(hex: 0xE03A2F)
    default:  return Color(hex: 0x9AA3B2)
    }
}

struct NutriScoreBar: View {
    let grade: String?   // "a"..."e"
    var body: some View {
        HStack(spacing: 6) {
            ForEach(["a","b","c","d","e"], id: \.self) { g in
                let active = g == (grade ?? "").lowercased()
                Text(g.uppercased())
                    .font(.system(size: active ? 18 : 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: active ? 38 : 30, height: active ? 38 : 30)
                    .background(nutriColor(g).opacity(active ? 1 : 0.30), in: Circle())
                    .scaleEffect(active ? 1 : 0.95)
            }
        }
    }
}

#if !targetEnvironment(macCatalyst)
// VisionKit data scanner pour les codes-barres
struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        try? vc.startScanning()
    }
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var fired = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }
        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in added {
                if case let .barcode(b) = item, let code = b.payloadStringValue, !fired {
                    fired = true
                    onScan(code)
                    // ré-armer après un court délai pour permettre un nouveau scan
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.fired = false }
                    break
                }
            }
        }
    }
}
#else
struct BarcodeScanner: View {
    let onScan: (String) -> Void
    var body: some View { EmptyView() }
}
#endif
