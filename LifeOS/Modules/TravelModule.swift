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
                    subtitle: "Compte à rebours & statut", tint: .travelTint) { FlightTrackerView() }
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

// MARK: - Suivi des vols (tracker manuel, hors-ligne, avec compte à rebours)

struct TrackedFlight: Identifiable, Codable, Equatable {
    var id = UUID()
    var number = ""
    var airline = ""
    var from = ""
    var to = ""
    var departure = Date()
    var status = "À l'heure"

    static let statuses = ["À l'heure", "Embarquement", "Retardé", "Décollé", "Atterri", "Annulé"]
    var statusColor: Color {
        switch status {
        case "Retardé":  return .orange
        case "Annulé":   return .red
        case "Atterri":  return .green
        case "Décollé", "Embarquement": return .blue
        default:         return Color.travelTint
        }
    }
}

struct FlightTrackerView: View {
    @AppStorage("trackedFlights") private var raw = "[]"
    @State private var flights: [TrackedFlight] = []
    @State private var editing: TrackedFlight?
    @State private var showAdd = false

    private var sorted: [TrackedFlight] { flights.sorted { $0.departure < $1.departure } }

    var body: some View {
        ZStack {
            Theme.background
            if flights.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "airplane.circle.fill").font(.system(size: 54)).foregroundStyle(.travelTint)
                    Text("Aucun vol suivi").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("Ajoute un vol pour voir le compte à rebours et son statut.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { showAdd = true } label: { Label("Ajouter un vol", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(.travelTint)
                }.padding(30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sorted) { f in flightCard(f) }
                    }.padding(Theme.pad)
                }
            }
        }
        .navigationTitle("Suivi des vols").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { FlightEditor { add($0) } }
        .sheet(item: $editing) { f in FlightEditor(flight: f) { update($0) } onDelete: { remove(f) } }
        .onAppear(perform: reload)
    }

    private func flightCard(_ f: TrackedFlight) -> some View {
        Button { editing = f } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(f.from.isEmpty ? "???" : f.from)  →  \(f.to.isEmpty ? "???" : f.to)")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(f.status).font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(f.statusColor, in: Capsule())
                }
                HStack(spacing: 8) {
                    if !f.airline.isEmpty { Text(f.airline) }
                    if !f.number.isEmpty { Text(f.number).foregroundStyle(.travelTint) }
                    Spacer()
                    Text(f.departure, format: .dateTime.day().month().hour().minute())
                }.font(.subheadline).foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(countdown(to: f.departure, now: ctx.date))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(f.departure < ctx.date ? Color.secondary : Color.travelTint)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { Button(role: .destructive) { remove(f) } label: { Label("Supprimer", systemImage: "trash") } }
    }

    private func countdown(to date: Date, now: Date) -> String {
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 { return "Départ passé" }
        let h = s / 3600, m = (s % 3600) / 60
        if h >= 24 { return "Dans \(h / 24) j \(h % 24) h" }
        if h >= 1 { return "Décollage dans \(h) h \(m) min" }
        return "Décollage dans \(m) min"
    }

    // MARK: persistance JSON (aucune migration SwiftData)
    private func reload() {
        flights = (try? JSONDecoder().decode([TrackedFlight].self, from: Data(raw.utf8))) ?? []
    }
    private func persist() {
        raw = String(data: (try? JSONEncoder().encode(flights)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }
    private func add(_ f: TrackedFlight) { flights.append(f); persist() }
    private func update(_ f: TrackedFlight) {
        if let i = flights.firstIndex(where: { $0.id == f.id }) { flights[i] = f; persist() }
    }
    private func remove(_ f: TrackedFlight) { flights.removeAll { $0.id == f.id }; persist() }
}

private struct FlightEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var flight: TrackedFlight
    let onSave: (TrackedFlight) -> Void
    let onDelete: (() -> Void)?

    init(flight: TrackedFlight = TrackedFlight(), onSave: @escaping (TrackedFlight) -> Void, onDelete: (() -> Void)? = nil) {
        self._flight = State(initialValue: flight)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trajet") {
                    TextField("De (ex: CDG)", text: $flight.from).textInputAutocapitalization(.characters)
                    TextField("À (ex: JFK)", text: $flight.to).textInputAutocapitalization(.characters)
                }
                Section("Vol") {
                    TextField("Compagnie (ex: Air France)", text: $flight.airline)
                    TextField("N° de vol (ex: AF008)", text: $flight.number).textInputAutocapitalization(.characters)
                    DatePicker("Départ", selection: $flight.departure)
                }
                Section("Statut") {
                    Picker("Statut", selection: $flight.status) {
                        ForEach(TrackedFlight.statuses, id: \.self) { Text($0).tag($0) }
                    }
                }
                if let onDelete {
                    Section {
                        Button(role: .destructive) { onDelete(); dismiss() } label: {
                            Label("Supprimer ce vol", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(onDelete == nil ? "Nouveau vol" : "Modifier le vol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { onSave(flight); dismiss() } }
            }
        }
    }
}
