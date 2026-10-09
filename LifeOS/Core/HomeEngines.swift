import Foundation

// Regles pures de l'accueil (lot 8) : « Maintenant » et « 3 priorites ».
// Elles travaillent sur des valeurs simples, pas sur SwiftData, pour etre testees
// sans base et appelees sans cout dans `body`.

// MARK: - Maintenant

/// Une chose a faire, quelle que soit sa source.
struct NowCandidate: Identifiable, Equatable {
    enum Kind: Int, Comparable {
        // L'ordre sert de departage a heure egale : tache, habitude, agenda, evenement.
        case task = 0, habit, agenda, event
        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }
    let id: String
    let kind: Kind
    let title: String
    /// Heure prevue aujourd'hui (ou echeance pour une tache). nil = sans heure.
    let time: Date?
    /// Tache : echeance passee (voir `ProductivityRules.isLate`).
    var overdue: Bool = false
    /// Tache : 0 normale, 1 importante, 2 urgente.
    var priority: Int = 0
    /// Une heure precise compte (pas « toute la journee »).
    var hasTime: Bool = true
}

enum HomeNowEngine {
    /// Fenetre « c'est maintenant » : ce qui commence dans l'heure.
    static let soonWindow: TimeInterval = 60 * 60
    /// Une habitude ou un rappel deja passe aujourd'hui reste « maintenant » 2 h.
    static let lateWindow: TimeInterval = 2 * 60 * 60

    /// Ordre des propositions :
    /// 1. taches en retard (urgence d'abord, puis la plus ancienne) ;
    /// 2. ce qui est « maintenant » : heure dans l'heure qui vient, ou passee depuis
    ///    moins de 2 h et pas encore fait (habitude, rappel), par heure ;
    /// 3. le reste de la journee avec une heure, du plus proche au plus lointain ;
    /// 4. sans heure : taches du jour (urgence d'abord), agenda, habitudes.
    /// A heure egale : tache, habitude, agenda, evenement.
    static func ordered(_ items: [NowCandidate], now: Date) -> [NowCandidate] {
        func tier(_ c: NowCandidate) -> Int {
            if c.kind == .task && c.overdue { return 0 }
            guard c.hasTime, let t = c.time else { return 3 }
            let delta = t.timeIntervalSince(now)
            if delta <= soonWindow && delta >= -lateWindow { return 1 }
            if delta > soonWindow { return 2 }
            return 4   // passe depuis longtemps sans etre une tache en retard : en dernier
        }
        return items.sorted { a, b in
            let ta = tier(a), tb = tier(b)
            if ta != tb { return ta < tb }
            switch ta {
            case 0:
                if a.priority != b.priority { return a.priority > b.priority }
                return (a.time ?? .distantFuture) < (b.time ?? .distantFuture)
            case 1, 2, 4:
                let x = a.time ?? .distantFuture, y = b.time ?? .distantFuture
                if x != y { return x < y }
                return a.kind < b.kind
            default:
                if a.kind != b.kind { return a.kind < b.kind }
                if a.priority != b.priority { return a.priority > b.priority }
                return a.title.localizedCompare(b.title) == .orderedAscending
            }
        }
    }

    /// La premiere proposition qui n'a pas ete passee (« Autre chose »).
    static func current(_ items: [NowCandidate], skipped: Set<String>, now: Date) -> NowCandidate? {
        ordered(items, now: now).first { !skipped.contains($0.id) }
    }
}

// MARK: - Liste par jour (priorites epinglees, propositions passees)

/// Une liste d'identifiants valable pour UN jour : "aaaa-mm-jj|a,b,c".
/// Le lendemain elle se lit vide, sans job de nettoyage.
struct DayScopedList: Equatable {
    var day: String
    var ids: [String]

    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func read(_ raw: String, today: Date, calendar: Calendar = .current) -> DayScopedList {
        let key = dayKey(today, calendar: calendar)
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, String(parts[0]) == key else { return DayScopedList(day: key, ids: []) }
        var seen = Set<String>()
        let ids = parts[1].split(separator: ",").map(String.init).filter { !$0.isEmpty && seen.insert($0).inserted }
        return DayScopedList(day: key, ids: ids)
    }

    var raw: String { day + "|" + ids.joined(separator: ",") }

    mutating func add(_ id: String, cap: Int = .max) -> Bool {
        guard !ids.contains(id), ids.count < cap else { return false }
        ids.append(id)
        return true
    }

    mutating func remove(_ id: String) { ids.removeAll { $0 == id } }
}

// MARK: - 3 priorites

/// Une tache vue par la regle des priorites.
struct PriorityCandidate: Equatable {
    let uid: String
    let title: String
    let priority: Int
    let due: Date?
    let done: Bool
}

struct PrioritySuggestion: Equatable {
    let uid: String
    let title: String
    let reason: String
}

enum HomePriorityEngine {
    static let maxPinned = 3
    static let pinnedKey = "homePriorities"
    static let ignoredKey = "homePrioritiesIgnored"

    /// Propose de quoi completer les 3 priorites du jour.
    /// Candidates, dans cet ordre : en retard, urgentes, prevues aujourd'hui,
    /// importantes sans date. A rang egal : urgence, puis echeance la plus proche.
    /// Jamais une tache deja epinglee ou ignoree aujourd'hui.
    static func suggestions(_ tasks: [PriorityCandidate], pinned: [String], ignored: [String],
                            now: Date, calendar cal: Calendar = .current) -> [PrioritySuggestion] {
        let slots = max(0, maxPinned - pinned.count)
        guard slots > 0 else { return [] }
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let excluded = Set(pinned).union(ignored)

        struct Scored { let c: PriorityCandidate; let rank: Int; let reason: String }
        var pool: [Scored] = []
        for t in tasks where !t.done && !t.uid.isEmpty && !excluded.contains(t.uid) {
            let late = t.due.map { ProductivityRules.isLate($0, now: now, calendar: cal) } ?? false
            let dueToday = t.due.map { $0 >= today && $0 < tomorrow } ?? false
            if late { pool.append(Scored(c: t, rank: 0, reason: "En retard")) }
            else if t.priority >= 2 { pool.append(Scored(c: t, rank: 1, reason: dueToday ? "Urgente, prévue aujourd'hui" : "Urgente")) }
            else if dueToday { pool.append(Scored(c: t, rank: 2, reason: t.priority == 1 ? "Importante, prévue aujourd'hui" : "Prévue aujourd'hui")) }
            else if t.priority == 1 && t.due == nil { pool.append(Scored(c: t, rank: 3, reason: "Importante, sans date")) }
        }
        pool.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.c.priority != b.c.priority { return a.c.priority > b.c.priority }
            switch (a.c.due, b.c.due) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.c.title.localizedCompare(b.c.title) == .orderedAscending
            }
        }
        return pool.prefix(slots).map { PrioritySuggestion(uid: $0.c.uid, title: $0.c.title, reason: $0.reason) }
    }
}
