import Foundation
import SwiftData

// MARK: - Modeles Apprentissage (lot 6: Anko, Coursia, Blinklist, Headwave)
//
// Les liens entre objets passent par des UUID (et non des relations SwiftData):
// la suppression en cascade est faite a la main par des fonctions pures testees,
// ce qui evite les surprises de cascade et garde les anciennes lignes intactes.

/// Paquet de cartes. La hierarchie suit la convention d'Anki: "Langues::Anglais".
@Model final class CardDeck {
    var uid: UUID?
    var name: String
    var createdAt: Date
    init(name: String = DeckTree.defaultName, createdAt: Date = .now) {
        self.uid = UUID(); self.name = name; self.createdAt = createdAt
    }
}

/// Une reponse donnee en revision. Garde l'etat de la carte AVANT la reponse:
/// c'est ce qui permet d'annuler, meme apres relance de l'app.
@Model final class CardReview {
    var uid: UUID?
    var cardUID: UUID?
    var date: Date
    var quality: Int
    var prevEase: Double
    var prevInterval: Int
    var prevDue: Date
    var prevReps: Int
    var prevLapses: Int = 0
    var prevLastReviewedAt: Date?
    init(cardUID: UUID?, date: Date = .now, quality: Int, before: CardSnapshot) {
        self.uid = UUID(); self.cardUID = cardUID; self.date = date; self.quality = quality
        self.prevEase = before.ease; self.prevInterval = before.intervalDays; self.prevDue = before.due
        self.prevReps = before.reps; self.prevLapses = before.lapses; self.prevLastReviewedAt = before.lastReviewedAt
    }
    var snapshot: CardSnapshot {
        CardSnapshot(ease: prevEase, intervalDays: prevInterval, due: prevDue, reps: prevReps,
                     lapses: prevLapses, lastReviewedAt: prevLastReviewedAt)
    }
}

/// Programme cree par l'utilisateur (Coursia).
@Model final class Course {
    var uid: UUID?
    var title: String
    var goal: String = ""
    var deadline: Date?
    var remind: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date
    /// "skillPlan" pour le programme repris de l'ancien plan unique.
    var origin: String = ""
    init(title: String = "", goal: String = "", deadline: Date? = nil, sortIndex: Int = 0, createdAt: Date = .now) {
        self.uid = UUID(); self.title = title; self.goal = goal; self.deadline = deadline
        self.sortIndex = sortIndex; self.createdAt = createdAt
    }
}

@Model final class CourseModule {
    var uid: UUID?
    var courseUID: UUID?
    var title: String
    var sortIndex: Int = 0
    init(courseUID: UUID?, title: String = "", sortIndex: Int = 0) {
        self.uid = UUID(); self.courseUID = courseUID; self.title = title; self.sortIndex = sortIndex
    }
}

@Model final class CourseLesson {
    var uid: UUID?
    var moduleUID: UUID?
    var title: String
    var link: String = ""
    var notes: String = ""
    var done: Bool = false
    var doneAt: Date?
    var deadline: Date?
    var remind: Bool = false
    var sortIndex: Int = 0
    init(moduleUID: UUID?, title: String = "", link: String = "", notes: String = "", sortIndex: Int = 0) {
        self.uid = UUID(); self.moduleUID = moduleUID; self.title = title; self.link = link
        self.notes = notes; self.sortIndex = sortIndex
    }
}

/// Chapitre, idee cle ou surlignage d'un livre, ecrit par l'utilisateur (Blinklist).
@Model final class BookPassage {
    var uid: UUID?
    var bookUID: UUID?
    /// "chapter", "idea" ou "highlight".
    var kind: String
    var text: String
    var page: String = ""
    var sortIndex: Int = 0
    var createdAt: Date
    init(bookUID: UUID?, kind: String = BookPassageKind.idea.rawValue, text: String = "", page: String = "", sortIndex: Int = 0, createdAt: Date = .now) {
        self.uid = UUID(); self.bookUID = bookUID; self.kind = kind; self.text = text
        self.page = page; self.sortIndex = sortIndex; self.createdAt = createdAt
    }
}

// MARK: - Anko: logique pure

struct CardSnapshot: Equatable {
    var ease: Double
    var intervalDays: Int
    var due: Date
    var reps: Int
    var lapses: Int
    var lastReviewedAt: Date?
}

/// Type de note, comme dans Anki: une note produit une ou plusieurs cartes.
enum NoteType: String, CaseIterable, Identifiable {
    case basic, basicReversed, cloze
    var id: String { rawValue }
    var label: String {
        switch self {
        case .basic: return "Basique"
        case .basicReversed: return "Recto et verso"
        case .cloze: return "Texte à trous"
        }
    }
}

enum CardKind {
    static let basic = "basic", reverse = "reverse", cloze = "cloze"
}

struct CardSpec: Equatable {
    var kind: String
    var clozeIndex: Int
}

/// Textes a trous au format Anki: {{c1::reponse}} ou {{c1::reponse::indice}}.
enum Cloze {
    private static let regex = try? NSRegularExpression(
        pattern: #"\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}"#, options: [.dotMatchesLineSeparators])

    private struct Match { let range: NSRange; let index: Int; let answer: String; let hint: String? }

    private static func matches(_ text: String) -> [Match] {
        guard let regex else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let idx = Int(ns.substring(with: m.range(at: 1))), idx > 0 else { return nil }
            let hintRange = m.range(at: 3)
            let hint = hintRange.location == NSNotFound ? nil : ns.substring(with: hintRange)
            return Match(range: m.range, index: idx, answer: ns.substring(with: m.range(at: 2)), hint: hint)
        }
    }

    static func indices(in text: String) -> [Int] {
        Array(Set(matches(text).map(\.index))).sorted()
    }

    private static func render(_ text: String, target: Int, reveal: Bool) -> String {
        var out = text as NSString
        for m in matches(text).reversed() {
            let r: String
            if m.index == target {
                r = reveal ? "[\(m.answer)]" : "[\(m.hint.map { $0.isEmpty ? "…" : $0 } ?? "…")]"
            } else { r = m.answer }
            out = out.replacingCharacters(in: m.range, with: r) as NSString
        }
        return out as String
    }

    /// Question: le trou vise est masque, les autres sont affiches en clair.
    static func question(_ text: String, index: Int) -> String { render(text, target: index, reveal: false) }
    static func answer(_ text: String, index: Int) -> String { render(text, target: index, reveal: true) }
    /// Texte sans aucun marqueur (recherche, liste).
    static func plain(_ text: String) -> String { render(text, target: -1, reveal: false) }
}

enum NoteFactory {
    /// Cartes produites par une note. Vide si la note ne peut produire aucune carte
    /// (texte a trous sans trou, recto vide).
    static func specs(type: NoteType, front: String, back: String) -> [CardSpec] {
        let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else { return [] }
        switch type {
        case .basic: return [CardSpec(kind: CardKind.basic, clozeIndex: 0)]
        case .basicReversed:
            // Une carte inversee sans verso serait une question vide.
            let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
            return b.isEmpty ? [CardSpec(kind: CardKind.basic, clozeIndex: 0)]
                : [CardSpec(kind: CardKind.basic, clozeIndex: 0), CardSpec(kind: CardKind.reverse, clozeIndex: 0)]
        case .cloze: return Cloze.indices(in: f).map { CardSpec(kind: CardKind.cloze, clozeIndex: $0) }
        }
    }

    /// Type de la note d'apres ses cartes.
    static func type(of kinds: [String]) -> NoteType {
        if kinds.contains(CardKind.cloze) { return .cloze }
        if kinds.contains(CardKind.reverse) { return .basicReversed }
        return .basic
    }
}

enum NoteSync {
    /// Compare les cartes existantes d'une note a celles voulues apres modification.
    /// Une carte gardee garde sa planification: modifier le texte ne remet pas a zero.
    static func plan(existing: [CardSpec], wanted: [CardSpec]) -> (keep: [Int], remove: [Int], add: [CardSpec]) {
        var keep: [Int] = [], remove: [Int] = [], seen: [CardSpec] = []
        for (i, s) in existing.enumerated() {
            if wanted.contains(s) && !seen.contains(s) { keep.append(i); seen.append(s) } else { remove.append(i) }
        }
        let add = wanted.filter { !seen.contains($0) }
        return (keep, remove, add)
    }
}

/// Recto et verso affiches selon le type de carte. Toutes les cartes d'une note
/// portent le meme texte: l'inversion se fait a l'affichage.
enum CardFace {
    static func question(_ c: Flashcard) -> String {
        switch c.kind {
        case CardKind.reverse: return c.back
        case CardKind.cloze: return Cloze.question(c.front, index: c.clozeIndex)
        default: return c.front
        }
    }
    static func answer(_ c: Flashcard) -> String {
        switch c.kind {
        case CardKind.reverse: return c.front
        case CardKind.cloze:
            let a = Cloze.answer(c.front, index: c.clozeIndex)
            return c.back.isEmpty ? a : a + "\n\n" + c.back
        default: return c.back
        }
    }
    static func kindLabel(_ c: Flashcard) -> String? {
        switch c.kind {
        case CardKind.reverse: return "Inversée"
        case CardKind.cloze: return "Trou \(c.clozeIndex)"
        default: return nil
        }
    }
}

enum CardTags {
    static func list(_ raw: String) -> [String] {
        var out: [String] = []
        for t in raw.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }) {
            var s = String(t).trimmingCharacters(in: .whitespaces)
            while s.hasPrefix("#") { s.removeFirst() }
            if !s.isEmpty, !out.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) { out.append(s) }
        }
        return out
    }
    static func normalize(_ raw: String) -> String { list(raw).joined(separator: " ") }
    static func has(_ raw: String, _ tag: String) -> Bool {
        list(raw).contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }
}

enum CardSearch {
    private static func has(_ hay: String, _ needle: String) -> Bool {
        hay.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
    /// Recherche texte, avec `tag:mot` pour une etiquette et `is:suspendue` / `is:enterree`.
    static func matches(_ c: Flashcard, query: String, now: Date = .now) -> Bool {
        let tokens = query.split(separator: " ").map(String.init)
        for t in tokens {
            let lower = t.lowercased()
            if lower.hasPrefix("tag:") {
                let tag = String(t.dropFirst(4))
                if tag.isEmpty { continue }
                if !CardTags.list(c.tags).contains(where: { has($0, tag) }) { return false }
            } else if lower == "is:suspendue" {
                if !c.suspended { return false }
            } else if lower == "is:enterree" || lower == "is:enterrée" {
                if !CardScheduling.isBuried(c, now: now) { return false }
            } else {
                let text = Cloze.plain(c.front) + "\n" + c.back + "\n" + c.tags + "\n" + c.source
                if !has(text, t) { return false }
            }
        }
        return true
    }
}

/// Algorithme SuperMemo-2 pour la répétition espacée.
/// `now` et `calendar` sont injectables: dates deterministes en test et au changement de fuseau.
enum SM2 {
    static func apply(to card: Flashcard, quality q: Int, now: Date = .now, calendar: Calendar = .current) {
        if q < 3 {
            card.reps = 0; card.intervalDays = 1
        } else {
            switch card.reps {
            case 0: card.intervalDays = 1
            case 1: card.intervalDays = 6
            default: card.intervalDays = Int((Double(card.intervalDays) * card.ease).rounded())
            }
            card.reps += 1
        }
        card.ease = max(1.3, card.ease + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02)))
        card.due = calendar.date(byAdding: .day, value: max(1, card.intervalDays), to: calendar.startOfDay(for: now)) ?? now
    }
}

enum CardScheduling {
    static func isBuried(_ c: Flashcard, now: Date) -> Bool { (c.buriedUntil ?? .distantPast) > now }
    static func isDue(_ c: Flashcard, now: Date) -> Bool { !c.suspended && !isBuried(c, now: now) && c.due <= now }

    /// Enterrer = cacher jusqu'au debut du jour suivant, sans toucher a la planification.
    static func bury(_ c: Flashcard, now: Date, calendar: Calendar = .current) {
        c.buriedUntil = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    }

    static func snapshot(_ c: Flashcard) -> CardSnapshot {
        CardSnapshot(ease: c.ease, intervalDays: c.intervalDays, due: c.due, reps: c.reps,
                     lapses: c.lapses, lastReviewedAt: c.lastReviewedAt)
    }
    static func restore(_ c: Flashcard, from s: CardSnapshot) {
        c.ease = s.ease; c.intervalDays = s.intervalDays; c.due = s.due; c.reps = s.reps
        c.lapses = s.lapses; c.lastReviewedAt = s.lastReviewedAt
    }

    /// Applique une reponse et rend l'etat d'avant (a journaliser pour l'annulation).
    @discardableResult
    static func answer(_ c: Flashcard, quality: Int, now: Date = .now, calendar: Calendar = .current) -> CardSnapshot {
        let before = snapshot(c)
        if quality < 3 && c.reps > 0 { c.lapses += 1 }
        SM2.apply(to: c, quality: quality, now: now, calendar: calendar)
        c.lastReviewedAt = now
        return before
    }

    /// Cartes de la seance: dues, triees, une seule carte par note (les cartes soeurs,
    /// comme l'inversee, attendent une autre seance comme dans Anki).
    static func sessionCards(_ cards: [Flashcard], now: Date) -> [Flashcard] {
        var seen = Set<UUID>()
        return cards.filter { isDue($0, now: now) }
            .sorted { ($0.due, $0.createdAt) < ($1.due, $1.createdAt) }
            .filter { c in
                guard let n = c.noteID else { return true }
                return seen.insert(n).inserted
            }
    }
}

/// File de revision d'une seance: une carte ratee revient en fin de seance
/// (reapprentissage), et chaque etape peut etre annulee dans l'ordre inverse.
struct ReviewQueue: Equatable {
    private(set) var order: [Int]
    private(set) var position = 0
    private var history: [Bool] = []   // true = la carte a ete remise en fin de file

    init(count: Int) { order = Array(0..<max(0, count)) }

    var current: Int? { position < order.count ? order[position] : nil }
    var remaining: Int { order.count - position }
    var answered: Int { position }
    var canUndo: Bool { !history.isEmpty }

    mutating func answer(quality: Int) {
        guard let c = current else { return }
        let requeue = quality < 3
        if requeue { order.append(c) }
        history.append(requeue)
        position += 1
    }

    /// Retire la carte courante de la seance (enterree ou suspendue).
    mutating func skip() {
        guard current != nil else { return }
        history.append(false)
        position += 1
    }

    /// Revient d'une etape; rend la carte a remontrer.
    @discardableResult
    mutating func undo() -> Int? {
        guard let requeued = history.popLast() else { return nil }
        if requeued { order.removeLast() }
        position -= 1
        return order[position]
    }
}

enum ReviewUndo {
    /// Derniere reponse annulable: la plus recente dont la carte existe encore.
    static func last(reviews: [CardReview], cards: [Flashcard]) -> (CardReview, Flashcard)? {
        for r in reviews.sorted(by: { $0.date > $1.date }) {
            if let card = cards.first(where: { $0.uid != nil && $0.uid == r.cardUID }) { return (r, card) }
        }
        return nil
    }
    static func undo(_ r: CardReview, on card: Flashcard) {
        CardScheduling.restore(card, from: r.snapshot)
    }
}

/// Noms de paquets hierarchiques ("Parent::Enfant").
enum DeckTree {
    static let separator = "::"
    static let defaultName = "Général"
    static let notionsName = "Notions"

    static func normalize(_ raw: String) -> String {
        raw.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
    static func depth(_ name: String) -> Int { max(0, name.components(separatedBy: separator).count - 1) }
    static func leaf(_ name: String) -> String { name.components(separatedBy: separator).last ?? name }
    static func contains(_ parent: String, _ name: String) -> Bool {
        name == parent || name.hasPrefix(parent + separator)
    }
    static func ancestors(_ name: String) -> [String] {
        let parts = name.components(separatedBy: separator)
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).map { parts[0..<$0].joined(separator: separator) }
    }
    /// Nom apres renommage de `old` en `new` (le paquet lui-meme ou un descendant), sinon nil.
    static func renamed(_ name: String, from old: String, to new: String) -> String? {
        if name == old { return new }
        if name.hasPrefix(old + separator) { return new + name.dropFirst(old.count) }
        return nil
    }
    /// Ordre d'affichage: les enfants suivent leur parent.
    static func sorted(_ names: [String]) -> [String] {
        names.sorted { $0.components(separatedBy: separator).lexicographicallyPrecedes($1.components(separatedBy: separator)) { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    }
}

enum DeckError: Error, Equatable {
    case empty, exists, protected
    var message: String {
        switch self {
        case .empty: return "Donne un nom au paquet."
        case .exists: return "Un paquet porte déjà ce nom."
        case .protected: return "Le paquet Général ne peut être ni renommé ni supprimé."
        }
    }
}

enum DeckOps {
    /// Rend le paquet de ce nom, en le creant (avec ses parents) si besoin.
    @discardableResult
    static func ensure(_ raw: String, decks: inout [CardDeck], in ctx: ModelContext) -> CardDeck {
        let name = DeckTree.normalize(raw).isEmpty ? DeckTree.defaultName : DeckTree.normalize(raw)
        for a in DeckTree.ancestors(name) + [name] where !decks.contains(where: { $0.name == a }) {
            let d = CardDeck(name: a); ctx.insert(d); decks.append(d)
        }
        let d = decks.first { $0.name == name }!
        if d.uid == nil { d.uid = UUID() }
        return d
    }

    static func create(_ raw: String, decks: inout [CardDeck], in ctx: ModelContext) -> Result<CardDeck, DeckError> {
        let name = DeckTree.normalize(raw)
        guard !name.isEmpty else { return .failure(.empty) }
        guard !decks.contains(where: { $0.name == name }) else { return .failure(.exists) }
        return .success(ensure(name, decks: &decks, in: ctx))
    }

    /// Renomme un paquet et ses sous-paquets; le nom recopie sur les cartes suit.
    static func rename(_ deck: CardDeck, to raw: String, decks: [CardDeck], cards: [Flashcard]) -> DeckError? {
        let new = DeckTree.normalize(raw)
        guard deck.name != DeckTree.defaultName else { return .protected }
        guard !new.isEmpty else { return .empty }
        if new == deck.name { return nil }
        guard !decks.contains(where: { $0.name == new }) else { return .exists }
        let old = deck.name
        for d in decks { if let n = DeckTree.renamed(d.name, from: old, to: new) { d.name = n } }
        for c in cards { if let n = DeckTree.renamed(c.deck, from: old, to: new) { c.deck = n } }
        return nil
    }

    /// Paquets touches par une suppression: le paquet et ses descendants.
    static func subtree(_ deck: CardDeck, decks: [CardDeck]) -> [CardDeck] {
        decks.filter { DeckTree.contains(deck.name, $0.name) }
    }

    /// Supprime le paquet et ses sous-paquets. Les cartes vont dans `moveTo`,
    /// ou sont supprimees si `moveTo` est nil (choix explicite de l'utilisateur).
    static func delete(_ deck: CardDeck, decks: [CardDeck], cards: [Flashcard], moveTo: CardDeck?, in ctx: ModelContext) -> DeckError? {
        guard deck.name != DeckTree.defaultName else { return .protected }
        let gone = subtree(deck, decks: decks)
        let ids = Set(gone.compactMap(\.uid))
        for c in cards where c.deckID.map(ids.contains) ?? false {
            if let t = moveTo, !ids.contains(t.uid ?? UUID()) { c.deckID = t.uid; c.deck = t.name } else { ctx.delete(c) }
        }
        gone.forEach { ctx.delete($0) }
        return nil
    }
}

/// Migration unique et idempotente: les anciennes cartes (sans uid, sans paquet
/// objet) recoivent un identifiant, une note a elles, et le paquet de leur nom.
/// Rien n'est supprime ni reecrit hors de ces champs.
enum DeckMigration {
    @discardableResult
    static func run(cards: [Flashcard], decks existing: [CardDeck], in ctx: ModelContext) -> Int {
        var decks = existing
        var changes = 0
        for d in decks where d.uid == nil { d.uid = UUID(); changes += 1 }
        if !decks.contains(where: { $0.name == DeckTree.defaultName }) {
            DeckOps.ensure(DeckTree.defaultName, decks: &decks, in: ctx); changes += 1
        }
        for c in cards {
            if c.uid == nil { c.uid = UUID(); changes += 1 }
            if c.noteID == nil { c.noteID = c.uid; changes += 1 }
            if c.deckID == nil || !decks.contains(where: { $0.uid == c.deckID }) {
                let before = decks.count
                let d = DeckOps.ensure(c.deck, decks: &decks, in: ctx)
                changes += 1 + (decks.count - before)
                c.deckID = d.uid; c.deck = d.name
            }
        }
        return changes
    }
}

enum NoteStore {
    /// Cree ou modifie une note et ses cartes. Les cartes gardees conservent leur
    /// planification; les cartes qui n'existent plus (trou retire) sont supprimees.
    @discardableResult
    static func save(existing: [Flashcard], type: NoteType, front rawFront: String, back rawBack: String,
                     deck: CardDeck, tags: String, source: String, in ctx: ModelContext, now: Date = .now) -> [Flashcard] {
        let front = rawFront.trimmingCharacters(in: .whitespacesAndNewlines)
        let back = rawBack.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = NoteFactory.specs(type: type, front: front, back: back)
        guard !wanted.isEmpty else { return existing }
        let plan = NoteSync.plan(existing: existing.map { CardSpec(kind: $0.kind, clozeIndex: $0.clozeIndex) }, wanted: wanted)
        let noteID = existing.compactMap(\.noteID).first ?? UUID()
        let cleanTags = CardTags.normalize(tags)
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        func fill(_ c: Flashcard) {
            c.front = front; c.back = back; c.deck = deck.name; c.deckID = deck.uid
            c.tags = cleanTags; c.source = cleanSource; c.noteID = noteID
        }
        var result: [Flashcard] = []
        for i in plan.keep { fill(existing[i]); result.append(existing[i]) }
        for i in plan.remove { ctx.delete(existing[i]) }
        for s in plan.add {
            let c = Flashcard(front: front, back: back, deck: deck.name, due: now, createdAt: now)
            c.kind = s.kind; c.clozeIndex = s.clozeIndex
            fill(c); ctx.insert(c); result.append(c)
        }
        return result
    }

    /// Cartes de la meme note.
    static func siblings(of card: Flashcard, in cards: [Flashcard]) -> [Flashcard] {
        guard let n = card.noteID else { return [card] }
        return cards.filter { $0.noteID == n }
    }
}

// MARK: - Import / export CSV

struct CSVNote: Equatable {
    var front: String
    var back: String
    var deck: String
    var tags: String
    var type: NoteType
}

/// Formats pris en charge: CSV (virgule ou point-virgule) et texte tabule,
/// dont l'export Anki "Notes en texte brut". Le paquet .apkg n'est PAS lu.
enum FlashcardCSV {
    static let header = ["recto", "verso", "paquet", "etiquettes", "type"]

    static func detectDelimiter(_ line: String) -> Character {
        if line.contains("\t") { return "\t" }
        let semi = line.filter { $0 == ";" }.count, comma = line.filter { $0 == "," }.count
        return semi > comma ? ";" : ","
    }

    /// Lignes et champs selon la RFC 4180 (guillemets, guillemets doubles, retours a la ligne).
    static func rows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false, chars = Array(text), i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(ch) }
            } else if ch == "\"" && field.isEmpty {
                inQuotes = true
            } else if ch == delimiter {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r" || ch == "\r\n" {
                if ch == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                rows.append(row); row = []
            } else { field.append(ch) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    /// Anki exporte du HTML: on garde le texte et les retours a la ligne.
    static func stripHTML(_ s: String) -> String {
        guard s.contains("<") || s.contains("&") else { return s }
        var t = s.replacingOccurrences(of: #"<br\s*/?>|</div>|</p>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (k, v) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseType(_ raw: String, front: String) -> NoteType {
        let t = raw.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespaces)
        if ["inversee", "recto et verso", "reverse", "reversed", "basic+reverse", "basic (and reversed card)"].contains(t) { return .basicReversed }
        if ["trous", "texte a trous", "cloze"].contains(t) { return .cloze }
        if t.isEmpty && !Cloze.indices(in: front).isEmpty { return .cloze }
        return .basic
    }

    static func parse(_ text: String, defaultDeck: String = DeckTree.defaultName) -> (notes: [CSVNote], skipped: Int) {
        var lines = text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var delimiter: Character?
        var anki = false, tagsCol: Int?, deckCol: Int?
        // Entete d'Anki: "#separator:tab", "#tags column:3"... seulement en debut de fichier.
        // Avec cet entete, les colonnes sont celles qu'Anki declare (pas notre ordre).
        func column(_ l: String, _ key: String) -> Int? {
            l.hasPrefix(key) ? Int(l.dropFirst(key.count).trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 - 1 } : nil
        }
        while let first = lines.first, first.hasPrefix("#") {
            let l = first.lowercased()
            anki = true
            if l.hasPrefix("#separator:") {
                let v = l.dropFirst("#separator:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                delimiter = v == "tab" ? "\t" : v == "semicolon" ? ";" : v == "comma" ? "," : v == "pipe" ? "|" : v.first
            }
            tagsCol = column(l, "#tags column:") ?? tagsCol
            deckCol = column(l, "#deck column:") ?? deckCol
            lines.removeFirst()
        }
        let body = lines.joined(separator: "\n")
        let firstLine = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var all = rows(body, delimiter: delimiter ?? detectDelimiter(firstLine))
        if let h = all.first?.first?.lowercased().trimmingCharacters(in: .whitespaces),
           ["recto", "front", "question", "avant"].contains(h) { all.removeFirst() }
        var notes: [CSVNote] = [], skipped = 0
        for r in all {
            let front = stripHTML(r[0])
            let back = r.count > 1 ? stripHTML(r[1]) : ""
            func cell(_ i: Int?) -> String { i.flatMap { r.indices.contains($0) ? r[$0] : nil } ?? "" }
            let deckCell = DeckTree.normalize(cell(anki ? deckCol : 2))
            let type = parseType(anki ? "" : cell(4), front: front)
            let n = CSVNote(front: front, back: back, deck: deckCell.isEmpty ? defaultDeck : deckCell,
                            tags: CardTags.normalize(cell(anki ? tagsCol : 3)), type: type)
            if NoteFactory.specs(type: n.type, front: n.front, back: n.back).isEmpty { skipped += 1 } else { notes.append(n) }
        }
        return (notes, skipped)
    }

    static func typeCode(_ t: NoteType) -> String {
        switch t { case .basic: return "basique"; case .basicReversed: return "inversee"; case .cloze: return "trous" }
    }

    static func escape(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains(";")
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    static func export(_ notes: [CSVNote]) -> String {
        ([header.joined(separator: ",")] + notes.map { n in
            [n.front, n.back, n.deck, n.tags, typeCode(n.type)].map(escape).joined(separator: ",")
        }).joined(separator: "\n") + "\n"
    }

    /// Une ligne par NOTE (pas par carte): l'inversee et les trous se regenerent a l'import.
    static func notes(from cards: [Flashcard]) -> [CSVNote] {
        var order: [UUID] = [], groups: [UUID: [Flashcard]] = [:]
        for c in cards.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = c.noteID ?? c.uid ?? UUID()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(c)
        }
        return order.compactMap { k in
            guard let g = groups[k], let c = g.first else { return nil }
            return CSVNote(front: c.front, back: c.back, deck: c.deck, tags: c.tags, type: NoteFactory.type(of: g.map(\.kind)))
        }
    }

    static func key(front: String, back: String, deck: String) -> String {
        [front, back, deck].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.joined(separator: "\u{1F}")
    }

    /// Ajoute les notes importees; ignore celles deja presentes (meme recto, verso, paquet),
    /// donc reimporter son propre export ne cree pas de doublons.
    static func apply(_ notes: [CSVNote], cards: [Flashcard], decks: [CardDeck], in ctx: ModelContext) -> (added: Int, duplicates: Int) {
        var keys = Set(cards.map { key(front: $0.front, back: $0.back, deck: $0.deck) })
        var decks = decks
        var added = 0, dup = 0
        for n in notes {
            let d = DeckOps.ensure(n.deck, decks: &decks, in: ctx)
            let k = key(front: n.front, back: n.back, deck: d.name)
            if keys.contains(k) { dup += 1; continue }
            keys.insert(k)
            NoteStore.save(existing: [], type: n.type, front: n.front, back: n.back, deck: d, tags: n.tags, source: "", in: ctx)
            added += 1
        }
        return (added, dup)
    }
}

// MARK: - Statistiques

struct CardStatsSummary: Equatable {
    var total: Int
    var dueToday: Int
    var suspended: Int
    var reviewsPerDay: [DayCount]
    /// Part des reponses reussies (Correct ou Facile) sur 30 jours; nil sans revision.
    var retention: Double?
    var reviews30: Int
    struct DayCount: Equatable { var day: Date; var count: Int }
}

enum CardStats {
    static func summary(cards: [Flashcard], reviews: [CardReview], now: Date = .now, days: Int = 14, calendar: Calendar = .current) -> CardStatsSummary {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let due = cards.filter { !$0.suspended && $0.due < tomorrow && ($0.buriedUntil ?? .distantPast) < tomorrow }.count
        var perDay: [CardStatsSummary.DayCount] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let d = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            perDay.append(.init(day: d, count: reviews.filter { calendar.isDate($0.date, inSameDayAs: d) }.count))
        }
        let since = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let recent = reviews.filter { $0.date >= since && $0.date < tomorrow }
        let retention = recent.isEmpty ? nil : Double(recent.filter { $0.quality >= 3 }.count) / Double(recent.count)
        return CardStatsSummary(total: cards.count, dueToday: due, suspended: cards.filter(\.suspended).count,
                                reviewsPerDay: perDay, retention: retention, reviews30: recent.count)
    }
}

// MARK: - Headwave: notions de l'utilisateur

/// Une notion est une carte d'Anko (paquet "Notions", etiquette "notion"): une seule
/// progression, revisee par le meme algorithme, visible dans les deux outils.
enum NotionStore {
    static let tag = "notion"
    static func isNotion(_ c: Flashcard) -> Bool { CardTags.has(c.tags, tag) }
    static func notions(_ cards: [Flashcard]) -> [Flashcard] {
        cards.filter(isNotion).sorted { $0.createdAt > $1.createdAt }
    }
    static func exists(title: String, in cards: [Flashcard]) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cards.contains { isNotion($0) && $0.front.caseInsensitiveCompare(t) == .orderedSame }
    }
}

// MARK: - Coursia: logique pure

enum CourseOps {
    static func modules(of course: Course, in all: [CourseModule]) -> [CourseModule] {
        all.filter { $0.courseUID != nil && $0.courseUID == course.uid }.sorted { $0.sortIndex < $1.sortIndex }
    }
    static func lessons(of module: CourseModule, in all: [CourseLesson]) -> [CourseLesson] {
        all.filter { $0.moduleUID != nil && $0.moduleUID == module.uid }.sorted { $0.sortIndex < $1.sortIndex }
    }
    /// Lecons du programme dans l'ordre des modules.
    static func lessons(of course: Course, modules: [CourseModule], lessons: [CourseLesson]) -> [CourseLesson] {
        Self.modules(of: course, in: modules).flatMap { Self.lessons(of: $0, in: lessons) }
    }
    static func progress(_ lessons: [CourseLesson]) -> (done: Int, total: Int) {
        (lessons.filter(\.done).count, lessons.count)
    }
    /// Lecon a reprendre: la premiere non faite.
    static func next(_ lessons: [CourseLesson]) -> CourseLesson? { lessons.first { !$0.done } }

    static func toggle(_ l: CourseLesson, now: Date = .now) {
        l.done.toggle(); l.doneAt = l.done ? now : nil
    }

    /// Nouvel ordre apres deplacement (meme semantique que List.onMove).
    static func moved<T>(_ items: [T], from source: IndexSet, to destination: Int) -> [T] {
        var out = items
        let moving = source.sorted().map { out[$0] }
        for i in source.sorted(by: >) { out.remove(at: i) }
        let insertAt = destination - source.filter { $0 < destination }.count
        out.insert(contentsOf: moving, at: max(0, min(insertAt, out.count)))
        return out
    }
    static func renumber(_ modules: [CourseModule]) { for (i, m) in modules.enumerated() { m.sortIndex = i } }
    static func renumber(_ lessons: [CourseLesson]) { for (i, l) in lessons.enumerated() { l.sortIndex = i } }
    static func renumber(_ courses: [Course]) { for (i, c) in courses.enumerated() { c.sortIndex = i } }

    /// Supprime un module et ses lecons. Rend les uid des lecons (rappels a annuler).
    @discardableResult
    static func delete(_ module: CourseModule, lessons: [CourseLesson], in ctx: ModelContext) -> [UUID] {
        let gone = Self.lessons(of: module, in: lessons)
        gone.forEach { ctx.delete($0) }
        ctx.delete(module)
        return gone.compactMap(\.uid)
    }
    @discardableResult
    static func delete(_ course: Course, modules: [CourseModule], lessons: [CourseLesson], in ctx: ModelContext) -> [UUID] {
        var ids: [UUID] = []
        for m in Self.modules(of: course, in: modules) { ids += delete(m, lessons: lessons, in: ctx) }
        ctx.delete(course)
        return ids
    }

    /// Lien saisi a la main: on ajoute https:// si le schema manque, et on refuse le reste.
    static func url(from raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let s = t.contains("://") ? t : "https://" + t
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = u.host, host.contains(".") else { return nil }
        return u
    }

    /// Rappel a 9 h le jour de l'echeance; nil si ce moment est passe.
    static func reminderDate(for deadline: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let d = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: deadline) ?? deadline
        return d > now ? d : nil
    }

    static func deadlineLabel(_ deadline: Date, now: Date = .now, calendar: Calendar = .current) -> (text: String, overdue: Bool) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: deadline)).day ?? 0
        switch days {
        case 0: return ("Échéance aujourd'hui", false)
        case 1: return ("Échéance demain", false)
        case let d where d > 1: return ("Échéance dans \(d) j", false)
        default: return ("En retard de \(-days) j", true)
        }
    }

    static func courseReminderID(_ c: Course) -> String { "lifeos.course." + (c.uid?.uuidString ?? "") }
    static func lessonReminderID(_ uid: UUID?) -> String { "lifeos.lesson." + (uid?.uuidString ?? "") }
}

/// Reprise unique de l'ancien plan (une competence + jalons en AppStorage) en un
/// programme. Les valeurs AppStorage ne sont PAS effacees: rien ne se perd.
enum SkillPlanMigration {
    static let flagKey = "learning.skillPlanMigrated.v1"

    static func migrate(skill: String, stepsRaw: String, doneRaw: String, in ctx: ModelContext) -> Course? {
        let steps = stepsRaw.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let name = skill.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !steps.isEmpty || !name.isEmpty else { return nil }
        let done = Set(doneRaw.split(separator: "\n").map(String.init))
        let course = Course(title: name.isEmpty ? "Mon plan" : name)
        course.origin = "skillPlan"
        ctx.insert(course)
        let module = CourseModule(courseUID: course.uid, title: "Jalons")
        ctx.insert(module)
        for (i, s) in steps.enumerated() {
            let l = CourseLesson(moduleUID: module.uid, title: s, sortIndex: i)
            l.done = done.contains(s)
            ctx.insert(l)
        }
        return course
    }
}

// MARK: - Blinklist: logique pure

enum BookPassageKind: String, CaseIterable, Identifiable {
    case chapter, idea, highlight
    var id: String { rawValue }
    var label: String {
        switch self { case .chapter: return "Chapitre"; case .idea: return "Idée clé"; case .highlight: return "Surlignage" }
    }
    var icon: String {
        switch self { case .chapter: return "list.number"; case .idea: return "lightbulb"; case .highlight: return "highlighter" }
    }
}

enum BookCollections {
    static func list(_ raw: String) -> [String] {
        var out: [String] = []
        for p in raw.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let s = p.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty, !out.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) { out.append(s) }
        }
        return out
    }
    static func join(_ items: [String]) -> String { list(items.joined(separator: "\n")).joined(separator: "\n") }
    static func all(_ books: [BookSummary]) -> [String] {
        list(books.map(\.collections).joined(separator: "\n")).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    static func toggled(_ raw: String, _ name: String) -> String {
        var l = list(raw)
        if let i = l.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { l.remove(at: i) } else { l.append(name) }
        return join(l)
    }
}

enum BookOps {
    static func passages(of book: BookSummary, in all: [BookPassage]) -> [BookPassage] {
        all.filter { $0.bookUID != nil && $0.bookUID == book.uid }.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    struct Section { var chapter: BookPassage?; var items: [BookPassage] }
    /// Plan du livre: chaque idee ou surlignage se range sous le chapitre qui le precede.
    static func outline(_ passages: [BookPassage]) -> [Section] {
        var out: [Section] = []
        for p in passages {
            if p.kind == BookPassageKind.chapter.rawValue { out.append(Section(chapter: p, items: [])) }
            else if out.isEmpty { out.append(Section(chapter: nil, items: [p])) }
            else { out[out.count - 1].items.append(p) }
        }
        return out
    }

    static func matches(_ book: BookSummary, passages: [BookPassage], query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let hay = ([book.title, book.author, book.keyIdeas, book.collections] + Self.passages(of: book, in: passages).map { $0.text + " " + $0.page }).joined(separator: "\n")
        return q.split(separator: " ").allSatisfy { hay.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Echange avec le voisin (monter = -1, descendre = +1) puis renumerote.
    static func move(_ p: BookPassage, by delta: Int, in ordered: [BookPassage]) {
        guard let i = ordered.firstIndex(where: { $0 === p }) else { return }
        let j = i + delta
        guard ordered.indices.contains(j) else { return }
        var l = ordered; l.swapAt(i, j)
        for (k, x) in l.enumerated() { x.sortIndex = k }
    }

    static func delete(_ book: BookSummary, passages: [BookPassage], in ctx: ModelContext) {
        Self.passages(of: book, in: passages).forEach { ctx.delete($0) }
        ctx.delete(book)
    }

    /// Les resumes d'avant le lot 6 n'ont pas d'uid: on le pose une fois.
    @discardableResult
    static func migrate(_ books: [BookSummary]) -> Int {
        var n = 0
        for b in books where b.uid == nil { b.uid = UUID(); n += 1 }
        return n
    }
}
