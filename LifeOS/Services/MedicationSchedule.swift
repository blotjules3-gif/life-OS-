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

    // MARK: - Plan de rappels

    /// Ce qu'il faut poser comme notifications pour un traitement.
    enum Plan: Equatable {
        case none
        /// Tous les jours, sans fin: un declencheur qui se repete.
        case repeatingDaily([Dose])
        /// Chaque semaine le meme jour (1 = dimanche ... 7 = samedi), sans fin.
        case repeatingWeekly(weekday: Int, doses: [Dose])
        /// Dates precises: traitement borne OU qui commence plus tard. Renouvele
        /// a chaque retour dans l'app (`MedicationReminders.renewAll`).
        case dates([Date])
    }

    /// iOS garde au plus 64 notifications en attente pour TOUTE l'app. Un
    /// traitement borne ne doit pas les consommer seul.
    static let maxDatedPerMedication = 24
    /// Jours couverts d'avance pour un traitement borne ou futur.
    static let horizonDays = 14

    /// Regle unique, testable. Avant, une date de fin envoyait TOUJOURS vers la
    /// branche quotidienne: un traitement hebdomadaire avec une fin sonnait donc
    /// tous les jours. Ici la frequence ET les bornes sont respectees ensemble.
    static func plan(frequency: String, hourMorning: Int?, hourEvening: Int?,
                     active: Bool, startDate: Date, endDate: Date?,
                     now: Date = .now, calendar cal: Calendar = .current,
                     horizonDays: Int = horizonDays, maxDates: Int = maxDatedPerMedication) -> Plan {
        guard isRunning(active: active, endDate: endDate, now: now, calendar: cal) else { return .none }
        let ds = doses(frequency: frequency, hourMorning: hourMorning, hourEvening: hourEvening)
        guard !ds.isEmpty else { return .none }
        let weekly = isWeekly(frequency)
        let startDay = cal.startOfDay(for: startDate)
        let today = cal.startOfDay(for: now)

        if endDate == nil && startDay <= today {
            return weekly
                ? .repeatingWeekly(weekday: cal.component(.weekday, from: startDate), doses: ds)
                : .repeatingDaily(ds)
        }

        let startWeekday = cal.component(.weekday, from: startDate)
        var day = max(startDay, today)
        let horizonEnd = cal.date(byAdding: .day, value: horizonDays, to: today) ?? today
        let lastDay = min(endDate.map { cal.startOfDay(for: $0) } ?? horizonEnd, horizonEnd)
        var out: [Date] = []
        while day <= lastDay && out.count < maxDates {
            if !weekly || cal.component(.weekday, from: day) == startWeekday {
                for d in ds {
                    if let at = cal.date(bySettingHour: d.hour, minute: d.minute, second: 0, of: day),
                       at > now, out.count < maxDates {
                        out.append(at)
                    }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return .dates(out)
    }

    private static func normalised(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    private static func clampHour(_ h: Int) -> Int { min(23, max(0, h)) }
}

// MARK: - Budget commun des rappels

/// iOS garde au plus 64 notifications programmees PAR APP, tous usages confondus
/// (medicaments, habitudes, complements, bilans...). Avant (audit du 28 sept.),
/// chaque medicament avait son propre plafond de 24: un traitement de 60 jours a
/// trois prises s'arretait au jour 7, et plusieurs traitements se disputaient
/// les 64 places sans le savoir. Ici la selection est COMMUNE: les rappels
/// repetitifs d'abord (une place chacun, ils couvrent sans fin), puis les rappels
/// dates les plus proches, tous traitements melanges, jusqu'a la place restante.
enum MedicationBudget {

    /// Limite d'iOS pour les notifications locales programmees.
    static let systemLimit = 64
    /// Places laissees aux autres fonctions qui programment plus tard.
    static let reserve = 8

    struct Item: Equatable {
        let medID: String
        let identifier: String
        /// nil: rappel repetitif (sans date de fin).
        let fireDate: Date?
    }

    enum Coverage: Equatable {
        case unlimited              // repetitif: sonne tant que le traitement existe
        case until(Date)            // dernier rappel programme
        case none                   // rien n'a pu etre programme
    }

    static func select(_ items: [Item], budget: Int) -> (chosen: [Item], coverage: [String: Coverage]) {
        let room = max(0, budget)
        let repeating = items.filter { $0.fireDate == nil }
        let dated = items.filter { $0.fireDate != nil }.sorted { $0.fireDate! < $1.fireDate! }
        let chosen = Array((repeating + dated).prefix(room))
        var coverage: [String: Coverage] = [:]
        for id in Set(items.map(\.medID)) {
            let mine = chosen.filter { $0.medID == id }
            if mine.contains(where: { $0.fireDate == nil }) { coverage[id] = .unlimited }
            else if let last = mine.compactMap(\.fireDate).max() { coverage[id] = .until(last) }
            else { coverage[id] = Coverage.none }
        }
        return (chosen, coverage)
    }
}
