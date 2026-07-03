import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var nutriTint: Color { AppCategory.nutrition.tint } }

// MARK: - Hub Nutrition

struct NutritionHubView: View {
    var body: some View {
        HubScaffold(category: .nutrition) {
            ToolRow(icon: "timer", title: "Jeûne intermittent",
                    subtitle: "16:8, 18:6, OMAD — façon Zero", tint: .nutriTint) { FastingView() }
            ToolRow(icon: "chart.pie.fill", title: "Calories & macros",
                    subtitle: "Journal du jour + objectifs", tint: .nutriTint) { CalAIView() }
            ToolRow(icon: "refrigerator.fill", title: "Mon frigo",
                    subtitle: "Inventaire + idées repas", tint: .nutriTint) { FridgeView() }
            ToolRow(icon: "cart.fill", title: "Liste de courses",
                    subtitle: "Par rayon, cochable", tint: .nutriTint) { ShoppingListView() }
            ToolRow(icon: "drop.fill", title: "Hydratation",
                    subtitle: "Suivi + rappels", tint: .nutriTint) { HydrationView() }
            ToolRow(icon: "pills.fill", title: "Compléments",
                    subtitle: "Rappels personnalisés", tint: .nutriTint) { SupplementsView() }
            ToolRow(icon: "allergens", title: "Allergènes & régimes",
                    subtitle: "Halal, vegan, sans gluten…", tint: .nutriTint) { DietProfileView() }
            ToolRow(icon: "camera.viewfinder", title: "Calories par photo",
                    subtitle: "Cal AI — à brancher", tint: .nutriTint) { PhotoCalorieScaffold() }
            ToolRow(icon: "barcode.viewfinder", title: "Scan code-barres santé",
                    subtitle: "Yuka + prix + alternative", tint: .nutriTint) { ScanProductView() }
        }
    }
}

// MARK: - Jeûne intermittent

struct FastingView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FastingSession.start, order: .reverse) private var sessions: [FastingSession]
    @State private var now = Date()
    @AppStorage("fastTarget") private var target = 16
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var active: FastingSession? { sessions.first(where: { $0.isActive }) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 20) {
                    if active == nil {
                        Picker("Protocole", selection: $target) {
                            Text("16:8").tag(16); Text("18:6").tag(18); Text("20:4").tag(20); Text("OMAD").tag(23)
                        }.pickerStyle(.segmented)
                    }

                    let elapsed = Int(active?.elapsed ?? 0)
                    let goal = (active?.targetHours ?? target) * 3600
                    ZStack {
                        ProgressRing(progress: goal == 0 ? 0 : Double(elapsed) / Double(goal), lineWidth: 16, tint: .nutriTint)
                        VStack(spacing: 4) {
                            Text(formatHMS(elapsed)).font(.system(size: 40, weight: .bold, design: .rounded))
                                .monospacedDigit().foregroundStyle(Theme.textPrimary)
                            Text(active == nil ? "Prêt à jeûner" : "Objectif \(active!.targetHours)h")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 240, height: 240)

                    if let a = active {
                        Text("Début : \(a.start.formatted(date: .omitted, time: .shortened)) · Fin prévue : \(a.start.addingTimeInterval(Double(a.targetHours*3600)).formatted(date: .omitted, time: .shortened))")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                        PrimaryButton(title: "Rompre le jeûne", icon: "fork.knife", tint: .nutriTint) {
                            a.end = Date()
                        }
                    } else {
                        PrimaryButton(title: "Démarrer le jeûne", icon: "play.fill", tint: .nutriTint) {
                            ctx.insert(FastingSession(targetHours: target))
                        }
                    }

                    if !completed.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Historique")
                            ForEach(completed.prefix(8)) { s in
                                HStack {
                                    Text(s.start, style: .date).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(formatHoursMinutes(Int(s.elapsed))).font(.subheadline.bold())
                                        .foregroundStyle(Int(s.elapsed) >= s.targetHours*3600 ? .green : .orange)
                                }
                                .padding(.vertical, 4)
                            }
                        }.card()
                    }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Jeûne intermittent").navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { now = $0 }
    }
    private var completed: [FastingSession] { sessions.filter { !$0.isActive } }
}

struct FoodEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var meal = "Déjeuner"
    @State private var kcal = ""; @State private var p = ""; @State private var c = ""; @State private var f = ""
    // Recherche OpenFoodFacts (des millions de produits, ex : Nutella)
    @State private var results: [FoodProduct] = []
    @State private var searching = false
    @State private var picked: FoodProduct? = nil
    @State private var grams = "100"
    @State private var searchTask: Task<Void, Never>? = nil

    private var factor: Double { (Double(grams) ?? 0) / 100 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Rechercher un aliment (ex : Nutella)", text: $name)
                            .onChange(of: name) { _, q in
                                // Ne pas relancer la recherche juste après avoir sélectionné un produit.
                                if let p = picked, q == p.name { return }
                                scheduleSearch(q)
                            }
                        if searching { ProgressView() }
                    }
                    Picker("Repas", selection: $meal) {
                        ForEach(["Petit-déj", "Déjeuner", "Dîner", "Collation"], id: \.self) { Text($0) }
                    }
                }

                if picked == nil, !results.isEmpty {
                    Section("Résultats") {
                        ForEach(results) { prod in
                            Button { select(prod) } label: { resultRow(prod) }.buttonStyle(.plain)
                        }
                    }
                } else if picked == nil, !searching, name.trimmingCharacters(in: .whitespaces).count >= 2 {
                    Section {
                        Text("Aucun produit trouvé — saisis les valeurs à la main ci-dessous.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let prod = picked {
                    Section("Portion") {
                        HStack {
                            Button { picked = nil } label: { Image(systemName: "chevron.left"); Text("Changer") }
                                .font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
                            Spacer()
                            Text(prod.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        HStack { Text("Quantité (g)"); Spacer()
                            TextField("g", text: $grams).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80) }
                        LabeledContent("Calories", value: "\(Int((Double(prod.kcal) * factor).rounded())) kcal")
                        LabeledContent("Protéines", value: String(format: "%.1f g", prod.protein * factor))
                        LabeledContent("Glucides", value: String(format: "%.1f g", prod.carbs * factor))
                        LabeledContent("Lipides", value: String(format: "%.1f g", prod.fat * factor))
                    }
                } else {
                    Section("Valeurs (manuel)") {
                        HStack { Text("Calories"); Spacer(); TextField("kcal", text: $kcal).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Protéines"); Spacer(); TextField("g", text: $p).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Glucides"); Spacer(); TextField("g", text: $c).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Lipides"); Spacer(); TextField("g", text: $f).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    }
                }
            }
            .navigationTitle("Ajouter un repas").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { add() }.disabled(name.isEmpty) }
            }
        }
    }

    private func resultRow(_ prod: FoodProduct) -> some View {
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
    }

    private func nutriColor(_ g: String) -> Color {
        switch g { case "a": return .green; case "b": return Color(hex: 0x8BC34A); case "c": return .yellow
        case "d": return .orange; default: return .red }
    }

    private func scheduleSearch(_ q: String) {
        picked = nil
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { results = []; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 380_000_000)
            if Task.isCancelled { return }
            let r = await FoodSearchService.search(trimmed)
            if Task.isCancelled { return }
            await MainActor.run { results = r; searching = false }
        }
    }

    private func select(_ prod: FoodProduct) {
        picked = prod; name = prod.name; results = []; searching = false
        if grams.isEmpty { grams = "100" }
    }

    private func add() {
        if let prod = picked {
            ctx.insert(FoodEntry(name: prod.name,
                                 calories: Int((Double(prod.kcal) * factor).rounded()),
                                 protein: prod.protein * factor, carbs: prod.carbs * factor,
                                 fat: prod.fat * factor, meal: meal))
        } else {
            ctx.insert(FoodEntry(name: name, calories: Int(kcal) ?? 0, protein: Double(p) ?? 0,
                                 carbs: Double(c) ?? 0, fat: Double(f) ?? 0, meal: meal))
        }
        dismiss()
    }
}

// MARK: - Frigo + suggestions

struct FridgeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PantryItem.name) private var items: [PantryItem]
    @State private var showAdd = false

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    let suggestions = RecipeEngine.suggest(from: items.map { $0.name })
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Avec ce que tu as", subtitle: "Idées repas")
                            ForEach(suggestions, id: \.name) { r in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(r.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text("\(r.matched)/\(r.ingredients.count) ingrédients").font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Text("\(Int(Double(r.matched)/Double(r.ingredients.count)*100))%")
                                        .font(.subheadline.bold()).foregroundStyle(.nutriTint)
                                }.padding(.vertical, 4)
                            }
                        }.card()
                    }

                    if items.isEmpty {
                        EmptyState(icon: "refrigerator", title: "Frigo vide", message: "Ajoute ce que tu as sous la main.")
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { it in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(it.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text("\(it.quantity) · \(it.location)").font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    if let e = it.expiry { ExpiryBadge(date: e) }
                                    Button(role: .destructive) { ctx.delete(it) } label: { Image(systemName: "trash").font(.caption) }
                                        .foregroundStyle(.red.opacity(0.7))
                                }.card(padding: 12)
                            }
                        }
                    }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Mon frigo").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { PantryEditor() }
    }
}

struct ExpiryBadge: View {
    let date: Date
    private var days: Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0 }
    var body: some View {
        Text(days < 0 ? "Périmé" : days == 0 ? "Aujourd'hui" : "J-\(days)")
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((days <= 1 ? Color.red : days <= 3 ? .orange : .green).opacity(0.2), in: Capsule())
            .foregroundStyle(days <= 1 ? .red : days <= 3 ? .orange : .green)
    }
}

struct PantryEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var qty = "1"
    @State private var category = "Légume"; @State private var location = "Frigo"
    @State private var hasExpiry = false; @State private var expiry = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                TextField("Quantité", text: $qty)
                Picker("Catégorie", selection: $category) { ForEach(["Légume","Fruit","Protéine","Laitier","Féculent","Épicerie","Boisson"], id: \.self) { Text($0) } }
                Picker("Endroit", selection: $location) { ForEach(["Frigo","Placard","Congélateur"], id: \.self) { Text($0) } }
                Toggle("Date de péremption", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Périme le", selection: $expiry, displayedComponents: .date) }
            }
            .navigationTitle("Ajouter au frigo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(PantryItem(name: name, quantity: qty, category: category, location: location, expiry: hasExpiry ? expiry : nil)); dismiss()
                }.disabled(name.isEmpty) }
            }
        }
    }
}

/// Moteur de suggestion de recettes basé sur les ingrédients disponibles.
enum RecipeEngine {
    struct Recipe { let name: String; let ingredients: [String]; var matched: Int = 0 }
    static let db: [Recipe] = [
        Recipe(name: "Omelette aux légumes", ingredients: ["oeuf","poivron","oignon","fromage"]),
        Recipe(name: "Pâtes à la tomate", ingredients: ["pâtes","tomate","ail","huile"]),
        Recipe(name: "Poulet riz curry", ingredients: ["poulet","riz","oignon","curry"]),
        Recipe(name: "Salade complète", ingredients: ["salade","tomate","thon","maïs","oeuf"]),
        Recipe(name: "Bowl avocat", ingredients: ["avocat","oeuf","pain","tomate"]),
        Recipe(name: "Soupe de légumes", ingredients: ["carotte","poireau","pomme de terre","oignon"]),
        Recipe(name: "Riz sauté", ingredients: ["riz","oeuf","oignon","poivron","sauce soja"]),
        Recipe(name: "Wrap poulet", ingredients: ["tortilla","poulet","salade","tomate","fromage"])
    ]
    static func suggest(from have: [String]) -> [Recipe] {
        let lower = have.map { $0.lowercased() }
        return db.map { r in
            var c = r
            c.matched = r.ingredients.filter { ing in lower.contains(where: { $0.contains(ing) || ing.contains($0) }) }.count
            return c
        }
        .filter { $0.matched >= 2 }
        .sorted { Double($0.matched)/Double($0.ingredients.count) > Double($1.matched)/Double($1.ingredients.count) }
    }
}

// MARK: - Liste de courses

struct ShoppingListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ShoppingItem.aisle) private var items: [ShoppingItem]
    @State private var newItem = ""

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                HStack {
                    TextField("Ajouter un article…", text: $newItem)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .foregroundStyle(.nutriTint).disabled(newItem.isEmpty)
                }.padding()

                if items.isEmpty {
                    EmptyState(icon: "cart", title: "Liste vide", message: "Ajoute des articles ou génère depuis un plan repas.")
                    Spacer()
                } else {
                    List {
                        ForEach(groupedAisles, id: \.self) { aisle in
                            Section(aisle) {
                                ForEach(items.filter { $0.aisle == aisle }) { it in
                                    Button { it.checked.toggle() } label: {
                                        HStack {
                                            Image(systemName: it.checked ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(it.checked ? .green : Theme.textSecondary)
                                            Text(it.name).strikethrough(it.checked).foregroundStyle(it.checked ? Theme.textSecondary : Theme.textPrimary)
                                            Spacer()
                                            Text(it.quantity).font(.caption).foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                }
                                .onDelete { idx in
                                    let arr = items.filter { $0.aisle == aisle }
                                    idx.map { arr[$0] }.forEach(ctx.delete)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Liste de courses").navigationBarTitleDisplayMode(.inline)
    }
    private var groupedAisles: [String] { Array(Set(items.map { $0.aisle })).sorted() }
    private func add() {
        guard !newItem.isEmpty else { return }
        ctx.insert(ShoppingItem(name: newItem, aisle: Aisle.guess(newItem)))
        newItem = ""
    }
}

enum Aisle {
    static func guess(_ name: String) -> String {
        let n = name.lowercased()
        if ["lait","yaourt","fromage","beurre","crème"].contains(where: n.contains) { return "Crèmerie" }
        if ["pomme","banane","salade","tomate","carotte","légume","fruit"].contains(where: n.contains) { return "Fruits & légumes" }
        if ["poulet","boeuf","poisson","jambon","viande","thon"].contains(where: n.contains) { return "Boucherie" }
        if ["pain","baguette","croissant"].contains(where: n.contains) { return "Boulangerie" }
        if ["pâtes","riz","farine","sucre","huile","conserve"].contains(where: n.contains) { return "Épicerie" }
        return "Divers"
    }
}

// MARK: - Hydratation

struct HydrationView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var entries: [WaterEntry]
    @AppStorage("waterGoal") private var goalML = 2500
    @AppStorage("waterReminder") private var reminderOn = false

    private var todayML: Int { entries.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        ProgressRing(progress: Double(todayML)/Double(max(1,goalML)), lineWidth: 16, tint: .nutriTint)
                        VStack {
                            Text("\(todayML)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                            Text("/ \(goalML) ml").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }.frame(width: 220, height: 220)
                    HStack(spacing: 12) {
                        addBtn(250, "cup.and.saucer.fill"); addBtn(500, "waterbottle.fill"); addBtn(750, "drop.fill")
                    }
                    Toggle("Rappels toutes les 2h (9h-21h)", isOn: $reminderOn)
                        .tint(.nutriTint)
                        .onChange(of: reminderOn) { _, on in on ? scheduleReminders() : cancelReminders() }
                        .card()
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Hydratation").navigationBarTitleDisplayMode(.inline)
        .task { syncWaterToContext() }
        .onChange(of: entries.count) { _, _ in syncWaterToContext() }
    }
    private func syncWaterToContext() {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app") else { return }
        grp.set(todayML, forKey: "today_water_ml")
    }
    private func addBtn(_ ml: Int, _ icon: String) -> some View {
        Button { ctx.insert(WaterEntry(amountML: ml)); syncWaterToContext(); Haptics.tap() } label: {
            VStack(spacing: 6) { Image(systemName: icon).font(.title2); Text("\(ml)").font(.caption.bold()) }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .foregroundStyle(.nutriTint)
        }
    }
    private func scheduleReminders() {
        for h in stride(from: 9, through: 21, by: 2) {
            NotificationManager.shared.scheduleDaily(id: "water\(h)", title: "Hydrate-toi 💧", body: "Un verre d'eau, ça fait du bien.", hour: h, minute: 0)
        }
    }
    private func cancelReminders() { for h in stride(from: 9, through: 21, by: 2) { NotificationManager.shared.cancel(id: "water\(h)") } }
}

// MARK: - Compléments

struct SupplementsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Supplement.hour) private var supps: [Supplement]
    @State private var name = ""
    @State private var time = Date()
    @State private var withFood = true
    @State private var confirm = true
    @State private var reco: SuppReco? = nil

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    addCard
                    if supps.isEmpty {
                        EmptyState(icon: "pills", title: "Aucun complément")
                            .padding(.top, 24)
                    } else {
                        VStack(spacing: 10) { ForEach(supps) { suppRow($0) } }
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Compléments").navigationBarTitleDisplayMode(.inline)
    }

    // Carte d'ajout : reco calculée EN DIRECT pendant la frappe.
    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Nom (ex: Oméga 3, Magnésium, Ashwagandha…)", text: $name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: name) { _, v in applyReco(v) }

            if let r = reco, !name.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: r.icon).font(.title3).foregroundStyle(.nutriTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(r.momentLabel) · \(withFood ? "avec un repas" : "à jeun")")
                            .font(.subheadline.weight(.semibold))
                        Text(r.advice).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.nutriTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                    Spacer()
                    Toggle("Avec un repas", isOn: $withFood).tint(.nutriTint)
                }
                Toggle("Vérif « bien pris ? » ~1h30 après", isOn: $confirm)
                    .tint(.nutriTint).font(.subheadline)
            }

            Button { add() } label: {
                Label("Ajouter", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.nutriTint).disabled(name.isEmpty)
        }
        .padding()
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
    }

    private func suppRow(_ s: Supplement) -> some View {
        let key = "supp\(s.persistentModelID.hashValue)"
        let streak = ConfirmationStore.shared.streak(key)
        return HStack(spacing: 12) {
            Image(systemName: "pills.fill").foregroundStyle(.nutriTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.body.weight(.medium))
                Text("\(momentLabel(s.moment)) · \(s.withFood ? "avec repas" : "à jeun") · \(String(format: "%02d:%02d", s.hour, s.minute))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if streak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.caption).foregroundStyle(.orange)
                    Text("\(streak)").font(.caption.weight(.bold)).foregroundStyle(.orange)
                }
            }
            Toggle("", isOn: Binding(get: { s.active }, set: { s.active = $0; reschedule(s) }))
                .labelsHidden().tint(.nutriTint)
        }
        .padding(12)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) { delete(s) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func momentLabel(_ m: String) -> String {
        m == "soir" ? "Le soir" : (m == "midi" ? "Le midi" : "Le matin")
    }

    private func applyReco(_ v: String) {
        guard !v.trimmingCharacters(in: .whitespaces).isEmpty else { reco = nil; return }
        let r = SupplementAdvisor.reco(for: v)
        reco = r
        withFood = r.withFood
        var c = DateComponents(); c.hour = r.hour; c.minute = r.minute
        if let d = Calendar.current.date(from: c) { time = d }
    }

    private func add() {
        let r = reco ?? SupplementAdvisor.reco(for: name)
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let s = Supplement(name: name.trimmingCharacters(in: .whitespaces),
                           hour: c.hour ?? r.hour, minute: c.minute ?? r.minute,
                           moment: r.moment, withFood: withFood, advice: r.advice, confirm: confirm)
        ctx.insert(s); reschedule(s)
        name = ""; reco = nil; withFood = true; confirm = true
    }

    private func delete(_ s: Supplement) {
        let id = "supp\(s.persistentModelID.hashValue)"
        NotificationManager.shared.cancel(id: id)
        NotificationManager.shared.cancel(id: id + ".confirm")
        ctx.delete(s)
    }

    private func reschedule(_ s: Supplement) {
        let id = "supp\(s.persistentModelID.hashValue)"
        let confirmId = id + ".confirm"
        NotificationManager.shared.cancel(id: id)
        NotificationManager.shared.cancel(id: confirmId)
        guard s.active else { return }
        NotificationManager.shared.scheduleDaily(
            id: id, title: "💊 \(s.name)",
            body: "C'est le moment — \(momentLabel(s.moment).lowercased()), \(s.withFood ? "avec un repas" : "à jeun").",
            hour: s.hour, minute: s.minute)
        if s.confirm {
            let total = s.hour * 60 + s.minute + 90
            NotificationManager.shared.scheduleDailyAction(
                id: confirmId, title: "Petite vérif 💊",
                body: "Tu as bien pris ton \(s.name) ?",
                hour: (total / 60) % 24, minute: total % 60,
                categoryId: "LIFEOS_CONFIRM",
                userInfo: ["confirmKey": id, "confirmLabel": s.name])
        }
    }
}

// MARK: - Allergènes & régimes

struct DietProfileView: View {
    @AppStorage("dietFlags") private var flagsRaw = ""
    @State private var test = ""

    private let diets = ["Halal","Casher","Vegan","Végétarien","Sans gluten","Sans lactose","Sans porc","Sans fruits à coque"]
    private var flags: Set<String> { Set(flagsRaw.split(separator: "|").map(String.init)) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Mes régimes & restrictions")
                        ForEach(diets, id: \.self) { d in
                            Toggle(d, isOn: Binding(
                                get: { flags.contains(d) },
                                set: { on in var f = flags; if on { f.insert(d) } else { f.remove(d) }; flagsRaw = f.joined(separator: "|") }
                            )).tint(.nutriTint)
                        }
                    }.card()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Tester un ingrédient")
                        TextField("Ex: gélatine, gluten, lait…", text: $test).textFieldStyle(.roundedBorder)
                        if !test.isEmpty {
                            let issues = AllergenChecker.check(test, against: flags)
                            if issues.isEmpty {
                                Label("Compatible avec ton profil ✓", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                            } else {
                                ForEach(issues, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            }
                        }
                    }.card()
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Allergènes & régimes").navigationBarTitleDisplayMode(.inline)
    }
}

enum AllergenChecker {
    static func check(_ ingredient: String, against flags: Set<String>) -> [String] {
        let n = ingredient.lowercased(); var issues: [String] = []
        let rules: [(String, [String])] = [
            ("Sans gluten", ["gluten","blé","orge","seigle","farine"]),
            ("Sans lactose", ["lait","lactose","crème","beurre","fromage"]),
            ("Vegan", ["lait","oeuf","miel","gélatine","viande","poisson","beurre","fromage"]),
            ("Végétarien", ["viande","poulet","boeuf","poisson","gélatine"]),
            ("Halal", ["porc","alcool","gélatine","lard"]),
            ("Sans porc", ["porc","lard","jambon","bacon"]),
            ("Sans fruits à coque", ["amande","noisette","noix","cajou","pistache"])
        ]
        for (diet, words) in rules where flags.contains(diet) {
            if words.contains(where: n.contains) { issues.append("Incompatible : \(diet)") }
        }
        return issues
    }
}

// MARK: - Scaffolds IA

struct PhotoCalorieScaffold: View {
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 56)).foregroundStyle(.nutriTint).padding(.top, 30)
                    Text("Calories par photo").font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                    IntegrationNotice(text: "Reconnaître un plat et estimer ses calories nécessite un modèle de vision (comme Cal AI). Branchement prévu : capture photo → envoi à une API de food-recognition (ex: une fonction Cloud avec un modèle multimodal) → retour kcal + macros, qui s'insèrent automatiquement dans ton journal.")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Étapes d'activation").font(.headline).foregroundStyle(Theme.textPrimary)
                        bullet("1. Caméra : VisionKit / AVCapture (déjà autorisé dans Info.plist)")
                        bullet("2. Endpoint d'analyse : modèle multimodal côté serveur")
                        bullet("3. Mapping résultat → FoodEntry (déjà prêt dans l'app)")
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Cal AI").navigationBarTitleDisplayMode(.inline)
    }
    private func bullet(_ t: String) -> some View { Text("• " + t).font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
}

struct BarcodeScaffold: View {
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "barcode.viewfinder").font(.system(size: 56)).foregroundStyle(.nutriTint).padding(.top, 30)
                    Text("Scan santé + prix + alternative").font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                    IntegrationNotice(text: "Le scan d'un code-barres peut être 100% fonctionnel via l'API gratuite OpenFoodFacts (note santé Nutri-Score + additifs, comme Yuka). L'enrichissement « prix + alternative moins chère en rayon » nécessite une base prix (API enseigne ou crowdsourcing). Le lecteur de code-barres natif (VisionKit) est prêt à brancher.")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ce qui est gratuit & branchable tout de suite").font(.headline).foregroundStyle(Theme.textPrimary)
                        bullet("Lecture code-barres : DataScannerViewController (VisionKit)")
                        bullet("Fiche produit + Nutri-Score : api.openfoodfacts.org (gratuit)")
                        bullet("Alternatives plus saines : champ « comparé à » d'OpenFoodFacts")
                        bullet("Prix : à connecter à une source enseigne (payant/scraping)")
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Scan santé").navigationBarTitleDisplayMode(.inline)
    }
    private func bullet(_ t: String) -> some View { Text("• " + t).font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
}
