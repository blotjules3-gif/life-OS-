import Foundation

/// Quand rappeler la prise d'un medicament.
///
/// Le defaut corrige etait grave pour un ecran medical: l'app promettait
/// "des rappels de prise" et programmait UNE notification, une seule fois,
/// avec `schedule(id:title:body:at:)` qui ne se repete pas. Un traitement
/// quotidien etait donc rappele le lendemain matin, puis plus jamais.
/// Trois autres trous allaient avec: "2x/jour" n'envoyait qu'un rappel,
/// supprimer ou desactiver un medicament n'annulait rien, et la date de fin
/// n'etait jamais regardee.
///
/// La regle est isolee ici pour etre testable: on ne peut pas verifier a la
/// main qu'une notification part bien dans six mois.
enum MedicationSchedule {

    struct Dose: Equatable {
        let hour: Int
        let minute: Int
        /// Sert au texte de la notification: "matin", "midi", "soir".
        let label: String
    }

    static let defaultMorning = 8
    static let defaultEvening = 20

    /// Un medicament "au besoin" ne se rappelle pas.
    ///
    /// C'est le cas le plus important de cette fonction. Rappeler chaque
    /// matin de prendre un antidouleur a prendre seulement en cas de douleur
    /// pousse a le prendre sans raison. Le silence est la bonne reponse.
    static func isOnDemand(_ frequency: String) -> Bool {
        normalised(frequency).contains("besoin")
    }

    static func isWeekly(_ frequency: String) -> Bool {
        normalised(frequency).contains("semaine")
    }

    /// Les prises d'une journee, dans l'ordre.
    static func doses(frequency: String, hourMorning: Int?, hourEvening: Int?) -> [Dose] {
        guard !isOnDemand(frequency) else { return [] }

        let morning = clampHour(hourMorning ?? defaultMorning)
        let evening = clampHour(hourEvening ?? defaultEvening)

        switch perDay(frequency) {
        case 1:
            return [Dose(hour: morning, minute: 0, label: "matin")]
        case 2:
            return [Dose(hour: morning, minute: 0, label: "matin"),
                    Dose(hour: evening, minute: 0, label: "soir")]
        default:
            // Le midi se place entre les deux plutot qu'a une heure fixe:
            // quelqu'un qui prend son traitement a 6 h et 18 h n'a pas midi
            // au milieu de sa journee.
            let midday = clampHour((morning + max(evening, morning + 2)) / 2)
            return [Dose(hour: morning, minute: 0, label: "matin"),
                    Dose(hour: midday, minute: 0, label: "midi"),
                    Dose(hour: evening, minute: 0, label: "soir")]
        }
    }

    /// Faut-il encore rappeler ce traitement aujourd'hui.
    ///
    /// La date de fin est INCLUSE: un traitement "jusqu'au 12" se prend le 12.
    static func isRunning(active: Bool, endDate: Date?, now: Date = .now,
                          calendar: Calendar = .current) -> Bool {
        guard active else { return false }
        guard let end = endDate else { return true }
        return calendar.startOfDay(for: now) <= calendar.startOfDay(for: end)
    }

    /// Une prise par jour annoncee par le libelle, 1 par defaut.
    private static func perDay(_ frequency: String) -> Int {
        let f = normalised(frequency)
        if isWeekly(f) { return 1 }
        // "3x/jour", "3 fois par jour", "x3"...
        for n in [3, 2] where f.contains("\(n)") { return n }
        return 1
    }

    private static func normalised(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    private static func clampHour(_ h: Int) -> Int { min(23, max(0, h)) }
}
