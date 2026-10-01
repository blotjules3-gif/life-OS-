import SwiftUI
import Charts
import WidgetKit
import SwiftData
import UserNotifications

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
    @State private var editing: FastingSession?
    @State private var backfill = false
    @State private var customMode = false
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
                    if active == nil { protocolPicker }

                    let elapsed = Int(active?.elapsed ?? 0)
                    let goal = (active?.targetHours ?? target) * 3600
                    ZStack {
                        ProgressRing(progress: goal == 0 ? 0 : Double(elapsed) / Double(goal), lineWidth: 16, tint: .nutriTint)
                        VStack(spacing: 4) {
                            Text(formatHMS(elapsed)).font(.system(size: 40, weight: .bold))
                                .monospacedDigit().foregroundStyle(Theme.textPrimary)
                                .minimumScaleFactor(0.6).lineLimit(1)
                            Text(active.map { "Objectif \($0.targetHours)h" } ?? "Prêt à jeûner")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: 240).aspectRatio(1, contentMode: .fit)

                    if let a = active { activeControls(a) } else {
                        PrimaryButton(title: "Démarrer le jeûne", icon: "play.fill", tint: .nutriTint) { start() }
                    }

                    if !completed.isEmpty { historyCard }

                    Button { backfill = true } label: {
                        Label("Ajouter un jeûne passé", systemImage: "clock.arrow.circlepath").font(.subheadline)
                    }
                }
                .padding(Theme.pad)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Jeûne intermittent").navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { now = $0 }
        .onAppear { customMode = !FastingRules.presets.contains(target) }
        .sheet(item: $editing) { s in
            FastingSessionEditor(session: s, others: spans(excluding: s)) { what in commit(what) }
        }
        .sheet(isPresented: $backfill) {
            FastingSessionEditor(session: nil, others: spans(excluding: nil)) { what in commit(what) }
        }
    }

    private var protocolPicker: some View {
        VStack(spacing: 10) {
            Picker("Protocole", selection: Binding(
                get: { customMode ? 0 : target },
                set: { v in
                    if v == 0 { customMode = true; if FastingRules.presets.contains(target) { target = 24 } }
                    else { customMode = false; target = v }
                })) {
                ForEach(FastingRules.presets, id: \.self) { Text(FastingRules.label(forTarget: $0)).tag($0) }
                Text("Perso").tag(0)
            }.pickerStyle(.segmented)
            if customMode {
                Stepper("Durée perso : \(target) h", value: $target, in: FastingRules.customRange)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func activeControls(_ a: FastingSession) -> some View {
        // Debut corrigeable : on oublie souvent de lancer le chrono au dernier repas.
        DatePicker("Début", selection: Binding(
            get: { a.start },
            set: { new in
                let clamped = FastingStats.clampStart(new)
                if let err = FastingRules.validate(start: clamped, end: nil, others: spans(excluding: a)) { saveError = err; return }
                a.start = clamped; commit("correction du début"); scheduleEnd(a)
            }),
                   in: Date().addingTimeInterval(-72 * 3600)...Date(),
                   displayedComponents: [.date, .hourAndMinute])
            .font(.footnote)
        Text("Fin prévue : \(a.start.addingTimeInterval(Double(a.targetHours*3600)).formatted(date: .omitted, time: .shortened)) · une notification te prévient.")
            .font(.footnote).foregroundStyle(Theme.textSecondary)
        TextField("Note (ressenti, motivation…)", text: Binding(get: { a.note }, set: { a.note = $0 }), axis: .vertical)
            .textFieldStyle(.roundedBorder).font(.footnote)
            .onSubmit { commit("note") }
        PrimaryButton(title: "Rompre le jeûne", icon: "fork.knife", tint: .nutriTint) {
            // Un seul evenement de fin : un double appui ne reecrit pas l'heure.
            guard a.end == nil else { return }
            a.end = Date()
            if commit("fin du jeûne") { NotificationManager.shared.cancel(id: Self.endNotificationID) } else { a.end = nil }
        }
    }

    private var historyCard: some View {
        let st = FastingStats.summary(completed.compactMap { s in s.end.map { (s.start, $0, s.targetHours) } })
        let streak = FastingRules.streak(completed.compactMap { s in
            s.end.map { ($0, $0.timeIntervalSince(s.start) >= Double(s.targetHours * 3600)) } })
        let chart = Array(completed.prefix(14).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Historique",
                          subtitle: "\(st.reached)/\(st.count) objectifs atteints · moyenne \(String(format: "%.1f", st.averageHours)) h")
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? Theme.warning : Theme.textSecondary)
                Text(streak > 0 ? "Série : \(streak) jour\(streak > 1 ? "s" : "") d'affilée avec l'objectif atteint"
                                : "Pas de série en cours")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            if chart.count >= 2 {
                Chart(chart) { s in
                    let h = s.elapsed / 3600
                    BarMark(x: .value("Jeûne", s.start, unit: .day), y: .value("Heures", h))
                        .foregroundStyle(h >= Double(s.targetHours) ? Color.nutriTint : Color.nutriTint.opacity(0.4))
                    PointMark(x: .value("Jeûne", s.start, unit: .day), y: .value("Objectif", s.targetHours))
                        .symbol(.circle).symbolSize(18).foregroundStyle(Theme.textSecondary)
                }
                .frame(height: 140)
                .accessibilityLabel("Durée des \(chart.count) derniers jeûnes, point gris = objectif")
            }
            ForEach(completed.prefix(30)) { s in
                let ok = Int(s.elapsed) >= s.targetHours*3600
                Button { editing = s } label: {
                    HStack {
                        Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(ok ? Theme.success : Theme.warning)
                            .accessibilityLabel(ok ? "objectif atteint" : "objectif non atteint")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.start, style: .date).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            if !s.note.isEmpty {
                                Text(s.note).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(formatHoursMinutes(Int(s.elapsed))) / \(s.targetHours) h").font(.subheadline.bold())
                            .foregroundStyle(ok ? Theme.success : Theme.warning)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .contextMenu {
                    Button { editing = s } label: { Label("Modifier", systemImage: "pencil") }
                    Button(role: .destructive) { ctx.delete(s); _ = commit("suppression") } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
            Text("Touche une ligne pour corriger les heures, la note ou la supprimer.").font(.caption2).foregroundStyle(Theme.textSecondary)
        }.card()
    }

    private var completed: [FastingSession] { sessions.filter { !$0.isActive } }

    private func spans(excluding s: FastingSession?) -> [FastingRules.Span] {
        sessions.filter { $0 !== s }.map { .init(start: $0.start, end: $0.end) }
    }

    private func start() {
        // Jamais deux jeunes en cours : le bouton ne s'affiche pas, et on revalide.
        if let err = FastingRules.validate(start: .now, end: nil, others: spans(excluding: nil)) { saveError = err; return }
        let s = FastingSession(targetHours: target)
        ctx.insert(s)
        if commit("début du jeûne") { scheduleEnd(s) } else { ctx.delete(s) }
    }

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

/// Corriger un jeune termine, ou en saisir un passe (oubli de lancer le chrono).
struct FastingSessionEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let session: FastingSession?
    let others: [FastingRules.Span]
    let onSaved: (String) -> Bool
    @State private var start = Date().addingTimeInterval(-16 * 3600)
    @State private var end = Date()
    @State private var target = 16
    @State private var note = ""
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) } }
                Section {
                    DatePicker("Début", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Fin", selection: $end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    LabeledContent("Durée", value: end > start ? formatHoursMinutes(Int(end.timeIntervalSince(start))) : "-")
                    Stepper("Objectif : \(target) h", value: $target, in: 12...72)
                }
                Section("Note") { TextField("Ressenti, raison de l'arrêt…", text: $note, axis: .vertical) }
                if session != nil {
                    Section { Button("Supprimer ce jeûne", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(session == nil ? "Jeûne passé" : "Modifier le jeûne").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
            .confirmationDialog("Supprimer ce jeûne ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let s = session { ctx.delete(s); if onSaved("suppression") { dismiss() } }
                }
            }
            .onAppear {
                if let s = session { start = s.start; end = s.end ?? .now; target = s.targetHours; note = s.note }
            }
        }
    }

    private func save() {
        if let err = FastingRules.validate(start: start, end: end, others: others) { error = err; Haptics.warning(); return }
        let s = session ?? FastingSession(start: start, end: end, targetHours: target)
        if session == nil { ctx.insert(s) }
        s.start = start; s.end = end; s.targetHours = target; s.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if onSaved(session == nil ? "jeûne passé" : "correction du jeûne") { dismiss() }
        else { error = "Échec de l'enregistrement." }
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
    // Profil Figue : avertissement en lecture seule, le repas s'ajoute quand meme.
    @AppStorage(AppStorageKeys.dietFlags) private var flagsRaw = ""
    @AppStorage(DietGuard.personalKey) private var personalRaw = "[]"

    private var factor: Double { (Double(grams) ?? 0) / 100 }
    private var dietFindings: [DietGuard.Finding] {
        DietGuard.check(name, flags: Set(flagsRaw.split(separator: "|").map(String.init)), personal: DietGuard.decode(personalRaw))
    }

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

                if !dietFindings.isEmpty {
                    Section {
                        DietFindingsList(findings: dietFindings)
                    } header: { Text("Ton profil Figue") } footer: {
                        Text("Lu dans le nom du repas seulement. Vérifie l'étiquette.")
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
    @State private var editing: PantryItem?
    @State private var listToast: String?
    @State private var location: String?
    @State private var category: String?
    @AppStorage("fridgySort") private var sortRaw = PantryOps.Sort.expiry.rawValue
    @AppStorage("fridgyAlertsOn") private var alertsOn = false
    @State private var alertsDenied = false

    private var sort: PantryOps.Sort { PantryOps.Sort(rawValue: sortRaw) ?? .expiry }
    private var shown: [PantryItem] {
        let rows = items.map { PantryOps.Row(name: $0.name, category: $0.category, location: $0.location, expiry: $0.expiry) }
        return PantryOps.filterSort(rows, location: location, category: category, sort: sort).map { items[$0] }
    }

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

                    alertsCard

                    if items.isEmpty {
                        EmptyState(icon: "refrigerator", title: "Frigo vide", message: "Ajoute ce que tu as sous la main.")
                    } else {
                        filterBar
                        if shown.isEmpty {
                            Text("Aucun article pour ce filtre.").font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        LazyVStack(spacing: 8) {
                            ForEach(shown) { it in itemRow(it) }
                        }
                    }
                }
                .padding(Theme.pad)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Mon frigo").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd, onDismiss: rescheduleAlerts) { PantryEditor(item: nil) }
        .sheet(item: $editing, onDismiss: rescheduleAlerts) { PantryEditor(item: $0) }
        // Les articles ajoutes ailleurs (NoGaspi) recoivent aussi leur alerte.
        .task { await refreshPermission(); rescheduleAlerts() }
        .overlay(alignment: .bottom) {
            if let listToast {
                Text(listToast).font(.footnote.weight(.semibold)).padding(10).raisedSurface(Capsule()).padding(.bottom, 24)
                    .task { try? await Task.sleep(for: .seconds(2)); self.listToast = nil }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("Endroit", selection: $location) {
                Text("Tout").tag(String?.none)
                ForEach(PantryOps.locations, id: \.self) { Text($0).tag(String?.some($0)) }
            }.pickerStyle(.segmented)
            HStack {
                Menu {
                    Button("Toutes les catégories") { category = nil }
                    ForEach(PantryOps.categories, id: \.self) { c in Button(c) { category = c } }
                } label: { Label(category ?? "Catégorie", systemImage: "line.3.horizontal.decrease.circle").font(.footnote) }
                Spacer()
                Picker("Tri", selection: $sortRaw) {
                    ForEach(PantryOps.Sort.allCases, id: \.self) { Text("Tri : \($0.rawValue)").tag($0.rawValue) }
                }.font(.footnote)
            }
        }
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Alertes de péremption (9 h)", isOn: $alertsOn)
                .tint(.nutriTint)
                .onChange(of: alertsOn) { _, on in
                    guard on else { rescheduleAlerts(); return }
                    Task {
                        if await NotificationManager.shared.requestAuthorization() { alertsDenied = false; rescheduleAlerts() }
                        else { alertsDenied = true; alertsOn = false }
                    }
                }
            Text("Chaque article daté te prévient le nombre de jours choisi dans sa fiche.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            if alertsDenied { NotificationsDeniedNotice() }
        }.card()
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
            Button { editing = it } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(it.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(it.quantity) · \(it.category) · \(it.location)").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let e = it.expiry { ExpiryBadge(date: e) }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Modifier l'article")
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
        if !it.stableID.isEmpty { NotificationManager.shared.cancel(id: PantryOps.notificationID(it.stableID)) }
        ctx.delete(it)
        _ = LifeOSTry(try ctx.save(), context: "suppression frigo", category: AppLog.data)
    }

    private func refreshPermission() async {
        let st = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        alertsDenied = alertsOn && st == .denied
    }

    /// Remplace TOUTES les alertes du frigo d'un coup (pas d'annulation asynchrone qui
    /// effacerait les nouvelles) : article modifie, supprime ou mange = alerte juste.
    private func rescheduleAlerts() {
        var requests: [UNNotificationRequest] = []
        if alertsOn {
            var changed = false
            for it in items {
                guard let e = it.expiry, let at = PantryOps.alertDate(expiry: e, daysBefore: it.alertDaysBefore) else { continue }
                if it.stableID.isEmpty { it.stableID = UUID().uuidString; changed = true }
                let content = UNMutableNotificationContent()
                content.title = "Bientôt périmé : \(it.name)"
                content.body = it.alertDaysBefore == 0 ? "À consommer aujourd'hui." : "Périme dans \(it.alertDaysBefore) jour\(it.alertDaysBefore > 1 ? "s" : "") (\(it.location.lowercased()))."
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                requests.append(UNNotificationRequest(identifier: PantryOps.notificationID(it.stableID), content: content,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
            if changed { _ = LifeOSTry(try ctx.save(), context: "stableID frigo", category: AppLog.data) }
        }
        let reqs = requests
        Task { await NotificationManager.shared.replacePending(prefix: PantryOps.notificationPrefix, with: reqs) }
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

/// Notifications refusees : on le dit, avec le chemin pour les reactiver.
struct NotificationsDeniedNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Notifications refusées pour LifeOS. Aucun rappel ne peut partir.", systemImage: "bell.slash.fill")
                .font(.caption).foregroundStyle(Theme.warning)
            Button("Ouvrir les Réglages") {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }.font(.caption)
        }
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
    /// nil = nouvel article.
    let item: PantryItem?
    @State private var name = ""; @State private var qty = "1"
    @State private var category = "Légume"; @State private var location = "Frigo"
    @State private var hasExpiry = false; @State private var expiry = Date()
    @State private var alertDays = 1
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                TextField("Nom", text: $name)
                TextField("Quantité (ex : 2, 500 g, 1 L)", text: $qty)
                Picker("Catégorie", selection: $category) { ForEach(PantryOps.categories, id: \.self) { Text($0) } }
                Picker("Endroit", selection: $location) { ForEach(PantryOps.locations, id: \.self) { Text($0) } }
                Toggle("Date de péremption", isOn: $hasExpiry)
                if hasExpiry {
                    DatePicker("Périme le", selection: $expiry, displayedComponents: .date)
                    Stepper(alertDays == 0 ? "Alerte le jour même" : "Alerte \(alertDays) jour\(alertDays > 1 ? "s" : "") avant",
                            value: $alertDays, in: 0...14)
                }
                if let item {
                    Section { Button("Supprimer l'article", role: .destructive) { delete(item) } }
                }
            }
            .navigationTitle(item == nil ? "Ajouter au frigo" : "Modifier l'article").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Ajouter" : "Enregistrer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let it = item else { return }
                name = it.name; qty = it.quantity
                category = PantryOps.categories.contains(it.category) ? it.category : "Épicerie"
                location = PantryOps.locations.contains(it.location) ? it.location : "Frigo"
                hasExpiry = it.expiry != nil; expiry = it.expiry ?? .now; alertDays = it.alertDaysBefore
            }
        }
    }

    /// Avant : insertion sans enregistrement, la feuille se fermait quoi qu'il arrive.
    private func save() {
        let it = item ?? PantryItem()
        if item == nil { ctx.insert(it) }
        it.name = name.trimmingCharacters(in: .whitespaces)
        it.quantity = qty.trimmingCharacters(in: .whitespaces).isEmpty ? "1" : qty
        it.category = category; it.location = location
        it.expiry = hasExpiry ? expiry : nil; it.alertDaysBefore = alertDays
        do { try ctx.save(); dismiss() }
        catch { self.error = "Échec de l'enregistrement : \(error.localizedDescription)"; Haptics.warning() }
    }

    private func delete(_ it: PantryItem) {
        if !it.stableID.isEmpty { NotificationManager.shared.cancel(id: PantryOps.notificationID(it.stableID)) }
        ctx.delete(it)
        do { try ctx.save(); dismiss() } catch { self.error = error.localizedDescription }
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
        let haveTokens = have.map(tokens)
        return db.map { r in
            var c = r
            c.matched = r.ingredients.filter { ing in
                let need = tokens(ing)
                return haveTokens.contains { containsPhrase(need, in: $0) }
            }.count
            return c
        }
        .filter { $0.matched >= 2 }
        .sorted { Double($0.matched)/Double($0.ingredients.count) > Double($1.matched)/Double($1.ingredients.count) }
    }

    /// Mots entiers, sans accents ni ligatures, au singulier simple: la sous-chaine
    /// dans les deux sens comptait "pomme" pour "pomme de terre", et "œuf" ne
    /// correspondait pas a "oeuf".
    static func tokens(_ text: String) -> [String] {
        let folded = text.lowercased()
            .replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        return folded.split { !$0.isLetter }.map { part in
            var word = String(part)
            if word.count > 3, let last = word.last, last == "s" || last == "x" { word.removeLast() }
            return word
        }
    }

    /// Vrai si l'ingredient (suite de mots) apparait tel quel, mots consecutifs, dans l'article.
    static func containsPhrase(_ need: [String], in have: [String]) -> Bool {
        guard !need.isEmpty, need.count <= have.count else { return false }
        return (0...(have.count - need.count)).contains { Array(have[$0..<($0 + need.count)]) == need }
    }
}

// MARK: - Liste de courses

struct ShoppingListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ShoppingItem.aisle) private var items: [ShoppingItem]
    @State private var newItem = ""
    @State private var newQty = ""
    @State private var newUnit = ""
    @State private var message: String?
    @State private var editing: ShoppingItem?
    @AppStorage(ShoppingMemory.storageKey) private var memoryRaw = "[]"

    private var memory: [ShoppingMemoryEntry] { ShoppingMemory.decode(memoryRaw) }
    private var suggestions: [ShoppingMemoryEntry] {
        ShoppingMemory.suggestions(memory, query: newItem, toBuy: items.filter { !$0.checked }.map(\.name))
    }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                HStack {
                    TextField("Ajouter un article…", text: $newItem)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    TextField("Qté", text: $newQty).textFieldStyle(.roundedBorder).frame(maxWidth: 64)
                        .keyboardType(.decimalPad)
                    Menu {
                        Picker("Unité", selection: $newUnit) {
                            ForEach(ShoppingUnits.all, id: \.self) { Text(ShoppingUnits.label($0)).tag($0) }
                        }
                    } label: { Text(ShoppingUnits.label(newUnit)).font(.caption).lineLimit(1) }
                    .accessibilityLabel("Unité : \(ShoppingUnits.label(newUnit))")
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .foregroundStyle(.nutriTint).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Ajouter l'article")
                }.padding([.horizontal, .top])

                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.name) { m in
                                Button { addFromMemory(m) } label: {
                                    Label(m.name, systemImage: m.favorite ? "star.fill" : "clock.arrow.circlepath")
                                        .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                                        .raisedSurface(Capsule())
                                }.buttonStyle(.plain)
                                .accessibilityLabel("Ajouter \(m.name)\(m.favorite ? ", favori" : ", récent")")
                            }
                        }.padding(.horizontal).padding(.vertical, 8)
                    }
                } else { Spacer().frame(height: 8) }
                if let message { Text(message).font(.caption).foregroundStyle(Theme.textSecondary).padding(.bottom, 4) }

                if items.isEmpty {
                    EmptyState(icon: "cart", title: "Liste vide", message: "Ajoute des articles ici, ou depuis ton frigo (bouton panier).")
                    Spacer()
                } else {
                    List {
                        ForEach(groupedAisles, id: \.self) { aisle in
                            Section(aisle) {
                                ForEach(items.filter { $0.aisle == aisle }) { it in
                                    row(it)
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
            .frame(maxWidth: 820)
        }
        .navigationTitle("Liste de courses").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ShoppingItemEditor(item: $0) }
    }

    private func row(_ it: ShoppingItem) -> some View {
        HStack {
            Button { it.checked.toggle(); save("article coché") } label: {
                Image(systemName: it.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(it.checked ? Theme.success : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(it.checked ? "Décocher \(it.name)" : "Cocher \(it.name)")
            Button { editing = it } label: {
                HStack {
                    Text(it.name).strikethrough(it.checked).foregroundStyle(it.checked ? Theme.textSecondary : Theme.textPrimary)
                    Spacer()
                    Text(it.unit.isEmpty ? it.quantity : "\(it.quantity) \(it.unit)").font(.caption).foregroundStyle(Theme.textSecondary)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Modifier l'article")
        }
    }

    private var groupedAisles: [String] { Array(Set(items.map { $0.aisle })).sorted() }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let qty = newQty.trimmingCharacters(in: .whitespaces)
        let remembered = memory.first { ShoppingListOps.normalized($0.name) == ShoppingListOps.normalized(name) }
        insert(name: name, qty: qty.isEmpty ? "1" : qty, unit: newUnit, aisle: remembered?.aisle ?? Aisle.guess(name))
    }

    private func addFromMemory(_ m: ShoppingMemoryEntry) {
        insert(name: m.name, qty: "1", unit: m.unit, aisle: m.aisle)
    }

    /// Un article encore a acheter n'est pas double : si les quantites s'additionnent
    /// (meme unite, ou g/kg, ml/L), on additionne ; sinon on le signale.
    private func insert(name: String, qty: String, unit: String, aisle: String) {
        if let same = items.first(where: { !$0.checked && ShoppingListOps.normalized($0.name) == ShoppingListOps.normalized(name) }) {
            if let merged = ShoppingUnits.merged(existing: (same.quantity, same.unit), adding: (qty, unit)) {
                same.quantity = merged
                if save("quantité") { message = "Quantité ajoutée à « \(same.name) »."; resetField() }
            } else {
                message = "« \(name) » est déjà dans la liste (touche-le pour changer la quantité)."
            }
            return
        }
        let it = ShoppingItem(name: name, quantity: qty, aisle: aisle)
        it.unit = unit
        ctx.insert(it)
        if save("ajout") {
            memoryRaw = ShoppingMemory.encode(ShoppingMemory.record(memory, name: name, aisle: aisle, unit: unit))
            message = nil; resetField()
        }
    }

    private func resetField() { newItem = ""; newQty = ""; newUnit = "" }

    private func clearChecked() {
        items.filter(\.checked).forEach(ctx.delete)
        save("nettoyage")
    }

    private func moveCheckedToFridge() {
        let bought = items.filter(\.checked)
        for it in bought {
            let q = it.unit.isEmpty ? it.quantity : "\(it.quantity) \(it.unit)"
            ctx.insert(PantryItem(name: it.name, quantity: q, category: "Épicerie", location: "Frigo", expiry: nil))
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

/// Modifier un article : nom, quantite, unite, rayon (libre), favori.
struct ShoppingItemEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let item: ShoppingItem
    @AppStorage(ShoppingMemory.storageKey) private var memoryRaw = "[]"
    @State private var name = ""; @State private var qty = ""; @State private var unit = ""
    @State private var aisle = ""; @State private var favorite = false
    @State private var error: String?

    static let aisles = ["Fruits & légumes", "Crèmerie", "Boucherie", "Boulangerie", "Épicerie", "Surgelés",
                         "Boissons", "Hygiène", "Maison & épicerie", "Divers"]

    var body: some View {
        NavigationStack {
            Form {
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                TextField("Nom", text: $name)
                HStack {
                    TextField("Quantité", text: $qty).keyboardType(.decimalPad)
                    Picker("Unité", selection: $unit) {
                        ForEach(ShoppingUnits.all, id: \.self) { Text(ShoppingUnits.label($0)).tag($0) }
                    }.labelsHidden()
                }
                Section("Rayon") {
                    Picker("Rayon", selection: $aisle) {
                        ForEach(Array(Set(Self.aisles + [aisle])).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0) }
                    }
                    TextField("Ou un rayon à toi", text: $aisle)
                    Text("Le rayon choisi est retenu pour la prochaine fois.").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Toggle("Favori (proposé en premier)", isOn: $favorite)
                Section { Button("Supprimer l'article", role: .destructive) { ctx.delete(item); persist() } }
            }
            .navigationTitle("Modifier l'article").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { apply() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = item.name; qty = item.quantity; unit = item.unit; aisle = item.aisle
                favorite = ShoppingMemory.decode(memoryRaw).first {
                    ShoppingListOps.normalized($0.name) == ShoppingListOps.normalized(item.name) }?.favorite ?? false
            }
        }
    }

    private func apply() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let a = aisle.trimmingCharacters(in: .whitespaces).isEmpty ? Aisle.guess(n) : aisle.trimmingCharacters(in: .whitespaces)
        item.name = n; item.quantity = qty.trimmingCharacters(in: .whitespaces).isEmpty ? "1" : qty
        item.unit = unit; item.aisle = a
        var mem = ShoppingMemory.record(ShoppingMemory.decode(memoryRaw), name: n, aisle: a, unit: unit)
        mem = ShoppingMemory.setFavorite(mem, name: n, aisle: a, unit: unit, on: favorite)
        memoryRaw = ShoppingMemory.encode(mem)
        persist()
    }

    private func persist() {
        do { try ctx.save(); dismiss() } catch { self.error = "Échec de l'enregistrement : \(error.localizedDescription)" }
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
    @State private var editingEntry: WaterEntry?
    @State private var showBeverages = false
    @AppStorage(WaterMath.beveragesKey) private var beveragesRaw = ""
    @AppStorage("waterSelectedBeverage") private var selectedBeverage = "Eau"
    @AppStorage(AppStorageKeys.userWeightKg) private var profileWeightKg: Double = 0
    @Query(filter: #Predicate<VitalRecord> { $0.type == "poids" }, sort: \VitalRecord.date, order: .reverse)
    private var weights: [VitalRecord]

    private var beverages: [BeverageType] { WaterMath.decode(beveragesRaw) }
    private var currentBeverage: BeverageType {
        beverages.first { $0.name == selectedBeverage } ?? beverages.first ?? WaterMath.defaults[0]
    }
    /// Poids du profil : jamais la valeur par defaut du questionnaire (75 kg) si rien n'a ete saisi.
    private var knownWeight: Double? {
        WaterMath.knownWeight(latestVital: weights.first?.value, profileKg: profileWeightKg,
                              setupKg: UserDefaults.standard.object(forKey: AppStorageKeys.userWeight) as? Int)
    }

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
                    beveragePicker
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
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper("Objectif : \(goalML) ml", value: $goalML, in: 1000...5000, step: 250)
                            .onChange(of: goalML) { _, _ in syncWaterToContext() }
                        goalSuggestion
                    }
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
                                    Button { editingEntry = e } label: {
                                        HStack {
                                            Text(e.beverage.isEmpty ? "Eau" : e.beverage).font(.caption)
                                                .foregroundStyle(Theme.textSecondary)
                                            Spacer()
                                            entryAmount(e)
                                        }.contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Modifier la prise")
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
        .sheet(item: $editingEntry) { WaterEntryEditor(entry: $0, beverages: beverages) }
        .sheet(isPresented: $showBeverages) { BeverageSettingsView() }
        .task { syncWaterToContext() }
        .onChange(of: entries.map { "\($0.date.timeIntervalSince1970)|\($0.amountML)" }) { _, _ in syncWaterToContext() }
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
    private var beveragePicker: some View {
        HStack {
            Menu {
                Picker("Boisson", selection: $selectedBeverage) {
                    ForEach(beverages) { b in Label("\(b.name) · \(b.percent) %", systemImage: b.icon).tag(b.name) }
                }
            } label: {
                Label(currentBeverage.name, systemImage: currentBeverage.icon).font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Boisson : \(currentBeverage.name)")
            Spacer()
            Text(currentBeverage.percent == 100 ? "compte à 100 %" : "compte à \(currentBeverage.percent) %")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Button { showBeverages = true } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Régler les boissons")
        }
    }

    @ViewBuilder
    private func entryAmount(_ e: WaterEntry) -> some View {
        let vol = WaterMath.volume(amountML: e.amountML, volumeML: e.volumeML)
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(vol) ml").font(.subheadline).foregroundStyle(Theme.textPrimary)
            if vol != e.amountML {
                Text("compte \(e.amountML) ml").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var goalSuggestion: some View {
        if let w = knownWeight, let s = WaterMath.suggestedGoal(weightKg: w) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pour \(Int(w.rounded())) kg : \(s.low) à \(s.high) ml par jour (repère courant de 30 à 35 ml par kg, à ajuster selon chaleur, sport et avis médical).")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                if goalML != s.suggested {
                    Button("Mettre \(s.suggested)") { goalML = s.suggested }.font(.caption.weight(.semibold))
                }
            }
        } else {
            Text("Ajoute ton poids (Santé ou profil) pour une suggestion d'objectif.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func add(_ volume: Int) {
        let b = currentBeverage
        let e = WaterEntry(amountML: WaterMath.counted(volume: volume, percent: b.percent))
        e.volumeML = volume
        e.beverage = b.name == "Eau" ? "" : b.name
        ctx.insert(e)
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

/// Corriger une prise : volume, boisson, heure. Le total du jour et le widget suivent
/// (la synchro de HydrationView observe date et quantite comptee).
struct WaterEntryEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let entry: WaterEntry
    let beverages: [BeverageType]
    @State private var volume = ""
    @State private var beverage = "Eau"
    @State private var date = Date()
    @State private var error: String?

    private var vol: Int? { Int(volume).flatMap { (1...3000).contains($0) ? $0 : nil } }
    private var percent: Int { beverages.first { $0.name == beverage }?.percent ?? 100 }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                HStack { Text("Volume"); Spacer()
                    TextField("ml", text: $volume).keyboardType(.numberPad).multilineTextAlignment(.trailing); Text("ml") }
                Picker("Boisson", selection: $beverage) {
                    ForEach(Array(Set(beverages.map(\.name) + [beverage])).sorted(), id: \.self) { Text($0) }
                }
                DatePicker("Heure", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                if let v = vol {
                    LabeledContent("Compté dans l'objectif", value: "\(WaterMath.counted(volume: v, percent: percent)) ml (\(percent) %)")
                }
                Section { Button("Supprimer la prise", role: .destructive) { ctx.delete(entry); persist() } }
            }
            .navigationTitle("Modifier la prise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { apply() }.disabled(vol == nil) }
            }
            .onAppear {
                volume = String(WaterMath.volume(amountML: entry.amountML, volumeML: entry.volumeML))
                beverage = entry.beverage.isEmpty ? "Eau" : entry.beverage
                date = entry.date
            }
        }
    }

    private func apply() {
        guard let v = vol else { return }
        entry.volumeML = v
        entry.amountML = WaterMath.counted(volume: v, percent: percent)
        entry.beverage = beverage == "Eau" ? "" : beverage
        entry.date = date
        persist()
    }

    private func persist() {
        do { try ctx.save(); dismiss() } catch { self.error = "Échec de l'enregistrement : \(error.localizedDescription)" }
    }
}

/// Boissons et part comptee. C'est l'utilisateur qui la regle : nous n'imposons aucun
/// coefficient, tout compte a 100 % par defaut. Les prises deja notees ne changent pas.
struct BeverageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WaterMath.beveragesKey) private var beveragesRaw = ""
    @State private var list: [BeverageType] = []
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($list) { $b in
                        Stepper(value: $b.percent, in: 0...100, step: 5) {
                            Label("\(b.name) · \(b.percent) %", systemImage: b.icon)
                        }
                    }
                    .onDelete { idx in
                        list.remove(atOffsets: idx)
                        if list.isEmpty { list = WaterMath.defaults }
                    }
                } footer: {
                    Text("Part du volume comptée dans ton objectif. Par défaut tout compte à 100 % : règle-la si tu le souhaites. Les prises déjà notées gardent leur valeur.")
                }
                Section("Ajouter une boisson") {
                    HStack {
                        TextField("Nom", text: $newName)
                        Button("Ajouter") {
                            let n = newName.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty, !list.contains(where: { $0.name.lowercased() == n.lowercased() }) else { return }
                            list.append(.init(name: n, icon: "drop", percent: 100)); newName = ""
                        }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section { Button("Revenir aux boissons de départ") { list = WaterMath.defaults } }
            }
            .navigationTitle("Boissons").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { beveragesRaw = WaterMath.encode(list); dismiss() }
                }
            }
            .onAppear { list = WaterMath.decode(beveragesRaw) }
        }
    }
}

// MARK: - Compléments

/// Pose les rappels d'un complement. UN seul endroit : l'ecran SuppSafe et le
/// questionnaire Alimentation passent tous deux ici (avant, le questionnaire posait
/// un rappel par NOM que rien ne savait annuler).
enum SupplementScheduler {
    /// Remplit l'identifiant stable si besoin. Le contexte est enregistre par l'appelant.
    @discardableResult
    static func ensureID(_ s: Supplement) -> String {
        if s.stableID.isEmpty { s.stableID = UUID().uuidString }
        return s.stableID
    }

    static func momentLabel(_ m: String) -> String { m == "soir" ? "Le soir" : (m == "midi" ? "Le midi" : "Le matin") }

    /// Remplace toutes les notifications du complement (heures, jours, verification,
    /// reassort). Renommer, changer les heures ou supprimer ne laisse aucun ancien rappel.
    static func apply(_ s: Supplement, deleted: Bool = false) {
        let sid = ensureID(s)
        let base = SupplementSchedule.baseID(sid)
        var reqs: [UNNotificationRequest] = []
        if !deleted && s.active {
            let times = SupplementSchedule.times(raw: s.timesRaw, hour: s.hour, minute: s.minute)
            let dose = s.doseText.isEmpty ? "" : " · \(s.doseText)"
            for slot in SupplementSchedule.slots(stableID: sid, times: times, daysRaw: s.weekdaysRaw, confirm: s.confirm) {
                let c = UNMutableNotificationContent()
                c.sound = .default
                if slot.isConfirm {
                    c.title = "Petite vérif"; c.body = "Tu as bien pris ton \(s.name) ?"
                    c.categoryIdentifier = "LIFEOS_CONFIRM"
                    c.userInfo = ["confirmKey": base, "confirmLabel": s.name]
                } else {
                    c.title = s.name + dose
                    c.body = "C'est le moment, \(s.withFood ? "avec un repas" : "à jeun")."
                }
                var comps = DateComponents(); comps.hour = slot.hour; comps.minute = slot.minute; comps.weekday = slot.weekday
                reqs.append(UNNotificationRequest(identifier: slot.id, content: c,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
            }
            if SupplementSchedule.needsRefill(trackStock: s.trackStock, stock: s.stock, threshold: s.refillThreshold) {
                let c = UNMutableNotificationContent()
                c.title = "Réassort : \(s.name)"; c.body = "Il en reste \(s.stock). Pense à en racheter."; c.sound = .default
                reqs.append(UNNotificationRequest(identifier: "\(base).refill", content: c,
                                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
            }
        }
        // Ancien rappel du questionnaire, pose par le nom et jamais annule.
        NotificationManager.shared.cancel(id: SupplementSchedule.legacySetupID(name: s.name))
        let all = reqs
        Task { await NotificationManager.shared.replacePending(prefix: base, with: all) }
    }
}

struct SupplementsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Supplement.hour) private var supps: [Supplement]
    @Query(sort: \SupplementDose.loggedAt, order: .reverse) private var doses: [SupplementDose]
    @State private var name = ""
    @State private var time = Date()
    @State private var withFood = true
    @State private var confirm = true
    @State private var reco: SuppReco?
    @State private var editing: Supplement?
    @State private var notifDenied = false
    @State private var message: String?

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    if notifDenied { NotificationsDeniedNotice().frame(maxWidth: .infinity, alignment: .leading).card() }
                    if let message { Text(message).font(.footnote).foregroundStyle(Theme.warning) }
                    addCard
                    if supps.isEmpty {
                        EmptyState(icon: "pills", title: "Aucun complément")
                            .padding(.top, 24)
                    } else {
                        todayCard
                        VStack(spacing: 10) { ForEach(supps) { suppRow($0) } }
                        historyCard
                    }
                }
                .padding()
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Compléments").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { SupplementEditor(supplement: $0) }
        // Remise a plat idempotente : rappels poses avant les identifiants stables
        // ou par l'ancien questionnaire.
        .task {
            resyncAll()
            await refreshPermission()
        }
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
                Text("Dose, autres heures, jours et stock : touche le complément une fois ajouté.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }

            Button { add() } label: {
                Label("Ajouter", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.nutriTint).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .raisedSurface(RoundedRectangle(cornerRadius: 16))
    }

    /// Prises prevues aujourd'hui, a cocher prise ou sautee.
    private var todayCard: some View {
        let due = supps.filter { $0.active && SupplementSchedule.isDue(on: .now, daysRaw: $0.weekdaysRaw) }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Aujourd'hui", subtitle: due.isEmpty ? "Rien de prévu" : nil)
            ForEach(due) { s in
                ForEach(SupplementSchedule.times(raw: s.timesRaw, hour: s.hour, minute: s.minute), id: \.self) { t in
                    doseRow(s, t)
                }
            }
        }.card()
    }

    private func doseRow(_ s: Supplement, _ t: SupplementSchedule.Time) -> some View {
        let logged = todayDose(s, t)
        return HStack {
            Text(String(format: "%02d:%02d", t.hour, t.minute)).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            Text(s.name).font(.subheadline).lineLimit(1)
            Spacer()
            if let d = logged {
                Button { undo(d, s) } label: {
                    Label(d.state == "taken" ? "Pris" : "Sauté", systemImage: d.state == "taken" ? "checkmark.circle.fill" : "forward.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d.state == "taken" ? Theme.success : Theme.textSecondary)
                }
                .accessibilityHint("Annuler")
            } else {
                Button("Sauté") { log(s, t, "skipped") }.font(.caption)
                Button("Pris") { log(s, t, "taken") }.font(.caption.weight(.semibold)).buttonStyle(.borderedProminent).tint(.nutriTint)
            }
        }
    }

    private var historyCard: some View {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -14, to: cal.startOfDay(for: .now)) ?? .distantPast
        let recent = doses.filter { $0.day >= since }
        let byDay = Dictionary(grouping: recent) { $0.day }
        return VStack(alignment: .leading, spacing: 8) {
            let rate = SupplementSchedule.adherence(states: recent.map(\.state))
            SectionHeader(title: "Historique des prises",
                          subtitle: rate.map { "14 jours · \(Int(($0 * 100).rounded())) % prises" } ?? "Aucune prise notée")
            ForEach(byDay.keys.sorted(by: >).prefix(14), id: \.self) { day in
                let list = byDay[day] ?? []
                HStack(alignment: .top) {
                    Text(day, format: .dateTime.weekday(.abbreviated).day().month()).font(.caption).foregroundStyle(Theme.textSecondary)
                        .frame(minWidth: 80, alignment: .leading)
                    Text(list.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
                        .map { "\($0.name) \($0.state == "taken" ? "✓" : "sauté")" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
        }.card()
    }

    private func suppRow(_ s: Supplement) -> some View {
        let streak = ConfirmationStore.shared.streak(SupplementSchedule.baseID(s.stableID))
        let times = SupplementSchedule.times(raw: s.timesRaw, hour: s.hour, minute: s.minute)
        return HStack(spacing: 12) {
            Button { editing = s } label: {
                HStack(spacing: 12) {
                    Image(systemName: "pills.fill").foregroundStyle(.nutriTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.doseText.isEmpty ? s.name : "\(s.name) · \(s.doseText)").font(.body.weight(.medium))
                        Text("\(times.map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: ", ")) · \(daysLabel(s.weekdaysRaw)) · \(s.withFood ? "avec repas" : "à jeun")")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        if s.trackStock {
                            let left = SupplementSchedule.daysLeft(stock: s.stock, unitsPerDose: s.unitsPerDose,
                                                                   timesPerDay: times.count, daysRaw: s.weekdaysRaw)
                            let low = SupplementSchedule.needsRefill(trackStock: true, stock: s.stock, threshold: s.refillThreshold)
                            Text("Stock : \(s.stock)\(left.map { " · environ \($0) j" } ?? "")\(low ? " · à racheter" : "")")
                                .font(.caption).foregroundStyle(low ? Theme.warning : Theme.textSecondary)
                        }
                    }
                    Spacer()
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Modifier le complément")
            if streak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.caption).foregroundStyle(Theme.warning)
                    Text("\(streak)").font(.caption.weight(.bold)).foregroundStyle(Theme.warning)
                }
            }
            Toggle("Actif", isOn: Binding(get: { s.active }, set: { on in
                s.active = on; saveAndSchedule(s)
                if on { Task { await askPermission() } }
            }))
                .labelsHidden().tint(.nutriTint)
        }
        .padding(12)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .contextMenu {
            Button { editing = s } label: { Label("Modifier", systemImage: "pencil") }
            Button(role: .destructive) { delete(s) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func resyncAll() {
        for s in supps { SupplementScheduler.ensureID(s) }
        _ = LifeOSTry(try ctx.save(), context: "stableID complements", category: AppLog.data)
        for s in supps { SupplementScheduler.apply(s) }
    }

    private func daysLabel(_ raw: String) -> String {
        let d = SupplementSchedule.parseDays(raw)
        guard !d.isEmpty, d.count < 7 else { return "tous les jours" }
        let names = ["", "lun", "mar", "mer", "jeu", "ven", "sam", "dim"]
        return d.sorted().map { names[$0] }.joined(separator: " ")
    }

    private func todayDose(_ s: Supplement, _ t: SupplementSchedule.Time) -> SupplementDose? {
        doses.first { $0.supplementKey == s.stableID && Calendar.current.isDateInToday($0.day) && $0.hour == t.hour && $0.minute == t.minute }
    }

    private func log(_ s: Supplement, _ t: SupplementSchedule.Time, _ state: String) {
        // Une seule prise notee par heure prevue : pas de double comptage du stock.
        guard todayDose(s, t) == nil else { return }
        let sid = SupplementScheduler.ensureID(s)
        ctx.insert(SupplementDose(supplementKey: sid, name: s.name, day: .now, hour: t.hour, minute: t.minute, state: state))
        if s.trackStock { s.stock = SupplementSchedule.stock(after: s.stock, unitsPerDose: s.unitsPerDose, taken: state == "taken", undo: false) }
        if saveAndSchedule(s), state == "taken" { ConfirmationStore.shared.markDone(SupplementSchedule.baseID(sid)) }
        Haptics.tap()
    }

    private func undo(_ d: SupplementDose, _ s: Supplement) {
        if s.trackStock { s.stock = SupplementSchedule.stock(after: s.stock, unitsPerDose: s.unitsPerDose, taken: d.state == "taken", undo: true) }
        ctx.delete(d)
        saveAndSchedule(s)
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
        SupplementScheduler.ensureID(s)
        ctx.insert(s)
        if saveAndSchedule(s) { name = ""; reco = nil; withFood = true; confirm = true }
        Task { await askPermission() }
    }

    private func delete(_ s: Supplement) {
        // L'historique garde ses prises (nom copie), seuls les rappels partent.
        SupplementScheduler.apply(s, deleted: true)
        ctx.delete(s)
        _ = LifeOSTry(try ctx.save(), context: "suppression complement", category: AppLog.data)
    }

    @discardableResult
    private func saveAndSchedule(_ s: Supplement) -> Bool {
        do { try ctx.save(); message = nil } catch {
            message = "Échec de l'enregistrement : \(error.localizedDescription)"; return false
        }
        SupplementScheduler.apply(s)
        return true
    }

    private func askPermission() async {
        let st = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if st == .notDetermined { notifDenied = !(await NotificationManager.shared.requestAuthorization()) }
        else { notifDenied = st == .denied }
    }

    private func refreshPermission() async {
        let st = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notifDenied = st == .denied && supps.contains(where: \.active)
    }
}

/// Modifier un complement : nom, dose, heures, jours, stock. Les rappels sont reposes
/// sous le meme identifiant stable, l'historique garde ses prises.
struct SupplementEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let supplement: Supplement
    @State private var name = ""
    @State private var dose = ""
    @State private var times: [Date] = []
    @State private var days: Set<Int> = []
    @State private var withFood = true
    @State private var confirm = true
    @State private var trackStock = false
    @State private var stock = 0
    @State private var unitsPerDose = 1
    @State private var threshold = 7
    @State private var error: String?
    @State private var confirmDelete = false

    private let dayNames = ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"]

    var body: some View {
        NavigationStack {
            Form {
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                Section {
                    TextField("Nom", text: $name)
                    TextField("Dose (ex : 2 gélules, 300 mg)", text: $dose)
                    Toggle("Avec un repas", isOn: $withFood)
                    Toggle("Vérif « bien pris ? » ~1h30 après", isOn: $confirm)
                }
                Section("Heures de prise") {
                    ForEach(times.indices, id: \.self) { i in
                        HStack {
                            DatePicker("Prise \(i + 1)", selection: $times[i], displayedComponents: .hourAndMinute)
                            if times.count > 1 {
                                Button(role: .destructive) { times.remove(at: i) } label: { Image(systemName: "minus.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(Theme.danger)
                                    .accessibilityLabel("Retirer la prise \(i + 1)")
                            }
                        }
                    }
                    if times.count < SupplementSchedule.maxTimes {
                        Button { times.append(times.last?.addingTimeInterval(4 * 3600) ?? .now) } label: {
                            Label("Ajouter une heure", systemImage: "plus")
                        }
                    }
                }
                Section {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = days.isEmpty || days.contains(d)
                            Button(dayNames[d - 1]) {
                                var cur = days.isEmpty ? Set(1...7) : days
                                if cur.contains(d) { cur.remove(d) } else { cur.insert(d) }
                                days = cur.count == 7 ? [] : cur
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(on ? Color.nutriTint.opacity(0.3) : Color.clear, in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                } header: { Text("Jours") } footer: {
                    Text(days.isEmpty ? "Tous les jours." : "Seulement les jours surlignés.")
                }
                Section("Stock") {
                    Toggle("Suivre le stock", isOn: $trackStock)
                    if trackStock {
                        Stepper("Reste : \(stock)", value: $stock, in: 0...2000)
                        Stepper("Unités par prise : \(unitsPerDose)", value: $unitsPerDose, in: 1...20)
                        Stepper("Prévenir à \(threshold) ou moins", value: $threshold, in: 0...200)
                    }
                }
                Section { Button("Supprimer le complément", role: .destructive) { confirmDelete = true } }
            }
            .navigationTitle("Modifier").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || times.isEmpty)
                }
            }
            .confirmationDialog("Supprimer \(supplement.name) ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    SupplementScheduler.apply(supplement, deleted: true)
                    ctx.delete(supplement)
                    do { try ctx.save(); dismiss() } catch { self.error = error.localizedDescription }
                }
            } message: { Text("L'historique des prises est gardé.") }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let s = supplement
        name = s.name; dose = s.doseText; withFood = s.withFood; confirm = s.confirm
        days = SupplementSchedule.parseDays(s.weekdaysRaw)
        if days.count == 7 { days = [] }
        trackStock = s.trackStock; stock = s.stock; unitsPerDose = s.unitsPerDose; threshold = s.refillThreshold
        let cal = Calendar.current
        times = SupplementSchedule.times(raw: s.timesRaw, hour: s.hour, minute: s.minute).compactMap {
            cal.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: .now)
        }
    }

    private func save() {
        let cal = Calendar.current
        let t = times.map { SupplementSchedule.Time(hour: cal.component(.hour, from: $0), minute: cal.component(.minute, from: $0)) }
        let raw = SupplementSchedule.formatTimes(t)
        let parsed = SupplementSchedule.parseTimes(raw)
        guard let first = parsed.first else { error = "Ajoute au moins une heure."; return }
        let s = supplement
        // Ancien rappel du questionnaire pose sous l'ancien nom.
        NotificationManager.shared.cancel(id: SupplementSchedule.legacySetupID(name: s.name))
        s.name = name.trimmingCharacters(in: .whitespaces); s.doseText = dose.trimmingCharacters(in: .whitespaces)
        s.timesRaw = raw; s.hour = first.hour; s.minute = first.minute
        s.weekdaysRaw = days.sorted().map(String.init).joined(separator: ",")
        s.withFood = withFood; s.confirm = confirm
        s.trackStock = trackStock; s.stock = stock; s.unitsPerDose = unitsPerDose; s.refillThreshold = threshold
        do { try ctx.save() } catch { self.error = "Échec de l'enregistrement : \(error.localizedDescription)"; return }
        SupplementScheduler.apply(s)
        dismiss()
    }
}

// MARK: - Allergènes & régimes

struct DietProfileView: View {
    @AppStorage(AppStorageKeys.dietFlags) private var flagsRaw = ""
    @AppStorage(DietGuard.personalKey) private var personalRaw = "[]"
    @Query(sort: \FoodEntry.date, order: .reverse) private var food: [FoodEntry]
    @State private var test = ""
    @State private var newWord = ""
    @State private var newSeverity = 2

    private let diets = AllergenChecker.options
    private var flags: Set<String> { Set(flagsRaw.split(separator: "|").map(String.init)) }
    private var personal: [PersonalAllergen] { DietGuard.decode(personalRaw) }

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

                    personalCard

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Tester un ingrédient")
                        TextField("Ex: gélatine, gluten, « peut contenir des traces de noisette »", text: $test, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        if !test.isEmpty {
                            let findings = DietGuard.check(test, flags: flags, personal: personal)
                            if findings.isEmpty {
                                // Aucun mot a risque trouve ne veut PAS dire sans risque.
                                Label("Aucun mot à risque trouvé pour ton profil", systemImage: "checkmark.circle").foregroundStyle(Theme.success)
                                Text("Ce test lit les mots de l'ingrédient. Il ne remplace ni l'étiquette, ni une certification (halal, casher), ni les traces possibles.")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            } else {
                                DietFindingsList(findings: findings)
                            }
                        }
                    }.card()

                    journalCard
                }
                .padding(Theme.pad)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Allergènes & régimes").navigationBarTitleDisplayMode(.inline)
    }

    private var personalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Mes allergènes perso", subtitle: "Ce que la liste ne couvre pas (kiwi, fraise, lupin…)")
            ForEach(personal) { a in
                HStack {
                    Text(a.word).font(.subheadline)
                    Spacer()
                    Menu {
                        ForEach(1...3, id: \.self) { lvl in Button(DietGuard.severityLabel(lvl)) { update(a.word, severity: lvl) } }
                    } label: { SeverityBadge(severity: a.severity) }
                    .accessibilityLabel("Gravité de \(a.word) : \(DietGuard.severityLabel(a.severity))")
                    Button(role: .destructive) { remove(a.word) } label: { Image(systemName: "trash").font(.caption) }
                        .accessibilityLabel("Retirer \(a.word)")
                }
            }
            HStack {
                TextField("Ajouter un aliment", text: $newWord).textFieldStyle(.roundedBorder).onSubmit(addWord)
                Picker("Gravité", selection: $newSeverity) {
                    ForEach(1...3, id: \.self) { Text(DietGuard.severityLabel($0)).tag($0) }
                }.labelsHidden()
                Button(action: addWord) { Image(systemName: "plus.circle.fill").font(.title3) }
                    .foregroundStyle(.nutriTint).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Ajouter l'allergène")
            }
            Text("La gravité est celle que tu choisis. En cas d'allergie sévère, suis l'avis de ton médecin.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }.card()
    }

    /// Le profil applique au journal alimentaire (Yumzio), en lecture seule.
    private var journalCard: some View {
        let since = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        let recent = food.filter { $0.date >= since }
        let hits = DietGuard.journal(recent.map(\.name), flags: flags, personal: personal)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ton journal (7 jours)",
                          subtitle: flags.isEmpty && personal.isEmpty ? "Choisis un régime ou un allergène pour vérifier tes repas"
                                    : hits.isEmpty ? "Aucun mot à risque dans les noms de tes \(recent.count) repas" : "\(hits.count) repas à vérifier")
            ForEach(hits, id: \.index) { h in
                let e = recent[h.index]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(e.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(e.date, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    DietFindingsList(findings: h.findings)
                }.padding(.vertical, 4)
            }
            if !hits.isEmpty || !recent.isEmpty {
                Text("Seul le nom du repas est lu, pas sa composition réelle.").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }.card()
    }

    private func addWord() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !personal.contains(where: { AllergenChecker.fold($0.word) == AllergenChecker.fold(w) }) else { newWord = ""; return }
        personalRaw = DietGuard.encode(personal + [.init(word: w, severity: newSeverity)])
        newWord = ""
    }
    private func update(_ word: String, severity: Int) {
        personalRaw = DietGuard.encode(personal.map { $0.word == word ? .init(word: word, severity: severity) : $0 })
    }
    private func remove(_ word: String) { personalRaw = DietGuard.encode(personal.filter { $0.word != word }) }
}

struct SeverityBadge: View {
    let severity: Int
    var body: some View {
        let c = severity >= 3 ? Theme.danger : severity == 2 ? Theme.warning : Theme.textSecondary
        Text(DietGuard.severityLabel(severity)).font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(c.opacity(0.2), in: Capsule()).foregroundStyle(c)
    }
}

/// Liste d'avertissements : incompatibles, puis traces possibles, chacun avec sa gravite.
struct DietFindingsList: View {
    let findings: [DietGuard.Finding]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(findings.sorted { ($0.isTrace ? 1 : 0, -$0.severity) < ($1.isTrace ? 1 : 0, -$1.severity) }, id: \.self) { f in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: f.isTrace ? "exclamationmark.circle" : "exclamationmark.triangle.fill")
                        .foregroundStyle(f.severity >= 3 ? Theme.danger : Theme.warning)
                    Text(f.label).font(.footnote).foregroundStyle(f.severity >= 3 ? Theme.danger : Theme.warning)
                }
            }
        }
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

