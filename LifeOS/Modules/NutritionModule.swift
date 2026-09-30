import SwiftUI
import Charts
import WidgetKit
import SwiftData

extension ShapeStyle where Self == Color { static var nutriTint: Color { AppCategory.nutrition.tint } }

// MARK: - Hub Nutrition


// MARK: - Jeûne intermittent

/// Chiffres de l'historique de jeune, calcules sans effet de bord (testes).
enum FastingStats {
    struct Summary: Equatable { let count: Int; let reached: Int; let averageHours: Double }
    static func summary(_ done: [(start: Date, end: Date, targetHours: Int)]) -> Summary {
        guard !done.isEmpty else { return .init(count: 0, reached: 0, averageHours: 0) }
        let hours = done.map { max(0, $0.end.timeIntervalSince($0.start)) / 3600 }
        let reached = zip(done, hours).filter { $1 >= Double($0.targetHours) }.count
        return .init(count: done.count, reached: reached, averageHours: hours.reduce(0, +) / Double(done.count))
    }
    /// Un debut corrige ne peut pas etre dans le futur ni avant 72 h.
    static func clampStart(_ d: Date, now: Date = .now) -> Date {
        min(now, max(now.addingTimeInterval(-72 * 3600), d))
    }
}

struct FastingView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FastingSession.start, order: .reverse) private var sessions: [FastingSession]
    @State private var now = Date()
    @State private var saveError: String?
    @AppStorage(AppStorageKeys.fastTarget) private var target = 16
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let endNotificationID = "fasting.end"

    private var active: FastingSession? { sessions.first(where: { $0.isActive }) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 20) {
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning)
                    }
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
                            Text(formatHMS(elapsed)).font(.system(size: 40, weight: .bold))
                                .monospacedDigit().foregroundStyle(Theme.textPrimary)
                            Text(active.map { "Objectif \($0.targetHours)h" } ?? "Prêt à jeûner")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 240, height: 240)

                    if let a = active {
                        // Debut corrigeable : on oublie souvent de lancer le chrono au dernier repas.
                        DatePicker("Début", selection: Binding(
                            get: { a.start },
                            set: { a.start = FastingStats.clampStart($0); commit("correction du début"); scheduleEnd(a) }),
                                   in: Date().addingTimeInterval(-72 * 3600)...Date(),
                                   displayedComponents: [.date, .hourAndMinute])
                            .font(.footnote)
                        Text("Fin prévue : \(a.start.addingTimeInterval(Double(a.targetHours*3600)).formatted(date: .omitted, time: .shortened)) · une notification te prévient.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                        PrimaryButton(title: "Rompre le jeûne", icon: "fork.knife", tint: .nutriTint) {
                            a.end = Date()
                            if commit("fin du jeûne") { NotificationManager.shared.cancel(id: Self.endNotificationID) } else { a.end = nil }
                        }
                    } else {
                        PrimaryButton(title: "Démarrer le jeûne", icon: "play.fill", tint: .nutriTint) {
                            let s = FastingSession(targetHours: target)
                            ctx.insert(s)
                            if commit("début du jeûne") { scheduleEnd(s) } else { ctx.delete(s) }
                        }
                    }

                    if !completed.isEmpty {
                        let st = FastingStats.summary(completed.compactMap { s in s.end.map { (s.start, $0, s.targetHours) } })
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Historique",
                                          subtitle: "\(st.reached)/\(st.count) objectifs atteints · moyenne \(String(format: "%.1f", st.averageHours)) h")
                            ForEach(completed.prefix(12)) { s in
                                let ok = Int(s.elapsed) >= s.targetHours*3600
                                HStack {
                                    Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                                        .foregroundStyle(ok ? Theme.success : Theme.warning)
                                        .accessibilityLabel(ok ? "objectif atteint" : "objectif non atteint")
                                    Text(s.start, style: .date).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(formatHoursMinutes(Int(s.elapsed))) / \(s.targetHours) h").font(.subheadline.bold())
                                        .foregroundStyle(ok ? Theme.success : Theme.warning)
                                }
                                .padding(.vertical, 4)
                                .contextMenu {
                                    Button(role: .destructive) { ctx.delete(s); _ = commit("suppression") } label: { Label("Supprimer", systemImage: "trash") }
                                }
                            }
                            Text("Appui long sur une ligne pour la supprimer.").font(.caption2).foregroundStyle(Theme.textSecondary)
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

    /// Enregistre et dit si ca a marche ; l'erreur s'affiche au lieu d'etre avalee.
    @discardableResult
    private func commit(_ what: String) -> Bool {
        do { try ctx.save(); saveError = nil; return true }
        catch { saveError = "Échec de l'enregistrement (\(what)) : \(error.localizedDescription)"; return false }
    }

    private func scheduleEnd(_ s: FastingSession) {
        NotificationManager.shared.schedule(id: Self.endNotificationID, title: "Objectif de jeûne atteint",
                                            body: "\(s.targetHours) h de jeûne : tu peux manger.",
                                            at: s.start.addingTimeInterval(Double(s.targetHours * 3600)))
    }
}

struct FoodEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var meal = "Déjeuner"
    @State private var kcal = ""; @State private var p = ""; @State private var c = ""; @State private var f = ""
    // Recherche OpenFoodFacts (des millions de produits, ex : Nutella)
    @State private var results: [FoodProduct] = []
    @State private var searching = false
    @State private var picked: FoodProduct?
    @State private var saveError: String?
    @State private var grams = "100"
    @State private var searchTask: Task<Void, Never>?

    private var factor: Double { (Double(grams) ?? 0) / 100 }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    }
                }
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
                                .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.finance)
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
        switch g { case "a": return Theme.success; case "b": return Color(hex: 0x8BC34A); case "c": return Theme.learning
        case "d": return Theme.warning; default: return Theme.danger }
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

    /// La feuille ne se ferme que si le repas est vraiment ecrit. Avant, elle
    /// inserait sans enregistrer puis se fermait, quoi qu'il arrive.
    private func add() {
        let draft: FoodLogService.Draft
        if let prod = picked {
            draft = .init(name: prod.name,
                          calories: Int((Double(prod.kcal) * factor).rounded()),
                          protein: prod.protein * factor, carbs: prod.carbs * factor,
                          fat: prod.fat * factor, meal: meal)
        } else {
            draft = .init(name: name, calories: Int(kcal) ?? 0, protein: Double(p) ?? 0,
                          carbs: Double(c) ?? 0, fat: Double(f) ?? 0, meal: meal)
        }
        do {
            try FoodLogService.log([draft], in: ctx)
            dismiss()
        } catch {
            Haptics.warning()
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Frigo + suggestions

struct FridgeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \PantryItem.name) private var items: [PantryItem]
    @Query private var shopping: [ShoppingItem]
    @State private var showAdd = false
    @State private var listToast: String?

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    let suggestions = RecipeEngine.suggest(from: items.map { $0.name })
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Avec ce que tu as", subtitle: "Idées repas")
                            ForEach(suggestions, id: \.name) { r in recipeRow(r) }
                        }.card()
                    }

                    if items.isEmpty {
                        EmptyState(icon: "refrigerator", title: "Frigo vide", message: "Ajoute ce que tu as sous la main.")
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { it in itemRow(it) }
                        }
                    }
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Mon frigo").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { PantryEditor() }
        .overlay(alignment: .bottom) {
            if let listToast {
                Text(listToast).font(.footnote.weight(.semibold)).padding(10).raisedSurface(Capsule()).padding(.bottom, 24)
                    .task { try? await Task.sleep(for: .seconds(2)); self.listToast = nil }
            }
        }
    }


    private func recipeRow(_ r: RecipeEngine.Recipe) -> some View {
        let pct = Int(Double(r.matched) / Double(max(1, r.ingredients.count)) * 100)
        return HStack {
            VStack(alignment: .leading) {
                Text(r.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(r.matched)/\(r.ingredients.count) ingrédients").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("\(pct)%").font(.subheadline.bold()).foregroundStyle(.nutriTint)
        }.padding(.vertical, 4)
    }

    private func itemRow(_ it: PantryItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(it.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(it.quantity) · \(it.location)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let e = it.expiry { ExpiryBadge(date: e) }
            Button {
                addToList(it.name)
            } label: { Image(systemName: "cart.badge.plus").font(.caption) }
                .accessibilityLabel("Ajouter \(it.name) à la liste de courses")
            Button(role: .destructive) { remove(it) } label: { Image(systemName: "trash").font(.caption) }
                .foregroundStyle(Theme.danger.opacity(0.7))
                .accessibilityLabel("Supprimer \(it.name)")
        }.card(padding: 12)
    }

    private func remove(_ it: PantryItem) {
        ctx.delete(it)
        _ = LifeOSTry(try ctx.save(), context: "suppression frigo", category: AppLog.data)
    }

    /// Frigo → liste de courses (Bringo), sans doublon d'un article encore a acheter.
    private func addToList(_ name: String) {
        let existing = shopping.map { ShoppingListOps.Item(name: $0.name, checked: $0.checked) }
        guard ShoppingListOps.shouldAdd(name, existing: existing) else { listToast = "Déjà dans la liste"; return }
        ctx.insert(ShoppingItem(name: name, aisle: Aisle.guess(name)))
        listToast = LifeOSTry(try ctx.save(), context: "ajout liste de courses", category: AppLog.data) != nil
            ? "Ajouté à la liste de courses" : "Échec de l'enregistrement"
        Haptics.tap()
    }
}

struct ExpiryBadge: View {
    let date: Date
    private var days: Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0 }
    var body: some View {
        Text(days < 0 ? "Périmé" : days == 0 ? "Aujourd'hui" : "J-\(days)")
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((days <= 1 ? Theme.danger : days <= 3 ? Theme.warning : Theme.success).opacity(0.2), in: Capsule())
            .foregroundStyle(days <= 1 ? Theme.danger : days <= 3 ? Theme.warning : Theme.success)
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
    @State private var newQty = ""
    @State private var message: String?

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                HStack {
                    TextField("Ajouter un article…", text: $newItem)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    TextField("Qté", text: $newQty).textFieldStyle(.roundedBorder).frame(width: 56)
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .foregroundStyle(.nutriTint).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Ajouter l'article")
                }.padding()
                if let message { Text(message).font(.caption).foregroundStyle(Theme.textSecondary).padding(.bottom, 4) }

                if items.isEmpty {
                    EmptyState(icon: "cart", title: "Liste vide", message: "Ajoute des articles ici, ou depuis ton frigo (bouton panier).")
                    Spacer()
                } else {
                    List {
                        ForEach(groupedAisles, id: \.self) { aisle in
                            Section(aisle) {
                                ForEach(items.filter { $0.aisle == aisle }) { it in
                                    Button { it.checked.toggle(); save("article coché") } label: {
                                        HStack {
                                            Image(systemName: it.checked ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(it.checked ? Theme.success : Theme.textSecondary)
                                            Text(it.name).strikethrough(it.checked).foregroundStyle(it.checked ? Theme.textSecondary : Theme.textPrimary)
                                            Spacer()
                                            Text(it.quantity).font(.caption).foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                }
                                .onDelete { idx in
                                    let arr = items.filter { $0.aisle == aisle }
                                    idx.map { arr[$0] }.forEach(ctx.delete)
                                    save("suppression")
                                }
                            }
                        }
                        if items.contains(where: \.checked) {
                            Section {
                                Button { moveCheckedToFridge() } label: {
                                    Label("Articles cochés → frigo", systemImage: "refrigerator")
                                }
                                Button(role: .destructive) { clearChecked() } label: {
                                    Label("Retirer les articles cochés", systemImage: "trash")
                                }
                            } footer: {
                                Text("« Cochés → frigo » les range dans ton frigo (Fridgy) et les retire de la liste.")
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
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard ShoppingListOps.shouldAdd(name, existing: items.map { .init(name: $0.name, checked: $0.checked) }) else {
            message = "« \(name) » est déjà dans la liste."; return
        }
        let qty = newQty.trimmingCharacters(in: .whitespaces)
        ctx.insert(ShoppingItem(name: name, quantity: qty.isEmpty ? "1" : qty, aisle: Aisle.guess(name)))
        if save("ajout") { newItem = ""; newQty = ""; message = nil }
    }

    private func clearChecked() {
        items.filter(\.checked).forEach(ctx.delete)
        save("nettoyage")
    }

    private func moveCheckedToFridge() {
        let bought = items.filter(\.checked)
        for it in bought {
            ctx.insert(PantryItem(name: it.name, quantity: it.quantity, category: "Épicerie", location: "Frigo", expiry: nil))
            ctx.delete(it)
        }
        if save("rangement au frigo") { message = "\(bought.count) article(s) rangé(s) dans le frigo." }
    }

    @discardableResult
    private func save(_ what: String) -> Bool {
        do { try ctx.save(); return true }
        catch { message = "Échec de l'enregistrement (\(what)) : \(error.localizedDescription)"; return false }
    }
}

/// Regles de la liste de courses, sans effet de bord (testees).
enum ShoppingListOps {
    struct Item: Equatable { let name: String; let checked: Bool }
    static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
    /// Pas de doublon d'un article encore a acheter ; un article deja coche peut revenir.
    static func shouldAdd(_ name: String, existing: [Item]) -> Bool {
        let n = normalized(name)
        guard !n.isEmpty else { return false }
        return !existing.contains { !$0.checked && normalized($0.name) == n }
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
    @AppStorage(AppStorageKeys.waterGoal) private var goalML = 2500
    @AppStorage(AppStorageKeys.waterReminder) private var reminderOn = false
    @State private var customML = ""
    @State private var reminderDenied = false

    private var todayML: Int { entries.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML } }
    /// Totaux des 7 derniers jours (aujourd'hui compris), du plus ancien au plus recent.
    private var week: [(day: Date, ml: Int)] {
        let cal = Calendar.current
        return (0..<7).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: .now)) else { return nil }
            return (d, entries.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.amountML })
        }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        ProgressRing(progress: Double(todayML)/Double(max(1,goalML)), lineWidth: 16, tint: .nutriTint)
                        VStack {
                            Text("\(todayML)").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            Text("/ \(goalML) ml").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }.frame(width: 220, height: 220)
                    HStack(spacing: 12) {
                        addBtn(250, "cup.and.saucer.fill"); addBtn(500, "waterbottle.fill"); addBtn(750, "drop.fill")
                    }
                    HStack {
                        TextField("Autre quantité (ml)", text: $customML).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Button("Ajouter") {
                            if let ml = Int(customML), (1...3000).contains(ml) { add(ml); customML = "" }
                        }
                        .disabled(!(1...3000).contains(Int(customML) ?? 0))
                    }
                    Stepper("Objectif : \(goalML) ml", value: $goalML, in: 1000...5000, step: 250)
                        .onChange(of: goalML) { _, _ in syncWaterToContext() }
                        .card()

                    // On pouvait AJOUTER de l'eau sans jamais pouvoir en
                    // retirer: un double appui sur 250 ml restait faux pour la
                    // journee, et le total nourrit le score du jour.
                    if !todayEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("Aujourd'hui").font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Button {
                                    if let last = todayEntries.first { remove(last) }
                                } label: {
                                    Label("Annuler le dernier", systemImage: "arrow.uturn.backward")
                                        .font(.caption)
                                }
                            }
                            .padding(.bottom, 6)

                            ForEach(todayEntries) { e in
                                HStack {
                                    Text(e.date, style: .time)
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Text("\(e.amountML) ml").font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Button(role: .destructive) { remove(e) } label: {
                                        Image(systemName: "trash").font(.caption)
                                    }
                                    .accessibilityLabel("Supprimer \(e.amountML) millilitres")
                                }
                                .padding(.vertical, 6)
                                Divider().opacity(0.15)
                            }
                        }
                        .card()
                    }

                    if week.contains(where: { $0.ml > 0 }) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "7 derniers jours",
                                          subtitle: "Objectif atteint \(week.filter { $0.ml >= goalML }.count)/7")
                            Chart(week, id: \.day) { d in
                                BarMark(x: .value("Jour", d.day, unit: .day), y: .value("ml", d.ml))
                                    .foregroundStyle(d.ml >= goalML ? Color.nutriTint : Color.nutriTint.opacity(0.4))
                                RuleMark(y: .value("Objectif", goalML)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(height: 140)
                            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        }.card()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Rappels toutes les 2h (9h-21h)", isOn: $reminderOn)
                            .tint(.nutriTint)
                            .onChange(of: reminderOn) { _, on in
                                if on {
                                    Task {
                                        // iOS peut avoir refuse les notifications : on le dit et on
                                        // remet l'interrupteur, au lieu de programmer dans le vide.
                                        if await NotificationManager.shared.requestAuthorization() {
                                            reminderDenied = false; scheduleReminders()
                                        } else {
                                            reminderDenied = true; reminderOn = false
                                        }
                                    }
                                } else { cancelReminders() }
                            }
                        if reminderDenied {
                            Text("Notifications refusées pour LifeOS.").font(.caption).foregroundStyle(Theme.warning)
                            Button("Ouvrir les Réglages") {
                                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                            }.font(.caption)
                        }
                    }
                    .card()
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Hydratation").navigationBarTitleDisplayMode(.inline)
        .task { syncWaterToContext() }
        .onChange(of: entries.count) { _, _ in syncWaterToContext() }
    }
    /// Prises du jour, la plus recente en premier.
    private var todayEntries: [WaterEntry] {
        entries.filter { Calendar.current.isDateInToday($0.date) }
               .sorted { $0.date > $1.date }
    }

    private func remove(_ e: WaterEntry) {
        ctx.delete(e)
        _ = LifeOSTry(try ctx.save(), context: "suppression prise d eau", category: AppLog.data)
        syncWaterToContext()
        Haptics.soft()
    }

    /// Memes cles que les widgets (`WidgetKeys`), avec le jour : une valeur d'hier ne
    /// s'affiche pas aujourd'hui.
    private func syncWaterToContext() {
        guard let grp = UserDefaults(suiteName: "group.com.chifandco.lifeos") else { return }
        grp.set(todayML, forKey: WidgetKeys.waterToday)
        grp.set(WidgetKeys.dayStamp(), forKey: WidgetKeys.waterDay)
        grp.set(goalML, forKey: WidgetKeys.waterGoal)
        WidgetCenter.shared.reloadTimelines(ofKind: "HydrationWidget")
    }
    private func add(_ ml: Int) {
        ctx.insert(WaterEntry(amountML: ml))
        _ = LifeOSTry(try ctx.save(), context: "ajout prise d eau", category: AppLog.data)
        syncWaterToContext(); Haptics.tap()
    }
    private func addBtn(_ ml: Int, _ icon: String) -> some View {
        Button { add(ml) } label: {
            VStack(spacing: 6) { Image(systemName: icon).font(.title2); Text("\(ml)").font(.caption.bold()) }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .foregroundStyle(.nutriTint)
        }
    }
    private func scheduleReminders() {
        for h in stride(from: 9, through: 21, by: 2) {
            NotificationManager.shared.scheduleDaily(id: "water\(h)", title: "Hydrate-toi", body: "Un verre d'eau, ça fait du bien.", hour: h, minute: 0)
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
    @State private var reco: SuppReco?

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
        // Meme remise a plat que pour les medicaments: un complement cree
        // avant que les identifiants stables existent n'avait plus aucun
        // rappel posable. Idempotent, on annule puis on repose.
        .onAppear { supps.forEach(reschedule) }
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
                .background(Color.nutriTint.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))

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
            .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.nutriTint).disabled(name.isEmpty)
        }
        .padding()
        .raisedSurface(RoundedRectangle(cornerRadius: 16))
    }

    private func suppRow(_ s: Supplement) -> some View {
        let key = supplementID(s)
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
                    Image(systemName: "flame.fill").font(.caption).foregroundStyle(Theme.warning)
                    Text("\(streak)").font(.caption.weight(.bold)).foregroundStyle(Theme.warning)
                }
            }
            Toggle("", isOn: Binding(get: { s.active }, set: { s.active = $0; reschedule(s) }))
                .labelsHidden().tint(.nutriTint)
        }
        .padding(12)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
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
        let id = supplementID(s)
        NotificationManager.shared.cancel(id: id)
        NotificationManager.shared.cancel(id: id + ".confirm")
        ctx.delete(s)
    }

    /// Identifiant de notification stable entre deux lancements.
    /// Rempli paresseusement puis persiste, comme CustomReminder.stableID.
    private func supplementID(_ s: Supplement) -> String {
        if s.stableID.isEmpty {
            s.stableID = UUID().uuidString
            LifeOSTry(try ctx.save(), context: "stableID complement", category: AppLog.data)
        }
        return "supp.\(s.stableID)"
    }

    private func reschedule(_ s: Supplement) {
        let id = supplementID(s)
        let confirmId = id + ".confirm"
        NotificationManager.shared.cancel(id: id)
        NotificationManager.shared.cancel(id: confirmId)
        guard s.active else { return }
        NotificationManager.shared.scheduleDaily(
            id: id, title: "\(s.name)",
            body: "C'est le moment — \(momentLabel(s.moment).lowercased()), \(s.withFood ? "avec un repas" : "à jeun").",
            hour: s.hour, minute: s.minute)
        if s.confirm {
            let total = s.hour * 60 + s.minute + 90
            NotificationManager.shared.scheduleDailyAction(
                id: confirmId, title: "Petite vérif",
                body: "Tu as bien pris ton \(s.name) ?",
                hour: (total / 60) % 24, minute: total % 60,
                categoryId: "LIFEOS_CONFIRM",
                userInfo: ["confirmKey": id, "confirmLabel": s.name])
        }
    }
}

// MARK: - Allergènes & régimes

struct DietProfileView: View {
    @AppStorage(AppStorageKeys.dietFlags) private var flagsRaw = ""
    @State private var test = ""

    private let diets = AllergenChecker.options
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
                                // Aucun mot a risque trouve ne veut PAS dire sans risque.
                                Label("Aucun mot à risque trouvé pour ton profil", systemImage: "checkmark.circle").foregroundStyle(Theme.success)
                                Text("Ce test lit les mots de l'ingrédient. Il ne remplace ni l'étiquette, ni une certification (halal, casher), ni les traces possibles.")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            } else {
                                ForEach(issues, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
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
    /// Regimes et allergenes proposes. Les 8 derniers sont des allergenes majeurs de
    /// l'UE (reglement 1169/2011, annexe II).
    static let options = ["Halal", "Casher", "Vegan", "Végétarien", "Sans gluten", "Sans lactose", "Sans porc",
                          "Sans fruits à coque", "Sans arachide", "Sans œuf", "Sans soja", "Sans poisson",
                          "Sans crustacés", "Sans sésame", "Sans moutarde", "Sans céleri"]

    /// Expressions qui CONTIENNENT un mot a risque sans l'etre : "noix de coco" n'est pas
    /// un fruit a coque au sens de l'UE, "lait d'amande" n'a pas de lactose.
    private static let harmless = ["noix de coco", "noix de muscade", "lait de coco", "creme de coco", "lait d'amande",
                                   "lait de soja", "lait d'avoine", "lait de riz", "lait vegetal", "beurre de cacahuete",
                                   "beurre de karite", "beurre de cacao", "sans gluten", "sans lactose", "sans oeuf"]

    private static let rules: [(String, [String])] = [
        ("Sans gluten", ["gluten", "ble", "orge", "seigle", "farine", "epeautre", "kamut"]),
        ("Sans lactose", ["lait", "lactose", "creme", "beurre", "fromage", "lactoserum", "petit-lait"]),
        ("Vegan", ["lait", "oeuf", "miel", "gelatine", "viande", "poisson", "beurre", "fromage", "creme", "carmin", "e120"]),
        ("Végétarien", ["viande", "poulet", "boeuf", "porc", "poisson", "gelatine", "carmin", "e120"]),
        ("Halal", ["porc", "alcool", "gelatine", "lard", "vin", "biere"]),
        ("Casher", ["porc", "lard", "jambon", "bacon", "crevette", "homard", "crabe", "moule", "huitre", "calamar",
                    "fruits de mer", "gelatine"]),
        ("Sans porc", ["porc", "lard", "jambon", "bacon", "saucisson"]),
        ("Sans fruits à coque", ["amande", "noisette", "noix", "cajou", "pistache", "pecan", "macadamia"]),
        ("Sans arachide", ["arachide", "cacahuete"]),
        ("Sans œuf", ["oeuf", "albumine", "lysozyme"]),
        ("Sans soja", ["soja", "soya", "lecithine de soja", "tofu"]),
        ("Sans poisson", ["poisson", "thon", "saumon", "anchois", "cabillaud", "colin"]),
        ("Sans crustacés", ["crevette", "crabe", "homard", "langoustine", "ecrevisse"]),
        ("Sans sésame", ["sesame", "tahini", "tahin"]),
        ("Sans moutarde", ["moutarde"]),
        ("Sans céleri", ["celeri"]),
    ]

    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "’", with: "'")
    }

    static func check(_ ingredient: String, against flags: Set<String>) -> [String] {
        var n = fold(ingredient)
        for h in harmless { n = n.replacingOccurrences(of: h, with: " ") }
        var issues: [String] = []
        for (diet, words) in rules where flags.contains(diet) {
            if let w = words.first(where: n.contains) { issues.append("Incompatible : \(diet) (« \(w) »)") }
        }
        return issues
    }
}

// MARK: - Scaffolds IA

