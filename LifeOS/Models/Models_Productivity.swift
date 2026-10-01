import Foundation
import SwiftData

// MARK: - Lot 7 Productivite : modele et regles pures
//
// Les regles vivent ici en fonctions statiques sans interface: elles sont
// testees une par une dans Lot7ProductivityTests. Les ecrans de
// ProductivityModule.swift ne font que les appeler.

// MARK: - Forêt : historique des sessions

/// Une phase de concentration terminee, interrompue ou abandonnee. Avant, le
/// compteur etait un entier du jour: aucune trace, aucun tag, aucune stat.
@Model final class FocusSession {
    /// Debut de la phase en secondes: une phase ne s'enregistre qu'une fois, meme
    /// si l'app est relancee pendant ou apres (pas de session en double).
    var phaseKey: String = ""
    var start: Date = Date.now
    var end: Date = Date.now
    var plannedMinutes: Int = 25
    var focusedSeconds: Int = 0
    var tag: String = ""
    /// completed | interrupted (sortie de l'app) | abandoned (Stop)
    var outcome: String = "completed"

    init(phaseKey: String, start: Date, end: Date, plannedMinutes: Int, focusedSeconds: Int,
         tag: String, outcome: String) {
        self.phaseKey = phaseKey; self.start = start; self.end = end
        self.plannedMinutes = plannedMinutes; self.focusedSeconds = focusedSeconds
        self.tag = tag; self.outcome = outcome
    }

    var isCompleted: Bool { outcome == FocusRules.Outcome.completed.rawValue }
}

// MARK: - Texte

enum TextFold {
    /// Comparaison sans accents ni casse, apostrophe typographique comprise.
    static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }
}

/// Etiquettes stockees en texte separe par des virgules (TodoItem.tagsRaw, Note.tags).
enum TagList {
    static func parse(_ raw: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for part in raw.split(separator: ",") {
            var t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            while t.hasPrefix("#") || t.hasPrefix("@") { t.removeFirst() }
            guard !t.isEmpty, seen.insert(TextFold.fold(t)).inserted else { continue }
            out.append(t)
        }
        return out
    }

    static func serialize(_ tags: [String]) -> String { parse(tags.joined(separator: ",")).joined(separator: ",") }

    static func contains(_ raw: String, _ tag: String) -> Bool {
        parse(raw).contains { TextFold.fold($0) == TextFold.fold(tag) }
    }
}

// MARK: - Todoo : sous-taches

struct ChecklistItem: Equatable, Identifiable {
    var id = UUID()
    var title: String
    var done: Bool
    static func == (a: ChecklistItem, b: ChecklistItem) -> Bool { a.title == b.title && a.done == b.done }
}

enum Checklist {
    /// Une ligne par sous-tache: « [x] texte » cochee, « [ ] texte » ou texte nu = a faire.
    static func parse(_ raw: String) -> [ChecklistItem] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("[x]") || l.hasPrefix("[X]") {
                let t = String(l.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : ChecklistItem(title: t, done: true)
            }
            let t = (l.hasPrefix("[ ]") ? String(l.dropFirst(3)) : l).trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : ChecklistItem(title: t, done: false)
        }
    }

    static func serialize(_ items: [ChecklistItem]) -> String {
        items.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.done ? "[x]" : "[ ]") \($0.title.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n")
    }

    static func progress(_ raw: String) -> (done: Int, total: Int) {
        let items = parse(raw)
        return (items.filter(\.done).count, items.count)
    }

    /// Une tache recurrente qui revient repart avec ses sous-taches decochees.
    static func reset(_ raw: String) -> String {
        serialize(parse(raw).map { ChecklistItem(title: $0.title, done: false) })
    }
}

// MARK: - Todoo : recurrence

enum TaskRecurrence: Equatable, Hashable {
    case none, daily, weekdays, weekly(Set<Int>), monthly

    static let workweek: Set<Int> = [2, 3, 4, 5, 6]

    static func of(daysRaw: String, rule: String) -> TaskRecurrence {
        if rule == "monthly" { return .monthly }
        let days = Set(daysRaw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
        if days.isEmpty { return .none }
        if days.count == 7 { return .daily }
        if days == workweek { return .weekdays }
        return .weekly(days)
    }

    static func of(_ t: TodoItem) -> TaskRecurrence { of(daysRaw: t.recurringDaysRaw, rule: t.recurrenceRule) }

    /// Ecriture dans les deux champs existants (jours de semaine, regle mensuelle).
    var storage: (daysRaw: String, rule: String) {
        switch self {
        case .none: return ("", "")
        case .daily: return ("1,2,3,4,5,6,7", "")
        case .weekdays: return ("2,3,4,5,6", "")
        case .weekly(let d): return (d.sorted().map(String.init).joined(separator: ","), "")
        case .monthly: return ("", "monthly")
        }
    }

    func apply(to t: TodoItem) {
        t.recurringDaysRaw = storage.daysRaw
        t.recurrenceRule = storage.rule
    }

    var label: String {
        switch self {
        case .none: return "Jamais"
        case .daily: return "Tous les jours"
        case .weekdays: return "En semaine"
        case .weekly(let d):
            let names = [2: "lun", 3: "mar", 4: "mer", 5: "jeu", 6: "ven", 7: "sam", 1: "dim"]
            return "Chaque " + [2, 3, 4, 5, 6, 7, 1].filter(d.contains).compactMap { names[$0] }.joined(separator: ", ")
        case .monthly: return "Tous les mois"
        }
    }

    var weekdaySet: Set<Int> {
        switch self {
        case .daily: return Set(1...7)
        case .weekdays: return Self.workweek
        case .weekly(let d): return d
        default: return []
        }
    }

    /// Le jour revient-il dans cette recurrence ? (mensuel: meme quantieme que l'ancre)
    func matches(_ day: Date, anchor: Date?, calendar cal: Calendar = .current) -> Bool {
        switch self {
        case .none: return false
        case .monthly:
            let dom = cal.component(.day, from: anchor ?? day)
            let range = cal.range(of: .day, in: .month, for: day)?.count ?? 31
            return cal.component(.day, from: day) == min(dom, range)
        default: return weekdaySet.contains(cal.component(.weekday, from: day))
        }
    }

    /// Prochaine occurrence STRICTEMENT apres `after`, a l'heure de `timeOf`.
    func next(after: Date, timeOf: Date?, calendar cal: Calendar = .current) -> Date? {
        switch self {
        case .none: return nil
        case .monthly:
            return Self.nextMonthly(after: after, dayOfMonth: cal.component(.day, from: timeOf ?? after),
                                    timeOf: timeOf, calendar: cal)
        default:
            return ProductivityRules.nextOccurrence(after: after, weekdays: weekdaySet, timeOf: timeOf, calendar: cal)
        }
    }

    /// Meme quantieme le mois suivant, ramene au dernier jour quand le mois est
    /// plus court (31 -> 30 avril, 28/29 fevrier).
    static func nextMonthly(after: Date, dayOfMonth: Int, timeOf: Date?, calendar cal: Calendar = .current) -> Date? {
        let hm = timeOf.map { cal.dateComponents([.hour, .minute], from: $0) }
        guard var month = cal.dateInterval(of: .month, for: after)?.start else { return nil }
        for _ in 0..<14 {
            guard let days = cal.range(of: .day, in: .month, for: month)?.count else { return nil }
            var c = cal.dateComponents([.year, .month], from: month)
            c.day = min(max(dayOfMonth, 1), days); c.hour = hm?.hour ?? 0; c.minute = hm?.minute ?? 0
            if let d = cal.date(from: c), d > after { return d }
            guard let n = cal.date(byAdding: .month, value: 1, to: month) else { return nil }
            month = n
        }
        return nil
    }
}

// MARK: - Todoo : saisie rapide en francais

struct ParsedTask: Equatable {
    var title = ""
    var due: Date?
    var hasTime = false
    var priority: Int?
    var project: String?
    var tags: [String] = []
    var recurrence: TaskRecurrence = .none
}

/// « Appeler maman demain 18h #maison !2 » -> titre, echeance, projet, priorite.
/// Conventions (affichees dans l'app): #projet, @etiquette, !1 urgente,
/// !2 importante, !3 normale. Ce qui n'est pas reconnu reste dans le titre.
enum TaskCapture {
    static let weekdays: [String: Int] = ["lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5,
                                          "vendredi": 6, "samedi": 7, "dimanche": 1]
    static let months: [String: Int] = [
        "janvier": 1, "janv": 1, "fevrier": 2, "fevr": 2, "fev": 2, "mars": 3, "avril": 4, "avr": 4,
        "mai": 5, "juin": 6, "juillet": 7, "juil": 7, "aout": 8, "septembre": 9, "sept": 9,
        "octobre": 10, "oct": 10, "novembre": 11, "nov": 11, "decembre": 12, "dec": 12
    ]
    static let numberWords: [String: Int] = ["un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4,
                                             "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
                                             "quinze": 15]

    private static func clean(_ s: String) -> String {
        var t = TextFold.fold(s)
        while let last = t.last, ",;.!?".contains(last), !(t.hasPrefix("!") && t.count <= 2) { t.removeLast() }
        return t
    }

    static func weekday(_ t: String) -> Int? {
        if let d = weekdays[t] { return d }
        if t.hasSuffix("s"), let d = weekdays[String(t.dropLast())] { return d }
        return nil
    }

    static func time(_ t: String) -> (Int, Int)? {
        if t == "midi" { return (12, 0) }
        let parts: [Substring]
        if t.contains("h") { parts = t.split(separator: "h", omittingEmptySubsequences: false) }
        else if t.contains(":") { parts = t.split(separator: ":", omittingEmptySubsequences: false) }
        else { return nil }
        guard parts.count == 2, let h = Int(parts[0]), (0...23).contains(h), parts[0].count <= 2 else { return nil }
        if parts[1].isEmpty { return t.contains("h") ? (h, 0) : nil }
        guard parts[1].count == 2, let m = Int(parts[1]), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private static func number(_ t: String) -> Int? {
        if let n = Int(t) { return n }
        if t == "1er" { return 1 }
        return numberWords[t]
    }

    static func parse(_ text: String, now: Date = .now, calendar cal: Calendar = .current) -> ParsedTask {
        let raw = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let norm = raw.map(clean)
        var used = Array(repeating: false, count: raw.count)
        var r = ParsedTask()
        let today = cal.startOfDay(for: now)
        var day: Date?
        var time: (Int, Int)?
        var softTime: (Int, Int)?     // « ce soir », « demain matin »: si aucune heure precise
        var pendingWeekly = false      // « chaque semaine »: jour resolu a la fin

        func at(_ j: Int) -> String? { j < norm.count && !used[j] ? norm[j] : nil }
        func mark(_ a: Int, _ n: Int) { for k in a..<min(a + n, raw.count) { used[k] = true } }
        func plusDays(_ n: Int) -> Date? { cal.date(byAdding: .day, value: n, to: today) }
        func nextWeekday(_ wd: Int) -> Date? {
            for o in 1...7 { if let d = plusDays(o), cal.component(.weekday, from: d) == wd { return d } }
            return nil
        }
        func dated(day d: Int, month m: Int?, year y: Int?) -> Date? {
            var c = cal.dateComponents([.year, .month], from: today)
            if let m { c.month = m }
            if let y { c.year = y < 100 ? 2000 + y : y }
            c.day = d
            guard let date = cal.date(from: c), cal.component(.day, from: date) == d else {
                // Quantieme inexistant ce mois-ci (31 sans mois): mois suivant.
                if m == nil, let nm = cal.date(byAdding: .month, value: 1, to: today) {
                    var c2 = cal.dateComponents([.year, .month], from: nm); c2.day = d
                    if let d2 = cal.date(from: c2), cal.component(.day, from: d2) == d { return d2 }
                }
                return nil
            }
            if date < today, y == nil {
                return cal.date(byAdding: m == nil ? .month : .year, value: 1, to: date)
            }
            return date
        }

        var i = 0
        while i < raw.count {
            if used[i] { i += 1; continue }
            let t = norm[i]

            // Recurrence
            if t == "tous" || t == "toutes" || t == "chaque" {
                let j = (t == "chaque") ? i + 1 : (at(i + 1) == "les" ? i + 2 : -1)
                if j > 0, let w = at(j) {
                    if w == "jours" || w == "jour" { r.recurrence = .daily; mark(i, j - i + 1); i = j + 1; continue }
                    if w == "semaines" || w == "semaine" { pendingWeekly = true; mark(i, j - i + 1); i = j + 1; continue }
                    if w == "mois" { r.recurrence = .monthly; mark(i, j - i + 1); i = j + 1; continue }
                    if weekday(w) != nil {
                        var days = Set<Int>(), k = j
                        while let tk = at(k) {
                            if let wd = weekday(tk) { days.insert(wd); k += 1; continue }
                            if (tk == "et" || tk == ","), let nx = at(k + 1), weekday(nx) != nil { k += 1; continue }
                            break
                        }
                        r.recurrence = TaskRecurrence.of(daysRaw: days.map(String.init).joined(separator: ","), rule: "")
                        mark(i, k - i); i = k; continue
                    }
                }
            }
            if t == "quotidien" || t == "quotidiennement" { r.recurrence = .daily; mark(i, 1); i += 1; continue }
            if t == "hebdomadaire" { pendingWeekly = true; mark(i, 1); i += 1; continue }
            if t == "mensuel" || t == "mensuellement" { r.recurrence = .monthly; mark(i, 1); i += 1; continue }
            if t == "en", at(i + 1) == "semaine" { r.recurrence = .weekdays; mark(i, 2); i += 2; continue }
            if t == "jours", let n = at(i + 1), n == "ouvres" || n == "ouvrables" { r.recurrence = .weekdays; mark(i, 2); i += 2; continue }

            // Jours relatifs
            if t == "aujourd'hui" || t == "aujourdhui" { day = today; mark(i, 1); i += 1; continue }
            if (t == "ce" || t == "cet"), let n = at(i + 1) {
                if n == "soir" { day = today; softTime = (20, 0); mark(i, 2); i += 2; continue }
                if n == "matin" { day = today; softTime = (9, 0); mark(i, 2); i += 2; continue }
                if n == "apres-midi" || n == "aprem" { day = today; softTime = (14, 0); mark(i, 2); i += 2; continue }
                if let wd = weekday(n) { day = nextWeekday(wd); mark(i, 2); i += 2; continue }
            }
            if t == "demain" { day = plusDays(1); mark(i, 1); i += 1; continue }
            if t == "apres-demain" { day = plusDays(2); mark(i, 1); i += 1; continue }
            if t == "apres", at(i + 1) == "demain" { day = plusDays(2); mark(i, 2); i += 2; continue }
            if (t == "soir" || t == "matin"), i > 0, used[i - 1], day != nil {
                softTime = t == "soir" ? (20, 0) : (9, 0); mark(i, 1); i += 1; continue
            }
            if t == "le", let n = at(i + 1), let wd = weekday(n) {
                day = nextWeekday(wd); mark(i, 2)
                if at(i + 2) == "prochain" { mark(i + 2, 1); i += 3 } else { i += 2 }
                continue
            }
            if let wd = weekday(t) {
                day = nextWeekday(wd); mark(i, 1)
                if at(i + 1) == "prochain" { mark(i + 1, 1); i += 2 } else { i += 1 }
                continue
            }
            if t == "dans", let n = at(i + 1).flatMap(number), let unit = at(i + 2) {
                if unit.hasPrefix("jour") { day = plusDays(n); mark(i, 3); i += 3; continue }
                if unit.hasPrefix("semaine") { day = plusDays(7 * n); mark(i, 3); i += 3; continue }
                if unit == "mois" { day = cal.date(byAdding: .month, value: n, to: today); mark(i, 3); i += 3; continue }
                if unit.hasPrefix("heure") || unit == "h" || unit.hasPrefix("min") {
                    let secs = Double(n) * (unit.hasPrefix("min") ? 60 : 3600)
                    let d = now.addingTimeInterval(secs)
                    day = cal.startOfDay(for: d)
                    let c = cal.dateComponents([.hour, .minute], from: d)
                    time = (c.hour ?? 0, c.minute ?? 0)
                    mark(i, 3); i += 3; continue
                }
            }

            // Dates explicites: « le 12 », « le 12 octobre », « 12 octobre 2026 », « 12/10 »
            let leOffset = (t == "le" || t == "du" || t == "au") ? 1 : 0
            if let dt = at(i + leOffset), let d = number(dt), (1...31).contains(d), Int(dt) != nil || dt == "1er" {
                if let mt = at(i + leOffset + 1), let m = months[mt] {
                    var len = leOffset + 2
                    var y: Int?
                    if let yt = at(i + len), let yy = Int(yt), yy >= 2000, yy < 2100 { y = yy; len += 1 }
                    if let date = dated(day: d, month: m, year: y) { day = date; mark(i, len); i += len; continue }
                } else if leOffset == 1 {
                    if let date = dated(day: d, month: nil, year: nil) { day = date; mark(i, 2); i += 2; continue }
                }
            }
            if t.contains("/") {
                let p = t.split(separator: "/").map { Int($0) }
                if p.count >= 2, p.allSatisfy({ $0 != nil }), let d = p[0], let m = p[1], (1...12).contains(m),
                   let date = dated(day: d, month: m, year: p.count > 2 ? p[2] : nil) {
                    day = date; mark(i, 1); i += 1; continue
                }
            }

            // Heure: « 18h », « 18h30 », « 18:30 », « a 9h », « midi »
            if (t == "a" || t == "vers"), let n = at(i + 1), let tm = Self.time(n) { time = tm; mark(i, 2); i += 2; continue }
            if let tm = Self.time(t) { time = tm; mark(i, 1); i += 1; continue }

            // Projet, etiquettes, priorite
            if raw[i].hasPrefix("#"), raw[i].count > 1 {
                let name = String(raw[i].dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",;."))
                if !name.isEmpty {
                    if r.project == nil { r.project = name } else { r.tags.append(name) }
                    mark(i, 1); i += 1; continue
                }
            }
            if raw[i].hasPrefix("@"), raw[i].count > 1 {
                let name = String(raw[i].dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",;."))
                if !name.isEmpty { r.tags.append(name); mark(i, 1); i += 1; continue }
            }
            if t == "!1" || t == "!2" || t == "!3" {
                r.priority = t == "!1" ? 2 : (t == "!2" ? 1 : 0); mark(i, 1); i += 1; continue
            }
            i += 1
        }

        if pendingWeekly {
            r.recurrence = .weekly([cal.component(.weekday, from: day ?? today)])
        }
        if day == nil, r.recurrence != .none {
            // Premiere occurrence: aujourd'hui s'il compte (et que l'heure n'est pas passee).
            for o in 0..<62 {
                guard let d = plusDays(o), r.recurrence == .monthly || r.recurrence.matches(d, anchor: nil, calendar: cal) else { continue }
                if o == 0, let tm = time ?? softTime,
                   let at = cal.date(bySettingHour: tm.0, minute: tm.1, second: 0, of: d), at <= now { continue }
                day = d; break
            }
        }
        if day == nil, let tm = time {
            // Heure seule: aujourd'hui, ou demain si elle est deja passee.
            let atToday = cal.date(bySettingHour: tm.0, minute: tm.1, second: 0, of: today)
            day = (atToday.map { $0 > now } ?? true) ? today : plusDays(1)
        }
        if let d = day {
            if let tm = time ?? softTime {
                r.due = cal.date(bySettingHour: tm.0, minute: tm.1, second: 0, of: d)
                r.hasTime = true
            } else {
                r.due = d
            }
        }
        r.tags = TagList.parse(r.tags.joined(separator: ","))
        r.title = raw.indices.filter { !used[$0] }.map { raw[$0] }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return r
    }
}

// MARK: - Todoo : vues et filtres

enum TodoList: String, CaseIterable, Identifiable {
    case inbox, today, upcoming, all, projects, done
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inbox: return "Boîte de réception"
        case .today: return "Aujourd'hui"
        case .upcoming: return "À venir"
        case .all: return "Toutes"
        case .projects: return "Projets"
        case .done: return "Terminées"
        }
    }
    var icon: String {
        switch self {
        case .inbox: return "tray"
        case .today: return "star"
        case .upcoming: return "calendar"
        case .all: return "list.bullet"
        case .projects: return "folder"
        case .done: return "checkmark.circle"
        }
    }
}

enum TodoFilter {
    static func isInbox(_ t: TodoItem) -> Bool { t.project.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Taches d'une vue. A venir: ordre CHRONOLOGIQUE strict (critere d'acceptation).
    static func tasks(_ all: [TodoItem], in list: TodoList, now: Date = .now, calendar cal: Calendar = .current) -> [TodoItem] {
        let open = all.filter { !$0.done }
        switch list {
        case .inbox:
            return open.filter(isInbox).sorted(by: ProductivityRules.todoPrecedes)
        case .today:
            return open.filter { t in
                guard let d = t.due else { return false }
                return cal.isDate(d, inSameDayAs: now) || ProductivityRules.isLate(d, now: now, calendar: cal)
            }.sorted(by: ProductivityRules.todoPrecedes)
        case .upcoming:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            return open.filter { ($0.due ?? .distantPast) >= tomorrow }.sorted {
                let (a, b) = ($0.due ?? .distantFuture, $1.due ?? .distantFuture)
                return a != b ? a < b : $0.priority > $1.priority
            }
        case .all, .projects:
            return open.sorted(by: ProductivityRules.todoPrecedes)
        case .done:
            return all.filter(\.done).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
    }

    /// Recherche plein texte (titre, notes, projet, section, etiquettes, sous-taches),
    /// tous les mots doivent etre presents, sans accents ni casse.
    static func matches(_ t: TodoItem, search: String, tag: String? = nil, project: String? = nil, priority: Int? = nil) -> Bool {
        if let tag, !TagList.contains(t.tagsRaw, tag) { return false }
        if let project, TextFold.fold(t.project) != TextFold.fold(project) { return false }
        if let priority, t.priority != priority { return false }
        let words = TextFold.fold(search).split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return true }
        let hay = TextFold.fold([t.title, t.notes, t.project, t.section, t.tagsRaw, t.checklistRaw].joined(separator: " "))
        return words.allSatisfy { hay.contains($0) }
    }

    /// Groupes par jour pour « À venir ».
    static func groupedByDay(_ tasks: [TodoItem], calendar cal: Calendar = .current) -> [TodoDayGroup] {
        var out: [TodoDayGroup] = []
        for t in tasks {
            let d = cal.startOfDay(for: t.due ?? .distantFuture)
            if let last = out.last, last.day == d { out[out.count - 1].tasks.append(t) } else { out.append(TodoDayGroup(day: d, tasks: [t])) }
        }
        return out
    }
}

struct TodoDayGroup: Identifiable {
    let day: Date
    var tasks: [TodoItem]
    var id: Date { day }
}

enum TodoProjects {
    /// Projets connus (taches ouvertes ou non), ordre alphabetique, sans la boite de reception.
    static func projects(_ all: [TodoItem]) -> [String] {
        var seen = [String: String]()
        for t in all {
            let p = t.project.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { continue }
            seen[TextFold.fold(p)] = seen[TextFold.fold(p)] ?? p
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Sections d'un projet dans l'ordre d'apparition, « sans section » en premier.
    static func sections(of project: String, in all: [TodoItem]) -> [String] {
        var out: [String] = []
        for t in all where TextFold.fold(t.project) == TextFold.fold(project) {
            let s = t.section.trimmingCharacters(in: .whitespaces)
            if !out.contains(where: { TextFold.fold($0) == TextFold.fold(s) }) { out.append(s) }
        }
        return out.sorted { a, b in a.isEmpty ? !b.isEmpty : (b.isEmpty ? false : a.localizedCaseInsensitiveCompare(b) == .orderedAscending) }
    }

    static func allTags(_ all: [TodoItem]) -> [String] {
        TagList.parse(all.map(\.tagsRaw).joined(separator: ",")).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Renomme un projet (ou le fusionne dans un autre) sur toutes ses taches.
    @discardableResult
    static func rename(_ from: String, to: String, in all: [TodoItem]) -> Int {
        let target = to.trimmingCharacters(in: .whitespaces)
        var n = 0
        for t in all where TextFold.fold(t.project) == TextFold.fold(from) { t.project = target; n += 1 }
        return n
    }
}

/// Retour arriere d'un coche (une tache recurrente a deja saute a l'occurrence suivante).
struct TodoSnapshot {
    let done: Bool, due: Date?, completedAt: Date?, blockStart: Date?, blockEnd: Date?, locked: Bool, checklist: String

    init(_ t: TodoItem) {
        done = t.done; due = t.due; completedAt = t.completedAt
        blockStart = t.blockStart; blockEnd = t.blockEnd; locked = t.blockLocked; checklist = t.checklistRaw
    }

    func restore(_ t: TodoItem) {
        t.done = done; t.due = due; t.completedAt = completedAt
        t.blockStart = blockStart; t.blockEnd = blockEnd; t.blockLocked = locked; t.checklistRaw = checklist
    }
}

@MainActor
enum TodoIDs {
    /// Donne un identifiant stable aux taches creees avant son existence (ou copiees).
    @discardableResult
    static func ensure(_ ctx: ModelContext) -> Int {
        guard let all = try? ctx.fetch(FetchDescriptor<TodoItem>()) else { return 0 }
        var seen = Set<String>(), fixed = 0
        for t in all {
            if t.uid.isEmpty || seen.contains(t.uid) { t.uid = UUID().uuidString; fixed += 1 }
            seen.insert(t.uid)
        }
        if fixed > 0 { try? ctx.save() }
        return fixed
    }

    static func ensure(_ t: TodoItem) { if t.uid.isEmpty { t.uid = UUID().uuidString } }
}

enum TaskReminderRules {
    static let options: [(minutes: Int, label: String)] = [
        (-1, "Aucun"), (0, "À l'heure"), (15, "15 min avant"), (60, "1 h avant"), (1440, "La veille")
    ]

    /// Heure du rappel. Une echeance sans heure rappelle a 9 h ce jour-la (moins le
    /// decalage). Rien si la date est passee.
    static func fireDate(due: Date?, minutesBefore: Int, now: Date = .now, calendar cal: Calendar = .current) -> Date? {
        guard let due, minutesBefore >= 0 else { return nil }
        let base = ProductivityRules.isDateOnly(due, calendar: cal)
            ? (cal.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due) : due
        let fire = base.addingTimeInterval(-Double(minutesBefore) * 60)
        return fire > now ? fire : nil
    }
}

// MARK: - Structurd : planificateur de journee

struct PlanSlot: Equatable {
    var start: Date
    var end: Date
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    func overlaps(_ o: PlanSlot) -> Bool { start < o.end && o.start < end }
}

struct PlanItem: Equatable {
    let key: String
    let minutes: Int
    /// Creneau deja pose (non verrouille). Garde s'il reste valable.
    var existing: PlanSlot?
}

struct PlanOverflow: Equatable {
    let key: String
    let reason: String
}

struct PlanOutcome: Equatable {
    var placed: [String: PlanSlot] = [:]
    var overflow: [PlanOverflow] = []
}

/// Planning deterministe: occupe d'abord ce qui ne bouge pas (calendrier, blocs
/// verrouilles, pause), garde les creneaux encore valables, puis place le reste
/// dans le premier trou assez long, dans l'ordre recu (priorite puis echeance).
/// Ce qui ne rentre pas sort avec une raison: rien n'est jamais pose en
/// chevauchement.
enum DayPlanner {
    static let grid = 5

    static func roundUp(_ d: Date, minutes: Int = grid, calendar cal: Calendar = .current) -> Date {
        let start = cal.startOfDay(for: d)
        let secs = d.timeIntervalSince(start)
        let step = Double(minutes * 60)
        return start.addingTimeInterval((secs / step).rounded(.up) * step)
    }

    static func plan(items: [PlanItem], busy: [PlanSlot], window: PlanSlot, earliest: Date,
                     bufferMinutes: Int = 0, keepExisting: Bool = true, calendar cal: Calendar = .current) -> PlanOutcome {
        var out = PlanOutcome()
        let buffer = TimeInterval(max(0, bufferMinutes) * 60)
        let lower = roundUp(max(window.start, earliest), calendar: cal)
        var occupied = busy.filter { $0.end > window.start && $0.start < window.end }
        var pending: [PlanItem] = []

        for it in items {
            if keepExisting, let ex = it.existing, ex.start >= lower, ex.end <= window.end,
               ex.minutes == max(it.minutes, grid), !occupied.contains(where: { $0.overlaps(ex) }) {
                out.placed[it.key] = ex
                occupied.append(ex)
            } else {
                pending.append(it)
            }
        }

        for it in pending {
            let dur = TimeInterval(max(it.minutes, grid) * 60)
            if lower >= window.end {
                out.overflow.append(PlanOverflow(key: it.key, reason: "Ta journée est terminée."))
                continue
            }
            if dur > window.end.timeIntervalSince(lower) {
                out.overflow.append(PlanOverflow(key: it.key, reason: "Plus longue que le temps qui reste dans ta journée."))
                continue
            }
            let blocked = occupied.map { PlanSlot(start: $0.start.addingTimeInterval(-buffer), end: $0.end.addingTimeInterval(buffer)) }
                .sorted { $0.start < $1.start }
            var cursor = lower
            var found: PlanSlot?
            for b in blocked {
                if b.start > cursor, b.start.timeIntervalSince(cursor) >= dur {
                    found = PlanSlot(start: cursor, end: cursor.addingTimeInterval(dur)); break
                }
                if b.end > cursor { cursor = roundUp(b.end, calendar: cal) }
            }
            if found == nil, window.end.timeIntervalSince(cursor) >= dur {
                found = PlanSlot(start: cursor, end: cursor.addingTimeInterval(dur))
            }
            if let f = found {
                out.placed[it.key] = f
                occupied.append(f)
            } else {
                out.overflow.append(PlanOverflow(key: it.key, reason: "Pas de créneau libre assez long."))
            }
        }
        return out
    }

    /// Deplacement au doigt: decale de `deltaMinutes`, aligne sur la grille de
    /// `snap` minutes et reste dans la journee.
    static func moved(_ slot: PlanSlot, byMinutes delta: Double, snap: Int = 15, within window: PlanSlot,
                      calendar cal: Calendar = .current) -> PlanSlot {
        let dur = slot.end.timeIntervalSince(slot.start)
        let dayStart = cal.startOfDay(for: slot.start)
        let raw = slot.start.addingTimeInterval(delta * 60).timeIntervalSince(dayStart)
        let step = Double(max(snap, 1) * 60)
        var start = dayStart.addingTimeInterval((raw / step).rounded() * step)
        if start < window.start { start = window.start }
        if start.addingTimeInterval(dur) > window.end { start = window.end.addingTimeInterval(-dur) }
        return PlanSlot(start: start, end: start.addingTimeInterval(dur))
    }

    static func durationOf(_ t: TodoItem) -> Int { t.estimateMinutes > 0 ? t.estimateMinutes : 60 }
}

// MARK: - Habitly : regles

enum HabitRules {
    static func skipped(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func serialize(_ s: Set<String>) -> String { s.sorted().joined(separator: ",") }

    static func toggledSkip(_ raw: String, day: Date, calendar cal: Calendar = .current) -> String {
        var s = skipped(raw)
        let k = ProductivityRules.dayKey(day, calendar: cal)
        if s.contains(k) { s.remove(k) } else { s.insert(k) }
        return serialize(s)
    }

    /// Pause = jours sautes de `from` a `through` inclus (une annee au plus): la
    /// serie et le taux les ignorent sans regle a part.
    static func pausing(_ raw: String, from: Date, through: Date, calendar cal: Calendar = .current) -> String {
        var s = skipped(raw)
        var d = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: through)
        var n = 0
        while d <= end, n < 366 {
            s.insert(ProductivityRules.dayKey(d, calendar: cal))
            guard let nx = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = nx; n += 1
        }
        return serialize(s)
    }

    /// Reprise: les jours sautes a partir de `from` sont retires (le passe reste).
    static func resuming(_ raw: String, from: Date, calendar cal: Calendar = .current) -> String {
        let k = ProductivityRules.dayKey(from, calendar: cal)
        return serialize(skipped(raw).filter { $0 < k })
    }

    static func isPaused(_ until: Date?, on day: Date, calendar cal: Calendar = .current) -> Bool {
        guard let until else { return false }
        return cal.startOfDay(for: day) <= cal.startOfDay(for: until)
    }

    private static func mondayCalendar(_ cal: Calendar) -> Calendar { var c = cal; c.firstWeekday = 2; return c }

    static func doneCount(inWeekOf day: Date, completions: [Date], calendar cal: Calendar = .current) -> Int {
        let c = mondayCalendar(cal)
        guard let w = c.dateInterval(of: .weekOfYear, for: day) else { return 0 }
        return Set(completions.filter { w.contains($0) }.map { c.startOfDay(for: $0) }).count
    }

    /// Fait aujourd'hui, ou du a faire aujourd'hui ? (liste du jour, frise)
    static func isDueToday(activeDays: Set<Int>, weeklyTarget: Int, skipped: Set<String>,
                           completions: [Date], now: Date = .now, calendar cal: Calendar = .current) -> Bool {
        let doneToday = completions.contains { cal.isDate($0, inSameDayAs: now) }
        if doneToday { return true }
        if skipped.contains(ProductivityRules.dayKey(now, calendar: cal)) { return false }
        if weeklyTarget > 0 { return doneCount(inWeekOf: now, completions: completions, calendar: cal) < weeklyTarget }
        let active = activeDays.isEmpty ? Set(1...7) : activeDays
        return active.contains(cal.component(.weekday, from: now))
    }

    /// Serie. Jours actifs: jours consecutifs dus et faits; un jour saute ou en pause
    /// est neutre (gel de serie). « x fois par semaine »: semaines consecutives qui
    /// atteignent l'objectif; la semaine en cours ne casse rien tant qu'elle n'est pas finie.
    static func streak(completions: [Date], activeDays: Set<Int>, weeklyTarget: Int, skipped: Set<String>,
                       now: Date = .now, calendar cal: Calendar = .current) -> Int {
        guard !completions.isEmpty else { return 0 }
        if weeklyTarget > 0 { return weeklyStreak(completions, target: weeklyTarget, skipped: skipped, now: now, calendar: cal) }
        let active = activeDays.isEmpty ? Set(1...7) : activeDays
        let doneDays = Set(completions.map { cal.startOfDay(for: $0) })
        let first = doneDays.min() ?? cal.startOfDay(for: now)
        let today = cal.startOfDay(for: now)
        var day = today, streak = 0
        for _ in 0..<3660 {
            if day < first { break }
            // Comme la regle d'origine: seuls les jours actifs non sautes comptent.
            let due = active.contains(cal.component(.weekday, from: day)) && !skipped.contains(ProductivityRules.dayKey(day, calendar: cal))
            if due {
                if doneDays.contains(day) { streak += 1 }
                else if day != today { break }
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private static func weekRequirement(_ week: DateInterval, target: Int, skipped: Set<String>, calendar cal: Calendar) -> Int {
        var n = 0, d = week.start
        while d < week.end {
            if skipped.contains(ProductivityRules.dayKey(d, calendar: cal)) { n += 1 }
            guard let nx = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = nx
        }
        return max(0, min(target, 7 - n))
    }

    static func weeklyStreak(_ completions: [Date], target: Int, skipped: Set<String>, now: Date, calendar cal: Calendar) -> Int {
        let c = mondayCalendar(cal)
        guard var week = c.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let first = completions.min() ?? now
        var streak = 0
        for idx in 0..<520 {
            if week.end <= first { break }
            let need = weekRequirement(week, target: target, skipped: skipped, calendar: c)
            let got = doneCount(inWeekOf: week.start, completions: completions, calendar: c)
            if need > 0 && got >= need { streak += 1 }
            else if need > 0 && idx > 0 { break }
            guard let prev = c.date(byAdding: .day, value: -7, to: week.start),
                  let w = c.dateInterval(of: .weekOfYear, for: prev) else { break }
            week = w
        }
        return streak
    }

    /// Meilleure serie depuis `since`.
    static func bestStreak(completions: [Date], activeDays: Set<Int>, weeklyTarget: Int, skipped: Set<String>,
                           since: Date, now: Date = .now, calendar cal: Calendar = .current) -> Int {
        guard let firstDone = completions.min() else { return 0 }
        let start = cal.startOfDay(for: min(since, firstDone))
        let today = cal.startOfDay(for: now)
        var run = 0, best = 0
        if weeklyTarget > 0 {
            let c = mondayCalendar(cal)
            guard var week = c.dateInterval(of: .weekOfYear, for: start) else { return 0 }
            while week.start <= today {
                let need = weekRequirement(week, target: weeklyTarget, skipped: skipped, calendar: c)
                let got = doneCount(inWeekOf: week.start, completions: completions, calendar: c)
                if need > 0 && got >= need { run += 1; best = max(best, run) }
                else if need > 0 && week.end <= today { run = 0 }
                guard let nx = c.date(byAdding: .day, value: 7, to: week.start), let w = c.dateInterval(of: .weekOfYear, for: nx) else { break }
                week = w
            }
            return best
        }
        let active = activeDays.isEmpty ? Set(1...7) : activeDays
        let doneDays = Set(completions.map { cal.startOfDay(for: $0) })
        var d = start, n = 0
        while d <= today, n < 3660 {
            let due = active.contains(cal.component(.weekday, from: d)) && !skipped.contains(ProductivityRules.dayKey(d, calendar: cal))
            if due {
                if doneDays.contains(d) { run += 1; best = max(best, run) }
                else if d != today { run = 0 }
            }
            guard let nx = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = nx; n += 1
        }
        return best
    }

    /// Taux de reussite sur les `days` derniers jours (jours dus seulement, jours
    /// sautes exclus, aujourd'hui compte seulement s'il est fait). nil = rien de du.
    static func completionRate(completions: [Date], activeDays: Set<Int>, weeklyTarget: Int, skipped: Set<String>,
                               since: Date, days: Int = 30, now: Date = .now, calendar cal: Calendar = .current) -> Double? {
        let today = cal.startOfDay(for: now)
        let from = max(cal.startOfDay(for: since), cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today)
        let doneDays = Set(completions.map { cal.startOfDay(for: $0) })
        if weeklyTarget > 0 {
            let c = mondayCalendar(cal)
            guard var week = c.dateInterval(of: .weekOfYear, for: from) else { return nil }
            var due = 0, met = 0
            while week.start <= today {
                let need = weekRequirement(week, target: weeklyTarget, skipped: skipped, calendar: c)
                let got = doneCount(inWeekOf: week.start, completions: completions, calendar: c)
                let finished = week.end <= today
                if need > 0 && (finished || got >= need) { due += 1; if got >= need { met += 1 } }
                guard let nx = c.date(byAdding: .day, value: 7, to: week.start), let w = c.dateInterval(of: .weekOfYear, for: nx) else { break }
                week = w
            }
            return due == 0 ? nil : Double(met) / Double(due)
        }
        let active = activeDays.isEmpty ? Set(1...7) : activeDays
        var due = 0, done = 0, d = from
        while d <= today {
            let isDue = active.contains(cal.component(.weekday, from: d)) && !skipped.contains(ProductivityRules.dayKey(d, calendar: cal))
            let isDone = doneDays.contains(d)
            if isDue && !(d == today && !isDone) { due += 1; if isDone { done += 1 } }
            guard let nx = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = nx
        }
        return due == 0 ? nil : Double(done) / Double(due)
    }

    // MARK: Lecture d'une habitude

    static func completionDates(_ h: Habit) -> [Date] { h.completions.map(\.date) }

    static func streak(_ h: Habit, now: Date = .now) -> Int {
        streak(completions: completionDates(h), activeDays: h.activeDays, weeklyTarget: h.weeklyTarget,
               skipped: skipped(h.skippedDaysRaw), now: now)
    }

    static func isDueToday(_ h: Habit, now: Date = .now) -> Bool {
        guard !h.isPending, !h.isArchived else { return false }
        return isDueToday(activeDays: h.activeDays, weeklyTarget: h.weeklyTarget, skipped: skipped(h.skippedDaysRaw),
                          completions: completionDates(h), now: now)
    }

    static func hasTarget(_ h: Habit) -> Bool { h.targetKind > 0 && h.targetValue > 0 }

    static func unitLabel(_ h: Habit) -> String {
        if h.targetKind == 2 { return "min" }
        return h.targetUnit.trimmingCharacters(in: .whitespaces)
    }

    /// Progression du jour (une completion du jour = objectif atteint, y compris
    /// depuis le widget qui ne connait pas les quantites).
    static func progress(_ h: Habit, now: Date = .now, calendar cal: Calendar = .current) -> Double {
        let today = ProductivityRules.dayKey(now, calendar: cal)
        let stored = h.progressDay == today ? h.progressValue : 0
        if let c = h.completions.first(where: { cal.isDate($0.date, inSameDayAs: now) }) {
            return max(stored, c.value, h.targetValue)
        }
        return stored
    }

    /// Pas d'un appui: 1 pour une quantite, 5 min pour une duree.
    static func step(_ h: Habit) -> Double { h.targetKind == 2 ? 5 : 1 }

    /// Ajoute (ou retire) de la progression du jour. La completion n'existe que
    /// quand l'objectif est atteint: le widget et la serie restent justes.
    @discardableResult
    static func addProgress(_ h: Habit, amount: Double, now: Date = .now, ctx: ModelContext?,
                            calendar cal: Calendar = .current) -> Bool {
        let today = ProductivityRules.dayKey(now, calendar: cal)
        let current = progress(h, now: now, calendar: cal)
        h.progressDay = today
        h.progressValue = max(0, current + amount)
        let existing = h.completions.filter { cal.isDate($0.date, inSameDayAs: now) }
        if h.progressValue >= h.targetValue {
            if let c = existing.first { c.value = h.progressValue }
            else {
                let c = HabitCompletion(date: now); c.value = h.progressValue
                h.completions.append(c)
            }
            return true
        }
        let ids = Set(existing.map(\.persistentModelID))
        h.completions.removeAll { ids.contains($0.persistentModelID) }
        existing.forEach { ctx?.delete($0) }
        return false
    }

    /// Coche ou decoche un jour passe (rattrapage). Refuse le futur.
    @discardableResult
    static func setDone(_ h: Habit, on day: Date, done: Bool, now: Date = .now, ctx: ModelContext?,
                        calendar cal: Calendar = .current) -> Bool {
        guard cal.startOfDay(for: day) <= cal.startOfDay(for: now) else { return false }
        let existing = h.completions.filter { cal.isDate($0.date, inSameDayAs: day) }
        if done {
            guard existing.isEmpty else { return true }
            // Midi du jour: aucun changement d'heure ne le fait glisser d'un jour.
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            let at = cal.isDate(day, inSameDayAs: now) ? now : noon
            let c = HabitCompletion(date: at); c.value = hasTarget(h) ? h.targetValue : 0
            h.completions.append(c)
            if cal.isDate(day, inSameDayAs: now), hasTarget(h) {
                h.progressDay = ProductivityRules.dayKey(now, calendar: cal); h.progressValue = h.targetValue
            }
        } else {
            let ids = Set(existing.map(\.persistentModelID))
            h.completions.removeAll { ids.contains($0.persistentModelID) }
            existing.forEach { ctx?.delete($0) }
            if cal.isDate(day, inSameDayAs: now) { h.progressValue = 0 }
        }
        return true
    }
}

// MARK: - Forêt : regles

enum FocusPhase: String {
    case focus, shortBreak, longBreak
    var label: String {
        switch self {
        case .focus: return "CONCENTRATION"
        case .shortBreak: return "PAUSE COURTE"
        case .longBreak: return "PAUSE LONGUE"
        }
    }
}

struct FocusConfig: Equatable {
    var focus = 25, shortBreak = 5, longBreak = 15, cycleLength = 4
}

enum FocusRules {
    enum Outcome: String { case completed, interrupted, abandoned }
    enum Away: Equatable { case keepGoing, finishedWhileAway, broken }

    /// Plus de 10 s hors de l'app pendant une phase de concentration la casse.
    /// Verrouiller l'ecran est tolere (detecte quand l'iPhone a un code).
    static let graceSeconds: TimeInterval = 10

    static func phaseAfter(_ p: FocusPhase, focusDoneInCycle: Int, config: FocusConfig) -> (phase: FocusPhase, minutes: Int, focusDoneInCycle: Int) {
        switch p {
        case .focus:
            let n = focusDoneInCycle + 1
            if n >= max(config.cycleLength, 1) { return (.longBreak, config.longBreak, 0) }
            return (.shortBreak, config.shortBreak, n)
        case .shortBreak, .longBreak:
            return (.focus, config.focus, focusDoneInCycle)
        }
    }

    static func awayOutcome(leftAt: Date, returnedAt: Date, phaseEnd: Date, deviceLocked: Bool,
                            grace: TimeInterval = graceSeconds) -> Away {
        let awayBeforeEnd = min(returnedAt, phaseEnd).timeIntervalSince(leftAt)
        if !deviceLocked && awayBeforeEnd > grace { return .broken }
        return returnedAt >= phaseEnd ? .finishedWhileAway : .keepGoing
    }

    /// Stade de l'arbre: 0 graine, 1 pousse, 2 jeune plant, 3 arbuste, 4 arbre.
    static func growthStage(progress: Double) -> Int {
        Int((min(max(progress, 0), 1) * 4).rounded(.down))
    }

    static func phaseKey(start: Date) -> String { String(Int(start.timeIntervalSince1970)) }

    static func shouldRecord(key: String, existing: Set<String>) -> Bool { !key.isEmpty && !existing.contains(key) }

    struct TagStat: Equatable {
        let tag: String
        var completed = 0
        var failed = 0
        var seconds = 0
        var minutes: Int { seconds / 60 }
        var successRate: Double { completed + failed == 0 ? 0 : Double(completed) / Double(completed + failed) }
    }

    static let noTag = "Sans tag"

    /// Stats par tag: sessions reussies, echouees (interrompues ou abandonnees) et
    /// minutes REELLEMENT concentrees. Trie par minutes.
    static func stats(_ rows: [(tag: String, outcome: String, seconds: Int)]) -> [TagStat] {
        var by: [String: TagStat] = [:]
        for r in rows {
            let t = r.tag.trimmingCharacters(in: .whitespaces).isEmpty ? noTag : r.tag
            var s = by[t] ?? TagStat(tag: t)
            if r.outcome == Outcome.completed.rawValue { s.completed += 1 } else { s.failed += 1 }
            s.seconds += max(0, r.seconds)
            by[t] = s
        }
        return by.values.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.tag < $1.tag }
    }

    static func stats(_ sessions: [FocusSession]) -> [TagStat] {
        stats(sessions.map { ($0.tag, $0.outcome, $0.focusedSeconds) })
    }
}

// MARK: - Notio : Markdown

enum MDBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(text: String, indent: Int)
    case numbered(number: Int, text: String)
    case task(done: Bool, text: String, line: Int)
    case quote(text: String)
    case paragraph(text: String)
    case rule
}

enum Markdown {
    static func blocks(_ s: String) -> [MDBlock] {
        var out: [MDBlock] = []
        for (idx, line) in s.components(separatedBy: "\n").enumerated() {
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t == "---" || t == "***" || t == "___" { out.append(.rule); continue }
            if t.hasPrefix("#") {
                let hashes = t.prefix(while: { $0 == "#" }).count
                let rest = t.dropFirst(hashes)
                if hashes <= 6, rest.hasPrefix(" ") {
                    out.append(.heading(level: min(hashes, 3), text: rest.trimmingCharacters(in: .whitespaces))); continue
                }
            }
            if let f = t.first, "-*+".contains(f), t.dropFirst().hasPrefix(" ") {
                let rest = t.dropFirst(2)
                if rest.hasPrefix("[ ]") || rest.hasPrefix("[x]") || rest.hasPrefix("[X]") {
                    out.append(.task(done: !rest.hasPrefix("[ ]"), text: rest.dropFirst(3).trimmingCharacters(in: .whitespaces), line: idx))
                } else {
                    out.append(.bullet(text: rest.trimmingCharacters(in: .whitespaces), indent: indent))
                }
                continue
            }
            let digits = t.prefix(while: { $0.isNumber })
            if !digits.isEmpty, let n = Int(digits) {
                let rest = t.dropFirst(digits.count)
                if let f = rest.first, f == "." || f == ")", rest.dropFirst().hasPrefix(" ") {
                    out.append(.numbered(number: n, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))); continue
                }
            }
            if t.hasPrefix(">") { out.append(.quote(text: t.dropFirst().trimmingCharacters(in: .whitespaces))); continue }
            out.append(.paragraph(text: t))
        }
        return out
    }

    /// Coche ou decoche la case de la ligne `line` (depuis l'apercu).
    static func togglingTask(_ s: String, line: Int) -> String {
        var lines = s.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return s }
        let l = lines[line]
        if let r = l.range(of: "[ ]") { lines[line] = l.replacingCharacters(in: r, with: "[x]") }
        else if let r = l.range(of: "[x]") ?? l.range(of: "[X]") { lines[line] = l.replacingCharacters(in: r, with: "[ ]") }
        return lines.joined(separator: "\n")
    }

    /// Gras, italique, liens et [[liens internes]] d'une ligne.
    static func inline(_ text: String) -> AttributedString {
        let linked = NoteLinks.linkify(text)
        return (try? AttributedString(markdown: linked,
                                      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// Entoure la selection (offsets en caracteres) d'un marqueur (** ou _).
    /// Sans selection: insere la paire et place le curseur au milieu.
    static func wrapping(_ s: String, selection: Range<Int>, marker: String) -> (text: String, selection: Range<Int>) {
        let chars = Array(s)
        let lo = min(max(selection.lowerBound, 0), chars.count), hi = min(max(selection.upperBound, lo), chars.count)
        let m = Array(marker)
        let text = String(chars[..<lo] + m + chars[lo..<hi] + m + chars[hi...])
        return (text, (lo + m.count)..<(hi + m.count))
    }

    /// Ajoute un prefixe (« # », « - », « - [ ] ») au debut des lignes de la
    /// selection, ou le retire s'il y est deja sur toutes.
    static func prefixing(_ s: String, selection: Range<Int>, prefix: String) -> (text: String, selection: Range<Int>) {
        var lines = s.components(separatedBy: "\n").map { Array($0) }
        let lo = max(selection.lowerBound, 0), hi = max(selection.upperBound, lo)
        var offset = 0, affected: [Int] = []
        for (i, l) in lines.enumerated() {
            let start = offset, end = offset + l.count
            if (start <= hi && end >= lo) { affected.append(i) }
            offset = end + 1
        }
        if affected.isEmpty, !lines.isEmpty { affected = [lines.count - 1] }
        let p = Array(prefix)
        let allHave = affected.allSatisfy { lines[$0].starts(with: p) }
        var delta = 0
        for i in affected {
            if allHave { lines[i].removeFirst(p.count); delta -= p.count }
            else if !lines[i].starts(with: p) { lines[i] = p + lines[i]; delta += p.count }
        }
        let text = lines.map { String($0) }.joined(separator: "\n")
        let end = min(max(hi + delta, 0), text.count)
        return (text, end..<end)
    }

    /// Texte brut pour l'export PDF et les extraits.
    static func plain(_ text: String) -> String {
        String(inline(text).characters)
    }
}

enum NoteLinks {
    static let scheme = "lifeos-note"

    /// Cibles des [[liens]] du texte, sans doublon (casse et accents ignores).
    static func targets(in body: String) -> [String] {
        var out: [String] = [], seen = Set<String>()
        var rest = Substring(body)
        while let open = rest.range(of: "[[") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "]]") else { break }
            let inner = after[..<close.lowerBound]
            if !inner.contains("[") && !inner.contains("\n") {
                let t = inner.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, seen.insert(TextFold.fold(t)).inserted { out.append(t) }
                rest = after[close.upperBound...]
            } else {
                rest = after
            }
        }
        return out
    }

    static func url(for title: String) -> URL? {
        var c = URLComponents()
        c.scheme = scheme; c.host = "open"
        c.queryItems = [URLQueryItem(name: "t", value: title)]
        return c.url
    }

    static func title(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "t" }?.value
    }

    /// [[Titre]] -> [Titre](lifeos-note://open?t=Titre) pour le rendu Markdown.
    static func linkify(_ text: String) -> String {
        var out = "", rest = Substring(text)
        while let open = rest.range(of: "[[") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "]]") else { break }
            let inner = after[..<close.lowerBound]
            let t = inner.trimmingCharacters(in: .whitespaces)
            if !inner.contains("["), !inner.contains("\n"), !t.isEmpty, let u = url(for: t) {
                out += rest[..<open.lowerBound] + "[\(t)](\(u.absoluteString))"
                rest = after[close.upperBound...]
            } else {
                out += rest[..<open.upperBound]
                rest = after
            }
        }
        return out + rest
    }

    /// Indices des notes qui pointent vers `title` (la note elle-meme exclue par l'appelant).
    static func backlinks(to title: String, in notes: [(title: String, body: String)]) -> [Int] {
        let key = TextFold.fold(title.trimmingCharacters(in: .whitespaces))
        guard !key.isEmpty else { return [] }
        return notes.indices.filter { i in targets(in: notes[i].body).contains { TextFold.fold($0) == key } }
    }

    static func resolve(_ target: String, among titles: [String]) -> Int? {
        let key = TextFold.fold(target.trimmingCharacters(in: .whitespaces))
        return titles.firstIndex { TextFold.fold($0.trimmingCharacters(in: .whitespaces)) == key }
    }
}

enum NoteHistory {
    struct Version: Codable, Equatable {
        var savedAt: Date
        var title: String
        var body: String
        var tags: String
    }

    /// Nombre de versions gardees par note.
    static let limit = 20

    static func decode(_ raw: String) -> [Version] {
        guard let d = raw.data(using: .utf8), !raw.isEmpty else { return [] }
        return (try? JSONDecoder().decode([Version].self, from: d)) ?? []
    }

    static func encode(_ v: [Version]) -> String {
        guard let d = try? JSONEncoder().encode(v) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    /// Garde l'ancien contenu avant de l'ecraser: rien si identique a la derniere
    /// version, les plus anciennes sortent au-dela de `limit`.
    static func pushing(_ old: Version, onto raw: String, limit: Int = limit) -> String {
        var v = decode(raw)
        if let last = v.last, last.title == old.title, last.body == old.body, last.tags == old.tags { return raw }
        if old.title.isEmpty && old.body.isEmpty { return raw }
        v.append(old)
        if v.count > limit { v.removeFirst(v.count - limit) }
        return encode(v)
    }

    /// Enregistre de nouvelles valeurs dans une note en versionnant l'ancienne.
    /// Rend false si rien n'a change.
    @discardableResult
    static func save(_ n: Note, title: String, body: String, tags: String, folder: String, now: Date = .now) -> Bool {
        let folderNorm = NoteFolders.normalize(folder)
        guard n.title != title || n.body != body || n.tags != tags || n.folder != folderNorm else { return false }
        if n.title != title || n.body != body || n.tags != tags {
            n.historyRaw = pushing(Version(savedAt: n.modified ?? n.created, title: n.title, body: n.body, tags: n.tags), onto: n.historyRaw)
        }
        n.title = title; n.body = body; n.tags = tags; n.folder = folderNorm
        n.modified = now
        return true
    }

    /// Restaure une version: le contenu actuel devient lui-meme une version.
    static func restore(_ n: Note, to v: Version, now: Date = .now) {
        save(n, title: v.title, body: v.body, tags: v.tags, folder: n.folder, now: now)
    }
}

enum NoteFolders {
    static func normalize(_ path: String) -> String {
        path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "/")
    }

    /// Tous les dossiers et leurs parents (« A », « A/B »), tries.
    static func folders(_ paths: [String]) -> [String] {
        var s = Set<String>()
        for p in paths.map(normalize) where !p.isEmpty {
            var acc: [String] = []
            for part in p.split(separator: "/") { acc.append(String(part)); s.insert(acc.joined(separator: "/")) }
        }
        return s.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func contains(_ path: String, folder: String) -> Bool {
        let p = normalize(path), f = normalize(folder)
        return f.isEmpty || p == f || p.hasPrefix(f + "/")
    }
}

enum NoteSearch {
    /// Tous les mots de la requete, sans accents ni casse, dans le titre, le texte,
    /// les etiquettes ou le dossier.
    static func matches(title: String, body: String, tags: String, folder: String, query: String) -> Bool {
        let words = TextFold.fold(query).split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return true }
        let hay = TextFold.fold([title, body, tags, folder].joined(separator: " "))
        return words.allSatisfy { hay.contains($0) }
    }

    /// Extrait autour de la premiere occurrence d'un mot de la requete.
    static func snippet(_ body: String, query: String, radius: Int = 40) -> String? {
        guard let w = TextFold.fold(query).split(whereSeparator: { $0.isWhitespace }).first.map(String.init) else { return nil }
        let chars = Array(body)
        // Le pliage garde la longueur pour le texte latin (é -> e): on cherche dans
        // le texte plie et on decoupe l'original. Sinon on decoupe le texte plie.
        let foldedChars = Array(TextFold.fold(body))
        let source = foldedChars.count == chars.count ? chars : foldedChars
        guard let r = String(foldedChars).range(of: w) else { return nil }
        let i = String(foldedChars).distance(from: String(foldedChars).startIndex, to: r.lowerBound)
        let a = max(0, i - radius), b = min(source.count, i + w.count + radius)
        let core = String(source[a..<b]).replacingOccurrences(of: "\n", with: " ")
        return (a > 0 ? "…" : "") + core + (b < source.count ? "…" : "")
    }
}

enum NoteExport {
    static func fileName(_ title: String, ext: String) -> String {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return (safe.isEmpty ? "Note" : String(safe.prefix(80))) + "." + ext
    }

    /// Markdown exporte: titre en # , etiquettes et dossier en en-tete lisible.
    static func markdown(title: String, body: String, tags: String, folder: String) -> String {
        var out = "# \(title.isEmpty ? "Sans titre" : title)\n\n"
        let tagList = TagList.parse(tags)
        if !folder.isEmpty || !tagList.isEmpty {
            var meta: [String] = []
            if !folder.isEmpty { meta.append("Dossier : \(folder)") }
            if !tagList.isEmpty { meta.append(tagList.map { "#\($0)" }.joined(separator: " ")) }
            out += meta.joined(separator: " · ") + "\n\n"
        }
        out += body
        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }
}
