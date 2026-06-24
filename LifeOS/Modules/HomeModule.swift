import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var homeTint: Color { AppCategory.home.tint } }

// MARK: - Hub Maison

struct HomeHubView: View {
    var body: some View {
        HubScaffold(category: .home) {
            ToolRow(icon: "calendar.badge.exclamationmark", title: "Anti-gaspi & péremption",
                    subtitle: "Ce qui périme bientôt", tint: .homeTint) { AntiWasteView() }
            ToolRow(icon: "frying.pan.fill", title: "Recettes avec les restes",
                    subtitle: "Cuisine ce que tu as", tint: .homeTint) { LeftoverRecipesView() }
            ToolRow(icon: "checklist", title: "Tâches ménagères",
                    subtitle: "Réparties couple / coloc", tint: .homeTint) { ChoresView() }
            ToolRow(icon: "pawprint.fill", title: "Mes animaux",
                    subtitle: "Gamelle, véto, vaccins", tint: .homeTint) { PetsView() }
            ToolRow(icon: "wrench.and.screwdriver.fill", title: "Maintenance récurrente",
                    subtitle: "Filtres, révisions, plantes", tint: .homeTint) { MaintenanceView() }
        }
    }
}

// MARK: - Anti-gaspi (réutilise PantryItem)

struct AntiWasteView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var items: [PantryItem]
    private var withExpiry: [PantryItem] { items.filter { $0.expiry != nil }.sorted { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if withExpiry.isEmpty {
                        EmptyState(icon: "calendar.badge.exclamationmark", title: "Rien à surveiller", message: "Ajoute des dates de péremption à tes produits (dans Nutrition › Mon frigo).")
                    } else {
                        ForEach(withExpiry) { it in
                            HStack {
                                VStack(alignment: .leading) { Text(it.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary); Text("\(it.quantity) · \(it.location)").font(.caption).foregroundStyle(Theme.textSecondary) }
                                Spacer()
                                if let e = it.expiry { ExpiryBadge(date: e) }
                                Button(role: .destructive) { ctx.delete(it) } label: { Image(systemName: "checkmark.circle").font(.title3) }.foregroundStyle(.green)
                            }.card(padding: 12)
                        }
                        Text("Coche pour marquer comme consommé. Astuce : cuisine d'abord ce qui est en haut.").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Anti-gaspi").navigationBarTitleDisplayMode(.inline)
    }
}

struct LeftoverRecipesView: View {
    @Query private var items: [PantryItem]
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    let suggestions = RecipeEngine.suggest(from: items.map { $0.name })
                    if suggestions.isEmpty {
                        EmptyState(icon: "frying.pan", title: "Pas assez d'ingrédients", message: "Remplis ton frigo (Nutrition › Mon frigo) pour des idées recettes.")
                    } else {
                        ForEach(suggestions, id: \.name) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(r.name).font(.headline).foregroundStyle(Theme.textPrimary); Spacer(); Text("\(Int(Double(r.matched)/Double(r.ingredients.count)*100))%").font(.subheadline.bold()).foregroundStyle(.homeTint) }
                                Text("Ingrédients : " + r.ingredients.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).card()
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Recettes restes").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tâches ménagères

struct ChoresView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var chores: [Chore]
    @State private var showAdd = false
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if chores.isEmpty {
                        EmptyState(icon: "checklist", title: "Aucune tâche", message: "Répartis les corvées et coche-les quand c'est fait.")
                    } else {
                        ForEach(chores.sorted { ($0.nextDue ?? .distantPast) < ($1.nextDue ?? .distantPast) }) { c in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(c.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(c.assignee).font(.caption2).padding(.horizontal,6).padding(.vertical,2).background(Color.homeTint.opacity(0.2), in: Capsule()).foregroundStyle(.homeTint)
                                        if let due = c.nextDue { Text(dueLabel(due)).font(.caption).foregroundStyle(due < .now ? .red : Theme.textSecondary) }
                                        else { Text("Jamais faite").font(.caption).foregroundStyle(.orange) }
                                    }
                                }
                                Spacer()
                                Button { c.lastDone = Date(); Haptics.tap() } label: { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green) }
                            }.card(padding: 12)
                                .contextMenu { Button(role: .destructive) { ctx.delete(c) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Tâches ménagères").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { ChoreEditor() }
    }
    private func dueLabel(_ d: Date) -> String { let days = Calendar.current.dateComponents([.day], from: .now, to: d).day ?? 0; return days < 0 ? "En retard" : days == 0 ? "Aujourd'hui" : "Dans \(days)j" }
}

struct ChoreEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var assignee = "Moi"; @State private var freq = 7
    var body: some View {
        NavigationStack {
            Form {
                TextField("Tâche (ex: Sortir les poubelles)", text: $name)
                TextField("Assigné à", text: $assignee)
                Stepper("Tous les \(freq) jours", value: $freq, in: 1...90)
            }
            .navigationTitle("Nouvelle tâche").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(Chore(name: name, assignee: assignee, frequencyDays: freq)); dismiss() }.disabled(name.isEmpty) }
            }
        }
    }
}

// MARK: - Animaux

struct PetsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var pets: [Pet]
    @State private var showAdd = false
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if pets.isEmpty {
                        EmptyState(icon: "pawprint", title: "Aucun animal", message: "Ajoute tes chats pour suivre gamelle, véto et vaccins.")
                    } else {
                        ForEach(pets) { p in PetCard(pet: p) }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Mes animaux").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { PetEditor() }
    }
}

struct PetCard: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var pet: Pet
    @State private var showAddEvent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: pet.species == "Chat" ? "cat.fill" : pet.species == "Chien" ? "dog.fill" : "pawprint.fill").font(.title2).foregroundStyle(.homeTint)
                Text(pet.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { showAddEvent = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.homeTint) }
                Button(role: .destructive) { ctx.delete(pet) } label: { Image(systemName: "trash").font(.caption) }.foregroundStyle(.red.opacity(0.6))
            }
            if pet.events.isEmpty { Text("Aucun événement.").font(.caption).foregroundStyle(Theme.textSecondary) }
            ForEach(pet.events.sorted { $0.date < $1.date }) { e in
                HStack {
                    Image(systemName: iconFor(e.type)).foregroundStyle(.homeTint).frame(width: 22)
                    VStack(alignment: .leading) { Text(e.type).font(.subheadline).foregroundStyle(Theme.textPrimary); if !e.note.isEmpty { Text(e.note).font(.caption).foregroundStyle(Theme.textSecondary) } }
                    Spacer()
                    Text(e.date, style: .date).font(.caption).foregroundStyle(e.date < .now ? .red : Theme.textSecondary)
                }
            }
        }.card()
        .sheet(isPresented: $showAddEvent) { PetEventEditor(pet: pet) }
    }
    private func iconFor(_ t: String) -> String { switch t { case "Vétérinaire": return "cross.case.fill"; case "Vaccin": return "syringe.fill"; case "Anti-puces": return "ant.fill"; default: return "fork.knife" } }
}

struct PetEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var species = "Chat"
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                Picker("Espèce", selection: $species) { ForEach(["Chat","Chien","Autre"], id: \.self) { Text($0) } }
            }
            .navigationTitle("Nouvel animal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(Pet(name: name, species: species)); dismiss() }.disabled(name.isEmpty) }
            }
        }
    }
}

struct PetEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var pet: Pet
    @State private var type = "Vétérinaire"; @State private var date = Date(); @State private var note = ""; @State private var remind = true
    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) { ForEach(["Gamelle","Vétérinaire","Vaccin","Anti-puces"], id: \.self) { Text($0) } }
                DatePicker("Date", selection: $date)
                TextField("Note", text: $note)
                Toggle("Me rappeler", isOn: $remind)
            }
            .navigationTitle("Événement").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    pet.events.append(PetCare(type: type, date: date, note: note))
                    if remind { NotificationManager.shared.schedule(id: "pet-\(pet.name)-\(type)-\(Int(date.timeIntervalSince1970))", title: "\(pet.name) — \(type)", body: note.isEmpty ? "Rappel pour \(pet.name)" : note, at: date) }
                    dismiss()
                } }
            }
        }
    }
}

// MARK: - Maintenance

struct MaintenanceView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var items: [Maintenance]
    @State private var showAdd = false
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if items.isEmpty {
                        EmptyState(icon: "wrench.and.screwdriver", title: "Aucune maintenance", message: "Filtre clim, révision voiture, arroser les plantes…")
                    } else {
                        ForEach(items.sorted { ($0.nextDue ?? .distantPast) < ($1.nextDue ?? .distantPast) }) { m in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(m.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    if let due = m.nextDue { Text("Prochaine : \(due, style: .date)").font(.caption).foregroundStyle(due < .now ? .red : Theme.textSecondary) }
                                    else { Text("Jamais faite").font(.caption).foregroundStyle(.orange) }
                                }
                                Spacer()
                                Button { m.lastDone = Date(); Haptics.tap() } label: { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green) }
                            }.card(padding: 12)
                                .contextMenu { Button(role: .destructive) { ctx.delete(m) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Maintenance").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { MaintenanceEditor() }
    }
}

struct MaintenanceEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var interval = 90; @State private var doneNow = true
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex: Révision voiture)", text: $name)
                Stepper("Tous les \(interval) jours", value: $interval, in: 1...730, step: 1)
                Toggle("Fait aujourd'hui", isOn: $doneNow)
            }
            .navigationTitle("Nouvelle maintenance").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(Maintenance(name: name, lastDone: doneNow ? Date() : nil, intervalDays: interval)); dismiss() }.disabled(name.isEmpty) }
            }
        }
    }
}
