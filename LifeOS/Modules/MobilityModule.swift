import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var mobTint: Color { AppCategory.mobility.tint } }

// MARK: - Hub Mobilité


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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { VehicleEditor() }
    }
}

struct VehicleCard: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var vehicle: Vehicle
    /// Pour ne pas annuler le rappel d'un autre vehicule au meme nom.
    @Query private var allVehicles: [Vehicle]
    @State private var showFuel = false

    private var avgConsumption: Double? {
        FuelMath.averageConsumption(vehicle.fuelLogs.map { FuelMath.Entry(date: $0.date, liters: $0.liters, odometer: $0.odometer) })
    }
    private var monthCost: Double { vehicle.fuelLogs.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }.reduce(0) { $0 + $1.total } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "car.fill").font(.title2).foregroundStyle(.mobTint)
                Text(vehicle.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { showFuel = true } label: { Image(systemName: "fuelpump.fill").foregroundStyle(.mobTint) }.accessibilityLabel("Ajouter un plein")
                Button(role: .destructive) {
                    VehicleReminders.cancel(vehicle, others: allVehicles)
                    ctx.delete(vehicle)
                } label: { Image(systemName: "trash").font(.caption) }.foregroundStyle(Theme.danger.opacity(0.6))
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
                Text(date, style: .date).font(.subheadline.bold()).foregroundStyle(date < .now ? Theme.danger : (date < Calendar.current.date(byAdding: .day, value: 30, to: .now)! ? Theme.warning : Theme.textPrimary))
            } else { Text("—").foregroundStyle(Theme.textSecondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).raisedSurface(RoundedRectangle(cornerRadius: 10), .nested)
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
                    VehicleReminders.schedule(v)
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
    private var l: AmountInput.Parsed { AmountInput.parse(liters) }
    private var p: AmountInput.Parsed { AmountInput.parse(price) }
    // Kilometrage obligatoire: vide devenait 0, ce plein passait premier au
    // tri par compteur et la conso affichee s'effondrait.
    private var odo: Int? { FuelMath.parseOdometer(odometer) }
    var body: some View {
        NavigationStack {
            Form {
                HStack { Text("Litres"); Spacer(); TextField("0", text: $liters).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if !liters.isEmpty, let m = l.message { Text(m).font(.caption).foregroundStyle(Theme.warning) }
                HStack { Text("Prix / litre"); Spacer(); TextField("0", text: $price).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if !price.isEmpty, let m = p.message { Text(m).font(.caption).foregroundStyle(Theme.warning) }
                HStack { Text("Kilométrage"); Spacer(); TextField("0", text: $odometer).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                if odometer.trimmingCharacters(in: .whitespaces).isEmpty { Text("Kilométrage du compteur requis (sert au calcul de la conso).").font(.caption).foregroundStyle(Theme.textSecondary) }
                else if odo == nil { Text("Kilométrage : chiffres seulement, plus grand que 0.").font(.caption).foregroundStyle(Theme.warning) }
            }
            .navigationTitle("Plein de carburant").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    guard let lv = l.value, let pv = p.value, let o = odo else { return }
                    vehicle.fuelLogs.append(FuelLog(liters: lv, pricePerL: pv, odometer: o)); dismiss()
                }.disabled(l.value == nil || p.value == nil || odo == nil) }
            }
        }
    }
}

// MARK: - Calculs carburant (purs, testes)

enum FuelMath {
    struct Entry { let date: Date; let liters: Double; let odometer: Int }

    /// Compteur saisi. Vide ou 0 = nil: un plein sans kilometrage ne doit
    /// jamais entrer dans le calcul comme "0 km".
    static func parseOdometer(_ text: String) -> Int? {
        guard let v = Int(text.filter { !$0.isWhitespace }), v > 0 else { return nil }
        return v
    }

    /// Conso moyenne plein a plein (L/100 km), ou nil si on ne peut pas la
    /// calculer honnetement.
    ///
    /// Les pleins enregistres avec un compteur a 0 (ancienne saisie vide) sont
    /// ignores: tries par compteur ils passaient premiers et la conso tombait
    /// presque a zero. Si un de ces pleins tombe ENTRE le premier et le dernier
    /// plein valide, ses litres manquent au total: on ne montre rien plutot
    /// qu'une conso fausse.
    static func averageConsumption(_ entries: [Entry]) -> Double? {
        let valid = entries.filter { $0.odometer > 0 }.sorted { $0.odometer < $1.odometer }
        guard valid.count >= 2, let first = valid.first, let last = valid.last,
              last.odometer > first.odometer else { return nil }
        let gap = entries.contains { $0.odometer <= 0 && $0.date > first.date && $0.date <= last.date }
        if gap { return nil }
        let liters = valid.dropFirst().reduce(0) { $0 + $1.liters }
        let km = Double(last.odometer - first.odometer)
        return km > 0 ? liters / km * 100 : nil
    }
}

// MARK: - Rappels vehicule (un seul endroit pour poser et annuler)

enum VehicleReminders {
    /// Pose les rappels J-7 assurance et revision avec le nom et les dates
    /// ACTUELS du vehicule.
    static func schedule(_ v: Vehicle) {
        let cal = Calendar.current
        if let d = v.insuranceRenewal {
            NotificationManager.shared.schedule(id: ReminderIDs.vehicleInsurance(name: v.name, date: d), title: "Assurance \(v.name)", body: "Renouvellement à prévoir.", at: cal.date(byAdding: .day, value: -7, to: d) ?? d)
        }
        if let d = v.nextService {
            NotificationManager.shared.schedule(id: ReminderIDs.vehicleService(name: v.name, date: d), title: "Révision \(v.name)", body: "Révision à planifier.", at: cal.date(byAdding: .day, value: -7, to: d) ?? d)
        }
    }

    /// Annule les rappels qu'un vehicule a pu poser (nom et dates passes en
    /// parametre: a appeler AVANT un renommage), sauf ceux qu'un autre
    /// vehicule utilise encore.
    static func cancel(name: String, insurance: Date?, service: Date?, excluding v: Vehicle, others: [Vehicle]) {
        let remaining = others.filter { $0 !== v }.map { ReminderIDs.vehicleIDs(name: $0.name, insurance: $0.insuranceRenewal, service: $0.nextService) }
        let ids = ReminderIDs.cancellable(ReminderIDs.vehicleIDs(name: name, insurance: insurance, service: service), stillUsedBy: remaining)
        for id in ids { NotificationManager.shared.cancel(id: id) }
    }

    static func cancel(_ v: Vehicle, others: [Vehicle]) {
        cancel(name: v.name, insurance: v.insuranceRenewal, service: v.nextService, excluding: v, others: others)
    }
}

// MARK: - Scaffolds



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
