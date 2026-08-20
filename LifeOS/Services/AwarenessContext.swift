import Foundation
import CoreLocation

/// Extrait le contexte temporel et locationnel actuel pour l'injecter dans le
/// prompt coach — le coach répond différemment à 6h vs 22h, à la gym vs au boulot.
///
/// Aucune permission n'est FORCÉE : la location retombe sur "inconnue" si le user
/// n'a pas autorisé. Le time est toujours disponible (Calendar.current).
///
/// Utilisation :
///   let text = await AwarenessContext.snapshot()
///   → "Contexte actuel: mardi 22h35, week-end approche, lieu inconnu"
@MainActor
enum AwarenessContext {

    /// Résumé texte prêt à injecter dans le prompt système.
    static func snapshot() async -> String {
        var lines: [String] = ["Contexte actuel :"]
        lines.append("- " + timeSnapshot())
        if let loc = await locationSnapshot() {
            lines.append("- " + loc)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Time

    private static func timeSnapshot() -> String {
        let cal = Calendar.current
        let now = Date.now
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now)  // 1=dimanche, 2=lundi...
        let weekdayName: String = {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "fr_FR")
            fmt.dateFormat = "EEEE"
            return fmt.string(from: now).capitalized
        }()

        let momentOfDay: String
        switch hour {
        case 5..<9:   momentOfDay = "début de matinée"
        case 9..<12:  momentOfDay = "matinée"
        case 12..<14: momentOfDay = "midi"
        case 14..<18: momentOfDay = "après-midi"
        case 18..<22: momentOfDay = "soirée"
        case 22..<24, 0..<5: momentOfDay = "nuit / avant le coucher"
        default: momentOfDay = ""
        }

        let weekPart: String
        if weekday == 1 || weekday == 7 {
            weekPart = "week-end"
        } else if weekday == 6 {
            weekPart = "vendredi (week-end demain)"
        } else if weekday == 2 && hour < 12 {
            weekPart = "début de semaine"
        } else {
            weekPart = "en semaine"
        }

        return "\(weekdayName) \(hour)h, \(momentOfDay), \(weekPart)"
    }

    // MARK: - Location

    /// Retourne un texte type "à la maison / au bureau / gym / inconnu"
    /// basé sur les distances aux "significant locations" enregistrées.
    /// Actuellement : simplification — utilise la dernière location connue si dispo.
    private static func locationSnapshot() async -> String? {
        let manager = LocationSnapshot.shared
        return await manager.currentLabel()
    }
}

// MARK: - LocationSnapshot (helper CoreLocation)

/// Manager location minimaliste : demande "when in use" (permission déjà OK dans Info.plist),
/// lit la dernière position, retourne un label lisible.
///
/// Aucune écoute continue — juste "location au moment où on demande". Pas de tracking.
@MainActor
final class LocationSnapshot: NSObject, CLLocationManagerDelegate {
    static let shared = LocationSnapshot()

    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLLocation?, Never>?
    private var latestLocation: CLLocation?
    private var latestFetchedAt: Date = .distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer  // pas besoin de précision GPS
    }

    /// Retourne un label descriptif ou nil si location indispo.
    /// Cache 10 min pour éviter d'énergiver le GPS à chaque message.
    func currentLabel() async -> String? {
        // Cache
        if let latestLocation, Date().timeIntervalSince(latestFetchedAt) < 600 {
            return labelFor(latestLocation)
        }
        // Vérif permission
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }
        // Fetch async
        let loc: CLLocation? = await withCheckedContinuation { cont in
            pendingContinuation = cont
            manager.requestLocation()
        }
        latestLocation = loc
        latestFetchedAt = .now
        guard let loc else { return nil }
        return labelFor(loc)
    }

    /// Label descriptif basique — sans reverse-geocoding (économie batterie + no réseau).
    /// À terme : comparer aux significant places du user (Home, Work) stockées dans le profil.
    private func labelFor(_ location: CLLocation) -> String {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        return String(format: "position approx. %.2f°N, %.2f°E", lat, lon)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let loc = locations.last
            self.pendingContinuation?.resume(returning: loc)
            self.pendingContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.pendingContinuation?.resume(returning: nil)
            self.pendingContinuation = nil
        }
    }
}
