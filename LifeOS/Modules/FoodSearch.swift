import SwiftUI
import SwiftData
import VisionKit

// MARK: - Aliments via OpenFoodFacts (serveur, aucune DB locale)
//
// Recherche par nom OU scan de code-barres -> fiche produit avec la NOTE santé
// (Nutri-Score A–E, NOVA transformation, Eco-Score) + calories/macros, et ajout au journal.

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
}

enum FoodSearchService {
    private static let fields = "product_name,product_name_fr,brands,nutriments,nutriscore_grade,nova_group,ecoscore_grade,code"

    static func search(_ query: String) async -> [FoodProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2,
              let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q)&search_simple=1&action=process&json=1&page_size=30&fields=\(fields)")
        else { return [] }
        guard let data = try? await get(url) else { return [] }
        guard let decoded = try? JSONDecoder().decode(OFFResponse.self, from: data) else { return [] }
        return decoded.products.compactMap { $0.toProduct() }.filter { $0.kcal > 0 }
    }

    static func product(barcode: String) async -> FoodProduct? {
        let code = barcode.trimmingCharacters(in: .whitespaces)
        guard code.count >= 6,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)")
        else { return nil }
        guard let data = try? await get(url) else { return nil }
        guard let r = try? JSONDecoder().decode(OFFSingle.self, from: data), r.status == 1 else { return nil }
        return r.product?.toProduct(fallbackCode: code)
    }

    private static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("LifeOS - iOS - Version 1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}

// MARK: décodage tolérant

private struct FlexDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
    init(_ v: Double?) { value = v }
}
private struct FlexInt: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = Int(d) }
        else if let s = try? c.decode(String.self) { value = Int(s) }
        else { value = nil }
    }
    init(_ v: Int?) { value = v }
}
private struct OFFResponse: Decodable { let products: [OFFProduct] }
private struct OFFSingle: Decodable { let status: Int; let product: OFFProduct? }
private struct OFFProduct: Decodable {
    let product_name: String?
    let product_name_fr: String?
    let brands: String?
    let nutriments: OFFNutriments?
    let nutriscore_grade: String?
    let nova_group: FlexInt?
    let ecoscore_grade: String?
    let code: String?

    func toProduct(fallbackCode: String = "") -> FoodProduct? {
        let nm = (product_name_fr?.isEmpty == false ? product_name_fr : product_name)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !nm.isEmpty else { return nil }
        let n = nutriments
        let g = nutriscore_grade?.lowercased()
        let e = ecoscore_grade?.lowercased()
        return FoodProduct(
            barcode: code ?? fallbackCode,
            name: nm,
            brand: (brands ?? "").components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "",
            kcal: Int((n?.energyKcal100g.value ?? 0).rounded()),
            protein: n?.proteins100g.value ?? 0,
            carbs: n?.carbohydrates100g.value ?? 0,
            fat: n?.fat100g.value ?? 0,
            nutriscore: (g == "a" || g == "b" || g == "c" || g == "d" || g == "e") ? g : nil,
            nova: nova_group?.value,
            ecoscore: (e == "a" || e == "b" || e == "c" || e == "d" || e == "e") ? e : nil
        )
    }
}
private struct OFFNutriments: Decodable {
    let energyKcal100g: FlexDouble
    let proteins100g: FlexDouble
    let carbohydrates100g: FlexDouble
    let fat100g: FlexDouble
    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal100g = (try? c.decode(FlexDouble.self, forKey: .energyKcal100g)) ?? FlexDouble(nil)
        proteins100g = (try? c.decode(FlexDouble.self, forKey: .proteins100g)) ?? FlexDouble(nil)
        carbohydrates100g = (try? c.decode(FlexDouble.self, forKey: .carbohydrates100g)) ?? FlexDouble(nil)
        fat100g = (try? c.decode(FlexDouble.self, forKey: .fat100g)) ?? FlexDouble(nil)
    }
}

// MARK: - Note Nutri-Score (badge façon Yuka)

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

// MARK: - Fiche produit (note + macros + ajout au journal)

struct ProductDetailView: View {
    let product: FoodProduct
    @Environment(\.modelContext) private var ctx
    @State private var grams: Double = 100
    @State private var meal = "Déjeuner"
    @State private var added = false
    private let meals = ["Petit-déj", "Déjeuner", "Dîner", "Collation"]

    private var factor: Double { grams / 100 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // En-tête
                VStack(spacing: 6) {
                    Text(product.name).font(.title2.bold()).multilineTextAlignment(.center)
                    if !product.brand.isEmpty { Text(product.brand).font(.subheadline).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity).padding(.top, 4)

                // Note santé (Nutri-Score)
                VStack(spacing: 12) {
                    HStack {
                        Text("Note santé").font(.headline)
                        Spacer()
                        if product.nutriscore == nil { Text("Non notée").font(.caption).foregroundStyle(.secondary) }
                    }
                    NutriScoreBar(grade: product.nutriscore)
                    HStack(spacing: 10) {
                        if let nova = product.nova {
                            badge("Transformation", "NOVA \(nova)", novaColor(nova))
                        }
                        if let eco = product.ecoscore {
                            badge("Éco-score", eco.uppercased(), nutriColor(eco))
                        }
                    }
                }
                .card()

                // Apports (pour la quantité choisie)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pour \(Int(grams)) g").font(.headline)
                    HStack { Text("\(Int(grams)) g"); Slider(value: $grams, in: 10...500, step: 5) }
                    HStack(spacing: 10) {
                        macro("Calories", "\(Int(Double(product.kcal) * factor))", "kcal", Color(hex: 0x4CC38A))
                        macro("Protéines", "\(Int(product.protein * factor))", "g", Color(hex: 0xF1746C))
                    }
                    HStack(spacing: 10) {
                        macro("Glucides", "\(Int(product.carbs * factor))", "g", Color(hex: 0xE0A23C))
                        macro("Lipides", "\(Int(product.fat * factor))", "g", Color(hex: 0x9B6CF1))
                    }
                    HStack { Text("Repas"); Spacer(); Picker("", selection: $meal) { ForEach(meals, id: \.self) { Text($0) } }.labelsHidden() }
                }
                .card()

                Button {
                    ctx.insert(FoodEntry(name: product.name, calories: Int(Double(product.kcal) * factor),
                                         protein: product.protein * factor, carbs: product.carbs * factor,
                                         fat: product.fat * factor, meal: meal))
                    try? ctx.save(); Haptics.medium()
                    withAnimation { added = true }
                } label: {
                    Label(added ? "Ajouté ✓" : "Ajouter au journal", systemImage: added ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(added ? Color.green : Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 4)
            }
            .padding(Theme.pad)
        }
        .background(Theme.bg)
        .navigationTitle("Produit").navigationBarTitleDisplayMode(.inline)
    }

    private func badge(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(color, in: Capsule())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    private func macro(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text("\(title) · \(unit)").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func novaColor(_ n: Int) -> Color {
        switch n { case 1: return Color(hex: 0x1E8F4E); case 2: return Color(hex: 0xF1C40F); case 3: return Color(hex: 0xE8821E); default: return Color(hex: 0xE03A2F) }
    }
}

// MARK: - Recherche par nom

struct FoodSearchView: View {
    @State private var query = ""
    @State private var results: [FoodProduct] = []
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView().padding(.vertical, 8); Spacer() }.listRowBackground(Color.clear)
            } else if results.isEmpty && query.trimmingCharacters(in: .whitespaces).count >= 2 {
                Text("Aucun produit trouvé.").foregroundStyle(.secondary)
            } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                Text("Tape le nom d'un aliment (banane, yaourt nature, Coca-Cola…). Base mondiale des supermarchés via OpenFoodFacts.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(results) { p in
                NavigationLink { ProductDetailView(product: p) } label: { row(p) }
            }
        }
        .navigationTitle("Rechercher un aliment").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Banane, yaourt, Coca…")
        .onChange(of: query) { _, q in
            searchTask?.cancel()
            guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; loading = false; return }
            loading = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(380))
                if Task.isCancelled { return }
                let r = await FoodSearchService.search(q)
                if Task.isCancelled { return }
                results = r; loading = false
            }
        }
    }

    private func row(_ p: FoodProduct) -> some View {
        HStack(spacing: 12) {
            Text((p.nutriscore ?? "?").uppercased())
                .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(nutriColor(p.nutriscore), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                Text(p.brand.isEmpty ? "\(p.kcal) kcal /100g" : "\(p.brand) · \(p.kcal) kcal /100g")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Scan code-barres (VisionKit) -> fiche produit

struct ScanProductView: View {
    @State private var found: FoodProduct?
    @State private var loadingCode: String?
    @State private var notFound = false
    @State private var manual = ""

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            if scannerAvailable {
                BarcodeScanner { code in lookup(code) }
                    .ignoresSafeArea()
                VStack {
                    Spacer()
                    statusBar
                        .padding(.bottom, 110)
                }
            } else {
                // Simulateur / pas de caméra : saisie manuelle + recherche par nom
                Form {
                    Section("Scanner indisponible ici") {
                        Text("Le scan caméra marche sur un vrai iPhone. En attendant tu peux entrer un code-barres ou chercher par nom.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Section("Code-barres") {
                        TextField("Ex. 3017620422003", text: $manual).keyboardType(.numberPad)
                        Button("Chercher ce code") { lookup(manual) }.disabled(manual.count < 6)
                    }
                    Section {
                        NavigationLink { FoodSearchView() } label: {
                            Label("Rechercher par nom", systemImage: "magnifyingglass")
                        }
                    }
                }
            }
        }
        .navigationTitle("Scan produit").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $found) { ProductDetailView(product: $0) }
        .alert("Produit introuvable", isPresented: $notFound) {
            Button("OK", role: .cancel) { }
        } message: { Text("Ce code-barres n'est pas dans la base OpenFoodFacts.") }
    }

    private var statusBar: some View {
        Group {
            if loadingCode != nil {
                HStack { ProgressView().tint(.white); Text("Recherche…").foregroundStyle(.white) }
            } else {
                Label("Vise le code-barres", systemImage: "barcode.viewfinder").foregroundStyle(.white)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func lookup(_ code: String) {
        guard loadingCode == nil else { return }
        loadingCode = code
        Task {
            let p = await FoodSearchService.product(barcode: code)
            await MainActor.run {
                loadingCode = nil
                if let p { found = p; Haptics.medium() } else { notFound = true; Haptics.tap() }
            }
        }
    }
}

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
