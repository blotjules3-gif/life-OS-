import Foundation
import SwiftData

// MARK: - Recherche globale : outils + contenus
//
// Deux sources :
// - les outils des espaces (memes champs que l'ancienne recherche d'outils :
//   titre affiche, nom d'origine, ancien nom descriptif, sous-titre, espace) ;
// - les contenus SwiftData, lus par predicat `localizedStandardContains`
//   (insensible a la casse et aux accents), avec une limite par type.
// Le classement est fait ici, en fonctions pures testables.

enum SearchKind: String, CaseIterable, Hashable {
    case tool, task, note, habit, contact, document, dream, food, transaction, trip

    /// Titre du groupe dans les resultats.
    var groupTitle: String {
        switch self {
        case .tool:        return "Outils"
        case .task:        return "Tâches"
        case .note:        return "Notes"
        case .habit:       return "Habitudes"
        case .contact:     return "Contacts"
        case .document:    return "Documents"
        case .dream:       return "Rêves"
        case .food:        return "Repas"
        case .transaction: return "Dépenses et revenus"
        case .trip:        return "Voyages"
        }
    }

    var icon: String {
        switch self {
        case .tool:        return "square.grid.2x2"
        case .task:        return "checklist"
        case .note:        return "note.text"
        case .habit:       return "square.grid.3x3.fill"
        case .contact:     return "person.crop.circle"
        case .document:    return "lock.doc.fill"
        case .dream:       return "cloud.moon.fill"
        case .food:        return "fork.knife"
        case .transaction: return "eurosign.circle"
        case .trip:        return "airplane"
        }
    }

    /// Outil qui contient ce type de contenu (`defaultTitle` dans CategoryHub).
    var home: (AppCategory, String)? {
        switch self {
        case .tool:        return nil
        case .task:        return (.productivity, "Todoo")
        case .note:        return (.productivity, "Notio")
        case .habit:       return (.productivity, "Habitly")
        case .contact:     return (.social, "Dexo")
        case .document:    return (.admin, "Digicoffre")
        case .dream:       return (.sleep, "Awaken")
        case .food:        return (.nutrition, "Yumzio")
        case .transaction: return (.finance, "Bankino")
        case .trip:        return (.travel, "TripUp")
        }
    }

    /// Ordre des groupes : les outils d'abord, puis ce qu'on cherche le plus souvent.
    static let displayOrder: [SearchKind] = [.tool, .task, .note, .habit, .contact, .document, .trip, .dream, .food, .transaction]
}

struct SearchHit: Identifiable, Hashable {
    let id: String
    let kind: SearchKind
    let title: String
    let subtitle: String
    let category: AppCategory
    let score: Int
    /// Outil vise (pour `.tool`, ou l'outil d'origine d'un contenu).
    let toolCategory: AppCategory?
    let toolName: String?
    /// Contenu precis, quand il en a un.
    let record: SearchRecordRef?
    let icon: String
}

/// Champs d'un outil utilises pour la correspondance (independant des vues).
struct ToolSearchEntry: Equatable {
    let category: AppCategory
    let categoryTitle: String
    let title: String
    let defaultTitle: String
    let alias: String
    let subtitle: String
    let icon: String
}

enum SearchIndex {
    static let perTypeLimit = 8
    static let foodWindowDays = 90
    static let transactionWindowDays = 365

    /// Minuscules, sans accents, espaces reduits.
    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Note de correspondance d'un champ : 100 egal, 80 debut, 60 debut d'un mot,
    /// 40 contenu ailleurs, nil absent. Chaque mot de la requete doit etre trouve.
    static func fieldScore(query: String, field: String) -> Int? {
        let q = normalize(query), f = normalize(field)
        guard !q.isEmpty, !f.isEmpty else { return nil }
        if f == q { return 100 }
        if f.hasPrefix(q) { return 80 }
        let words = f.split(separator: " ").map(String.init)
        if words.contains(where: { $0.hasPrefix(q) }) { return 60 }
        if f.contains(q) { return 40 }
        // Requete en plusieurs mots : tous presents, dans n'importe quel ordre.
        let parts = q.split(separator: " ").map(String.init)
        if parts.count > 1, parts.allSatisfy({ f.contains($0) }) { return 30 }
        return nil
    }

    /// Meilleure note parmi des champs ponderes (poids en pourcentage).
    static func score(query: String, fields: [(String, Int)]) -> Int? {
        var best: Int?
        for (field, weight) in fields {
            guard let s = fieldScore(query: query, field: field) else { continue }
            let w = s * weight / 100
            if w > (best ?? -1) { best = w }
        }
        return best
    }

    // MARK: Outils

    @MainActor
    static func toolCatalog() -> [ToolSearchEntry] {
        AppCategory.allCases.flatMap { cat in
            cat.tools.map {
                ToolSearchEntry(category: cat, categoryTitle: cat.title, title: $0.title,
                                defaultTitle: $0.defaultTitle, alias: $0.alias, subtitle: $0.subtitle, icon: $0.icon)
            }
        }
    }

    /// Outils qui correspondent, les meilleurs d'abord. Un nom vaut plus qu'un mot
    /// du sous-titre.
    static func toolHits(_ query: String, in catalog: [ToolSearchEntry], limit: Int = 12) -> [SearchHit] {
        guard !normalize(query).isEmpty else { return [] }
        let hits: [SearchHit] = catalog.compactMap { e in
            guard let s = score(query: query, fields: [(e.title, 100), (e.defaultTitle, 100), (e.alias, 90),
                                                        (e.categoryTitle, 60), (e.subtitle, 50)]) else { return nil }
            return SearchHit(id: "tool:\(e.category.rawValue):\(e.defaultTitle)", kind: .tool, title: e.title,
                             subtitle: e.alias.isEmpty ? e.categoryTitle : "\(e.alias) · \(e.categoryTitle)",
                             category: e.category, score: s, toolCategory: e.category, toolName: e.defaultTitle,
                             record: nil, icon: e.icon)
        }
        return Array(sorted(hits).prefix(limit))
    }

    static func sorted(_ hits: [SearchHit]) -> [SearchHit] {
        hits.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Groupes dans l'ordre d'affichage, groupes vides retires.
    static func grouped(_ hits: [SearchHit]) -> [(kind: SearchKind, hits: [SearchHit])] {
        let byKind = Dictionary(grouping: hits, by: \.kind)
        return SearchKind.displayOrder.compactMap { k in
            guard let list = byKind[k], !list.isEmpty else { return nil }
            return (k, sorted(list))
        }
    }

    /// Repas : le meme aliment revient tous les jours. On garde le plus recent par nom.
    static func dedupeByTitle(_ hits: [SearchHit]) -> [SearchHit] {
        var seen = Set<String>()
        return hits.filter { seen.insert(normalize($0.title)).inserted }
    }

    // MARK: Contenus

    @MainActor
    static func contentHits(_ rawQuery: String, in ctx: ModelContext, now: Date = .now) -> [SearchHit] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        var out: [SearchHit] = []
        let fetchCap = perTypeLimit * 3

        func run<T: PersistentModel>(_ d: FetchDescriptor<T>, _ map: (T) -> SearchHit?) -> [SearchHit] {
            do { return try ctx.fetch(d).compactMap(map) }
            catch {
                AppLog.data.error("recherche \(String(describing: T.self), privacy: .public): \(error.localizedDescription, privacy: .public)")
                return []
            }
        }
        func keep(_ hits: [SearchHit]) { out += Array(sorted(hits).prefix(perTypeLimit)) }
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateStyle = .medium
        df.timeStyle = .none

        // Taches
        var td = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.title.localizedStandardContains(q) || $0.notes.localizedStandardContains(q) })
        td.fetchLimit = fetchCap
        keep(run(td) { t in
            guard let s = score(query: q, fields: [(t.title, 100), (t.notes, 60)]) else { return nil }
            var sub = t.done ? "Faite" : (t.due.map { "Pour le \(df.string(from: $0))" } ?? "Sans date")
            if !t.project.isEmpty { sub += " · \(t.project)" }
            return hit(.task, t, title: t.title.isEmpty ? "Sans titre" : t.title, subtitle: sub, score: s - (t.done ? 15 : 0))
        })

        // Notes
        var nd = FetchDescriptor<Note>(predicate: #Predicate { $0.title.localizedStandardContains(q) || $0.body.localizedStandardContains(q) })
        nd.fetchLimit = fetchCap
        keep(run(nd) { n in
            guard let s = score(query: q, fields: [(n.title, 100), (n.body, 60), (n.tags, 50)]) else { return nil }
            let firstLine = n.body.split(separator: "\n").first.map(String.init) ?? ""
            return hit(.note, n, title: n.title.isEmpty ? "Sans titre" : n.title,
                       subtitle: firstLine.isEmpty ? df.string(from: n.created) : String(firstLine.prefix(60)), score: s)
        })

        // Habitudes
        var hd = FetchDescriptor<Habit>(predicate: #Predicate { !$0.isArchived && $0.name.localizedStandardContains(q) })
        hd.fetchLimit = fetchCap
        keep(run(hd) { h in
            guard let s = score(query: q, fields: [(h.name, 100)]) else { return nil }
            return hit(.habit, h, title: h.name, subtitle: "Habitude", score: s)
        })

        // Contacts (Dexo)
        var cd = FetchDescriptor<Contact>(predicate: #Predicate { $0.name.localizedStandardContains(q) || $0.notes.localizedStandardContains(q) })
        cd.fetchLimit = fetchCap
        keep(run(cd) { c in
            guard let s = score(query: q, fields: [(c.name, 100), (c.notes, 50)]) else { return nil }
            return hit(.contact, c, title: c.name, subtitle: c.lastSeen.map { "Vu le \(df.string(from: $0))" } ?? "Contact", score: s)
        })

        // Documents (Digicoffre)
        var dd = FetchDescriptor<DocVault>(predicate: #Predicate {
            $0.title.localizedStandardContains(q) || $0.category.localizedStandardContains(q) || $0.note.localizedStandardContains(q)
        })
        dd.fetchLimit = fetchCap
        keep(run(dd) { d in
            guard let s = score(query: q, fields: [(d.title, 100), (d.category, 60), (d.note, 50)]) else { return nil }
            return hit(.document, d, title: d.title, subtitle: d.category, score: s)
        })

        // Reves
        var rd = FetchDescriptor<DreamEntry>(predicate: #Predicate { $0.title.localizedStandardContains(q) || $0.text.localizedStandardContains(q) },
                                             sortBy: [SortDescriptor(\.date, order: .reverse)])
        rd.fetchLimit = fetchCap
        keep(run(rd) { r in
            guard let s = score(query: q, fields: [(r.title, 100), (r.text, 60)]) else { return nil }
            return hit(.dream, r, title: r.title.isEmpty ? "Rêve" : r.title, subtitle: df.string(from: r.date), score: s)
        })

        // Repas (90 derniers jours), un seul resultat par aliment
        let foodStart = Calendar.current.date(byAdding: .day, value: -foodWindowDays, to: now) ?? now
        var fd = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= foodStart && $0.name.localizedStandardContains(q) },
                                            sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = fetchCap * 2
        let foods = run(fd) { f in
            guard let s = score(query: q, fields: [(f.name, 100)]) else { return nil }
            return hit(.food, f, title: f.name, subtitle: "\(f.calories) kcal · \(df.string(from: f.date))", score: s)
        }
        keep(dedupeByTitle(foods))

        // Depenses et revenus (365 derniers jours)
        let txnStart = Calendar.current.date(byAdding: .day, value: -transactionWindowDays, to: now) ?? now
        var xd = FetchDescriptor<Txn>(predicate: #Predicate {
            $0.date >= txnStart && ($0.note.localizedStandardContains(q) || $0.category.localizedStandardContains(q))
        }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        xd.fetchLimit = fetchCap
        keep(run(xd) { x in
            guard let s = score(query: q, fields: [(x.note, 100), (x.category, 70)]) else { return nil }
            let amount = x.amountValue.formatted(.number.precision(.fractionLength(2)))
            let title = x.note.isEmpty ? x.category : x.note
            return hit(.transaction, x, title: title, subtitle: "\(amount) · \(x.category) · \(df.string(from: x.date))", score: s)
        })

        // Voyages
        var vd = FetchDescriptor<Trip>(predicate: #Predicate {
            $0.name.localizedStandardContains(q) || $0.destination.localizedStandardContains(q) || $0.notes.localizedStandardContains(q)
        })
        vd.fetchLimit = fetchCap
        keep(run(vd) { v in
            guard let s = score(query: q, fields: [(v.name, 100), (v.destination, 90), (v.notes, 50)]) else { return nil }
            return hit(.trip, v, title: v.name, subtitle: "\(v.destination) · \(df.string(from: v.start))", score: s)
        })

        return out
    }

    private static func hit<T: PersistentModel>(_ kind: SearchKind, _ model: T, title: String, subtitle: String, score: Int) -> SearchHit {
        let home = kind.home
        let cat = home?.0 ?? .productivity
        return SearchHit(id: "\(kind.rawValue):\(model.persistentModelID.hashValue)", kind: kind, title: title,
                         subtitle: subtitle, category: cat, score: score, toolCategory: home?.0, toolName: home?.1,
                         record: SearchRecordRef(kind: kind, id: model.persistentModelID), icon: kind.icon)
    }

    /// Tout : outils puis contenus.
    @MainActor
    static func search(_ query: String, in ctx: ModelContext, now: Date = .now) -> [SearchHit] {
        toolHits(query, in: toolCatalog()) + contentHits(query, in: ctx, now: now)
    }
}
