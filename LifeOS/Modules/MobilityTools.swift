import SwiftUI
import CoreLocation
import UIKit

// MARK: - Trajets & CO₂ (100% local, aucune permission)

enum TripMode: String, CaseIterable, Codable, Identifiable {
    case car, ev, moto, bus, ter, tgv, bike, plane
    var id: String { rawValue }
    var label: String {
        switch self {
        case .car: return "Voiture"; case .ev: return "Élec"; case .moto: return "Moto"
        case .bus: return "Bus"; case .ter: return "Train"; case .tgv: return "TGV"
        case .bike: return "Vélo"; case .plane: return "Avion"
        }
    }
    var icon: String {
        switch self {
        case .car: return "car.fill"; case .ev: return "bolt.car.fill"; case .moto: return "bicycle"
        case .bus: return "bus.fill"; case .ter: return "tram.fill"; case .tgv: return "train.side.front.car"
        case .bike: return "figure.outdoor.cycle"; case .plane: return "airplane"
        }
    }
    var gPerKm: Double {   // estimations ADEME (g CO₂e/km)
        switch self {
        case .car: return 193; case .ev: return 50; case .moto: return 110; case .bus: return 100
        case .ter: return 30; case .tgv: return 3; case .bike: return 0; case .plane: return 230
        }
    }
    var euroPerKm: Double {
        switch self {
        case .car: return 0.25; case .ev: return 0.08; case .moto: return 0.15; case .bus: return 0.10
        case .ter: return 0.12; case .tgv: return 0.12; case .bike: return 0; case .plane: return 0.15
        }
    }
}

private struct MobTrip: Codable, Identifiable {
    var id = UUID()
    var mode: TripMode
    var km: Double
    var date: Double
    var co2kg: Double { mode.gPerKm * km / 1000 }
    var cost: Double { mode.euroPerKm * km }
}

struct TripCO2View: View {
    @AppStorage("mobTrips") private var raw = ""
    @State private var mode: TripMode = .car
    @State private var kmText = ""

    private var trips: [MobTrip] {
        (try? JSONDecoder().decode([MobTrip].self, from: Data(raw.utf8))) ?? []
    }
    private func save(_ t: [MobTrip]) {
        if let d = try? JSONEncoder().encode(t) { raw = String(decoding: d, as: UTF8.self) }
    }
    private var monthTrips: [MobTrip] {
        trips.filter { Calendar.current.isDate(Date(timeIntervalSince1970: $0.date), equalTo: .now, toGranularity: .month) }
    }
    private var monthCO2: Double { monthTrips.reduce(0) { $0 + $1.co2kg } }
    private var monthCost: Double { monthTrips.reduce(0) { $0 + $1.cost } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    summary
                    inputCard
                    if trips.isEmpty {
                        EmptyStateCard(icon: "leaf.arrow.circlepath",
                                       title: "Aucun trajet",
                                       message: "Ajoute un trajet pour estimer ton empreinte et ton budget mobilité.")
                    } else {
                        tripList
                    }
                    Text("Estimations ADEME (g CO₂e/km). Indicatif.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Trajets & CO₂").navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            StatCard(value: String(format: "%.1f kg", monthCO2), label: "CO₂ ce mois", icon: "carbon.dioxide.cloud.fill")
            StatCard(value: String(format: "%.0f €", monthCost), label: "Coût ce mois", icon: "eurosign.circle.fill")
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nouveau trajet").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TripMode.allCases) { m in
                        Button { mode = m; Haptics.soft() } label: {
                            VStack(spacing: 4) {
                                Image(systemName: m.icon).font(.system(size: 18))
                                Text(m.label).font(.caption2)
                            }
                            .frame(width: 62, height: 54)
                            .background(mode == m ? AnyShapeStyle(Color.mobTint.gradient) : AnyShapeStyle(Theme.bg2),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(mode == m ? .white : Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 10) {
                HStack {
                    TextField("Distance", text: $kmText).keyboardType(.decimalPad)
                    Text("km").foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 10))
                Button { add() } label: {
                    Image(systemName: "plus").font(.headline).foregroundStyle(.white)
                        .frame(width: 46, height: 44)
                        .background(Color.mobTint.gradient, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled((Double(kmText.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
            }
            if let km = Double(kmText.replacingOccurrences(of: ",", with: ".")), km > 0 {
                Text("≈ \(String(format: "%.1f", mode.gPerKm * km / 1000)) kg CO₂ · \(String(format: "%.2f", mode.euroPerKm * km)) €")
                    .font(.caption).foregroundStyle(.mobTint)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var tripList: some View {
        VStack(spacing: 0) {
            ForEach(trips.sorted { $0.date > $1.date }) { t in
                HStack(spacing: 12) {
                    Image(systemName: t.mode.icon).foregroundStyle(.mobTint).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(t.mode.label) · \(String(format: "%.0f", t.km)) km").font(.subheadline.weight(.medium))
                        Text(Date(timeIntervalSince1970: t.date).formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f kg", t.co2kg)).font(.subheadline.weight(.semibold)).foregroundStyle(.mobTint)
                        Text(String(format: "%.2f €", t.cost)).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 11).padding(.horizontal, 14)
                .contentShape(Rectangle())
                .swipeActions { Button(role: .destructive) { remove(t) } label: { Label("Suppr", systemImage: "trash") } }
                Divider().padding(.leading, 50)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func add() {
        guard let km = Double(kmText.replacingOccurrences(of: ",", with: ".")), km > 0 else { return }
        var t = trips
        t.append(MobTrip(mode: mode, km: km, date: Date().timeIntervalSince1970))
        save(t); kmText = ""; Haptics.soft()
    }
    private func remove(_ trip: MobTrip) { save(trips.filter { $0.id != trip.id }); Haptics.soft() }
}

// MARK: - Où ai-je garé ? (CoreLocation, on-device)

final class OneShotLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var last: CLLocation?
    @Published var busy = false
    @Published var failed = false

    private let mgr = CLLocationManager()
    override init() { super.init(); mgr.delegate = self; status = mgr.authorizationStatus }

    func request() {
        failed = false; busy = true
        switch mgr.authorizationStatus {
        case .notDetermined: mgr.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: mgr.requestLocation()
        default: busy = false; failed = true
        }
    }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        status = m.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if busy { m.requestLocation() }
        } else if status == .denied || status == .restricted {
            busy = false; failed = true
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        last = locs.last; busy = false
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        busy = false; failed = true
    }
}

struct ParkingView: View {
    @AppStorage("parkLat") private var lat = 0.0
    @AppStorage("parkLon") private var lon = 0.0
    @AppStorage("parkDate") private var savedAt = 0.0
    @AppStorage("parkNote") private var note = ""
    @StateObject private var locator = OneShotLocator()
    @State private var editingNote = false
    @State private var draftNote = ""

    private var hasSpot: Bool { savedAt > 0 && (lat != 0 || lon != 0) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    if locator.busy { ProgressView("Localisation…").padding() }
                    if locator.failed { errorCard }
                    if hasSpot { savedCard } else if !locator.busy { emptyCard }
                    saveButton
                }
                .padding(Theme.pad)
            }
        }
        .navigationTitle("Où ai-je garé ?").navigationBarTitleDisplayMode(.inline)
        .onChange(of: locator.last) { _, loc in if let loc { commit(loc) } }
        .alert("Note (étage, place…)", isPresented: $editingNote) {
            TextField("Niveau -2, place 38", text: $draftNote)
            Button("Enregistrer") { note = draftNote }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "parkingsign.circle.fill").font(.system(size: 54)).foregroundStyle(.mobTint)
            Text("Aucune place enregistrée").font(.headline)
            Text("Appuie sur le bouton en sortant de ta voiture pour mémoriser l'endroit.")
                .font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "car.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.mobTint.gradient, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voiture garée").font(.subheadline.weight(.semibold))
                    Text("il y a \(elapsed)").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            if !note.isEmpty {
                Label(note, systemImage: "note.text").font(.subheadline).foregroundStyle(Theme.textPrimary)
            }
            Text(String(format: "%.5f, %.5f", lat, lon)).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Button { openInMaps() } label: {
                    Label("Itinéraire", systemImage: "map.fill").frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Color.mobTint.gradient, in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(.white)
                }.buttonStyle(.plain)
                Button { draftNote = note; editingNote = true } label: {
                    Image(systemName: "square.and.pencil").frame(width: 46, height: 44)
                        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(.mobTint)
                }.buttonStyle(.plain)
                Button { clear() } label: {
                    Image(systemName: "trash").frame(width: 46, height: 44)
                        .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(.red)
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var errorCard: some View {
        Label("Localisation indisponible. Active-la dans Réglages › Confidentialité › Localisation.",
              systemImage: "location.slash.fill")
            .font(.subheadline).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var saveButton: some View {
        Button { locator.request() } label: {
            Label(hasSpot ? "Mettre à jour ma place" : "Enregistrer ma place",
                  systemImage: "mappin.and.ellipse")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.mobTint.gradient, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(locator.busy)
    }

    private var elapsed: String {
        let s = Date().timeIntervalSince1970 - savedAt
        if s < 3600 { return "\(Int(s/60)) min" }
        if s < 86400 { return "\(Int(s/3600)) h" }
        return "\(Int(s/86400)) j"
    }
    private func commit(_ loc: CLLocation) {
        lat = loc.coordinate.latitude; lon = loc.coordinate.longitude
        savedAt = Date().timeIntervalSince1970; Haptics.soft()
    }
    private func clear() { savedAt = 0; lat = 0; lon = 0; note = ""; Haptics.soft() }
    private func openInMaps() {
        if let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=w") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - petits composants locaux

private struct StatCard: View {
    let value: String; let label: String; let icon: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(.mobTint)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

private struct EmptyStateCard: View {
    let icon: String; let title: String; let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 46)).foregroundStyle(.mobTint)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}
