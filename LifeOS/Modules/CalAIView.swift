import SwiftUI
import SwiftData
import VisionKit

/// Écran calories façon Cal AI : calories restantes + anneau, macros, bande de dates, streak, repas du jour.
struct CalAIView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]

    @AppStorage("kcalGoal") private var kcalGoal = 2200
    @AppStorage("proteinGoal") private var proteinGoal = 150
    @AppStorage("carbGoal") private var carbGoal = 250
    @AppStorage("fatGoal") private var fatGoal = 70

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showAdd = false
    @State private var showScan = false

    private let cal = Calendar.current

    /// Repas suggéré selon l'heure (pré-rempli au scan / ajout).
    private var currentMeal: String {
        switch cal.component(.hour, from: .now) {
        case 5..<11:  return "Petit-déj"
        case 11..<15: return "Déjeuner"
        case 15..<18: return "Collation"
        default:      return "Dîner"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                dateStrip
                caloriesCard
                quickActions
                macrosRow
                mealsSection
                historySection
            }
            .padding(Theme.pad)
        }
        .background(Theme.bg)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
        } }
        .sheet(isPresented: $showAdd) { FoodEditor() }
        .sheet(isPresented: $showScan) { BarcodeAddSheet(defaultMeal: currentMeal) }
        .task { syncNutritionToContext() }
        .onChange(of: foods.count) { _, _ in syncNutritionToContext() }
    }

    private func syncNutritionToContext() {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app") else { return }
        grp.set(totals.kcal, forKey: "today_kcal")
        grp.set(Int(totals.p), forKey: "today_protein_g")
    }

    // MARK: Actions rapides (Scanner code-barres + Ajouter)

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button { showScan = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "barcode.viewfinder").font(.system(size: 17, weight: .bold))
                    Text("Scanner").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Theme.onVolt)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Theme.volt, in: Capsule())
            }
            Button { showAdd = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .bold))
                    Text("Rechercher").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Theme.cardFill, in: Capsule())
            }
        }
        .buttonStyle(PressableButtonStyle())
>>>>>>> origin/pote
    }

    // MARK: En-tête + streak

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "flame.circle.fill").font(.largeTitle).foregroundStyle(Theme.textPrimary)
                Text("Calories").nikeTitle()
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").foregroundStyle(Theme.volt)
                Text("\(streak)").font(.headline.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.cardFill, in: Capsule())
        }
    }

    // MARK: Bande de dates

    private var dateStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                let isSel = cal.isDate(day, inSameDayAs: selectedDay)
                let isFuture = day > cal.startOfDay(for: .now)
                Button { selectedDay = day } label: {
                    VStack(spacing: 6) {
                        Text(weekdayShort(day)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        ZStack {
                            Circle()
                                .fill(isSel ? Color.primary : Color.clear)
                                .overlay(Circle().stroke(isSel ? Color.clear : Color.secondary.opacity(0.3),
                                                         style: StrokeStyle(lineWidth: 1.5, dash: isFuture ? [3] : [])))
                            Text("\(cal.component(.day, from: day))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSel ? Color(uiColor: .systemBackground) : (isFuture ? .secondary : .primary))
                        }
                        .frame(width: 38, height: 38)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
            }
        }
    }

    // MARK: Carte calories

    private var caloriesCard: some View {
        let consumed = totals.kcal
        let left = kcalGoal - consumed
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(left)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(left < 0 ? .red : .primary)
                    .contentTransition(.numericText())
                Text(left >= 0 ? "Calories restantes" : "Calories dépassées")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                ProgressRing(progress: kcalGoal == 0 ? 0 : Double(consumed) / Double(kcalGoal), lineWidth: 11, tint: Theme.volt)
                Image(systemName: "flame.fill").font(.title2).foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 92, height: 92)
        }
        .card(padding: 20, radius: 26)
    }

    // MARK: Macros

    private var macrosRow: some View {
        HStack(spacing: 12) {
            macroCard("Protéines", left: proteinGoal - Int(totals.p), goal: proteinGoal, value: Int(totals.p),
                      icon: "fork.knife", color: Color(hex: 0xF0584B))
            macroCard("Glucides", left: carbGoal - Int(totals.c), goal: carbGoal, value: Int(totals.c),
                      icon: "leaf.fill", color: Color(hex: 0xE0A23C))
            macroCard("Lipides", left: fatGoal - Int(totals.f), goal: fatGoal, value: Int(totals.f),
                      icon: "drop.fill", color: Color(hex: 0x4FA8E0))
        }
    }

    private func macroCard(_ label: String, left: Int, goal: Int, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(max(0, left))g").font(.title3.bold())
            Text("\(label) restant").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            ZStack {
                ProgressRing(progress: goal == 0 ? 0 : Double(value) / Double(goal), lineWidth: 7, tint: color)
                Image(systemName: icon).font(.caption).foregroundStyle(color)
            }
            .frame(width: 50, height: 50)
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Repas du jour

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repas du jour").nikeTitle(20)
            if dayFoods.isEmpty {
                Button { showScan = true } label: {
                    HStack(spacing: 14) {
<<<<<<< HEAD
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("Touche + pour ajouter ton premier repas").font(.subheadline).foregroundStyle(.secondary)
=======
                        Text("🥗").font(.system(size: 34))
                        Text("Scanne un produit ou touche Rechercher pour ajouter ton premier repas").font(.subheadline).foregroundStyle(.secondary)
>>>>>>> origin/pote
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }.buttonStyle(.plain)
            } else {
                ForEach(orderedMeals, id: \.self) { m in
                    mealGroup(m, dayFoods.filter { $0.meal == m })
                }
            }
        }
    }

    /// Repas présents aujourd'hui, ordonnés par heure du 1er aliment.
    private var orderedMeals: [String] {
        let groups = Dictionary(grouping: dayFoods, by: { $0.meal })
        return groups.keys.sorted {
            (groups[$0]?.map(\.date).min() ?? .now) < (groups[$1]?.map(\.date).min() ?? .now)
        }
    }

    private func mealGroup(_ meal: String, _ items: [FoodEntry]) -> some View {
        let kcal = items.reduce(0) { $0 + $1.calories }
        return VStack(spacing: 0) {
            HStack {
                Text(meal.uppercased()).font(.system(size: 12, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(kcal) kcal").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.volt)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ForEach(items.sorted(by: { $0.date < $1.date })) { f in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text("P\(Int(f.protein)) · G\(Int(f.carbs)) · L\(Int(f.fat))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(f.calories)").font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
                .contextMenu { Button(role: .destructive) { ctx.delete(f); Haptics.tap() } label: { Label("Supprimer", systemImage: "trash") } }
                if f.id != items.sorted(by: { $0.date < $1.date }).last?.id {
                    Divider().overlay(Theme.hairline).padding(.leading, 14)
                }
            }
            .padding(.bottom, 4)
        }
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Historique 7 jours + tendance

    private var last7: [(day: Date, kcal: Int)] {
        (0..<7).reversed().map { off in
            let d = cal.date(byAdding: .day, value: -off, to: cal.startOfDay(for: .now))!
            let k = foods.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.calories }
            return (d, k)
        }
    }

    private var historySection: some View {
        let data = last7
        let logged = data.filter { $0.kcal > 0 }
        let avg = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.kcal } / logged.count
        let maxV = max(kcalGoal, data.map(\.kcal).max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("7 derniers jours").nikeTitle(20)
                Spacer()
                if avg > 0 {
                    Text("moy. \(avg) kcal").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(data, id: \.day) { e in
                    let over = e.kcal > kcalGoal
                    VStack(spacing: 6) {
                        Text(e.kcal > 0 ? "\(e.kcal)" : "")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(e.kcal == 0 ? AnyShapeStyle(Color.primary.opacity(0.08))
                                              : AnyShapeStyle(over ? Color(hex: 0xF0584B) : Theme.volt))
                            .frame(height: max(4, 96 * CGFloat(e.kcal) / CGFloat(maxV)))
                        Text(weekdayLetter(e.day))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(cal.isDateInToday(e.day) ? Theme.textPrimary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
            HStack(spacing: 6) {
                Circle().fill(Theme.volt).frame(width: 7, height: 7)
                Text("Objectif \(kcalGoal) kcal").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func weekdayLetter(_ d: Date) -> String {
        ["D", "L", "M", "M", "J", "V", "S"][cal.component(.weekday, from: d) - 1]
    }

    // MARK: Données

    private var dayFoods: [FoodEntry] { foods.filter { cal.isDate($0.date, inSameDayAs: selectedDay) } }
    private var totals: (kcal: Int, p: Double, c: Double, f: Double) {
        dayFoods.reduce((0, 0.0, 0.0, 0.0)) { ($0.0 + $1.calories, $0.1 + $1.protein, $0.2 + $1.carbs, $0.3 + $1.fat) }
    }
    private var weekDays: [Date] {
        (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0 + 1, to: cal.startOfDay(for: .now))! }
    }
    private var streak: Int {
        var c = 0
        var day = cal.startOfDay(for: .now)
        let hasFood: (Date) -> Bool = { d in foods.contains { cal.isDate($0.date, inSameDayAs: d) } }
        if !hasFood(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while hasFood(day) { c += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return c
    }
    private func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE"
        return String(f.string(from: d).prefix(3)).capitalized
    }
}

// MARK: - Scan code-barres → ajout direct au journal

struct BarcodeAddSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    var defaultMeal: String = "Déjeuner"

    @State private var product: FoodProduct?
    @State private var grams = "100"
    @State private var meal = "Déjeuner"
    @State private var loadingCode: String?
    @State private var notFound = false
    @State private var manual = ""

    private let meals = ["Petit-déj", "Déjeuner", "Collation", "Dîner"]
    private var factor: Double { (Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0) / 100 }
    private var scannerAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            Group {
                if let p = product { confirm(p) } else { scanner }
            }
            .navigationTitle(product == nil ? "Scanner" : "Ajouter au journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                if product != nil {
                    ToolbarItem(placement: .topBarTrailing) { Button("Re-scanner") { product = nil } }
                }
            }
        }
        .onAppear { meal = defaultMeal }
        .alert("Produit introuvable", isPresented: $notFound) {
            Button("OK", role: .cancel) {}
        } message: { Text("Ce code-barres n'est pas dans OpenFoodFacts. Essaie « Rechercher » par nom.") }
    }

    @ViewBuilder private var scanner: some View {
        if scannerAvailable {
            ZStack {
                BarcodeScanner { lookup($0) }.ignoresSafeArea()
                VStack {
                    Spacer()
                    Group {
                        if loadingCode != nil {
                            HStack(spacing: 8) { ProgressView().tint(.white); Text("Recherche…").foregroundStyle(.white) }
                        } else {
                            Label("Vise le code-barres du produit", systemImage: "barcode.viewfinder").foregroundStyle(.white)
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 44)
                }
            }
        } else {
            Form {
                Section("Scanner indisponible ici") {
                    Text("Le scan caméra marche sur un vrai iPhone. En attendant, entre un code-barres.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Code-barres") {
                    TextField("Ex. 3017620422003 (Nutella)", text: $manual).keyboardType(.numberPad)
                    Button("Chercher ce code") { lookup(manual) }.disabled(manual.count < 6)
                }
            }
        }
    }

    private func confirm(_ p: FoodProduct) -> some View {
        let kcal = Int(Double(p.kcal) * factor)
        return Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.name).font(.headline)
                    HStack(spacing: 8) {
                        if !p.brand.isEmpty {
                            Text(p.brand).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let ns = p.nutriscore {
                            Text(ns.uppercased()).font(.caption2.weight(.black)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(nutriColor(ns), in: Capsule())
                        }
                    }
                    Text("Pour 100 g : \(p.kcal) kcal").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Portion") {
                HStack {
                    Text("Quantité")
                    Spacer()
                    TextField("100", text: $grams).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).frame(width: 80)
                    Text("g").foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach([30, 50, 100, 150, 200], id: \.self) { g in
                        Button("\(g)g") { grams = "\(g)" }
                            .font(.caption.bold()).buttonStyle(.bordered).tint(.secondary)
                    }
                }
            }
            Section("Pour cette portion") {
                macroRow("Calories", "\(kcal) kcal")
                macroRow("Protéines", "\(Int(p.protein * factor)) g")
                macroRow("Glucides", "\(Int(p.carbs * factor)) g")
                macroRow("Lipides", "\(Int(p.fat * factor)) g")
            }
            Section {
                Picker("Repas", selection: $meal) { ForEach(meals, id: \.self) { Text($0) } }
            }
            Section {
                Button {
                    ctx.insert(FoodEntry(date: .now, name: p.name, calories: kcal,
                                         protein: p.protein * factor, carbs: p.carbs * factor,
                                         fat: p.fat * factor, meal: meal))
                    Haptics.success(); dismiss()
                } label: { Text("Ajouter au journal").frame(maxWidth: .infinity).bold() }
                    .buttonStyle(.borderedProminent).tint(Theme.volt)
                    .disabled(factor <= 0)
            }
        }
    }

    private func macroRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).font(.body.weight(.semibold)) }
    }

    private func lookup(_ code: String) {
        guard loadingCode == nil else { return }
        loadingCode = code
        Task {
            let p = await FoodSearchService.product(barcode: code)
            await MainActor.run {
                loadingCode = nil
                if let p { product = p; grams = "100"; Haptics.medium() }
                else { notFound = true; Haptics.tap() }
            }
        }
    }
}
