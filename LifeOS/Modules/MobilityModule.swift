import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var mobTint: Color { AppCategory.mobility.tint } }

// MARK: - Hub Mobilité

struct MobilityHubView: View {
    var body: some View {
        HubScaffold(category: .mobility) {
            ToolRow(icon: "car.fill", title: "Ma voiture",
                    subtitle: "Assurance, révision, carburant", tint: .mobTint) { VehicleListView() }
            ToolRow(icon: "fuelpump.fill", title: "Carburant le moins cher",
                    subtitle: "Carte stations — à brancher", tint: .mobTint) { FuelMapScaffold() }
            ToolRow(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Itinéraire multimodal",
                    subtitle: "Citymapper — à brancher", tint: .mobTint) { MultimodalScaffold() }
        }
    }
}

// MARK: - Véhicules

struct VehicleListView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var vehicles: [Vehicle]
    @State private var showAdd = false
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if vehicles.isEmpty {
                        EmptyState(icon: "car", title: "Aucun véhicule", message: "Ajoute ta voiture pour suivre échéances et carburant.")
                    } else {
                        ForEach(vehicles) { v in VehicleCard(vehicle: v) }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Ma voiture").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { VehicleEditor() }
    }
}

struct VehicleCard: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var vehicle: Vehicle
    @State private var showFuel = false

    private var avgConsumption: Double? {
        let logs = vehicle.fuelLogs.sorted { $0.odometer < $1.odometer }
        guard logs.count >= 2, let first = logs.first, let last = logs.last, last.odometer > first.odometer else { return nil }
        let liters = logs.dropFirst().reduce(0) { $0 + $1.liters }
        let km = Double(last.odometer - first.odometer)
        return km > 0 ? liters / km * 100 : nil
    }
    private var monthCost: Double { vehicle.fuelLogs.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }.reduce(0) { $0 + $1.total } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "car.fill").font(.title2).foregroundStyle(.mobTint)
                Text(vehicle.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { showFuel = true } label: { Image(systemName: "fuelpump.fill").foregroundStyle(.mobTint) }
                Button(role: .destructive) { ctx.delete(vehicle) } label: { Image(systemName: "trash").font(.caption) }.foregroundStyle(.red.opacity(0.6))
            }
            HStack(spacing: 10) {
                deadlineTile("Assurance", vehicle.insuranceRenewal)
                deadlineTile("Révision", vehicle.nextService)
            }
            HStack(spacing: 10) {
                StatTile(value: avgConsumption.map { String(format: "%.1f L", $0) } ?? "—", label: "Conso /100km", icon: "gauge", tint: .mobTint)
                StatTile(value: "\(Int(monthCost))€", label: "Carburant ce mois", icon: "eurosign", tint: .mobTint)
            }
        }.card()
        .sheet(isPresented: $showFuel) { FuelEditor(vehicle: vehicle) }
    }
    private func deadlineTile(_ label: String, _ date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            if let date {
                Text(date, style: .date).font(.subheadline.bold()).foregroundStyle(date < .now ? .red : (date < Calendar.current.date(byAdding: .day, value: 30, to: .now)! ? .orange : Theme.textPrimary))
            } else { Text("—").foregroundStyle(Theme.textSecondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Theme.bg2, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct VehicleEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hasInsurance = false; @State private var insurance = Date()
    @State private var hasService = false; @State private var service = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex: Clio, Tesla M3…)", text: $name)
                Toggle("Renouvellement assurance", isOn: $hasInsurance)
                if hasInsurance { DatePicker("Date", selection: $insurance, displayedComponents: .date) }
                Toggle("Prochaine révision", isOn: $hasService)
                if hasService { DatePicker("Date", selection: $service, displayedComponents: .date) }
            }
            .navigationTitle("Nouveau véhicule").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    let v = Vehicle(name: name, insuranceRenewal: hasInsurance ? insurance : nil, nextService: hasService ? service : nil)
                    ctx.insert(v)
                    if hasInsurance { NotificationManager.shared.schedule(id: "ins-\(name)", title: "Assurance \(name)", body: "Renouvellement à prévoir.", at: Calendar.current.date(byAdding: .day, value: -7, to: insurance) ?? insurance) }
                    if hasService { NotificationManager.shared.schedule(id: "serv-\(name)", title: "Révision \(name)", body: "Révision à planifier.", at: Calendar.current.date(byAdding: .day, value: -7, to: service) ?? service) }
                    dismiss()
                }.disabled(name.isEmpty) }
            }
        }
    }
}

struct FuelEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vehicle: Vehicle
    @State private var liters = ""; @State private var price = ""; @State private var odometer = ""
    var body: some View {
        NavigationStack {
            Form {
                HStack { Text("Litres"); Spacer(); TextField("0", text: $liters).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Prix / litre"); Spacer(); TextField("0", text: $price).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Kilométrage"); Spacer(); TextField("0", text: $odometer).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            }
            .navigationTitle("Plein de carburant").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    vehicle.fuelLogs.append(FuelLog(liters: Double(liters.replacingOccurrences(of: ",", with: ".")) ?? 0, pricePerL: Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0, odometer: Int(odometer) ?? 0)); dismiss()
                }.disabled(liters.isEmpty) }
            }
        }
    }
}

// MARK: - Scaffolds

struct FuelMapScaffold: View {
    var body: some View {
        ScaffoldPage(icon: "fuelpump.fill", title: "Carburant le moins cher", tint: .mobTint,
            notice: "Le prix des carburants en France est ouvert et GRATUIT via le jeu de données officiel prix-carburants.gouv.fr (data.economie.gouv.fr). Branchement : récupérer ta position → requête des stations dans un rayon → tri par prix du gazole/SP95. La carte MapKit est native iOS.",
            bullets: ["Source gratuite : data.economie.gouv.fr (prix temps réel)", "Géoloc : CoreLocation (déjà autorisé)", "Carte : MapKit natif", "Tri par prix + type de carburant"])
    }
}

struct MultimodalScaffold: View {
    var body: some View {
        ScaffoldPage(icon: "tram.fill", title: "Itinéraire multimodal", tint: .mobTint,
            notice: "Un itinéraire porte-à-porte combinant métro/bus/train/marche (façon Citymapper) nécessite des données transport. Options : l'API Navitia (navitia.io, freemium, couvre la France), Google Directions API (payant) ou les GTFS open-data des réseaux. Le comparateur train/vol/covoit s'appuie lui sur SNCF Connect / Trainline / BlaBlaCar (APIs partenaires).",
            bullets: ["Navitia API : itinéraires multimodaux FR (freemium)", "Apple Maps Transit : ouverture via MapKit Directions", "Comparateur : APIs SNCF / aériennes (partenariat)"])
    }
}

/// Page de scaffold générique réutilisable.
struct ScaffoldPage: View {
    let icon: String; let title: String; var tint: Color = Theme.accent
    let notice: String; let bullets: [String]
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: icon).font(.system(size: 56)).foregroundStyle(tint).padding(.top, 30)
                    Text(title).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                    IntegrationNotice(text: notice)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pistes d'activation").font(.headline).foregroundStyle(Theme.textPrimary)
                        ForEach(bullets, id: \.self) { Text("• " + $0).font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
