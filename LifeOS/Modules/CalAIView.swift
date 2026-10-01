import SwiftUI
import SwiftData
import VisionKit
import AVFoundation

/// Écran calories façon Cal AI : calories restantes + anneau, macros, bande de dates, streak, repas du jour.
struct CalAIView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query private var microRows: [FoodMicros]

    @AppStorage(AppStorageKeys.kcalGoal) private var kcalGoal = 2200
    @AppStorage(AppStorageKeys.proteinGoal) private var proteinGoal = 150
    @AppStorage(AppStorageKeys.carbGoal) private var carbGoal = 250
    @AppStorage(AppStorageKeys.fatGoal) private var fatGoal = 70

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var showAdd = false
    @State private var showScan = false
    /// Ligne ouverte en modification. Taper un repas l'ouvre.
    @State private var editing: FoodEntry?
    @State private var showDayPicker = false
    /// Repas a enregistrer comme modele (nom demande dans une alerte).
    @State private var savingMeal: String?
    @State private var savedMealName = ""
    @State private var actionError: String?
    @State private var actionDone: String?

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
                dayNavigator
                dateStrip
                caloriesCard
                quickActions
                macrosRow
                microsRow
                mealsSection
                historySection
            }
            .padding(Theme.pad)
            // iPad et Mac: une colonne lisible au centre, pas des cartes etirees.
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }.accessibilityLabel("Ajouter")
        } }
        .sheet(isPresented: $showAdd) { JournalAddSheet(day: selectedDay, defaultMeal: currentMeal) }
        .sheet(isPresented: $showScan) { BarcodeAddSheet(defaultMeal: currentMeal, day: selectedDay) }
        .sheet(item: $editing) { FoodEntryEditor(entry: $0) }
        .sheet(isPresented: $showDayPicker) { dayPickerSheet }
        .alert("Enregistrer ce repas", isPresented: Binding(get: { savingMeal != nil }, set: { if !$0 { savingMeal = nil } })) {
            TextField("Nom (ex : Petit-déj habituel)", text: $savedMealName)
            Button("Enregistrer") { if let m = savingMeal { saveMeal(m) } }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Tu pourras l'ajouter en un geste depuis Ajouter, onglet Repas.") }
        .alert("Action impossible", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(actionError ?? "") }
        .overlay(alignment: .bottom) {
            if let actionDone {
                Text(actionDone).font(.footnote.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                    .raisedSurface(Capsule()).padding(.bottom, 24)
                    .task { try? await Task.sleep(for: .seconds(2)); self.actionDone = nil }
            }
        }
        .task { syncNutritionToContext(); purgeOrphanMicros() }
        .onChange(of: foods.prefix(200).map { "\($0.date.timeIntervalSince1970)|\($0.calories)|\($0.protein)" }) { _, _ in syncNutritionToContext() }
    }

    private func syncNutritionToContext() {
        guard let grp = UserDefaults(suiteName: "group.com.chifandco.lifeos") else { return }
        // Toujours AUJOURD'HUI: avant, regarder un jour passe envoyait ses totaux
        // au widget et au coach comme si c'etait ceux du jour.
        let today = FoodJournal.totals(foods, day: .now)
        grp.set(today.kcal, forKey: "today_kcal")
        grp.set(Int(today.protein), forKey: "today_protein_g")
    }

    // MARK: Actions rapides (Scanner code-barres + Ajouter)

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button { showScan = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "barcode.viewfinder").font(.system(size: 17, weight: .bold))
                    Text("Scanner").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .glassControl(Capsule())
            }
            Button { showAdd = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .bold))
                    Text("Rechercher").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .raisedSurface(Capsule())
            }
        }
        .buttonStyle(PressableButtonStyle())
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
                Image(systemName: "flame.fill").foregroundStyle(Color.accentColor)
                Text("\(streak)").font(.headline.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .raisedSurface(Capsule())
        }
    }

    // MARK: Navigation par jour

    private var isToday: Bool { cal.isDateInToday(selectedDay) }

    private var dayNavigator: some View {
        HStack(spacing: 12) {
            Button { selectedDay = FoodJournal.shift(selectedDay, by: -1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Jour précédent")
            Button { showDayPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(FoodJournal.dayTitle(selectedDay)).font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityHint("Choisir un jour")
            Button { selectedDay = FoodJournal.shift(selectedDay, by: 1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(isToday)
            .accessibilityLabel("Jour suivant")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
    }

    private var dayPickerSheet: some View {
        NavigationStack {
            DatePicker("Jour", selection: Binding(get: { selectedDay },
                                                  set: { selectedDay = cal.startOfDay(for: $0); showDayPicker = false }),
                       in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Aller au jour").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { showDayPicker = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Aujourd'hui") { selectedDay = cal.startOfDay(for: .now); showDayPicker = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
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
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(left < 0 ? Theme.danger : .primary)
                    .contentTransition(.numericText())
                Text(left >= 0 ? "Calories restantes" : "Calories dépassées")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                ProgressRing(progress: kcalGoal == 0 ? 0 : Double(consumed) / Double(kcalGoal), lineWidth: 11, tint: Color.accentColor)
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
        .raisedSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Micronutriments (seulement ce que la base ou l'utilisateur donne)

    private var microsRow: some View {
        let idx = FoodJournal.microsIndex(microRows)
        let values = dayFoods.map { idx[FoodJournal.microsKey($0)] ?? .unknown }
        let rows: [(String, FoodJournal.MicroTotal)] = [
            ("Fibres", FoodJournal.microTotal(values.map(\.fiber))),
            ("Sucres", FoodJournal.microTotal(values.map(\.sugars))),
            ("Sel", FoodJournal.microTotal(values.map(\.salt))),
        ]
        let unknown = rows.map(\.1.unknownCount).max() ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(rows, id: \.0) { label, total in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(total.label).font(.headline)
                            .foregroundStyle(total.knownCount == 0 ? Theme.textSecondary : Theme.textPrimary)
                        Text(label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !dayFoods.isEmpty, unknown > 0 {
                Text("\(unknown) aliment\(unknown > 1 ? "s" : "") sans valeur connue : pas compté\(unknown > 1 ? "s" : "") comme zéro.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Repas du jour

    private var previousDay: Date { cal.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay }
    private var previousDayFoods: [FoodEntry] { foods.filter { cal.isDate($0.date, inSameDayAs: previousDay) } }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isToday ? "Repas du jour" : "Repas · \(FoodJournal.dayTitle(selectedDay))").nikeTitle(20)
                Spacer()
                if !previousDayFoods.isEmpty {
                    Menu {
                        Button { copy(meal: nil) } label: { Label("Toute la veille", systemImage: "doc.on.doc") }
                        ForEach(Array(Set(previousDayFoods.map(\.meal))).sorted(), id: \.self) { m in
                            Button { copy(meal: m) } label: { Label("\(m) de la veille", systemImage: "fork.knife") }
                        }
                    } label: {
                        Label("Copier la veille", systemImage: "doc.on.doc").font(.caption.weight(.bold))
                    }
                }
            }
            if dayFoods.isEmpty {
                Button { showScan = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Scanne un produit ou touche Rechercher pour ajouter ton premier repas").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .raisedSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                Text("\(kcal) kcal").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.accentColor)
                Menu {
                    Button { savedMealName = meal; savingMeal = meal } label: {
                        Label("Enregistrer ce repas", systemImage: "square.and.arrow.down")
                    }
                    if !isToday {
                        Button { copyToToday(meal: meal) } label: { Label("Copier vers aujourd'hui", systemImage: "doc.on.doc") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.subheadline).frame(width: 32, height: 28)
                }
                .accessibilityLabel("Actions du repas \(meal)")
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
                .onTapGesture { editing = f }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Modifier ce repas")
                .contextMenu {
                    Button { editing = f } label: { Label("Modifier", systemImage: "pencil") }
                    Button(role: .destructive) {
                        // Via le service: un echec remet la ligne au lieu de la perdre
                        // en silence.
                        try? FoodLogService.delete(f, in: ctx); Haptics.tap()
                    } label: { Label("Supprimer", systemImage: "trash") }
                }
                if f.id != items.sorted(by: { $0.date < $1.date }).last?.id {
                    Divider().overlay(Theme.hairline).padding(.leading, 14)
                }
            }
            .padding(.bottom, 4)
        }
        .raisedSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                                              : AnyShapeStyle(over ? Color(hex: 0xF0584B) : Color.accentColor))
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
                Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                Text("Objectif \(kcalGoal) kcal").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func weekdayLetter(_ d: Date) -> String {
        ["D", "L", "M", "M", "J", "V", "S"][cal.component(.weekday, from: d) - 1]
    }

    // MARK: Copier, enregistrer, nettoyer

    /// Copie la veille du jour regarde (toute la journee ou un repas) sur ce jour.
    private func copy(meal: String?) {
        let lines = FoodJournal.copyLines(from: foods, micros: FoodJournal.microsIndex(microRows),
                                          sourceDay: previousDay, toDay: selectedDay, meal: meal)
        write(lines, done: meal == nil ? "Veille copiée" : "\(meal!) de la veille copié")
    }

    private func copyToToday(meal: String) {
        let lines = FoodJournal.copyLines(from: foods, micros: FoodJournal.microsIndex(microRows),
                                          sourceDay: selectedDay, toDay: cal.startOfDay(for: .now), meal: meal)
        write(lines, done: "\(meal) copié vers aujourd'hui")
    }

    private func write(_ lines: [JournalLine], done: String) {
        do { try FoodJournal.log(lines, in: ctx); Haptics.success(); actionDone = done }
        catch { Haptics.warning(); actionError = error.localizedDescription }
    }

    private func saveMeal(_ meal: String) {
        let items = FoodJournal.savedItems(from: dayFoods.filter { $0.meal == meal },
                                           micros: FoodJournal.microsIndex(microRows))
        let name = savedMealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !items.isEmpty else { return }
        let m = SavedMeal(name: name.isEmpty ? meal : name, items: items)
        ctx.insert(m)
        do { try ctx.save(); Haptics.success(); actionDone = "Repas « \(m.name) » enregistré" }
        catch { ctx.delete(m); actionError = "Le repas n'a pas pu être enregistré. Réessaie." }
        savingMeal = nil
    }

    /// Micros dont la ligne a ete supprimee par un autre ecran.
    private func purgeOrphanMicros() {
        let orphans = FoodJournal.orphanKeys(micros: microRows, entries: foods)
        guard !orphans.isEmpty else { return }
        microRows.filter { orphans.contains($0.entryKey) }.forEach { ctx.delete($0) }
        try? ctx.save()
    }

    // MARK: Données

    private var dayFoods: [FoodEntry] { foods.filter { cal.isDate($0.date, inSameDayAs: selectedDay) } }
    private var totals: (kcal: Int, p: Double, c: Double, f: Double) {
        dayFoods.reduce((0, 0.0, 0.0, 0.0)) { ($0.0 + $1.calories, $0.1 + $1.protein, $0.2 + $1.carbs, $0.3 + $1.fat) }
    }
    private var weekDays: [Date] { FoodJournal.stripDays(selected: selectedDay) }
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
    /// Jour regarde dans le journal: le produit scanne y est ajoute par defaut.
    var day: Date = .now

    @State private var product: FoodProduct?
    @State private var chosenDay = Calendar.current.startOfDay(for: .now)
    @State private var lookupError: String?
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var grams = "100"
    @State private var meal = "Déjeuner"
    @State private var saveError: String?
    @State private var loadingCode: String?
    @State private var notFound = false
    @State private var manual = ""

    private let meals = ["Petit-déj", "Déjeuner", "Collation", "Dîner"]
    private var factor: Double { (Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0) / 100 }
    private var scannerAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #endif
    }

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
        .onAppear { meal = defaultMeal; chosenDay = Calendar.current.startOfDay(for: min(day, .now)) }
        .alert("Produit introuvable", isPresented: $notFound) {
            Button("OK", role: .cancel) {}
        } message: { Text("Ce code-barres n'est pas dans Open Food Facts. Essaie « Rechercher » par nom, ou crée-le dans Perso.") }
        // Different de "introuvable": hors ligne, le produit existe peut-etre.
        .alert("Recherche impossible", isPresented: Binding(get: { lookupError != nil }, set: { if !$0 { lookupError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(lookupError ?? "") }
    }

    @ViewBuilder private var scanner: some View {
        if cameraStatus == .denied || cameraStatus == .restricted {
            Form {
                Section("Caméra refusée") {
                    Text("LifeOS n'a pas accès à la caméra, donc le scan est coupé. Tu peux l'autoriser dans Réglages, ou entrer le code à la main.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Ouvrir les Réglages") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                manualCodeSection
            }
        } else if cameraStatus == .notDetermined && scannerAvailableIgnoringPermission {
            Form {
                Section("Scanner un code-barres") {
                    Text("Le scan utilise la caméra, seulement pendant que cet écran est ouvert.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Autoriser la caméra") {
                        AVCaptureDevice.requestAccess(for: .video) { _ in
                            Task { @MainActor in cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }
                        }
                    }
                }
                manualCodeSection
            }
        } else if scannerAvailable {
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
                    .raisedSurface(Capsule())
                    .padding(.bottom, 44)
                }
            }
        } else {
            Form {
                Section("Scanner indisponible ici") {
                    Text("Le scan caméra marche sur un iPhone ou un iPad avec caméra. En attendant, entre un code-barres.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                manualCodeSection
            }
        }
    }

    private var manualCodeSection: some View {
        Section("Code-barres") {
            TextField("Ex. 3017620422003 (Nutella)", text: $manual).keyboardType(.numberPad)
            Button("Chercher ce code") { lookup(manual) }.disabled(manual.count < 6 || loadingCode != nil)
            if loadingCode != nil { ProgressView() }
        }
    }

    /// Le materiel sait scanner (la permission est demandee a part).
    private var scannerAvailableIgnoringPermission: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return DataScannerViewController.isSupported
        #endif
    }

    private func confirm(_ p: FoodProduct) -> some View {
        let line = FoodJournal.line(p.per100, grams: factor * 100, meal: meal,
                                    date: FoodLogService.mealDate(day: chosenDay))
        let kcal = line.draft.calories
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
                            .font(.caption.bold()).buttonStyle(LifeOSGlassButtonStyle()).tint(.secondary)
                    }
                }
            }
            Section("Pour cette portion") {
                macroRow("Calories", "\(kcal) kcal")
                macroRow("Protéines", "\(Int(p.protein * factor)) g")
                macroRow("Glucides", "\(Int(p.carbs * factor)) g")
                macroRow("Lipides", "\(Int(p.fat * factor)) g")
                macroRow("Fibres", FoodJournal.microText(line.micros.fiber))
                macroRow("Sucres", FoodJournal.microText(line.micros.sugars))
                macroRow("Sel", FoodJournal.microText(line.micros.salt))
            }
            Section {
                DatePicker("Jour", selection: $chosenDay, in: ...Date(), displayedComponents: .date)
                Picker("Repas", selection: $meal) { ForEach(meals, id: \.self) { Text($0) } }
            }
            Section {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                }
                Button {
                    // Avant: insertion sans enregistrement, puis fermeture. La feuille se
                    // ferme maintenant SEULEMENT si le repas est vraiment ecrit.
                    do {
                        var l = line; l.draft.meal = meal
                        try FoodJournal.log([l], in: ctx)
                        Haptics.success(); dismiss()
                    } catch {
                        Haptics.warning()
                        saveError = error.localizedDescription
                    }
                } label: { Text("Ajouter au journal").frame(maxWidth: .infinity).bold() }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(Color.accentColor)
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
            let r = await FoodSearchService.lookup(barcode: code)
            await MainActor.run {
                loadingCode = nil
                switch r {
                case .found(let p): product = p; grams = "100"; Haptics.medium()
                case .notFound: notFound = true; Haptics.tap()
                case .unavailable(let m): lookupError = m; Haptics.warning()
                }
            }
        }
    }
}
