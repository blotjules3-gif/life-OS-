import Foundation
import SwiftData

// MARK: - Modeles du lot medical

/// Une prise enregistree: prise, sautee ou reportee.
///
/// L'observance et le stock se calculent A PARTIR DE CES LIGNES, jamais a
/// partir des notifications: une notification livree ne dit pas qu'un
/// comprime a ete avale. Une prise "manquee" n'est pas stockee: elle se deduit
/// d'une heure prevue passee sans aucune ligne.
@Model final class DoseEvent {
    /// `Medication.stableID` du traitement.
    var medID: String = ""
    /// Heure prevue de la prise. nil: prise "au besoin", sans horaire.
    var scheduledAt: Date?
    var loggedAt: Date = Date()
    /// "taken", "skipped" ou "snoozed".
    var status: String = "taken"
    var snoozedUntil: Date?
    /// Unites retirees du stock, figees au moment de la prise: changer la
    /// quantite par prise ne doit pas reecrire le passe.
    var quantity: Double = 1
    init(medID: String, scheduledAt: Date?, status: String, loggedAt: Date = .now,
         snoozedUntil: Date? = nil, quantity: Double = 1) {
        self.medID = medID; self.scheduledAt = scheduledAt; self.status = status
        self.loggedAt = loggedAt; self.snoozedUntil = snoozedUntil; self.quantity = quantity
    }
}

/// Un proche suivi dans le carnet (enfant, parent...). "Moi" n'est pas une
/// ligne: un `personID` vide veut dire moi, ce qui garde toutes les fiches
/// existantes rattachees a la bonne personne sans migration.
@Model final class MedicalPerson {
    /// Fixe a la creation (jamais en valeur par defaut: deux lignes migrees
    /// partageraient le meme identifiant).
    var stableID: String = ""
    var name: String = ""
    var relation: String = ""
    var createdAt: Date = Date()
    init(name: String, relation: String = "") {
        self.stableID = UUID().uuidString
        self.name = name; self.relation = relation; self.createdAt = .now
    }
}

// MARK: - Calendrier de prise

/// Regle de prise d'un traitement: plusieurs heures a la minute, jours choisis,
/// tous les N jours, ou au besoin.
///
/// Les anciens traitements ("2x/jour" avec heures matin/soir) sont convertis a
/// la lecture: rien n'est reecrit tant que l'utilisateur ne modifie pas la fiche.
enum MedSchedule {

    enum Kind: String, CaseIterable, Identifiable {
        case daily, weekdays, interval, prn
        var id: String { rawValue }
        var label: String {
            switch self {
            case .daily: return "Tous les jours"
            case .weekdays: return "Certains jours"
            case .interval: return "Tous les N jours"
            case .prn: return "Au besoin"
            }
        }
    }

    struct Rule: Equatable {
        var kind: Kind
        /// Minutes depuis minuit, triees, sans doublon.
        var minutes: [Int]
        /// 1 = dimanche ... 7 = samedi (convention de Calendar).
        var weekdays: Set<Int>
        var intervalDays: Int
        /// Debut du traitement: jour 0 de l'intervalle.
        var anchor: Date
        /// Rien n'est attendu avant ce moment (creation ou derniere modification
        /// des horaires): l'ancien horaire n'est pas connu, donc on n'invente
        /// pas de prises manquees avant.
        var effectiveStart: Date
        /// Date de fin, jour INCLUS.
        var end: Date?
        /// Traitement termine a ce moment (bascule "Terminé").
        var stop: Date?
    }

    static let maxTimes = 8

    // MARK: Codage

    static func parseMinutes(_ raw: String) -> [Int] {
        normalize(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    static func encodeMinutes(_ m: [Int]) -> String { normalize(m).map(String.init).joined(separator: ",") }

    static func normalize(_ m: [Int]) -> [Int] {
        Array(Set(m.filter { (0..<1440).contains($0) })).sorted()
    }

    static func parseWeekdays(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...7).contains($0) })
    }

    static func encodeWeekdays(_ s: Set<Int>) -> String { s.filter { (1...7).contains($0) }.sorted().map(String.init).joined(separator: ",") }

    // MARK: Construction

    /// Regle d'un traitement. `kind` vide: ancienne fiche, convertie depuis
    /// la frequence en texte et les heures matin/soir.
    static func rule(kind: String, doseMinutes: String, weekdays: String, intervalDays: Int,
                     frequency: String, hourMorning: Int?, hourEvening: Int?,
                     startDate: Date, scheduleSince: Date?, endDate: Date?, inactiveSince: Date?,
                     calendar cal: Calendar = .current) -> Rule {
        let effective = max(startDate, scheduleSince ?? startDate)
        if let k = Kind(rawValue: kind) {
            return Rule(kind: k, minutes: k == .prn ? [] : parseMinutes(doseMinutes),
                        weekdays: parseWeekdays(weekdays), intervalDays: max(1, intervalDays),
                        anchor: startDate, effectiveStart: effective, end: endDate, stop: inactiveSince)
        }
        if MedicationSchedule.isOnDemand(frequency) {
            return Rule(kind: .prn, minutes: [], weekdays: [], intervalDays: 1, anchor: startDate,
                        effectiveStart: effective, end: endDate, stop: inactiveSince)
        }
        let mins = MedicationSchedule.doses(frequency: frequency, hourMorning: hourMorning, hourEvening: hourEvening)
            .map { $0.hour * 60 + $0.minute }
        if MedicationSchedule.isWeekly(frequency) {
            return Rule(kind: .weekdays, minutes: normalize(mins), weekdays: [cal.component(.weekday, from: startDate)],
                        intervalDays: 1, anchor: startDate, effectiveStart: effective, end: endDate, stop: inactiveSince)
        }
        return Rule(kind: .daily, minutes: normalize(mins), weekdays: [], intervalDays: 1, anchor: startDate,
                    effectiveStart: effective, end: endDate, stop: inactiveSince)
    }

    static func rule(for med: Medication, calendar: Calendar = .current) -> Rule {
        rule(kind: med.scheduleKind, doseMinutes: med.doseMinutes, weekdays: med.weekdays,
             intervalDays: med.intervalDays, frequency: med.frequency, hourMorning: med.hourMorning,
             hourEvening: med.hourEvening, startDate: med.startDate, scheduleSince: med.scheduleSince,
             endDate: med.endDate, inactiveSince: med.active ? nil : med.inactiveSince, calendar: calendar)
    }

    // MARK: Texte

    static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    static func label(minute: Int) -> String {
        switch minute / 60 {
        case ..<11: return "matin"
        case 11..<15: return "midi"
        case 15..<18: return "après-midi"
        default: return "soir"
        }
    }

    static let weekdayShort = [1: "Dim", 2: "Lun", 3: "Mar", 4: "Mer", 5: "Jeu", 6: "Ven", 7: "Sam"]
    /// Ordre d'affichage a la francaise: lundi d'abord.
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    static func summary(_ r: Rule) -> String {
        let times = r.minutes.map(time).joined(separator: ", ")
        switch r.kind {
        case .prn: return "Au besoin"
        case .daily: return "Chaque jour à \(times)"
        case .interval:
            return r.intervalDays <= 1 ? "Chaque jour à \(times)" : "Tous les \(r.intervalDays) jours à \(times)"
        case .weekdays:
            let days = weekdayOrder.filter { r.weekdays.contains($0) }.compactMap { weekdayShort[$0] }.joined(separator: ", ")
            return r.weekdays.count == 7 ? "Chaque jour à \(times)" : "\(days) à \(times)"
        }
    }

    // MARK: Prises prevues

    static func isDoseDay(_ r: Rule, day: Date, calendar cal: Calendar = .current) -> Bool {
        switch r.kind {
        case .prn: return false
        case .daily: return true
        case .weekdays: return r.weekdays.contains(cal.component(.weekday, from: day))
        case .interval:
            guard r.intervalDays > 1 else { return true }
            let n = cal.dateComponents([.day], from: cal.startOfDay(for: r.anchor), to: cal.startOfDay(for: day)).day ?? 0
            return n >= 0 && n % r.intervalDays == 0
        }
    }

    /// Heures de prise prevues dans [from, to], bornes du traitement comprises.
    static func occurrences(_ r: Rule, from: Date, to: Date, calendar cal: Calendar = .current, limit: Int = 20_000) -> [Date] {
        guard r.kind != .prn, !r.minutes.isEmpty else { return [] }
        let lower = max(from, r.effectiveStart)
        var upper = to
        if let stop = r.stop { upper = min(upper, stop) }
        guard lower <= upper else { return [] }
        let endDay = r.end.map { cal.startOfDay(for: $0) }
        var day = cal.startOfDay(for: lower)
        let lastDay = cal.startOfDay(for: upper)
        var out: [Date] = []
        while day <= lastDay, out.count < limit {
            if let endDay, day > endDay { break }
            if isDoseDay(r, day: day, calendar: cal) {
                for m in r.minutes {
                    guard let at = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day) else { continue }
                    if at >= lower && at <= upper { out.append(at) }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    // MARK: Plan de rappels

    struct RepeatSlot: Equatable {
        let weekday: Int?
        let hour: Int
        let minute: Int
    }

    enum ReminderPlan: Equatable {
        case none
        /// Declencheurs qui se repetent: un par heure (et par jour choisi).
        case repeating([RepeatSlot])
        /// Dates precises: traitement borne, futur, ou "tous les N jours".
        case dates([Date])
    }

    /// Ce qu'il faut programmer. `handled`: prises deja enregistrees (prises,
    /// sautees ou reportees), qu'on ne rappelle plus. Un declencheur repetitif
    /// ne sait pas sauter une occurrence: si une prise a VENIR est deja notee,
    /// on passe en dates precises pour ne pas rappeler un comprime deja pris.
    static func reminderPlan(_ r: Rule, active: Bool, now: Date, horizonDays: Int = 14,
                             maxDates: Int = 64, handled: Set<Date> = [],
                             calendar cal: Calendar = .current) -> ReminderPlan {
        guard active, r.kind != .prn, !r.minutes.isEmpty else { return .none }
        if r.kind == .weekdays && r.weekdays.isEmpty { return .none }
        if let end = r.end, cal.startOfDay(for: now) > cal.startOfDay(for: end) { return .none }
        let started = cal.startOfDay(for: r.effectiveStart) <= cal.startOfDay(for: now)
        let everyDay = r.kind == .daily || (r.kind == .interval && r.intervalDays <= 1)
            || (r.kind == .weekdays && r.weekdays.count == 7)
        let futureHandled = handled.contains { $0 > now }
        if r.end == nil && started && !futureHandled && r.effectiveStart <= now {
            if everyDay {
                return .repeating(r.minutes.map { RepeatSlot(weekday: nil, hour: $0 / 60, minute: $0 % 60) })
            }
            if r.kind == .weekdays {
                return .repeating(r.weekdays.sorted().flatMap { wd in
                    r.minutes.map { RepeatSlot(weekday: wd, hour: $0 / 60, minute: $0 % 60) }
                })
            }
        }
        let horizonEnd = cal.date(byAdding: .day, value: horizonDays, to: now) ?? now
        let dates = occurrences(r, from: now, to: horizonEnd, calendar: cal)
            .filter { $0 > now && !handled.contains($0) }
        let picked = Array(dates.prefix(maxDates))
        return picked.isEmpty ? .none : .dates(picked)
    }
}

// MARK: - Journal des prises

enum DoseLog {

    /// Apres ce delai sans rien noter, une prise prevue est "manquée".
    static let graceMinutes = 120

    enum Status: Equatable {
        case upcoming, due, taken, skipped, missed
        case snoozed(until: Date)

        var label: String {
            switch self {
            case .upcoming: return "À venir"
            case .due: return "À prendre"
            case .taken: return "Prise"
            case .skipped: return "Sautée"
            case .missed: return "Manquée"
            case .snoozed(let u): return "Reportée à \(u.formatted(date: .omitted, time: .shortened))"
            }
        }
        var isLogged: Bool {
            switch self { case .taken, .skipped, .snoozed: return true; default: return false }
        }
    }

    /// Copie neutre d'un DoseEvent: la logique reste testable sans base.
    struct Event: Equatable {
        var scheduledAt: Date?
        var loggedAt: Date
        var status: String
        var snoozedUntil: Date?
        var quantity: Double = 1
    }

    struct Slot: Equatable {
        let scheduledAt: Date
        let status: Status
    }

    /// Cle a la minute: une heure prevue recalculee doit retrouver sa ligne.
    static func key(_ d: Date) -> Int { Int((d.timeIntervalSince1970 / 60).rounded()) }

    /// Statut d'une prise prevue. La DERNIERE ligne gagne: c'est ce qui rend
    /// "annuler" possible (on retire la ligne, la precedente reprend la main).
    static func status(at: Date, events: [Event], now: Date) -> Status {
        let grace = TimeInterval(graceMinutes * 60)
        guard let last = events.max(by: { $0.loggedAt < $1.loggedAt }) else {
            if now < at { return .upcoming }
            return now < at.addingTimeInterval(grace) ? .due : .missed
        }
        switch last.status {
        case "taken": return .taken
        case "skipped": return .skipped
        default:
            let until = last.snoozedUntil ?? last.loggedAt
            return now < until.addingTimeInterval(grace) ? .snoozed(until: until) : .missed
        }
    }

    static func slots(occurrences: [Date], events: [Event], now: Date) -> [Slot] {
        let byKey = Dictionary(grouping: events.filter { $0.scheduledAt != nil }, by: { key($0.scheduledAt!) })
        return occurrences.map { Slot(scheduledAt: $0, status: status(at: $0, events: byKey[key($0)] ?? [], now: now)) }
    }

    /// Lignes qui ne correspondent a aucune prise prevue: prises au besoin, ou
    /// prises notees sous un ancien horaire. Elles restent dans l'historique.
    static func orphans(occurrences: [Date], events: [Event]) -> [Event] {
        let keys = Set(occurrences.map(key))
        return events.filter { e in e.scheduledAt.map { !keys.contains(key($0)) } ?? true }
    }

    struct Adherence: Equatable {
        var taken = 0, skipped = 0, missed = 0
        /// nil: rien d'attendu sur la periode (pas 0 %, qui accuserait a tort).
        var rate: Double? {
            let total = taken + skipped + missed
            return total == 0 ? nil : Double(taken) / Double(total)
        }
    }

    /// Les prises au besoin ne comptent pas: ne pas en prendre n'est pas un oubli.
    static func adherence(slots: [Slot], orphans: [Event]) -> Adherence {
        var a = Adherence()
        for s in slots {
            switch s.status {
            case .taken: a.taken += 1
            case .skipped: a.skipped += 1
            case .missed: a.missed += 1
            default: break
            }
        }
        let scheduled = orphans.filter { $0.scheduledAt != nil }
        for (_, group) in Dictionary(grouping: scheduled, by: { key($0.scheduledAt!) }) {
            guard let last = group.max(by: { $0.loggedAt < $1.loggedAt }) else { continue }
            if last.status == "taken" { a.taken += 1 } else if last.status == "skipped" { a.skipped += 1 }
        }
        return a
    }

    // MARK: Stock

    /// Stock restant: le compte saisi, moins les prises notees depuis. Une
    /// prise annulee (ligne retiree) revient donc dans la boite toute seule.
    static func stock(initial: Double, setAt: Date?, events: [Event]) -> Double {
        let used = events.filter { e in e.status == "taken" && (setAt.map { e.loggedAt >= $0 } ?? true) }
            .reduce(0) { $0 + $1.quantity }
        return initial - used
    }

    /// Moment ou le stock passera sous le seuil, d'apres les prochaines prises.
    /// nil: deja sous le seuil (l'ecran l'affiche), ou pas assez de prises prevues.
    static func refillDate(stock: Double, threshold: Double, perDose: Double, upcoming: [Date]) -> Date? {
        guard stock > threshold, perDose > 0 else { return nil }
        var left = stock
        for at in upcoming.sorted() {
            left -= perDose
            if left <= threshold { return at }
        }
        return nil
    }

    /// Jours restants au rythme prevu. nil si le rythme est inconnu (au besoin).
    static func daysLeft(stock: Double, perDose: Double, dosesPerDay: Double) -> Int? {
        guard dosesPerDay > 0, perDose > 0 else { return nil }
        return max(0, Int((stock / (perDose * dosesPerDay)).rounded(.down)))
    }

    static func dosesPerDay(_ r: MedSchedule.Rule) -> Double {
        let n = Double(r.minutes.count)
        switch r.kind {
        case .prn: return 0
        case .daily: return n
        case .weekdays: return n * Double(r.weekdays.count) / 7
        case .interval: return n / Double(max(1, r.intervalDays))
        }
    }
}

// MARK: - Export CSV

enum MedicalCSV {

    struct Row {
        var person: String
        var medication: String
        var dosage: String
        var scheduled: Date?
        var status: String
        var logged: Date?
    }

    /// Point-virgule: c'est le separateur qu'Excel attend en francais.
    static let separator = ";"

    static func escape(_ s: String) -> String {
        if s.contains(separator) || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func stamp(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    static func adherence(_ rows: [Row]) -> String {
        let header = ["Personne", "Médicament", "Dosage", "Prévu", "Statut", "Enregistré"]
        let lines = rows.map { r in
            [r.person, r.medication, r.dosage, stamp(r.scheduled), r.status, stamp(r.logged)].map(escape).joined(separator: separator)
        }
        return ([header.joined(separator: separator)] + lines).joined(separator: "\n") + "\n"
    }
}

// MARK: - Mesures: unites, reperes, periodes, sources

enum VitalUnits {
    /// 1 mmol/L de glucose = 0,18016 g/L (masse molaire du glucose 180,16 g/mol).
    static let glucoseGPerMmol = 0.18016
    static let lbPerKg = 2.20462262

    static func canonicalUnit(_ type: String) -> String {
        switch type {
        case "poids": return "kg"
        case "tension": return "mmHg"
        case "glycémie": return "g/L"
        case "fréquence cardiaque": return "bpm"
        case "température": return "°C"
        case "SpO2": return "%"
        case "sommeil": return "h"
        default: return ""
        }
    }

    static func displayUnit(_ type: String, glucose: String, weight: String) -> String {
        if type == "glycémie" && glucose == "mmol/L" { return "mmol/L" }
        if type == "poids" && weight == "lb" { return "lb" }
        return canonicalUnit(type)
    }

    /// Valeur stockee (unite canonique) vers l'unite choisie a l'ecran.
    static func toDisplay(_ v: Double, type: String, glucose: String, weight: String) -> Double {
        if type == "glycémie" && glucose == "mmol/L" { return v / glucoseGPerMmol }
        if type == "poids" && weight == "lb" { return v * lbPerKg }
        return v
    }

    /// Saisie a l'ecran vers l'unite canonique. On stocke toujours la meme
    /// unite: changer de preference ne touche aucune mesure.
    static func toCanonical(_ v: Double, type: String, glucose: String, weight: String) -> Double {
        if type == "glycémie" && glucose == "mmol/L" { return v * glucoseGPerMmol }
        if type == "poids" && weight == "lb" { return v / lbPerKg }
        return v
    }

    static func decimals(_ type: String, displayUnit: String) -> Int {
        switch type {
        case "tension", "fréquence cardiaque", "SpO2": return 0
        case "glycémie": return displayUnit == "mmol/L" ? 1 : 2
        default: return 1
        }
    }

    static func format(_ v: Double, type: String, displayUnit: String) -> String {
        String(format: "%.\(decimals(type, displayUnit: displayUnit))f", v)
    }
}

/// Reperes GENERAUX, pas un diagnostic. Chaque repere nomme sa source.
enum VitalReference {
    struct Range: Equatable {
        /// En unite canonique.
        let low: Double?
        let high: Double?
        /// Seuil diastolique (tension seulement).
        let high2: Double?
        let text: String
        let source: String
    }

    enum Position: Equatable { case below, within, above }

    static func range(_ type: String) -> Range? {
        switch type {
        case "tension":
            return Range(low: nil, high: 135, high2: 85,
                         text: "En automesure, hypertension à partir de 135/85 mmHg. Au cabinet, le seuil est 140/90.",
                         source: "HAS, prise en charge de l'hypertension artérielle de l'adulte (2016)")
        case "glycémie":
            return Range(low: 0.70, high: 1.10, high2: nil,
                         text: "À jeun : 0,70 à 1,10 g/L. Diabète à partir de 1,26 g/L à jeun, contrôlé deux fois.",
                         source: "OMS, définition du diabète (2006)")
        case "fréquence cardiaque":
            return Range(low: 60, high: 100, high2: nil,
                         text: "Au repos, chez l'adulte : 60 à 100 battements par minute.",
                         source: "American Heart Association")
        case "température":
            return Range(low: nil, high: 38, high2: nil,
                         text: "Fièvre à partir de 38 °C.",
                         source: "Assurance Maladie (ameli.fr)")
        case "SpO2":
            return Range(low: 95, high: 100, high2: nil,
                         text: "Saturation normale entre 95 et 100 %.",
                         source: "Assurance Maladie (ameli.fr)")
        case "sommeil":
            return Range(low: 7, high: 9, high2: nil,
                         text: "Adulte : 7 à 9 heures par nuit.",
                         source: "National Sleep Foundation (2015)")
        default:
            return nil
        }
    }

    static func position(value: Double, value2: Double?, type: String) -> Position? {
        guard let r = range(type) else { return nil }
        if let h = r.high, value > h { return .above }
        if let h2 = r.high2, let v2 = value2, v2 > h2 { return .above }
        if let l = r.low, value < l { return .below }
        return .within
    }
}

enum VitalPeriod: String, CaseIterable, Identifiable {
    case week = "7 j", month = "30 j", year = "1 an", all = "Tout"
    var id: String { rawValue }

    func start(now: Date, calendar cal: Calendar = .current) -> Date? {
        let today = cal.startOfDay(for: now)
        switch self {
        case .week: return cal.date(byAdding: .day, value: -6, to: today)
        case .month: return cal.date(byAdding: .day, value: -29, to: today)
        case .year: return cal.date(byAdding: .year, value: -1, to: today)
        case .all: return nil
        }
    }

    func contains(_ d: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard let s = start(now: now, calendar: calendar) else { return true }
        return d >= s
    }
}

enum VitalSource {
    static let health = "Apple Santé"

    /// Les mesures importees avant le champ `source` portaient "Apple Santé"
    /// dans leurs notes (HealthAutoSync): on les reconnait encore.
    static func label(source: String, notes: String) -> String {
        if !source.isEmpty { return source }
        return notes == health ? health : "Saisie manuelle"
    }

    /// Doublon: meme type et meme instant a la minute (ou meme jour pour le
    /// sommeil, qui n'a qu'une valeur par nuit).
    static func isDuplicate(type: String, date: Date, existing: [(type: String, date: Date)],
                            sameDay: Bool, calendar cal: Calendar = .current) -> Bool {
        existing.contains { e in
            guard e.type == type else { return false }
            return sameDay ? cal.isDate(e.date, inSameDayAs: date) : abs(e.date.timeIntervalSince(date)) < 60
        }
    }
}

// MARK: - Rendez-vous

enum AppointmentStatus: String, CaseIterable, Identifiable {
    case planned, confirmed, done, cancelled
    var id: String { rawValue }

    var label: String {
        switch self {
        case .planned: return "Prévu"
        case .confirmed: return "Confirmé par le cabinet"
        case .done: return "Passé"
        case .cancelled: return "Annulé"
        }
    }

    /// Statut affiche. "Confirmé" est ce que l'utilisateur DECLARE: LifeOS ne
    /// reserve rien et ne recoit aucune confirmation. Un RDV passe devient
    /// "Passé" tout seul; un RDV annule le reste.
    static func effective(stored: String, date: Date, now: Date) -> AppointmentStatus {
        let s = AppointmentStatus(rawValue: stored) ?? .planned
        if s == .cancelled { return .cancelled }
        return date < now ? .done : (s == .done ? .planned : s)
    }
}

enum AppointmentHistory {
    struct Entry: Equatable {
        var date: Date
        var doctor: String
        var specialty: String
        var notes: String
        var cancelled: Bool
        var files: Int
    }

    struct Group: Equatable {
        var key: String
        var title: String
        var subtitle: String
        var visits: [Entry]
    }

    static func practitionerKey(doctor: String, specialty: String) -> String {
        let d = doctor.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = d.isEmpty ? "spe:\(specialty)" : "dr:\(d)"
        return base.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Consultations passees (non annulees), regroupees par praticien. Sans
    /// nom de medecin, on regroupe par specialite plutot que de tout melanger.
    static func byPractitioner(_ entries: [Entry], now: Date) -> [Group] {
        let past = entries.filter { !$0.cancelled && $0.date < now }
        let grouped = Dictionary(grouping: past) { practitionerKey(doctor: $0.doctor, specialty: $0.specialty) }
        return grouped.map { key, visits in
            let sorted = visits.sorted { $0.date > $1.date }
            let first = sorted[0]
            let d = first.doctor.trimmingCharacters(in: .whitespacesAndNewlines)
            let specialties = Array(Set(sorted.map(\.specialty))).sorted().joined(separator: ", ")
            return Group(key: key, title: d.isEmpty ? first.specialty : d,
                         subtitle: d.isEmpty ? "Praticien non précisé" : specialties, visits: sorted)
        }
        .sorted { ($0.visits.first?.date ?? .distantPast) > ($1.visits.first?.date ?? .distantPast) }
    }
}

// MARK: - Pieces jointes (ordonnances, comptes rendus, certificats)

/// Les photos sont stockees comme les autres images de l'app (ImageStore), la
/// liste des fichiers dans la fiche. Le brouillon garde ce qui a ete ajoute ou
/// retire pendant l'edition: "Annuler" efface les nouvelles photos, "Enregistrer"
/// efface celles qu'on a retirees. Sans ca, chaque annulation laissait un
/// fichier orphelin sur le disque.
enum MedicalFiles {
    static func list(_ raw: String) -> [String] {
        raw.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func encode(_ files: [String]) -> String { files.filter { !$0.isEmpty }.joined(separator: "\n") }

    struct Draft: Equatable {
        let original: [String]
        var current: [String]

        init(raw: String) { original = MedicalFiles.list(raw); current = original }

        mutating func add(_ name: String) { if !current.contains(name) { current.append(name) } }
        mutating func remove(_ name: String) { current.removeAll { $0 == name } }

        /// A effacer du disque apres "Enregistrer".
        var deletedOnSave: [String] { original.filter { !current.contains($0) } }
        /// A effacer du disque apres "Annuler".
        var deletedOnCancel: [String] { current.filter { !original.contains($0) } }
        var raw: String { MedicalFiles.encode(current) }
    }
}

// MARK: - Personnes

enum MedicalPeople {
    /// Filtre "tout le monde". Un filtre vide veut dire "moi".
    static let everyone = "*"

    static func matches(filter: String, personID: String) -> Bool {
        filter == everyone || filter == personID
    }

    static func name(for id: String, in people: [(id: String, name: String)]) -> String {
        guard !id.isEmpty else { return "Moi" }
        return people.first { $0.id == id }?.name ?? "Proche supprimé"
    }
}
