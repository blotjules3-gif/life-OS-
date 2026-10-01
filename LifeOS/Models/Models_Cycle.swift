import Foundation
import SwiftData

// Domaine du cycle (Floé, Klue, Floé Stats): reglages, catalogue de
// symptomes, intensites, brouillon d'un jour, rapport. La logique de calcul
// (regles, previsions, associations) vit dans CycleStats.swift.

// MARK: - Cles de reglages

/// Cles UserDefaults propres au cycle. `cycleStartDate` et `cycleLengthDays`
/// restent dans AppStorageKeys (partagees avec l'onboarding).
enum CycleKeys {
    /// Date de debut DECLAREE par l'utilisatrice (reglages, onboarding).
    /// Separee du debut calcule: avant, le flux note ecrivait par dessus et
    /// supprimer des regles ne ramenait jamais le debut en arriere.
    static let manualStart = "cycleManualStartDate"
    /// Dernier debut ecrit par CycleContext dans `cycleStartDate`. S'il
    /// differe de la valeur lue, quelqu'un d'autre (onboarding) l'a change:
    /// on l'adopte comme declaration.
    static let startWritten = "cycleStartWritten"
    /// Duree utilisee pour les previsions (historique ou reglage), lue par le
    /// coach et LifeBrain pour faire le meme calcul que le suivi.
    static let predictionLength = "cyclePredictionLength"
    /// Duree des regles reglee, utilisee tant que l'historique ne suffit pas.
    static let periodLength = "cyclePeriodLengthDays"
    static let mode = "cycleMode"
    /// Rappels coupes, separes par des virgules (vide = tous actifs).
    static let remindersOff = "cycleRemindersOff"
    /// Tags personnels (JSON, tableau de chaines).
    static let customTags = "cycleCustomTags"
    /// Afficher toutes les categories, meme celles que le mode masque.
    static let showAllCategories = "cycleShowAllCategories"
}

// MARK: - Modes

/// Objectif choisi. Il change les previsions MONTREES, jamais le calcul.
enum CycleMode: String, CaseIterable, Identifiable {
    case tracking      // suivi des regles
    case conceiving    // essai bebe
    case contraception // contraception (information seulement)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tracking:      return "Suivi des règles"
        case .conceiving:    return "Essai bébé"
        case .contraception: return "Contraception"
        }
    }

    var explanation: String {
        switch self {
        case .tracking:
            return "Prochaines règles et phase du jour."
        case .conceiving:
            return "Ajoute la fenêtre fertile estimée d'après tes cycles. C'est une estimation, pas une ovulation confirmée."
        case .contraception:
            return "Prochaines règles seulement. Ces prévisions ne sont pas une méthode de contraception."
        }
    }

    /// La fenetre fertile n'est montree qu'en essai bebe: en mode
    /// contraception elle serait lue comme des "jours sans risque".
    var showsFertileWindow: Bool { self == .conceiving }
    /// Phase d'ovulation affichee comme phase du jour (energie, sport).
    var showsOvulationPhase: Bool { self != .contraception }

    var categories: [CycleSymptomCategory] {
        let base: [CycleSymptomCategory] = [.pain, .energy, .sleep, .skin, .digestion]
        switch self {
        case .tracking:      return base
        case .conceiving:    return base + [.discharge, .libido]
        case .contraception: return base + [.contraception]
        }
    }

    static func stored(_ d: UserDefaults = .standard) -> CycleMode {
        CycleMode(rawValue: d.string(forKey: CycleKeys.mode) ?? "") ?? .tracking
    }
}

// MARK: - Rappels

enum CycleReminderKind: String, CaseIterable, Identifiable {
    case period, pms, ovulation
    var id: String { rawValue }

    var notificationID: String {
        switch self {
        case .period:    return "lifeos.cycle.period_warning"
        case .pms:       return "lifeos.cycle.pms"
        case .ovulation: return "lifeos.cycle.ovulation"
        }
    }

    func label(mode: CycleMode) -> String {
        switch self {
        case .period:    return "Règles dans 3 jours"
        case .pms:       return "Une semaine avant les règles"
        case .ovulation: return mode == .conceiving ? "Début de la fenêtre fertile estimée" : "Phase d'ovulation estimée"
        }
    }

    /// Le rappel d'ovulation n'existe pas en mode contraception.
    func isAvailable(in mode: CycleMode) -> Bool { self != .ovulation || mode != .contraception }

    static func disabled(_ d: UserDefaults = .standard) -> Set<CycleReminderKind> {
        Set((d.string(forKey: CycleKeys.remindersOff) ?? "")
            .split(separator: ",").compactMap { CycleReminderKind(rawValue: String($0)) })
    }

    static func store(disabled: Set<CycleReminderKind>, _ d: UserDefaults = .standard) {
        d.set(disabled.map(\.rawValue).sorted().joined(separator: ","), forKey: CycleKeys.remindersOff)
    }
}

// MARK: - Catalogue des symptomes

/// Categories de saisie. Les libelles stockes sont stables et uniques entre
/// categories: ils servent d'identifiants dans `CycleEntry.symptoms`. Les
/// huit anciens symptomes gardent leur libelle exact, donc les entrees deja
/// enregistrees se rangent seules dans la bonne categorie.
enum CycleSymptomCategory: String, CaseIterable, Identifiable {
    case pain, discharge, sleep, energy, skin, digestion, libido, contraception, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .pain:          return "Douleur"
        case .discharge:     return "Pertes"
        case .sleep:         return "Sommeil"
        case .energy:        return "Énergie"
        case .skin:          return "Peau"
        case .digestion:     return "Digestion"
        case .libido:        return "Libido"
        case .contraception: return "Contraception"
        case .custom:        return "Mes tags"
        }
    }

    var options: [String] {
        switch self {
        case .pain:          return ["Crampes", "Maux de tête", "Dos douloureux", "Seins sensibles", "Douleur pelvienne"]
        case .discharge:     return ["Pertes sèches", "Pertes collantes", "Pertes crémeuses", "Pertes blanc d'œuf", "Pertes inhabituelles"]
        case .sleep:         return ["Bien dormi", "Sommeil agité", "Insomnie"]
        case .energy:        return ["Épuisement", "Fatigue", "En forme", "Pleine d'énergie"]
        case .skin:          return ["Acné", "Peau grasse", "Peau sèche"]
        case .digestion:     return ["Ballonnements", "Nausées", "Constipation", "Diarrhée"]
        case .libido:        return ["Libido basse", "Libido normale", "Libido haute"]
        case .contraception: return ["Pilule prise", "Pilule oubliée", "Saignement entre les règles"]
        case .custom:        return []
        }
    }

    /// Une seule reponse possible (on ne dort pas "bien" et "mal" le meme jour).
    var isExclusive: Bool { [.discharge, .sleep, .energy, .libido].contains(self) }
    /// L'intensite n'a de sens que pour ce qui se ressent plus ou moins fort.
    var hasIntensity: Bool { [.pain, .skin, .digestion, .custom].contains(self) }

    /// Categorie d'un libelle stocke (tag personnel si inconnu).
    static func of(_ symptom: String) -> CycleSymptomCategory {
        allCases.first { $0.options.contains(symptom) } ?? .custom
    }
}

enum CycleIntensity {
    static let labels = ["", "Léger", "Moyen", "Fort"]
    static func label(_ level: Int) -> String { (1...3).contains(level) ? labels[level] : "" }
}

enum CycleCatalog {
    static let flows = ["Aucun", "Léger", "Moyen", "Abondant"]
    static let moods = ["", "Triste", "Irritable", "Neutre", "Bien", "Super"]
    static func moodLabel(_ m: Int) -> String { (1...5).contains(m) ? moods[m] : "" }
    static func flowLabel(_ f: Int) -> String { (0...3).contains(f) ? flows[f] : "" }
}

// MARK: - Intensites stockees

/// `CycleEntry.intensityCodes` stocke "Crampes=2". Un tableau de chaines,
/// comme `symptoms`, plutot qu'un dictionnaire: c'est le type deja prouve
/// par la migration legere de SwiftData dans ce modele.
enum CycleIntensityCodec {
    static func decode(_ codes: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        for c in codes {
            guard let eq = c.lastIndex(of: "="), let v = Int(c[c.index(after: eq)...]), (1...3).contains(v) else { continue }
            out[String(c[..<eq])] = v
        }
        return out
    }

    static func encode(_ levels: [String: Int], keeping symptoms: Set<String>) -> [String] {
        levels.filter { symptoms.contains($0.key) && (1...3).contains($0.value) }
            .map { "\($0.key)=\($0.value)" }.sorted()
    }
}

// MARK: - Tags personnels

enum CycleTags {
    static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    static func encode(_ tags: [String]) -> String {
        (try? String(data: JSONEncoder().encode(tags), encoding: .utf8) ?? "[]") ?? "[]"
    }

    enum AddError: Error, Equatable { case empty, tooLong, duplicate }

    /// Ajoute un tag nettoye. Refuse le doublon, y compris avec un libelle du
    /// catalogue (deux "Crampes" se compteraient a part dans les stats).
    static func adding(_ raw: String, to tags: [String]) -> Result<[String], AddError> {
        let name = raw.replacingOccurrences(of: "=", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.empty) }
        guard name.count <= 40 else { return .failure(.tooLong) }
        let all = tags + CycleSymptomCategory.allCases.flatMap(\.options)
        if all.contains(where: { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return .failure(.duplicate)
        }
        return .success(tags + [name])
    }
}

// MARK: - Copie d'une entree

/// Copie en valeur d'une entree: les calculs purs la prennent, pas le
/// modele SwiftData, pour etre testables sans base.
struct CycleEntrySnapshot: Equatable {
    var date: Date
    var flow: Int
    var symptoms: [String]
    var levels: [String: Int]
    var mood: Int
    var note: String
    var isStart: Bool
    var isEnd: Bool

    init(date: Date, flow: Int = 0, symptoms: [String] = [], levels: [String: Int] = [:],
         mood: Int = 0, note: String = "", isStart: Bool = false, isEnd: Bool = false) {
        self.date = date; self.flow = flow; self.symptoms = symptoms; self.levels = levels
        self.mood = mood; self.note = note; self.isStart = isStart; self.isEnd = isEnd
    }

    var mark: CycleDayMark { CycleDayMark(date: date, flow: flow, isStart: isStart, isEnd: isEnd) }
}

extension CycleEntry {
    var snapshot: CycleEntrySnapshot {
        CycleEntrySnapshot(date: date, flow: flow, symptoms: symptoms,
                           levels: CycleIntensityCodec.decode(intensityCodes),
                           mood: mood, note: note, isStart: isPeriodStart, isEnd: isPeriodEnd)
    }
}

// MARK: - Brouillon d'un jour

struct CycleDayDraft: Equatable {
    var flow = 0
    var symptoms: Set<String> = []
    var levels: [String: Int] = [:]
    var mood = 0
    var note = ""
    var isStart = false
    var isEnd = false

    /// Rien de note: enregistrer ce jour reviendrait a garder une ligne vide.
    var isEmpty: Bool {
        flow == 0 && symptoms.isEmpty && mood == 0
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStart && !isEnd
    }

    /// Fusionne plusieurs entrees du meme jour (l'ancien ecran pouvait en
    /// creer deux): flux le plus fort, union des symptomes, notes jointes.
    static func merged(_ entries: [CycleEntrySnapshot]) -> CycleDayDraft {
        var d = CycleDayDraft()
        for e in entries.sorted(by: { $0.date < $1.date }) {
            d.flow = max(d.flow, e.flow)
            d.symptoms.formUnion(e.symptoms)
            d.levels.merge(e.levels) { max($0, $1) }
            if e.mood > 0 { d.mood = e.mood }
            let n = e.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty && !d.note.contains(n) { d.note = d.note.isEmpty ? n : d.note + "\n" + n }
            d.isStart = d.isStart || e.isStart
            d.isEnd = d.isEnd || e.isEnd
        }
        return d
    }

    /// Coche ou decoche un symptome, en respectant les categories a reponse unique.
    mutating func toggle(_ symptom: String) {
        if symptoms.contains(symptom) {
            symptoms.remove(symptom)
            levels[symptom] = nil
            return
        }
        let cat = CycleSymptomCategory.of(symptom)
        if cat.isExclusive {
            for other in cat.options where other != symptom { symptoms.remove(other); levels[other] = nil }
        }
        symptoms.insert(symptom)
    }
}

// MARK: - Lecture et ecriture d'un jour

@MainActor
enum CycleEntryStore {

    static func dayBounds(_ day: Date, calendar: Calendar = .current) -> (Date, Date) {
        let s = calendar.startOfDay(for: day)
        return (s, calendar.date(byAdding: .day, value: 1, to: s) ?? s.addingTimeInterval(86_400))
    }

    static func entries(on day: Date, in ctx: ModelContext, calendar: Calendar = .current) throws -> [CycleEntry] {
        let (from, to) = dayBounds(day, calendar: calendar)
        let desc = FetchDescriptor<CycleEntry>(predicate: #Predicate { $0.date >= from && $0.date < to },
                                               sortBy: [SortDescriptor(\.date)])
        return try ctx.fetch(desc)
    }

    static func draft(for day: Date, in ctx: ModelContext, calendar: Calendar = .current) throws -> CycleDayDraft {
        CycleDayDraft.merged(try entries(on: day, in: ctx, calendar: calendar).map(\.snapshot))
    }

    /// Enregistre le jour: une seule entree par jour (les doublons sont
    /// fusionnes puis supprimes), et un jour vide est supprime au lieu d'etre
    /// garde comme ligne vide qui fausserait les compteurs.
    @discardableResult
    static func save(_ draft: CycleDayDraft, for day: Date, in ctx: ModelContext,
                     calendar: Calendar = .current) throws -> CycleEntry? {
        let existing = try entries(on: day, in: ctx, calendar: calendar)
        if draft.isEmpty {
            existing.forEach { ctx.delete($0) }
            try ctx.save()
            return nil
        }
        let entry: CycleEntry
        if let first = existing.first {
            entry = first
            existing.dropFirst().forEach { ctx.delete($0) }
        } else {
            // Midi du jour choisi: un jour passe saisi a minuit changerait de
            // date au moindre decalage de fuseau.
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            entry = CycleEntry(date: noon, flow: 0)
            ctx.insert(entry)
        }
        entry.flow = draft.flow
        entry.symptoms = draft.symptoms.sorted()
        entry.intensityCodes = CycleIntensityCodec.encode(draft.levels, keeping: draft.symptoms)
        entry.mood = draft.mood
        entry.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.isPeriodStart = draft.isStart
        entry.isPeriodEnd = draft.isEnd
        try ctx.save()
        return entry
    }

    static func delete(day: Date, in ctx: ModelContext, calendar: Calendar = .current) throws {
        try entries(on: day, in: ctx, calendar: calendar).forEach { ctx.delete($0) }
        try ctx.save()
    }
}

// MARK: - Rapport et export

enum CycleReport {

    static func csvField(_ s: String) -> String {
        guard s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "," }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Une ligne par jour note, intensites comprises. Point-virgule: Excel en
    /// francais ouvre ce separateur directement.
    static func csv(_ entries: [CycleEntrySnapshot], calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        var lines = ["date;flux;debut_regles;fin_regles;symptomes;humeur;note"]
        for e in entries.sorted(by: { $0.date < $1.date }) {
            let symptoms = e.symptoms.sorted().map { s -> String in
                let l = CycleIntensity.label(e.levels[s] ?? 0)
                return l.isEmpty ? s : "\(s) (\(l.lowercased()))"
            }.joined(separator: ", ")
            lines.append([f.string(from: e.date), CycleCatalog.flowLabel(e.flow),
                          e.isStart ? "oui" : "", e.isEnd ? "oui" : "",
                          csvField(symptoms), CycleCatalog.moodLabel(e.mood), csvField(e.note)]
                .joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Rapport lisible: les memes chiffres que les ecrans (meme fonction).
    static func text(analysis: CycleAnalysis, rangeLabel: String, entries: [CycleEntrySnapshot],
                     now: Date = .now, calendar: Calendar = .current) -> String {
        let df = DateFormatter()
        df.calendar = calendar; df.timeZone = calendar.timeZone
        df.locale = Locale(identifier: "fr_FR"); df.dateStyle = .medium
        var out: [String] = ["Rapport de cycle (\(rangeLabel))", "Créé le \(df.string(from: now))", ""]
        let p = analysis.prediction
        switch p.basis {
        case .history(let n):
            out.append("Durée utilisée pour les prévisions : \(p.lengthDays) jours (moyenne de \(n) cycles notés, de \(p.shortestDays) à \(p.longestDays) jours)")
        case .setting:
            out.append("Durée utilisée pour les prévisions : \(p.lengthDays) jours (durée réglée, moins de 2 cycles notés)")
        }
        if let next = p.nextStart, let a = p.earliestStart, let b = p.latestStart {
            out.append(a == b ? "Prochaines règles estimées : \(df.string(from: next))"
                              : "Prochaines règles estimées : entre le \(df.string(from: a)) et le \(df.string(from: b))")
        }
        out.append("Durée des règles : \(p.periodLengthDays) jours" + (p.periodLengthFromHistory ? " (moyenne notée)" : " (durée réglée)"))
        if let s = analysis.rangeSummary {
            out.append("Sur la période : \(s.cycleCount) cycle\(s.cycleCount > 1 ? "s" : ""), moyenne \(Int(s.averageDays.rounded())) jours, de \(s.shortestDays) à \(s.longestDays) jours, \(s.isRegular ? "régulier" : "irrégulier")")
        } else {
            out.append("Sur la période : pas assez de cycles complets pour une moyenne.")
        }
        if !analysis.rangeCycles.isEmpty {
            out.append("")
            out.append("Cycles :")
            for c in analysis.rangeCycles {
                out.append("· \(df.string(from: c.start)) : \(c.days) jours" + (c.periodDays.map { ", règles \($0) j" } ?? ""))
            }
        }
        let counts = CycleInsights.symptomCounts(entries)
        if !counts.isEmpty {
            out.append("")
            out.append("Symptômes notés (jours) :")
            for (s, n) in counts.prefix(10) { out.append("· \(s) : \(n)") }
        }
        out.append("")
        out.append("Prévisions estimées d'après les cycles notés. Ce rapport n'est pas un avis médical.")
        return out.joined(separator: "\n")
    }
}
