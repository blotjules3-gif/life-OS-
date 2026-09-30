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

    private func field(_ label: String, _ value: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(width: 90)
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
    }

    private func save() {
        guard let k = number(kcal), let p = number(protein), let c = number(carbs), let f = number(fat) else {
            error = "Une valeur n'est pas un nombre."
            return
        }
        let draft = FoodLogService.Draft(name: name, calories: Int(k.rounded()), protein: p,
                                         carbs: c, fat: f, meal: meal, date: date)
        do {
            try FoodLogService.update(entry, to: draft, in: ctx)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try FoodLogService.delete(entry, in: ctx)
            Haptics.tap()
            dismiss()
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }
}
