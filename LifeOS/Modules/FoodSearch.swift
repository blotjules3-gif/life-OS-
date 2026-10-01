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
    /// Pour 100 g, seulement si Open Food Facts les donne. nil = inconnu, jamais 0.
    let fiber: Double?
    let sugars: Double?
    let salt: Double?

    init?(_ p: CatalogProduct) {
        guard let kcal = p.nutriments.energyKcal else { return nil }
        barcode = p.barcode; name = p.name; brand = p.brand ?? ""
        self.kcal = Int(kcal.rounded())
        protein = p.nutriments.proteins ?? 0
        carbs = p.nutriments.carbohydrates ?? 0
        fat = p.nutriments.fat ?? 0
        nutriscore = p.nutriscoreGrade; nova = p.novaGroup; ecoscore = nil
        fiber = p.nutriments.fiber; sugars = p.nutriments.sugars; salt = p.nutriments.salt
    }

    var per100: Per100Food {
        Per100Food(name: name, brand: brand, kcal: Double(kcal), protein: protein, carbs: carbs, fat: fat,
                   micros: .init(fiber: fiber, sugars: sugars, salt: salt), nutriscore: nutriscore)
    }
}

/// Issue d'une recherche, telle que l'ecran doit la montrer.
/// Avant, toute panne devenait une liste vide, donc "Aucun produit": hors ligne,
/// l'utilisateur croyait que le produit n'existait pas.
enum FoodSearchOutcome: Equatable {
    case results([FoodProduct], hasMore: Bool)
    case noResults
    /// La base a repondu, mais aucun de ces produits n'a de calories connues.
    case onlyUnknownEnergy(Int)
    case offline(String)
    case serverError(String)
}

enum FoodSearchService {
    static func search(_ query: String) async -> [FoodProduct] {
        guard case .results(let items, _) = await ProductCatalog.search(query) else { return [] }
        return items.compactMap(FoodProduct.init)
    }

    /// Recherche qui distingue: pas de reseau, panne du serveur, aucun resultat.
    static func outcome(_ query: String) async -> FoodSearchOutcome {
        classify(await ProductCatalog.search(query))
    }

    static func classify(_ search: ProductCatalog.Search) -> FoodSearchOutcome {
        switch search {
        case .results(let items, let more):
            let usable = items.compactMap(FoodProduct.init)
            if !usable.isEmpty { return .results(usable, hasMore: more) }
            return items.isEmpty ? .noResults : .onlyUnknownEnergy(items.count)
        case .unavailable(let message):
            // Meme texte que le catalogue produit pour une coupure reseau: on le
            // reconstruit plutot que de chercher des mots dedans.
            let offline = [URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed]
                .map { ProductCatalog.networkMessage(URLError($0)) }
            return offline.contains(message) ? .offline(message) : .serverError(message)
        }
    }

    enum BarcodeOutcome: Equatable {
        case found(FoodProduct)
        case notFound
        /// Pas de reponse (reseau, serveur) ou produit sans calories connues.
        case unavailable(String)
    }

    /// Comme `product(barcode:)` mais sans confondre "absent" et "pas de reseau".
    static func lookup(barcode: String) async -> BarcodeOutcome {
        switch await ProductCatalog.product(barcode: barcode) {
        case .found(let p):
            guard let f = FoodProduct(p) else {
                return .unavailable("« \(p.name) » est dans Open Food Facts, mais sans calories connues. Saisis-les à la main.")
            }
            return .found(f)
        case .notFound: return .notFound
        case .unavailable(let m): return .unavailable(m)
        }
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

// MARK: - Ajouter au journal (recherche, recents, favoris, perso, repas)
//
// Remplace l'ancien FoodEditor pour le journal Yumzio:
//   - le jour choisi part du jour regarde dans le journal (ajout sur un jour passe);
//   - une panne de recherche dit ce qu'elle est (hors ligne, serveur, aucun resultat);
//   - recents, favoris, aliments perso et repas enregistres marchent hors ligne.
// Toute ecriture passe par FoodJournal.log, donc par FoodLogService.

struct JournalAddSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case search = "Chercher", recents = "Récents", favorites = "Favoris", custom = "Perso", meals = "Repas"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]
    @Query(sort: \FavoriteFood.createdAt, order: .reverse) private var favorites: [FavoriteFood]
    @Query(sort: \CustomFood.name) private var customFoods: [CustomFood]
    @Query(sort: \SavedMeal.createdAt, order: .reverse) private var savedMeals: [SavedMeal]
    @Query private var microRows: [FoodMicros]

    @State private var day: Date
    @State private var meal: String
    @State private var tab: Tab = .search

    @State private var query = ""
    @State private var searching = false
    @State private var outcome: FoodSearchOutcome?
    @State private var searchTask: Task<Void, Never>?

    @State private var picked: Per100Food?
    @State private var grams = "100"

    @State private var manualKcal = ""
    @State private var manualP = ""
    @State private var manualC = ""
    @State private var manualF = ""

    @State private var error: String?
    @State private var lastAdded: String?
    @State private var editingCustom: CustomFood?
    @State private var creatingCustom = false
    @State private var customPrefill = ""

    static let meals = ["Petit-déj", "Déjeuner", "Collation", "Dîner"]

    init(day: Date = .now, defaultMeal: String = "Déjeuner", startTab: Tab = .search) {
        _day = State(initialValue: Calendar.current.startOfDay(for: min(day, .now)))
        _meal = State(initialValue: Self.meals.contains(defaultMeal) ? defaultMeal : "Déjeuner")
        _tab = State(initialValue: startTab)
    }

    private var factor: Double {
        if case .value(let g) = FoodJournal.parse(grams) { return g / 100 }
        return 0
    }
    private var microsIndex: [String: FoodMicroValues] { FoodJournal.microsIndex(microRows) }
    private var logDate: Date { FoodLogService.mealDate(day: day) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Jour", selection: $day, in: ...Date(), displayedComponents: .date)
                    Picker("Repas", selection: $meal) { ForEach(Self.meals, id: \.self) { Text($0) } }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                }
                if let lastAdded {
                    Section {
                        Label("Ajouté : \(lastAdded)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    }
                }
                if let p = picked {
                    portionSection(p)
                } else {
                    Section {
                        Picker("Source", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented)
                    }
                    switch tab {
                    case .search: searchSections
                    case .recents: recentsSection
                    case .favorites: favoritesSection
                    case .custom: customSection
                    case .meals: mealsSection
                    }
                }
            }
            .navigationTitle(picked == nil ? "Ajouter au journal" : "Portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if picked != nil { Button("Retour") { picked = nil } } else { Button("Fermer") { dismiss() } }
                }
            }
            .sheet(isPresented: $creatingCustom) { CustomFoodEditor(food: nil, prefillName: customPrefill) }
            .sheet(item: $editingCustom) { CustomFoodEditor(food: $0) }
        }
    }

    // MARK: Recherche

    @ViewBuilder private var searchSections: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher un aliment (ex : Nutella)", text: $query)
                    .autocorrectionDisabled()
                    .onChange(of: query) { _, q in scheduleSearch(q) }
                if searching { ProgressView() }
            }
        }
        if !searching, let outcome { outcomeSection(outcome) }
        Section("Saisie manuelle") {
            numberRow("Calories", $manualKcal, "kcal")
            numberRow("Protéines", $manualP, "g")
            numberRow("Glucides", $manualC, "g")
            numberRow("Lipides", $manualF, "g")
            Button("Ajouter « \(query.isEmpty ? "…" : query) »") { addManual() }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || manualKcal.isEmpty)
        }
    }

    @ViewBuilder private func outcomeSection(_ o: FoodSearchOutcome) -> some View {
        switch o {
        case .results(let items, _):
            Section("Résultats Open Food Facts") {
                ForEach(items) { prod in
                    Button { pick(prod.per100) } label: { productRow(prod) }.buttonStyle(.plain)
                }
            }
        case .noResults:
            Section {
                Text("Aucun produit trouvé pour « \(query) ».").font(.callout)
                Button { customPrefill = query; creatingCustom = true } label: {
                    Label("Créer « \(query) » comme aliment perso", systemImage: "plus.circle")
                }
            }
        case .onlyUnknownEnergy(let n):
            Section {
                Text("\(n) produit\(n > 1 ? "s" : "") trouvé\(n > 1 ? "s" : ""), mais sans calories connues dans Open Food Facts. Saisis les valeurs de l'étiquette ci-dessous.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .offline(let m):
            Section {
                Label(m, systemImage: "wifi.slash").font(.callout)
                Text("Hors ligne, tes récents, favoris, aliments perso et repas enregistrés marchent toujours.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Réessayer") { scheduleSearch(query, debounce: false) }
            }
        case .serverError(let m):
            Section {
                Label(m, systemImage: "exclamationmark.icloud").font(.callout)
                Button("Réessayer") { scheduleSearch(query, debounce: false) }
            }
        }
    }

    private func productRow(_ prod: FoodProduct) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(prod.name).foregroundStyle(.primary).lineLimit(1)
                Text("\(prod.brand.isEmpty ? "" : prod.brand + " · ")\(prod.kcal) kcal/100 g")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let ns = prod.nutriscore {
                Text(ns.uppercased()).font(.caption2.bold()).foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(nutriColor(ns), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .contentShape(Rectangle())
    }

    private func scheduleSearch(_ q: String, debounce: Bool = true) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { outcome = nil; searching = false; return }
        searching = true
        searchTask = Task {
            if debounce { try? await Task.sleep(nanoseconds: 380_000_000) }
            if Task.isCancelled { return }
            let r = await FoodSearchService.outcome(trimmed)
            if Task.isCancelled { return }
            await MainActor.run { outcome = r; searching = false }
        }
    }

    // MARK: Portion d'un aliment pour 100 g

    private func pick(_ food: Per100Food) {
        picked = food
        grams = FoodJournal.gramsText(food.defaultGrams)
        error = nil
    }

    @ViewBuilder private func portionSection(_ p: Per100Food) -> some View {
        let line = FoodJournal.line(p, grams: factor * 100, meal: meal, date: logDate)
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.headline)
                if !p.brand.isEmpty { Text(p.brand).font(.subheadline).foregroundStyle(.secondary) }
                Text("Pour 100 g : \(Int(p.kcal.rounded())) kcal").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Portion") {
            numberRow("Quantité", $grams, "g")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if p.defaultGrams != 100 {
                        Button("1 portion (\(FoodJournal.gramsText(p.defaultGrams)) g)") { grams = FoodJournal.gramsText(p.defaultGrams) }
                    }
                    ForEach([30, 50, 100, 150, 200], id: \.self) { g in Button("\(g) g") { grams = "\(g)" } }
                }
                .font(.caption.bold()).buttonStyle(.bordered)
            }
        }
        Section("Pour cette portion") {
            LabeledContent("Calories", value: "\(line.draft.calories) kcal")
            LabeledContent("Protéines", value: String(format: "%.1f g", line.draft.protein))
            LabeledContent("Glucides", value: String(format: "%.1f g", line.draft.carbs))
            LabeledContent("Lipides", value: String(format: "%.1f g", line.draft.fat))
            LabeledContent("Fibres", value: FoodJournal.microText(line.micros.fiber))
            LabeledContent("Sucres", value: FoodJournal.microText(line.micros.sugars))
            LabeledContent("Sel", value: FoodJournal.microText(line.micros.salt))
        }
        Section {
            Button { log([line], label: p.name, close: true) } label: {
                Text("Ajouter au journal").frame(maxWidth: .infinity).bold()
            }
            .disabled(factor <= 0)
            Button { addFavorite(line) } label: { Label("Garder en favori avec cette portion", systemImage: "star") }
                .disabled(factor <= 0)
        }
    }

    // MARK: Recents, favoris, perso, repas

    @ViewBuilder private var recentsSection: some View {
        let recents = FoodJournal.recents(entries)
        Section {
            if recents.isEmpty {
                Text("Les aliments que tu journalises apparaîtront ici.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(recents) { r in
                Button {
                    log([JournalLine(draft: .init(name: r.name, calories: r.calories, protein: r.protein, carbs: r.carbs,
                                                  fat: r.fat, meal: meal, date: logDate),
                                     micros: microsIndex[r.microsKey] ?? .unknown)], label: r.name)
                } label: { quickRow(r.name, r.calories, r.protein, r.carbs, r.fat) }
                .buttonStyle(.plain)
                .swipeActions {
                    Button {
                        addFavorite(JournalLine(draft: .init(name: r.name, calories: r.calories, protein: r.protein,
                                                             carbs: r.carbs, fat: r.fat),
                                                micros: microsIndex[r.microsKey] ?? .unknown))
                    } label: { Label("Favori", systemImage: "star") }.tint(.yellow)
                }
            }
        } footer: { if !recents.isEmpty { Text("Touche pour rajouter la même portion. Glisse pour en faire un favori.") } }
    }

    @ViewBuilder private var favoritesSection: some View {
        Section {
            if favorites.isEmpty {
                Text("Touche l'étoile d'un aliment, ou glisse un récent, pour le garder ici.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(favorites) { f in
                Button {
                    log([JournalLine(draft: .init(name: f.name, calories: f.calories, protein: f.protein, carbs: f.carbs,
                                                  fat: f.fat, meal: meal, date: logDate), micros: f.micros)], label: f.name)
                } label: { quickRow(f.name, f.calories, f.protein, f.carbs, f.fat) }
                .buttonStyle(.plain)
            }
            .onDelete { idx in remove(idx.map { favorites[$0] }) }
        }
    }

    @ViewBuilder private var customSection: some View {
        Section {
            Button { customPrefill = ""; creatingCustom = true } label: { Label("Créer un aliment", systemImage: "plus.circle.fill") }
            ForEach(customFoods) { c in
                Button { pick(c.per100) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).foregroundStyle(.primary)
                        Text("\(Int(c.kcalPer100.rounded())) kcal/100 g · portion \(FoodJournal.gramsText(c.portionGrams)) g\(c.portionLabel.isEmpty ? "" : " (\(c.portionLabel))")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) { remove([c]) } label: { Label("Supprimer", systemImage: "trash") }
                    Button { editingCustom = c } label: { Label("Modifier", systemImage: "pencil") }
                }
            }
        } footer: { Text("Tes plats maison et les produits absents de la base. Valeurs pour 100 g.") }
    }

    @ViewBuilder private var mealsSection: some View {
        Section {
            if savedMeals.isEmpty {
                Text("Dans le journal, touche « … » sur un repas puis « Enregistrer ce repas ».")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(savedMeals) { m in
                Button {
                    log(FoodJournal.lines(from: m.items, day: day, mealName: meal), label: m.name)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).foregroundStyle(.primary)
                            Text(m.items.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text("\(m.calories) kcal").font(.subheadline.bold())
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { idx in remove(idx.map { savedMeals[$0] }) }
        }
    }

    private func quickRow(_ name: String, _ kcal: Int, _ p: Double, _ c: Double, _ f: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary).lineLimit(1)
                Text("P\(Int(p)) · G\(Int(c)) · L\(Int(f))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(kcal) kcal").font(.subheadline.bold())
            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
        }
        .contentShape(Rectangle())
        .accessibilityHint("Ajouter au journal")
    }

    private func numberRow(_ label: String, _ value: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(minWidth: 60, maxWidth: 110)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    // MARK: Ecritures

    private func log(_ lines: [JournalLine], label: String, close: Bool = false) {
        var lines = lines
        for i in lines.indices { lines[i].draft.meal = meal }
        do {
            try FoodJournal.log(lines, in: ctx)
            Haptics.success()
            error = nil
            lastAdded = "\(label) · \(FoodJournal.dayTitle(day)) · \(meal)"
            if close { picked = nil }
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }

    private func addManual() {
        var values: [Double] = []
        for s in [manualKcal, manualP, manualC, manualF] {
            switch FoodJournal.parse(s) {
            case .value(let v): values.append(v)
            case .empty: values.append(0)
            case .invalid: error = "Une valeur n'est pas un nombre."; return
            }
        }
        log([JournalLine(draft: .init(name: query, calories: Int(values[0].rounded()), protein: values[1],
                                      carbs: values[2], fat: values[3], meal: meal, date: logDate))], label: query)
        if error == nil { manualKcal = ""; manualP = ""; manualC = ""; manualF = "" }
    }

    private func addFavorite(_ line: JournalLine) {
        let d = line.draft
        if favorites.contains(where: { $0.name == d.name && $0.calories == d.calories }) {
            lastAdded = nil; error = "« \(d.name) » est déjà dans tes favoris avec cette portion."; return
        }
        let f = FavoriteFood(name: d.name, calories: d.calories, protein: d.protein, carbs: d.carbs, fat: d.fat, micros: line.micros)
        ctx.insert(f)
        do { try ctx.save(); Haptics.tap(); error = nil; lastAdded = nil }
        catch { ctx.delete(f); self.error = "Favori non enregistré. Réessaie." }
    }

    private func remove(_ items: [any PersistentModel]) {
        items.forEach { ctx.delete($0) }
        do { try ctx.save() } catch {
            ctx.rollback()
            self.error = "Suppression impossible. Réessaie."
        }
    }
}
