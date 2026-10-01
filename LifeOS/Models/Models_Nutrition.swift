import Foundation
import SwiftData

// MARK: - Modeles et regles du lot Nutrition (Zerø, Fridgy, Bringo, WaterMind, SuppSafe, Figue)
//
// Les regles sont des fonctions statiques sans effet de bord pour etre testees
// (LifeOSTests/Lot6NutritionTests.swift). Les vues de NutritionModule.swift les appellent.

/// Une prise de complement notee : prise ou sautee.
///
/// Le nom est COPIE au moment de la prise : renommer ou supprimer le complement
/// ne doit pas reecrire l'historique. La cle relie quand meme au complement
/// (`Supplement.stableID`) tant qu'il existe.
@Model final class SupplementDose {
    var supplementKey: String = ""
    var name: String = ""
    /// Debut du jour de la prise prevue.
    var day: Date = Date()
    var hour: Int = 0
    var minute: Int = 0
    /// "taken" ou "skipped".
    var state: String = "taken"
    var loggedAt: Date = Date()
    init(supplementKey: String, name: String, day: Date, hour: Int, minute: Int, state: String, loggedAt: Date = .now) {
        self.supplementKey = supplementKey; self.name = name
        self.day = Calendar.current.startOfDay(for: day)
        self.hour = hour; self.minute = minute; self.state = state; self.loggedAt = loggedAt
    }
}

// MARK: - Zerø : regles des jeunes

enum FastingRules {
    struct Span: Equatable { let start: Date; let end: Date? }

    /// Duree maximale acceptee pour un jeune saisi a la main : au dela, c'est
    /// presque toujours une erreur de date (mauvais jour choisi).
    static let maxHours: Double = 7 * 24

    /// Presets de protocole ; tout autre nombre d'heures est une duree perso.
    static let presets = [16, 18, 20, 23]
    static let customRange = 12...72

    /// Message d'erreur si le jeune ne peut pas etre enregistre, nil sinon.
    /// `others` = les AUTRES jeunes ; un jeune en cours compte jusqu'a maintenant.
    static func validate(start: Date, end: Date?, others: [Span], now: Date = .now) -> String? {
        if start > now { return "Le début ne peut pas être dans le futur." }
        if let end {
            if end <= start { return "La fin doit être après le début." }
            if end > now.addingTimeInterval(60) { return "La fin ne peut pas être dans le futur." }
            if end.timeIntervalSince(start) / 3600 > maxHours { return "Un jeûne de plus de 7 jours : vérifie les dates." }
        }
        let myEnd = end ?? now
        for o in others {
            if end == nil && o.end == nil { return "Un jeûne est déjà en cours." }
            let oEnd = o.end ?? now
            if start < oEnd && o.start < myEnd { return "Ce jeûne chevauche un autre jeûne de l'historique." }
        }
        return nil
    }

    /// Jours consecutifs (jusqu'a aujourd'hui, ou hier si aujourd'hui n'a rien encore)
    /// ou au moins un jeune a atteint son objectif. Le jour compte a la FIN du jeune.
    static func streak(_ done: [(end: Date, reached: Bool)], now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(done.filter(\.reached).map { calendar.startOfDay(for: $0.end) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: day), days.contains(y) else { return 0 }
            day = y
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    static func label(forTarget h: Int) -> String {
        switch h { case 16: return "16:8"; case 18: return "18:6"; case 20: return "20:4"; case 23: return "OMAD"; default: return "\(h) h" }
    }
}

// MARK: - Fridgy : tri, filtre, alertes de peremption

enum PantryOps {
    struct Row: Equatable { let name: String; let category: String; let location: String; let expiry: Date? }
    enum Sort: String, CaseIterable { case name = "Nom", expiry = "Péremption" }

    static let locations = ["Frigo", "Placard", "Congélateur"]
    static let categories = ["Légume", "Fruit", "Protéine", "Laitier", "Féculent", "Épicerie", "Boisson"]

    /// Indices des lignes gardees, dans l'ordre d'affichage. `nil` = pas de filtre.
    /// Tri par peremption : la plus proche d'abord, les articles sans date a la fin.
    static func filterSort(_ rows: [Row], location: String?, category: String?, sort: Sort) -> [Int] {
        let kept = rows.indices.filter { i in
            (location == nil || rows[i].location == location) && (category == nil || rows[i].category == category)
        }
        switch sort {
        case .name:
            return kept.sorted { rows[$0].name.localizedCaseInsensitiveCompare(rows[$1].name) == .orderedAscending }
        case .expiry:
            return kept.sorted { a, b in
                switch (rows[a].expiry, rows[b].expiry) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return rows[a].name.localizedCaseInsensitiveCompare(rows[b].name) == .orderedAscending
                }
            }
        }
    }

    static let alertHour = 9

    /// Quand prevenir : `daysBefore` jours avant la peremption, a 9 h. nil si la date
    /// est deja passee (un rappel dans le passe ne partirait jamais).
    static func alertDate(expiry: Date, daysBefore: Int, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: expiry)
        guard let d = calendar.date(byAdding: .day, value: -max(0, daysBefore), to: day),
              let at = calendar.date(bySettingHour: alertHour, minute: 0, second: 0, of: d) else { return nil }
        return at > now ? at : nil
    }

    static let notificationPrefix = "pantry."
    static func notificationID(_ stableID: String) -> String { notificationPrefix + stableID }
}

// MARK: - Bringo : quantites, unites, fusion, memoire

enum ShoppingUnits {
    static let all = ["", "g", "kg", "ml", "cl", "L", "paquet", "boîte", "bouteille"]
    static func label(_ u: String) -> String { u.isEmpty ? "pièce" : u }

    /// Facteur vers l'unite de base de la famille (g ou ml), nil si l'unite ne se convertit pas.
    private static func base(_ u: String) -> (family: String, factor: Double)? {
        switch u.lowercased() {
        case "g": return ("masse", 1); case "kg": return ("masse", 1000)
        case "ml": return ("volume", 1); case "cl": return ("volume", 10); case "l": return ("volume", 1000)
        default: return nil
        }
    }

    static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r).replacingOccurrences(of: ".", with: ",")
    }

    /// Quantite fusionnee, exprimee dans l'unite de l'article DEJA dans la liste.
    /// nil si les deux ne s'additionnent pas (texte libre, "pièce" + "kg"...) :
    /// on ne devine pas ce que l'utilisateur voulait.
    static func merged(existing: (qty: String, unit: String), adding: (qty: String, unit: String)) -> String? {
        guard let a = number(existing.qty), let b = number(adding.qty), a > 0, b > 0 else { return nil }
        if existing.unit.lowercased() == adding.unit.lowercased() { return format(a + b) }
        guard let ea = base(existing.unit), let eb = base(adding.unit), ea.family == eb.family else { return nil }
        return format(a + b * eb.factor / ea.factor)
    }
}

/// Ce que Bringo retient des articles deja ajoutes (recents, favoris, rayon choisi).
struct ShoppingMemoryEntry: Codable, Equatable {
    var name: String
    var aisle: String
    var unit: String
    var count: Int
    var last: Date
    var favorite: Bool
}

enum ShoppingMemory {
    static let storageKey = "bringoMemory.v1"
    static let cap = 150

    static func decode(_ raw: String) -> [ShoppingMemoryEntry] {
        guard let d = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ShoppingMemoryEntry].self, from: d)) ?? []
    }
    static func encode(_ list: [ShoppingMemoryEntry]) -> String {
        (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? "[]"
    }

    /// Note un ajout : compte +1, garde le rayon et l'unite choisis en dernier.
    /// Au-dela du plafond, on oublie les moins recents qui ne sont pas favoris.
    static func record(_ list: [ShoppingMemoryEntry], name: String, aisle: String, unit: String, now: Date = .now) -> [ShoppingMemoryEntry] {
        let n = ShoppingListOps.normalized(name)
        guard !n.isEmpty else { return list }
        var out = list
        if let i = out.firstIndex(where: { ShoppingListOps.normalized($0.name) == n }) {
            out[i].count += 1; out[i].last = now; out[i].aisle = aisle; out[i].unit = unit
        } else {
            out.append(.init(name: name.trimmingCharacters(in: .whitespaces), aisle: aisle, unit: unit, count: 1, last: now, favorite: false))
        }
        if out.count > cap {
            let drop = out.enumerated().filter { !$0.element.favorite }
                .sorted { $0.element.last < $1.element.last }.prefix(out.count - cap).map(\.offset)
            out = out.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
        }
        return out
    }

    static func setFavorite(_ list: [ShoppingMemoryEntry], name: String, aisle: String, unit: String, on: Bool) -> [ShoppingMemoryEntry] {
        let n = ShoppingListOps.normalized(name)
        var out = list
        if let i = out.firstIndex(where: { ShoppingListOps.normalized($0.name) == n }) { out[i].favorite = on }
        else if on { out.append(.init(name: name, aisle: aisle, unit: unit, count: 0, last: .now, favorite: true)) }
        return out
    }

    /// Suggestions : favoris puis les plus recents, sans ce qui est deja a acheter.
    /// Avec un debut de saisie, seuls les noms qui commencent par ces lettres.
    static func suggestions(_ list: [ShoppingMemoryEntry], query: String, toBuy: [String], limit: Int = 12) -> [ShoppingMemoryEntry] {
        let q = ShoppingListOps.normalized(query)
        let pending = Set(toBuy.map(ShoppingListOps.normalized))
        return list
            .filter { !pending.contains(ShoppingListOps.normalized($0.name)) }
            .filter { q.isEmpty || ShoppingListOps.normalized($0.name).hasPrefix(q) }
            .sorted { a, b in a.favorite != b.favorite ? a.favorite : a.last > b.last }
            .prefix(limit).map { $0 }
    }
}

// MARK: - WaterMind : boissons, part comptee, objectif selon le poids

struct BeverageType: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var icon: String
    /// Part du volume comptee dans l'objectif, REGLEE PAR L'UTILISATEUR. 100 par defaut :
    /// nous n'affirmons aucun coefficient scientifique.
    var percent: Int
}

enum WaterMath {
    static let beveragesKey = "waterBeverages.v1"
    static let defaults: [BeverageType] = [
        .init(name: "Eau", icon: "drop.fill", percent: 100),
        .init(name: "Thé", icon: "cup.and.saucer.fill", percent: 100),
        .init(name: "Café", icon: "mug.fill", percent: 100),
        .init(name: "Tisane", icon: "leaf.fill", percent: 100),
        .init(name: "Lait", icon: "waterbottle.fill", percent: 100),
        .init(name: "Jus", icon: "takeoutbag.and.cup.and.straw.fill", percent: 100),
        .init(name: "Soda", icon: "sparkles", percent: 100),
    ]

    static func decode(_ raw: String) -> [BeverageType] {
        guard let d = raw.data(using: .utf8), let list = try? JSONDecoder().decode([BeverageType].self, from: d), !list.isEmpty
        else { return defaults }
        return list
    }
    static func encode(_ list: [BeverageType]) -> String {
        (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? ""
    }

    /// Millilitres comptes dans l'objectif. `WaterEntry.amountML` garde CE nombre pour
    /// que tous les ecrans (widget, score, briefing) restent d'accord sans changement.
    static func counted(volume: Int, percent: Int) -> Int {
        Int((Double(max(0, volume)) * Double(min(100, max(0, percent))) / 100).rounded())
    }

    /// Volume servi : les anciennes prises (avant les boissons) n'ont pas de volume a part.
    static func volume(amountML: Int, volumeML: Int) -> Int { volumeML > 0 ? volumeML : amountML }

    /// Repere courant : 30 a 35 ml par kg et par jour. Arrondi a 100 ml, borne a
    /// l'intervalle de reglage de l'ecran (1000 a 5000 ml).
    static let mlPerKgLow = 30.0, mlPerKgHigh = 35.0
    static func suggestedGoal(weightKg: Double) -> (low: Int, high: Int, suggested: Int)? {
        guard weightKg >= 30, weightKg <= 300 else { return nil }
        func r(_ v: Double) -> Int { min(5000, max(1000, Int((v / 100).rounded()) * 100)) }
        return (r(weightKg * mlPerKgLow), r(weightKg * mlPerKgHigh), r(weightKg * mlPerKgHigh))
    }

    /// Poids connu du profil, par ordre de confiance : dernier releve (Santé ou saisi),
    /// poids du profil fitness, poids du questionnaire SEULEMENT s'il a ete reellement
    /// enregistre (sa valeur par defaut 75 kg n'est pas un poids).
    static func knownWeight(latestVital: Double?, profileKg: Double, setupKg: Int?) -> Double? {
        if let v = latestVital, v > 0 { return v }
        if profileKg > 0 { return profileKg }
        if let s = setupKg, s > 0 { return Double(s) }
        return nil
    }
}

// MARK: - SuppSafe : horaires, jours, stock, notifications

enum SupplementSchedule {
    struct Time: Equatable, Hashable { let hour: Int; let minute: Int }
    struct Slot: Equatable { let id: String; let hour: Int; let minute: Int; let weekday: Int?; let isConfirm: Bool }

    static let maxTimes = 6

    static func parseTimes(_ raw: String) -> [Time] {
        let list = raw.split(separator: ",").compactMap { part -> Time? in
            let p = part.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard p.count == 2, (0...23).contains(p[0]), (0...59).contains(p[1]) else { return nil }
            return Time(hour: p[0], minute: p[1])
        }
        return Array(Set(list)).sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }.prefix(maxTimes).map { $0 }
    }
    static func formatTimes(_ t: [Time]) -> String {
        Array(Set(t)).sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            .map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: ",")
    }
    /// Les anciennes lignes n'ont qu'une heure (`hour`/`minute`).
    static func times(raw: String, hour: Int, minute: Int) -> [Time] {
        let t = parseTimes(raw)
        return t.isEmpty ? [Time(hour: hour, minute: minute)] : t
    }

    /// Jours lundi = 1 ... dimanche = 7 ; vide = tous les jours.
    static func parseDays(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
    }
    static func isDue(on date: Date, daysRaw: String, calendar: Calendar = .current) -> Bool {
        let days = parseDays(daysRaw)
        guard !days.isEmpty, days.count < 7 else { return true }
        let wd = calendar.component(.weekday, from: date)          // 1 = dimanche
        return days.contains(wd == 1 ? 7 : wd - 1)
    }

    static func baseID(_ stableID: String) -> String { "supp.\(stableID)" }
    /// Ancien identifiant pose par le questionnaire Alimentation (par le nom, jamais annule).
    static func legacySetupID(name: String) -> String { "supp.\(name)" }

    /// Toutes les notifications d'un complement : une par heure (et par jour choisi),
    /// plus la verification « bien pris ? » ~1 h 30 apres si elle est voulue.
    static func slots(stableID: String, times: [Time], daysRaw: String, confirm: Bool) -> [Slot] {
        let base = baseID(stableID)
        let days = parseDays(daysRaw)
        let weekly = !days.isEmpty && days.count < 7
        var out: [Slot] = []
        for (i, t) in times.prefix(maxTimes).enumerated() {
            let total = t.hour * 60 + t.minute + 90
            let ch = (total / 60) % 24, cm = total % 60
            let nextDay = total >= 24 * 60
            if weekly {
                for d in days.sorted() {
                    let wd = d % 7 + 1                                  // lun 1 -> 2 ... dim 7 -> 1
                    out.append(Slot(id: "\(base).t\(i).w\(d)", hour: t.hour, minute: t.minute, weekday: wd, isConfirm: false))
                    if confirm {
                        out.append(Slot(id: "\(base).t\(i).w\(d).confirm", hour: ch, minute: cm,
                                        weekday: nextDay ? wd % 7 + 1 : wd, isConfirm: true))
                    }
                }
            } else {
                out.append(Slot(id: "\(base).t\(i)", hour: t.hour, minute: t.minute, weekday: nil, isConfirm: false))
                if confirm { out.append(Slot(id: "\(base).t\(i).confirm", hour: ch, minute: cm, weekday: nil, isConfirm: true)) }
            }
        }
        return out
    }

    /// Stock apres une prise notee (ou annulee). Jamais negatif.
    static func stock(after current: Int, unitsPerDose: Int, taken: Bool, undo: Bool) -> Int {
        guard taken else { return current }
        let u = max(1, unitsPerDose)
        return undo ? current + u : max(0, current - u)
    }

    /// Jours de stock restants au rythme prevu, nil si rien n'est prevu.
    static func daysLeft(stock: Int, unitsPerDose: Int, timesPerDay: Int, daysRaw: String) -> Int? {
        let days = parseDays(daysRaw)
        let perWeek = Double(days.isEmpty ? 7 : days.count) * Double(max(1, timesPerDay) * max(1, unitsPerDose))
        guard perWeek > 0 else { return nil }
        return Int((Double(max(0, stock)) / (perWeek / 7)).rounded(.down))
    }

    static func needsRefill(trackStock: Bool, stock: Int, threshold: Int) -> Bool { trackStock && stock <= max(0, threshold) }

    /// Taux de prises confirmees parmi les prises notees (prises + sautees), nil sans donnee.
    static func adherence(states: [String]) -> Double? {
        let noted = states.filter { $0 == "taken" || $0 == "skipped" }
        guard !noted.isEmpty else { return nil }
        return Double(noted.filter { $0 == "taken" }.count) / Double(noted.count)
    }
}

// MARK: - Figue : allergenes perso, gravite, traces possibles

struct PersonalAllergen: Codable, Equatable, Identifiable {
    var id: String { word }
    var word: String
    /// 1 = légère, 2 = modérée, 3 = sévère (choisi par l'utilisateur).
    var severity: Int
}

enum DietGuard {
    static let personalKey = "figuePersonalAllergens.v1"

    struct Finding: Equatable, Hashable {
        let label: String
        /// 0 = regime (pas une gravite), 1...3 = gravite choisie pour un allergene perso.
        let severity: Int
        let isTrace: Bool
    }

    static func severityLabel(_ s: Int) -> String { s >= 3 ? "Sévère" : s == 2 ? "Modérée" : "Légère" }

    static func decode(_ raw: String) -> [PersonalAllergen] {
        guard let d = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PersonalAllergen].self, from: d)) ?? []
    }
    static func encode(_ list: [PersonalAllergen]) -> String {
        (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? "[]"
    }

    /// Marqueurs d'etiquette qui annoncent des traces possibles (contamination croisee).
    private static let traceMarkers = ["peut contenir", "traces de", "traces d'", "trace de", "traces eventuelles",
                                       "may contain", "traces of"]

    /// Coupe le texte en partie « ingredients » et partie « traces possibles ».
    static func split(_ text: String) -> (main: String, traces: String) {
        let f = AllergenChecker.fold(text)
        let hits = traceMarkers.compactMap { f.range(of: $0)?.lowerBound }
        guard let first = hits.min() else { return (f, "") }
        return (String(f[..<first]), String(f[first...]))
    }

    /// Tout ce que le texte declenche pour le profil. Ce qui est annonce en traces
    /// possibles est signale A PART : ce n'est ni un ingredient, ni « sans risque ».
    static func check(_ text: String, flags: Set<String>, personal: [PersonalAllergen]) -> [Finding] {
        let parts = split(text)
        var out: [Finding] = []
        for issue in AllergenChecker.check(parts.main, against: flags) { out.append(.init(label: issue, severity: 0, isTrace: false)) }
        for issue in AllergenChecker.check(parts.traces, against: flags) {
            out.append(.init(label: issue.replacingOccurrences(of: "Incompatible", with: "Traces possibles"), severity: 0, isTrace: true))
        }
        let mainTokens = RecipeEngine.tokens(parts.main), traceTokens = RecipeEngine.tokens(parts.traces)
        for a in personal {
            let need = RecipeEngine.tokens(a.word)
            guard !need.isEmpty else { continue }
            if RecipeEngine.containsPhrase(need, in: mainTokens) {
                out.append(.init(label: "Allergène perso : \(a.word) (\(severityLabel(a.severity).lowercased()))", severity: a.severity, isTrace: false))
            } else if RecipeEngine.containsPhrase(need, in: traceTokens) {
                out.append(.init(label: "Traces possibles : \(a.word) (\(severityLabel(a.severity).lowercased()))", severity: a.severity, isTrace: true))
            }
        }
        return out
    }

    struct JournalHit: Equatable { let index: Int; let findings: [Finding] }

    /// Entrees du journal alimentaire qui touchent le profil (lecture seule, rien n'est modifie).
    static func journal(_ names: [String], flags: Set<String>, personal: [PersonalAllergen]) -> [JournalHit] {
        names.enumerated().compactMap { i, n in
            let f = check(n, flags: flags, personal: personal)
            return f.isEmpty ? nil : JournalHit(index: i, findings: f)
        }
    }
}
