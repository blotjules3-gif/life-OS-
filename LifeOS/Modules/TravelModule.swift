import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var travelTint: Color { AppCategory.travel.tint } }

// MARK: - Hub Voyage

struct TravelHubView: View {
    var body: some View {
        HubScaffold(category: .travel) {
            ToolRow(icon: "map.fill", title: "Mes voyages",
                    subtitle: "Itinéraire + budget + valise", tint: .travelTint) { TripsView() }
            ToolRow(icon: "airplane.circle.fill", title: "Suivi des vols",
                    subtitle: "Statut & retards — à brancher", tint: .travelTint) { FlightScaffold() }
        }
    }
}

// MARK: - Voyages

struct TripsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Trip.start) private var trips: [Trip]
    @State private var showAdd = false
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if trips.isEmpty {
                        EmptyState(icon: "map", title: "Aucun voyage", message: "Planifie ton prochain voyage : dates, budget et checklist valise.")
                    } else {
                        ForEach(trips) { t in
                            NavigationLink { TripDetailView(trip: t) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Text(t.name).font(.headline).foregroundStyle(Theme.textPrimary); Spacer(); Text("\(Int(t.budget))€").font(.subheadline.bold()).foregroundStyle(.travelTint) }
                                    Label(t.destination, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(Theme.textSecondary)
                                    Text("\(t.start, style: .date) → \(t.end, style: .date)").font(.caption).foregroundStyle(Theme.textSecondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).card()
                            }.buttonStyle(.plain)
                                .contextMenu { Button(role: .destructive) { ctx.delete(t) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Mes voyages").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { TripEditor() }
    }
}

struct TripEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var destination = ""
    @State private var start = Date(); @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var budget = ""; @State private var climate = 1
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom du voyage", text: $name)
                TextField("Destination", text: $destination)
                DatePicker("Départ", selection: $start, displayedComponents: .date)
                DatePicker("Retour", selection: $end, in: start..., displayedComponents: .date)
                HStack { Text("Budget"); Spacer(); TextField("0", text: $budget).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                Picker("Climat", selection: $climate) { Text("❄️ Froid").tag(0); Text("🌤️ Tempéré").tag(1); Text("☀️ Chaud").tag(2) }
            }
            .navigationTitle("Nouveau voyage").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Créer") {
                    let t = Trip(name: name, destination: destination, start: start, end: end, budget: Double(budget) ?? 0)
                    let days = max(1, (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1))
                    t.packing = PackingEngine.generate(days: days, climate: climate).map { PackingItem(name: $0.0, category: $0.1) }
                    ctx.insert(t); dismiss()
                }.disabled(name.isEmpty) }
            }
        }
    }
}

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var ctx
    @State private var newItem = ""
    private var packedCount: Int { trip.packing.filter { $0.packed }.count }
    private var categories: [String] { Array(Set(trip.packing.map { $0.category })).sorted() }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(trip.destination, systemImage: "mappin.and.ellipse").foregroundStyle(.travelTint)
                        Text("\(trip.start, style: .date) → \(trip.end, style: .date)").font(.caption).foregroundStyle(Theme.textSecondary)
                        HStack {
                            StatTile(value: "\(Int(trip.budget))€", label: "Budget", icon: "eurosign.circle", tint: .travelTint)
                            StatTile(value: "\(packedCount)/\(trip.packing.count)", label: "Valise prête", icon: "suitcase.fill", tint: .travelTint)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Checklist valise", subtitle: "Générée selon durée & climat")
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).font(.caption.bold()).foregroundStyle(.travelTint)
                            ForEach(trip.packing.filter { $0.category == cat }) { item in
                                Button { item.packed.toggle(); Haptics.tap() } label: {
                                    HStack { Image(systemName: item.packed ? "checkmark.circle.fill" : "circle").foregroundStyle(item.packed ? .green : Theme.textSecondary); Text(item.name).strikethrough(item.packed).foregroundStyle(item.packed ? Theme.textSecondary : Theme.textPrimary); Spacer() }
                                }
                            }
                        }
                        HStack {
                            TextField("Ajouter un objet…", text: $newItem).textFieldStyle(.roundedBorder).onSubmit(add)
                            Button(action: add) { Image(systemName: "plus.circle.fill").foregroundStyle(.travelTint) }.disabled(newItem.isEmpty)
                        }
                    }.card()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Notes & itinéraire")
                        TextField("Vols, hôtels, activités, réservations…", text: $trip.notes, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(4...12)
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle(trip.name).navigationBarTitleDisplayMode(.inline)
    }
    private func add() { guard !newItem.isEmpty else { return }; trip.packing.append(PackingItem(name: newItem, category: "Divers")); newItem = "" }
}

/// Génère une checklist de valise selon durée et climat.
enum PackingEngine {
    static func generate(days: Int, climate: Int) -> [(String, String)] {
        var list: [(String, String)] = [
            ("Passeport / CNI", "Documents"), ("Billets / réservations", "Documents"),
            ("Carte bancaire", "Documents"), ("Chargeur téléphone", "Électronique"),
            ("Batterie externe", "Électronique"), ("Écouteurs", "Électronique"),
            ("Brosse à dents", "Toilette"), ("Dentifrice", "Toilette"),
            ("Déodorant", "Toilette"), ("Trousse de secours", "Toilette")
        ]
        let tops = min(days, 7)
        list.append(("\(tops) t-shirts", "Vêtements"))
        list.append(("\(max(1, days/2)) pantalons/shorts", "Vêtements"))
        list.append(("\(tops) sous-vêtements", "Vêtements"))
        list.append(("\(tops) paires de chaussettes", "Vêtements"))
        switch climate {
        case 0: list += [("Manteau chaud","Vêtements"),("Pull","Vêtements"),("Gants & bonnet","Vêtements"),("Chaussures imperméables","Vêtements")]
        case 2: list += [("Maillot de bain","Vêtements"),("Lunettes de soleil","Accessoires"),("Crème solaire","Toilette"),("Casquette","Accessoires"),("Tongs","Vêtements")]
        default: list += [("Veste légère","Vêtements"),("Pull","Vêtements"),("Parapluie","Accessoires")]
        }
        if days >= 5 { list.append(("Lessive en pod","Toilette")) }
        return list
    }
}

// MARK: - Suivi vols scaffold

struct FlightScaffold: View {
    var body: some View {
        ScaffoldPage(icon: "airplane.circle.fill", title: "Suivi des vols", tint: .travelTint,
            notice: "Suivre un vol en temps réel (statut, porte, retard) nécessite une API de données aériennes : AviationStack (offre gratuite limitée), FlightAware AeroAPI ou Amadeus. Branchement : saisir le n° de vol → requête API → statut + notifications push en cas de retard.",
            bullets: ["AviationStack : gratuit jusqu'à ~100 req/mois", "Amadeus Flight Status API (freemium)", "Saisie n° de vol → push en cas de retard", "Lien avec tes voyages déjà créés"])
    }
}
