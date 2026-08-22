import Foundation

/// Calcule la phase actuelle du cycle menstruel de l'utilisatrice pour
/// enrichir le contexte coach. Ne fait rien si `body.hasCycle` n'est pas true.
///
/// Feature très différenciante — corrélation forte cycle ↔ énergie, sommeil,
/// motivation sport. Trop peu d'apps coach l'exploitent bien.
///
/// Phases retournées :
///   - menstruelle (J1-J5)
///   - folliculaire (J6-J13)
///   - ovulatoire (J14-J16)
///   - lutéale (J17-fin)
///
/// Requiert : `cycle.lastPeriodStartDate` (ProfileField à ajouter) +
/// `cycle.averageLengthDays` (existe déjà, défaut 28).
@MainActor
enum CycleAwareness {

    enum Phase: String {
        case menstrual = "menstruelle"
        case follicular = "folliculaire"
        case ovulatory = "ovulatoire"
        case luteal = "lutéale"
    }

    struct Snapshot {
        let dayInCycle: Int
        let phase: Phase
        let cycleLength: Int
    }

    /// Retourne le snapshot si l'utilisatrice a un cycle actif ET a renseigné
    /// sa dernière date de règles. `nil` sinon (silencieux).
    static func currentSnapshot() -> Snapshot? {
        // Vérif du flag has cycle
        guard let hasCycleField = ProfileStore.shared.field("body.hasCycle"),
              hasCycleField.valueString.lowercased() == "true"
        else { return nil }

        // Lecture date dernière période (fieldID ajouté en Loop 8)
        guard let lastPeriodField = ProfileStore.shared.field("cycle.lastPeriodStartDate"),
              let lastPeriod = parseDate(lastPeriodField.valueString)
        else { return nil }

        // Longueur du cycle : lu depuis le profil, défaut 28
        let cycleLength: Int = {
            if let f = ProfileStore.shared.field("cycle.averageLengthDays"),
               let n = Int(f.valueString), n >= 20 && n <= 40 {
                return n
            }
            return 28
        }()

        let daysSince = Calendar.current.dateComponents([.day], from: lastPeriod, to: .now).day ?? 0
        // Modulo pour prendre en compte les cycles précédents
        let dayInCycle = (daysSince % cycleLength) + 1

        let phase: Phase
        switch dayInCycle {
        case 1...5:   phase = .menstrual
        case 6...13:  phase = .follicular
        case 14...16: phase = .ovulatory
        default:      phase = .luteal
        }

        return Snapshot(dayInCycle: dayInCycle, phase: phase, cycleLength: cycleLength)
    }

    /// Rend une ligne texte prête à injecter dans le prompt système. `""` si
    /// pas d'info dispo.
    static func promptLine() -> String {
        guard let snap = currentSnapshot() else { return "" }
        return "Cycle : phase \(snap.phase.rawValue) (J\(snap.dayInCycle)/\(snap.cycleLength))."
    }

    // MARK: - Helpers

    /// Parse ISO 8601 (produit par ProfileStore quand valueType = .date).
    private static func parseDate(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s)
            ?? DateFormatter.yyyyMMdd.date(from: s)
    }
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
