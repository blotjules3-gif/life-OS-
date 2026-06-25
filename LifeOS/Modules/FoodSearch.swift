import SwiftUI
import SwiftData

// MARK: - Recherche d'aliments via OpenFoodFacts (serveur, aucune DB locale)
//
// Base mondiale de produits (supermarchés EU/US + aliments basiques) avec calories,
// protéines, glucides, lipides. On interroge le serveur à la demande — rien n'est stocké.

struct FoodProduct: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let brand: String
    let kcal: Int        // pour 100 g
    let protein: Double
    let carbs: Double
    let fat: Double
}

enum FoodSearchService {
    static func search(_ query: String) async -> [FoodProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2,
              let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(q)&search_simple=1&action=process&json=1&page_size=30&fields=product_name,product_name_fr,brands,nutriments")
        else { return [] }

        var req = URLRequest(url: url)
        req.setValue("LifeOS - iOS - Version 1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
            return decoded.products.compactMap { p -> FoodProduct? in
                let name = (p.product_name_fr?.isEmpty == false ? p.product_name_fr : p.product_name)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard !name.isEmpty else { return nil }
                let n = p.nutriments
                let kcal = Int((n?.energyKcal100g.value ?? 0).rounded())
                guard kcal > 0 else { return nil }
                return FoodProduct(
                    name: name,
                    brand: (p.brands ?? "").components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "",
                    kcal: kcal,
                    protein: n?.proteins100g.value ?? 0,
                    carbs: n?.carbohydrates100g.value ?? 0,
                    fat: n?.fat100g.value ?? 0
                )
            }
        } catch {
            return []
        }
    }
}

// Décodage tolérant (les valeurs OFF sont parfois des nombres, parfois des chaînes)
private struct FlexDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}
private struct OFFResponse: Decodable { let products: [OFFProduct] }
private struct OFFProduct: Decodable {
    let product_name: String?
    let product_name_fr: String?
    let brands: String?
    let nutriments: OFFNutriments?
}
private struct OFFNutriments: Decodable {
    let energyKcal100g: FlexDouble
    let proteins100g: FlexDouble
    let carbohydrates100g: FlexDouble
    let fat100g: FlexDouble
    enum CodingKeys: String, CodingKey {
        case energyKcal100g  = "energy-kcal_100g"
        case proteins100g    = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g         = "fat_100g"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal100g    = (try? c.decode(FlexDouble.self, forKey: .energyKcal100g)) ?? FlexDouble(from2: nil)
        proteins100g      = (try? c.decode(FlexDouble.self, forKey: .proteins100g)) ?? FlexDouble(from2: nil)
        carbohydrates100g = (try? c.decode(FlexDouble.self, forKey: .carbohydrates100g)) ?? FlexDouble(from2: nil)
        fat100g           = (try? c.decode(FlexDouble.self, forKey: .fat100g)) ?? FlexDouble(from2: nil)
    }
}
private extension FlexDouble {
    init(from2 v: Double?) { self.value = v }
}

// MARK: - Vue de recherche

struct FoodSearchView: View {
    @Environment(\.modelContext) private var ctx
    @State private var query = ""
    @State private var results: [FoodProduct] = []
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var adding: FoodProduct?

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView().padding(.vertical, 8); Spacer() }
            } else if results.isEmpty && query.count >= 2 {
                ContentUnavailableView("Aucun produit", systemImage: "magnifyingglass",
                                       description: Text("Essaie un autre nom."))
                    .listRowBackground(Color.clear)
            } else if query.count < 2 {
                Section {
                    Text("Tape le nom d'un aliment ou produit (ex. banane, yaourt nature, Coca-Cola). Résultats des supermarchés EU/US via OpenFoodFacts.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(results) { p in
                Button { adding = p } label: { row(p) }
            }
        }
        .navigationTitle("Rechercher un aliment")
        .navigationBarTitleDisplayMode(.inline)
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
                results = r
                loading = false
            }
        }
        .sheet(item: $adding) { AddFoodSheet(product: $0) }
    }

    private func row(_ p: FoodProduct) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(hex: 0x4CC38A).gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                Text(p.brand.isEmpty ? "\(p.kcal) kcal · \(Int(p.protein))g prot. /100g"
                                     : "\(p.brand) · \(p.kcal) kcal /100g")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "plus.circle.fill").foregroundStyle(Color(hex: 0x4CC38A))
        }
        .padding(.vertical, 2)
    }
}

// Feuille pour choisir la quantité + le repas, puis ajouter au journal
private struct AddFoodSheet: View {
    let product: FoodProduct
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var grams: Double = 100
    @State private var meal = "Déjeuner"
    private let meals = ["Petit-déj", "Déjeuner", "Dîner", "Collation"]

    private var factor: Double { grams / 100 }
    private var kcal: Int { Int((Double(product.kcal) * factor).rounded()) }
    private var protein: Double { (product.protein * factor) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(product.name).font(.headline)
                    if !product.brand.isEmpty { Text(product.brand).font(.subheadline).foregroundStyle(.secondary) }
                }
                Section("Quantité") {
                    HStack {
                        Text("\(Int(grams)) g")
                        Slider(value: $grams, in: 10...500, step: 5)
                    }
                    HStack { Text("Repas"); Spacer(); Picker("", selection: $meal) { ForEach(meals, id: \.self) { Text($0) } }.labelsHidden() }
                }
                Section("Apport") {
                    LabeledContent("Calories", value: "\(kcal) kcal")
                    LabeledContent("Protéines", value: "\(Int(protein)) g")
                    LabeledContent("Glucides", value: "\(Int(product.carbs * factor)) g")
                    LabeledContent("Lipides", value: "\(Int(product.fat * factor)) g")
                }
            }
            .navigationTitle("Ajouter").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        ctx.insert(FoodEntry(name: product.name, calories: kcal, protein: protein,
                                             carbs: product.carbs * factor, fat: product.fat * factor, meal: meal))
                        try? ctx.save()
                        Haptics.medium()
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
