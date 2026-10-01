import SwiftUI
import SwiftData

/// Modifier ou supprimer une ligne du journal alimentaire.
///
/// Passe par `FoodLogService` : si l'ecriture echoue, les anciennes valeurs
/// reviennent et la feuille reste ouverte avec le message. Tous les totaux
/// (accueil, bureau, historique, coach) lisent `FoodEntry`, donc ils suivent.
struct FoodEntryEditor: View {
    let entry: FoodEntry

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var meal = "Déjeuner"
    @State private var date = Date()
    @State private var error: String?
    @State private var confirmDelete = false
    // Vide = inconnu (pas 0): la base ne donne pas toujours ces valeurs.
    @State private var fiber = ""
    @State private var sugars = ""
    @State private var salt = ""
    @State private var favoriteDone = false

    private let meals = ["Petit-déj", "Déjeuner", "Dîner", "Collation"]

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                }
                Section("Aliment") {
                    TextField("Nom", text: $name)
                    Picker("Repas", selection: $meal) { ForEach(meals, id: \.self) { Text($0) } }
                    DatePicker("Date", selection: $date, in: ...Date())
                }
                Section("Valeurs pour la portion mangée") {
                    field("Calories", $kcal, "kcal")
                    field("Protéines", $protein, "g")
                    field("Glucides", $carbs, "g")
                    field("Lipides", $fat, "g")
                }
                Section {
                    field("Fibres", $fiber, "g", placeholder: "inconnu")
                    field("Sucres", $sugars, "g", placeholder: "inconnu")
                    field("Sel", $salt, "g", placeholder: "inconnu")
                } header: { Text("Micronutriments") } footer: {
                    Text("Laisse vide quand l'étiquette ne le dit pas : vide veut dire inconnu, pas zéro.")
                }
                Section {
                    Button { addFavorite() } label: {
                        Label(favoriteDone ? "Ajouté aux favoris" : "Garder en favori", systemImage: favoriteDone ? "star.fill" : "star")
                    }
                    .disabled(favoriteDone)
                    Button("Supprimer ce repas", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Modifier le repas").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
            .confirmationDialog("Supprimer « \(entry.name) » ?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { remove() }
            }
            .onAppear(perform: load)
        }
    }

    private func field(_ label: String, _ value: Binding<String>, _ unit: String, placeholder: String = "0") -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: value).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(minWidth: 60, maxWidth: 110)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func number(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return t.isEmpty ? 0 : Double(t)
    }

    private func load() {
        name = entry.name; kcal = "\(entry.calories)"
        protein = String(format: "%.1f", entry.protein)
        carbs = String(format: "%.1f", entry.carbs)
        fat = String(format: "%.1f", entry.fat)
        meal = meals.contains(entry.meal) ? entry.meal : meals[1]
        date = entry.date
        let key = FoodJournal.microsKey(entry)
        let rows = (try? ctx.fetch(FetchDescriptor<FoodMicros>(predicate: #Predicate { $0.entryKey == key }))) ?? []
        let m = rows.first?.values ?? .unknown
        fiber = m.fiber.map { String(format: "%.1f", $0) } ?? ""
        sugars = m.sugars.map { String(format: "%.1f", $0) } ?? ""
        salt = m.salt.map { String(format: "%.2f", $0) } ?? ""
    }

    /// nil dans le resultat = champ non numerique.
    private func micros() -> FoodMicroValues? {
        var out: [Double?] = []
        for s in [fiber, sugars, salt] {
            switch FoodJournal.parse(s) {
            case .value(let v): out.append(v)
            case .empty: out.append(nil)
            case .invalid: return nil
            }
        }
        return FoodMicroValues(fiber: out[0], sugars: out[1], salt: out[2])
    }

    private func addFavorite() {
        guard let k = number(kcal), let p = number(protein), let c = number(carbs), let f = number(fat),
              let m = micros() else { error = "Une valeur n'est pas un nombre."; return }
        let fav = FavoriteFood(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                               calories: Int(k.rounded()), protein: p, carbs: c, fat: f, micros: m)
        ctx.insert(fav)
        do { try ctx.save(); favoriteDone = true; Haptics.tap() }
        catch { ctx.delete(fav); self.error = "Favori non enregistré. Réessaie." }
    }

    private func save() {
        guard let k = number(kcal), let p = number(protein), let c = number(carbs), let f = number(fat),
              let m = micros() else {
            error = "Une valeur n'est pas un nombre."
            return
        }
        let oldKey = FoodJournal.microsKey(entry)
        let draft = FoodLogService.Draft(name: name, calories: Int(k.rounded()), protein: p,
                                         carbs: c, fat: f, meal: meal, date: date)
        do {
            try FoodLogService.update(entry, to: draft, in: ctx)
            // La cle suit le nom et l'heure: sans ce deplacement, changer l'un
            // des deux faisait perdre les micronutriments de la ligne.
            try? FoodJournal.updateMicros(oldKey: oldKey, newKey: FoodJournal.microsKey(entry), values: m, in: ctx)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }

    private func remove() {
        let key = FoodJournal.microsKey(entry)
        do {
            try FoodLogService.delete(entry, in: ctx)
            try? FoodJournal.updateMicros(oldKey: key, newKey: key, values: .unknown, in: ctx)
            Haptics.tap()
            dismiss()
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Aliment perso (creer, modifier, supprimer)

struct CustomFoodEditor: View {
    let food: CustomFood?
    var prefillName: String = ""

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var sugars = ""
    @State private var salt = ""
    @State private var portion = "100"
    @State private var portionLabel = ""
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                }
                Section("Aliment") {
                    TextField("Nom (ex : Gratin de ma mère)", text: $name)
                }
                Section("Pour 100 g") {
                    row("Calories", $kcal, "kcal")
                    row("Protéines", $protein, "g")
                    row("Glucides", $carbs, "g")
                    row("Lipides", $fat, "g")
                }
                Section {
                    row("Fibres", $fiber, "g", placeholder: "inconnu")
                    row("Sucres", $sugars, "g", placeholder: "inconnu")
                    row("Sel", $salt, "g", placeholder: "inconnu")
                } header: { Text("Pour 100 g, si tu les connais") } footer: { Text("Vide = inconnu, jamais compté comme zéro.") }
                Section("Portion habituelle") {
                    row("Poids", $portion, "g")
                    TextField("Nom de la portion (ex : 1 bol), facultatif", text: $portionLabel)
                }
                if food != nil {
                    Section { Button("Supprimer cet aliment", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(food == nil ? "Nouvel aliment" : "Modifier l'aliment").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
            .confirmationDialog("Supprimer cet aliment ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { remove() }
            } message: { Text("Les repas déjà journalisés restent dans le journal.") }
            .onAppear(perform: load)
        }
    }

    private func row(_ label: String, _ value: Binding<String>, _ unit: String, placeholder: String = "0") -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: value).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(minWidth: 60, maxWidth: 110)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard let f = food else { name = prefillName; return }
        let fmt: (Double) -> String = { $0.rounded() == $0 ? "\(Int($0))" : String(format: "%.1f", $0) }
        name = f.name; kcal = fmt(f.kcalPer100); protein = fmt(f.proteinPer100)
        carbs = fmt(f.carbsPer100); fat = fmt(f.fatPer100)
        fiber = f.fiberPer100.map(fmt) ?? ""; sugars = f.sugarsPer100.map(fmt) ?? ""
        salt = f.saltPer100.map { String(format: "%.2f", $0) } ?? ""
        portion = fmt(f.portionGrams); portionLabel = f.portionLabel
    }

    private func save() {
        var req: [Double] = []
        for s in [kcal, protein, carbs, fat, portion] {
            switch FoodJournal.parse(s) {
            case .value(let v): req.append(v)
            case .empty: req.append(0)
            case .invalid: error = "Une valeur n'est pas un nombre."; return
            }
        }
        var opt: [Double?] = []
        for s in [fiber, sugars, salt] {
            switch FoodJournal.parse(s) {
            case .value(let v): opt.append(v)
            case .empty: opt.append(nil)
            case .invalid: error = "Une valeur n'est pas un nombre."; return
            }
        }
        if let why = FoodJournal.validateCustom(name: name, kcal: req[0], protein: req[1], carbs: req[2],
                                               fat: req[3], portion: req[4]) {
            error = why; return
        }
        let micros = FoodMicroValues(fiber: opt[0], sugars: opt[1], salt: opt[2])
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = portionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = food {
            f.name = cleanName; f.kcalPer100 = req[0]; f.proteinPer100 = req[1]; f.carbsPer100 = req[2]
            f.fatPer100 = req[3]; f.portionGrams = req[4]; f.portionLabel = label
            f.fiberPer100 = micros.fiber; f.sugarsPer100 = micros.sugars; f.saltPer100 = micros.salt
        } else {
            ctx.insert(CustomFood(name: cleanName, kcalPer100: req[0], proteinPer100: req[1], carbsPer100: req[2],
                                  fatPer100: req[3], microsPer100: micros, portionGrams: req[4], portionLabel: label))
        }
        do { try ctx.save(); Haptics.success(); dismiss() }
        catch { ctx.rollback(); Haptics.warning(); self.error = "Aliment non enregistré. Ta saisie est conservée, réessaie." }
    }

    private func remove() {
        guard let f = food else { return }
        ctx.delete(f)
        do { try ctx.save(); dismiss() }
        catch { ctx.rollback(); self.error = "Suppression impossible. Réessaie." }
    }
}
