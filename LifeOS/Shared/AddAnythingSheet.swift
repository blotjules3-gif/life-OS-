import SwiftUI
import SwiftData

// Flux « Ajouter » guidé, déclenché depuis le chat :
// 1) on choisit QUOI ajouter (tâche, habitude, complément, course, aliment, note)
// 2) on remplit les détails
// 3) on propose d'ajouter un RAPPEL (une fois / chaque jour / chaque semaine)
struct AddAnythingSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case task, habit, supplement, shopping, food, note
        var id: String { rawValue }
        var label: String {
            switch self {
            case .task: return "Tâche";        case .habit: return "Habitude"
            case .supplement: return "Complément"; case .shopping: return "Course"
            case .food: return "Aliment";      case .note: return "Note"
            }
        }
        var icon: String {
            switch self {
            case .task: return "checklist";    case .habit: return "repeat"
            case .supplement: return "pills.fill"; case .shopping: return "cart.fill"
            case .food: return "fork.knife";   case .note: return "note.text"
            }
        }
        var namePlaceholder: String {
            switch self {
            case .task: return "Nom de la tâche"; case .habit: return "Nom de l'habitude"
            case .supplement: return "Nom du complément"; case .shopping: return "Article à acheter"
            case .food: return "Aliment"; case .note: return "Titre de la note"
            }
        }
        // Rappel proposé par défaut pour ce qui se répète naturellement.
        var reminderByDefault: Bool { self == .supplement || self == .habit }
    }

    enum Recurrence: String, CaseIterable, Identifiable {
        case once, daily, weekly
        var id: String { rawValue }
        var label: String {
            switch self { case .once: return "Une fois"; case .daily: return "Chaque jour"; case .weekly: return "Chaque semaine" }
        }
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
    // rappel
    @State private var remind = false
    @State private var recurrence: Recurrence = .daily
    @State private var time = Date()
    @State private var onceDate = Date().addingTimeInterval(3600)
    @State private var weekday = 2   // 1=dim … 7=sam

    private let weekdays = [(2, "Lun"), (3, "Mar"), (4, "Mer"), (5, "Jeu"), (6, "Ven"), (7, "Sam"), (1, "Dim")]

    var body: some View {
        NavigationStack {
            Form {
                // 1) Quoi ajouter
                Section("Quoi ajouter ?") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Kind.allCases) { k in typeChip(k) }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                // 2) Détails
                Section(kind.label) {
                    TextField(kind.namePlaceholder, text: $name)
                    switch kind {
                    case .supplement:
                        Picker("Moment", selection: $moment) {
                            Text("Matin").tag("matin"); Text("Midi").tag("midi"); Text("Soir").tag("soir")
                        }
                    case .shopping:
                        HStack { Text("Quantité"); Spacer()
                            TextField("1", text: $quantity).multilineTextAlignment(.trailing).frame(width: 80) }
                    case .food:
                        Picker("Repas", selection: $meal) {
                            ForEach(["Petit-déj", "Déjeuner", "Dîner", "Collation"], id: \.self) { Text($0) }
                        }
                        HStack { Text("Calories"); Spacer()
                            TextField("kcal", text: $kcal).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90) }
                    case .note:
                        TextField("Contenu", text: $noteBody, axis: .vertical).lineLimit(2...5)
                    default:
                        EmptyView()
                    }
                }

                // 3) Rappel
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
                                Picker("Jour", selection: $weekday) {
                                    ForEach(weekdays, id: \.0) { Text($0.1).tag($0.0) }
                                }
                            }
                        }
                    }
                } footer: {
                    if remind { Text("Une notification te rappellera « \(name.isEmpty ? kind.label : name) ».") }
                }
            }
            .navigationTitle("Ajouter").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { add() }
                        .fontWeight(.bold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                kind = initialKind
                name = prefillName
                remind = initialKind.reminderByDefault
            }
            .onChange(of: kind) { _, k in withAnimation { remind = k.reminderByDefault } }
        }
    }

    private func typeChip(_ k: Kind) -> some View {
        let on = k == kind
        return Button {
            Haptics.tap(); withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { kind = k }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: k.icon).font(.system(size: 18, weight: .semibold))
                Text(k.label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(on ? Theme.onVolt : Color.primary)
            .frame(width: 78, height: 64)
            .background(on ? AnyShapeStyle(Theme.volt) : Theme.cardFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: on ? 0 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private func add() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        switch kind {
        case .task:
            let t = TodoItem(title: n)
            if remind && recurrence == .once { t.due = onceDate }
            ctx.insert(t)
        case .habit:
            ctx.insert(Habit(name: n, icon: "checkmark", colorHex: 0x4CF810))
        case .supplement:
            ctx.insert(Supplement(name: n,
                                  hour: cal.component(.hour, from: time),
                                  minute: cal.component(.minute, from: time),
                                  active: true, moment: moment))
        case .shopping:
            ctx.insert(ShoppingItem(name: n, quantity: quantity.isEmpty ? "1" : quantity))
        case .food:
            ctx.insert(FoodEntry(name: n, calories: Int(kcal) ?? 0, meal: meal))
        case .note:
            ctx.insert(Note(title: n, body: noteBody))
        }
        if remind { scheduleReminder(for: n) }
        Haptics.success()
        dismiss()
    }

    private func scheduleReminder(for n: String) {
        let id = "addflow.\(kind.rawValue).\(abs(n.hashValue))"
        let title = "\(kind.label) : \(n)"
        let body = reminderBody()
        let cal = Calendar.current
        let h = cal.component(.hour, from: time), m = cal.component(.minute, from: time)
        switch recurrence {
        case .once:   NotificationManager.shared.schedule(id: id, title: title, body: body, at: onceDate)
        case .daily:  NotificationManager.shared.scheduleDaily(id: id, title: title, body: body, hour: h, minute: m)
        case .weekly: NotificationManager.shared.scheduleWeekly(id: id, title: title, body: body, weekday: weekday, hour: h, minute: m)
        }
    }

    private func reminderBody() -> String {
        switch kind {
        case .supplement: return "N'oublie pas de prendre \(name) (\(moment))."
        case .habit:      return "C'est l'heure de ton habitude : \(name)."
        case .task:       return "Rappel : \(name)."
        case .shopping:   return "À acheter : \(name)."
        case .food:       return "Pense à logger : \(name)."
        case .note:       return name
        }
    }
}
