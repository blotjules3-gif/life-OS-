import SwiftUI
import SwiftData

// Flux « Ajouter » guidé et TRANSVERSAL, déclenché depuis le chat :
// 1) on choisit QUOI ajouter (couvre toutes les catégories : tâche, habitude, note,
//    aliment, eau, complément, course, séance, humeur, dépense, abonnement, événement,
//    échéance, tâche ménagère, plein d'essence…)
// 2) on remplit les détails adaptés au type
// 3) on propose un RAPPEL (une fois / chaque jour / chaque semaine)
struct AddAnythingSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case task, habit, note                    // Productivité
        case food, water, supplement, shopping    // Nutrition
        case workout                              // Sport
        case mood                                 // Mental
        case expense, subscription                // Argent
        case event                                // Social
        case deadline                             // Admin
        case chore                                // Maison
        case fuel                                 // Mobilité
        var id: String { rawValue }

        var label: String {
            switch self {
            case .task: return "Tâche";         case .habit: return "Habitude";     case .note: return "Note"
            case .food: return "Aliment";       case .water: return "Eau";          case .supplement: return "Complément"
            case .shopping: return "Course";    case .workout: return "Séance";     case .mood: return "Humeur"
            case .expense: return "Dépense";    case .subscription: return "Abonnement"
            case .event: return "Événement";    case .deadline: return "Échéance";  case .chore: return "Ménage"
            case .fuel: return "Plein"
            }
        }
        var icon: String {
            switch self {
            case .task: return "checklist";     case .habit: return "repeat";       case .note: return "note.text"
            case .food: return "fork.knife";    case .water: return "drop.fill";    case .supplement: return "pills.fill"
            case .shopping: return "cart.fill"; case .workout: return "figure.strengthtraining.traditional"
            case .mood: return "face.smiling";  case .expense: return "creditcard.fill"; case .subscription: return "arrow.triangle.2.circlepath"
            case .event: return "calendar";     case .deadline: return "flag.fill"; case .chore: return "house.fill"
            case .fuel: return "fuelpump.fill"
            }
        }
        // Faut-il un champ « nom » principal ? (non pour eau/humeur/plein)
        var needsName: Bool { self != .water && self != .mood && self != .fuel }
        var namePlaceholder: String {
            switch self {
            case .task: return "Nom de la tâche"; case .habit: return "Nom de l'habitude"; case .note: return "Titre de la note"
            case .food: return "Aliment"; case .supplement: return "Nom du complément"; case .shopping: return "Article à acheter"
            case .workout: return "Exercice (ex : Développé couché)"; case .expense: return "Intitulé de la dépense"
            case .subscription: return "Nom de l'abonnement"; case .event: return "Titre de l'événement"
            case .deadline: return "Intitulé de l'échéance"; case .chore: return "Tâche ménagère"
            default: return "Nom"
            }
        }
        var reminderByDefault: Bool { self == .supplement || self == .habit || self == .water }
    }

    enum Recurrence: String, CaseIterable, Identifiable {
        case once, daily, weekly
        var id: String { rawValue }
        var label: String { switch self { case .once: return "Une fois"; case .daily: return "Chaque jour"; case .weekly: return "Chaque semaine" } }
    }

    var initialKind: Kind = .task
    var prefillName: String = ""

    @State private var kind: Kind = .task
    @State private var name = ""
    // champs spécifiques
    @State private var meal = "Déjeuner"
    @State private var kcal = ""
    @State private var quantity = "1"
    @State private var noteBody = ""
    @State private var moment = "matin"
    @State private var amount = ""          // eau (ml) / dépense / abonnement (€)
    @State private var score = 3            // humeur 1…5
    @State private var weight = ""          // séance kg
    @State private var reps = ""            // séance reps
    @State private var txnCategory = "Divers"
    @State private var subCycle = "Mensuel"
    @State private var whenDate = Date()    // événement / échéance
    @State private var liters = ""          // plein
    @State private var pricePerL = ""
    // rappel
    @State private var remind = false
    @State private var recurrence: Recurrence = .daily
    @State private var time = Date()
    @State private var onceDate = Date().addingTimeInterval(3600)
    @State private var weekday = 2

    private let weekdays = [(2, "Lun"), (3, "Mar"), (4, "Mer"), (5, "Jeu"), (6, "Ven"), (7, "Sam"), (1, "Dim")]
    private let moods = ["😞", "😕", "😐", "🙂", "😄"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Quoi ajouter ?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                        ForEach(Kind.allCases) { k in typeChip(k) }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                }

                Section(kind.label) { detailFields }

                Section {
                    Toggle(isOn: $remind.animation()) { Label("Ajouter un rappel", systemImage: "bell.fill") }
                    if remind {
                        Picker("Fréquence", selection: $recurrence) {
                            ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
                        }
                        if recurrence == .once {
                            DatePicker("Quand", selection: $onceDate)
                        } else {
                            DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute)
                            if recurrence == .weekly {
                                Picker("Jour", selection: $weekday) { ForEach(weekdays, id: \.0) { Text($0.1).tag($0.0) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ajouter").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { add() }.fontWeight(.bold).disabled(!canAdd)
                }
            }
            .onAppear { kind = initialKind; name = prefillName; remind = initialKind.reminderByDefault }
            .onChange(of: kind) { _, k in withAnimation { remind = k.reminderByDefault } }
        }
    }

    // MARK: détails adaptés au type

    @ViewBuilder private var detailFields: some View {
        if kind.needsName {
            TextField(kind.namePlaceholder, text: $name)
        }
        switch kind {
        case .food:
            Picker("Repas", selection: $meal) { ForEach(["Petit-déj", "Déjeuner", "Dîner", "Collation"], id: \.self) { Text($0) } }
            numberField("Calories", $kcal, unit: "kcal")
        case .supplement:
            Picker("Moment", selection: $moment) { Text("Matin").tag("matin"); Text("Midi").tag("midi"); Text("Soir").tag("soir") }
        case .shopping:
            HStack { Text("Quantité"); Spacer(); TextField("1", text: $quantity).multilineTextAlignment(.trailing).frame(width: 80) }
        case .water:
            numberField("Quantité", $amount, unit: "ml")
            HStack(spacing: 8) { ForEach([250, 330, 500], id: \.self) { v in
                Button("\(v) ml") { amount = "\(v)" }.buttonStyle(.bordered).tint(Theme.volt) } }
        case .workout:
            numberField("Poids", $weight, unit: "kg", decimal: true)
            numberField("Répétitions", $reps, unit: "reps")
        case .mood:
            HStack {
                ForEach(1...5, id: \.self) { s in
                    Button { score = s } label: {
                        Text(moods[s - 1]).font(.system(size: 30)).opacity(score == s ? 1 : 0.35)
                    }.buttonStyle(.plain).frame(maxWidth: .infinity)
                }
            }
            TextField("Note (optionnel)", text: $noteBody, axis: .vertical).lineLimit(1...3)
        case .expense:
            numberField("Montant", $amount, unit: "€", decimal: true)
            Picker("Catégorie", selection: $txnCategory) {
                ForEach(["Courses", "Resto", "Transport", "Loisirs", "Logement", "Santé", "Divers"], id: \.self) { Text($0) }
            }
        case .subscription:
            numberField("Montant", $amount, unit: "€", decimal: true)
            Picker("Cycle", selection: $subCycle) { Text("Mensuel").tag("Mensuel"); Text("Annuel").tag("Annuel") }
        case .event:
            DatePicker("Date", selection: $whenDate)
        case .deadline:
            DatePicker("Échéance", selection: $whenDate, displayedComponents: .date)
        case .fuel:
            numberField("Litres", $liters, unit: "L", decimal: true)
            numberField("Prix / L", $pricePerL, unit: "€", decimal: true)
        case .note:
            TextField("Contenu", text: $noteBody, axis: .vertical).lineLimit(2...5)
        default:
            EmptyView()
        }
    }

    private func numberField(_ label: String, _ text: Binding<String>, unit: String, decimal: Bool = false) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", text: text).keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func typeChip(_ k: Kind) -> some View {
        let on = k == kind
        return Button {
            Haptics.tap(); withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { kind = k }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: k.icon).font(.system(size: 17, weight: .semibold))
                Text(k.label).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Theme.onVolt : Color.primary)
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(on ? AnyShapeStyle(Theme.volt) : Theme.cardFill,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hairline, lineWidth: on ? 0 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private var canAdd: Bool {
        switch kind {
        case .water:  return (Double(amount) ?? 0) > 0
        case .mood:   return true
        case .fuel:   return (Double(liters) ?? 0) > 0
        default:      return !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func add() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        switch kind {
        case .task:
            let t = TodoItem(title: n); if remind && recurrence == .once { t.due = onceDate }; ctx.insert(t)
        case .habit:
            ctx.insert(Habit(name: n, icon: "checkmark", colorHex: 0x4CF810))
        case .note:
            ctx.insert(Note(title: n, body: noteBody))
        case .food:
            ctx.insert(FoodEntry(name: n, calories: Int(kcal) ?? 0, meal: meal))
        case .water:
            ctx.insert(WaterEntry(amountML: Int(amount) ?? 0))
        case .supplement:
            ctx.insert(Supplement(name: n, hour: cal.component(.hour, from: time), minute: cal.component(.minute, from: time), active: true, moment: moment))
        case .shopping:
            ctx.insert(ShoppingItem(name: n, quantity: quantity.isEmpty ? "1" : quantity))
        case .workout:
            ctx.insert(WorkoutSet(exercise: n, weightKg: Double(weight) ?? 0, reps: Int(reps) ?? 0))
        case .mood:
            ctx.insert(MoodEntry(score: score, note: noteBody))
        case .expense:
            ctx.insert(Txn(amount: Double(amount) ?? 0, category: txnCategory, note: n))
        case .subscription:
            ctx.insert(Subscription(name: n, amount: Double(amount) ?? 0, cycle: subCycle, nextDate: whenDate))
        case .event:
            ctx.insert(SocialEvent(title: n, date: whenDate))
        case .deadline:
            ctx.insert(Deadline(title: n, date: whenDate))
        case .chore:
            ctx.insert(Chore(name: n))
        case .fuel:
            ctx.insert(FuelLog(liters: Double(liters) ?? 0, pricePerL: Double(pricePerL) ?? 0))
        }
        if remind { scheduleReminder(for: n.isEmpty ? kind.label : n) }
        Haptics.success()
        dismiss()
    }

    private func scheduleReminder(for n: String) {
        let id = "addflow.\(kind.rawValue).\(abs(n.hashValue))"
        let title = "\(kind.label) : \(n)"
        let body = reminderBody(n)
        let cal = Calendar.current
        let h = cal.component(.hour, from: time), m = cal.component(.minute, from: time)
        switch recurrence {
        case .once:   NotificationManager.shared.schedule(id: id, title: title, body: body, at: onceDate)
        case .daily:  NotificationManager.shared.scheduleDaily(id: id, title: title, body: body, hour: h, minute: m)
        case .weekly: NotificationManager.shared.scheduleWeekly(id: id, title: title, body: body, weekday: weekday, hour: h, minute: m)
        }
    }

    private func reminderBody(_ n: String) -> String {
        switch kind {
        case .supplement: return "N'oublie pas de prendre \(n) (\(moment))."
        case .habit:      return "C'est l'heure de ton habitude : \(n)."
        case .water:      return "Pense à boire 💧"
        case .workout:    return "Séance prévue : \(n)."
        case .event:      return "Événement : \(n)."
        case .deadline:   return "Échéance : \(n)."
        case .chore:      return "À faire à la maison : \(n)."
        default:          return "Rappel : \(n)."
        }
    }
}
