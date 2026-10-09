import Foundation

// MARK: - Capture universelle : lecture locale du texte
//
// « 12,50 € courses » -> depense ; « appeler maman demain 18h #perso » -> tache ;
// « note: idee de cadeau » -> note. Tout est fait sur l'appareil, sans service payant.
// Une valeur ambigue (pas de montant, deux montants, compte inconnu) n'est jamais
// devinee en silence : elle est signalee et l'ecran demande de la confirmer.

enum CaptureKind: String, CaseIterable, Identifiable {
    case task, expense, note
    var id: String { rawValue }
    var label: String {
        switch self {
        case .task: return "Tâche"
        case .expense: return "Dépense"
        case .note: return "Note"
        }
    }
    var icon: String {
        switch self {
        case .task: return "checklist"
        case .expense: return "creditcard.fill"
        case .note: return "note.text"
        }
    }
}

/// Ce qui doit etre confirme avant d'enregistrer.
enum CaptureFlag: String, Hashable {
    /// Depense sans montant lisible.
    case missingAmount
    /// Plusieurs montants : lequel ?
    case multipleAmounts
    /// Un nombre sans « € » : on ne sait pas si c'est un montant.
    case unconfirmedAmount
    /// Un compte cite qui n'existe pas.
    case unknownAccount
    /// Rien a enregistrer comme titre.
    case emptyTitle
}

struct CaptureProposal: Equatable {
    var kind: CaptureKind = .note
    var title: String = ""
    /// Tache : echeance. Depense : date de l'operation. Note : nil.
    var date: Date?
    var hasTime = false
    var amount: Double?
    /// Montants trouves quand il y en a plusieurs (a choisir).
    var amountCandidates: [Double] = []
    var category: String = "Divers"
    /// La categorie vient d'un mot reconnu (sinon « Divers »).
    var categoryGuessed = false
    /// Compte cite et retrouve.
    var accountName: String?
    /// Compte cite mais introuvable (affiche pour correction).
    var mentionedAccount: String?
    var noteBody: String = ""
    /// Lecture complete de la tache (projet, etiquettes, priorite, recurrence).
    var task: ParsedTask?
    var flags: Set<CaptureFlag> = []
}

enum CaptureParser {
    /// Memes categories que l'ecran Bankino (une seule liste pour l'argent).
    static let expenseCategories = ["Courses", "Restau", "Transport", "Logement", "Loisirs", "Santé", "Shopping", "Divers"]
    static let fallbackCategory = "Divers"

    /// Mots (sans accents) -> categorie. Le premier trouve gagne.
    static let categoryKeywords: [(String, [String])] = [
        ("Courses", ["courses", "course", "supermarche", "supermarché", "carrefour", "leclerc", "lidl", "auchan",
                     "monoprix", "franprix", "intermarche", "epicerie", "marche", "boulangerie", "pain", "picard"]),
        ("Restau", ["restau", "resto", "restaurant", "cafe", "cafes", "bar", "dejeuner", "diner", "mcdo", "burger",
                    "pizza", "kebab", "sushi", "brunch", "verre", "biere", "uber eats", "deliveroo"]),
        ("Transport", ["essence", "carburant", "plein", "uber", "taxi", "train", "sncf", "metro", "bus", "navigo",
                       "peage", "parking", "velib", "trottinette", "billet", "avion"]),
        ("Logement", ["loyer", "electricite", "edf", "gaz", "internet", "box", "charges", "assurance habitation"]),
        ("Loisirs", ["cinema", "cine", "concert", "netflix", "spotify", "jeu", "jeux", "sortie", "musee", "livre",
                     "livres", "theatre", "abonnement"]),
        ("Santé", ["pharmacie", "medecin", "docteur", "dentiste", "kine", "mutuelle", "ophtalmo", "medicament"]),
        ("Shopping", ["vetement", "vetements", "chaussures", "habits", "zara", "amazon", "cadeau"]),
    ]

    /// Mots qui annoncent une depense meme sans « € ».
    static let expenseVerbs: Set<String> = ["depense", "depenses", "paye", "payee", "payer", "achete", "achat", "achats", "debit"]
    /// Debuts d'une note explicite.
    static let notePrefixes = ["note:", "note :", "idee:", "idee :", "memo:", "memo :", "note "]
    /// Premiers mots qui annoncent une tache.
    static let taskVerbs: Set<String> = [
        "acheter", "appeler", "rappeler", "envoyer", "faire", "prendre", "payer", "reserver", "ecrire", "repondre",
        "penser", "finir", "terminer", "preparer", "ranger", "nettoyer", "laver", "aller", "passer", "verifier",
        "commander", "imprimer", "signer", "rendre", "chercher", "contacter", "planifier", "relancer", "lire",
        "regarder", "rdv", "rendez-vous", "reunion", "sortir", "inscrire", "renouveler", "annuler"
    ]

    // MARK: Entree

    static func parse(_ text: String, now: Date = .now, calendar cal: Calendar = .current,
                      accounts: [String] = []) -> CaptureProposal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var p = CaptureProposal()
        guard !trimmed.isEmpty else { p.flags.insert(.emptyTitle); return p }
        let folded = TextFold.fold(trimmed)

        // 1. Note explicite.
        if let prefix = notePrefixes.first(where: { folded.hasPrefix($0) }) {
            let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return note(rest, flagsEmpty: true)
        }

        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let money = moneyTokens(tokens)
        let foldedTokens = tokens.map { cleanFold($0) }
        let hasVerb = foldedTokens.contains { expenseVerbs.contains($0) } || folded.hasPrefix("j'ai paye") || folded.hasPrefix("j'ai depense")

        // 2. Depense : un montant avec « € », ou un verbe de depense.
        if !money.marked.isEmpty || hasVerb {
            return expense(tokens: tokens, folded: foldedTokens, money: money, now: now, calendar: cal, accounts: accounts)
        }

        // 3. Tache : marqueurs reconnus (date, heure, #projet, !priorite, recurrence) ou verbe.
        let parsed = TaskCapture.parse(trimmed, now: now, calendar: cal)
        let hasMarkers = parsed.due != nil || parsed.project != nil || parsed.priority != nil
            || !parsed.tags.isEmpty || parsed.recurrence != .none
        let firstWord = foldedTokens.first ?? ""
        let multiline = trimmed.contains("\n")
        if !multiline && (hasMarkers || taskVerbs.contains(firstWord)) {
            p.kind = .task
            p.title = parsed.title.isEmpty ? trimmed : parsed.title
            p.date = parsed.due
            p.hasTime = parsed.hasTime
            p.task = parsed
            if p.title.isEmpty { p.flags.insert(.emptyTitle) }
            return p
        }

        // 4. Sinon : une note (l'ecran permet de changer de type).
        return note(trimmed, flagsEmpty: false)
    }

    // MARK: Note

    private static func note(_ text: String, flagsEmpty: Bool) -> CaptureProposal {
        var p = CaptureProposal()
        p.kind = .note
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let first = (lines.first ?? "").trimmingCharacters(in: .whitespaces)
        p.title = String(first.prefix(80))
        p.noteBody = text
        if p.title.isEmpty { p.flags.insert(.emptyTitle) }
        return p
    }

    // MARK: Depense

    private static func expense(tokens: [String], folded: [String], money: MoneyScan, now: Date,
                                calendar cal: Calendar, accounts: [String]) -> CaptureProposal {
        var p = CaptureProposal()
        p.kind = .expense
        var used = Set<Int>()

        // Montant
        let marked = money.marked
        if marked.count == 1 {
            p.amount = marked[0].value
            used.formUnion(marked[0].indices)
        } else if marked.count > 1 {
            let distinct = uniqueValues(marked.map(\.value))
            if distinct.count == 1 {
                p.amount = distinct[0]
            } else {
                p.amountCandidates = distinct
                p.flags.insert(.multipleAmounts)
            }
            for m in marked { used.formUnion(m.indices) }
        } else if money.bare.count == 1 {
            // « paye 12 courses » : probablement 12 €, mais rien ne le dit. A confirmer.
            p.amount = money.bare[0].value
            p.flags.insert(.unconfirmedAmount)
            used.formUnion(money.bare[0].indices)
        } else if money.bare.count > 1 {
            p.amountCandidates = uniqueValues(money.bare.map(\.value))
            p.flags.insert(p.amountCandidates.count > 1 ? .multipleAmounts : .unconfirmedAmount)
            if p.amountCandidates.count == 1 { p.amount = p.amountCandidates[0] }
            for m in money.bare { used.formUnion(m.indices) }
        } else {
            p.flags.insert(.missingAmount)
        }

        // Date (passe : « hier », « lundi » = le dernier lundi)
        let d = expenseDate(folded, now: now, calendar: cal)
        p.date = d.date
        used.formUnion(d.indices)

        // Compte : « compte X », « carte X », « sur X »
        if let a = accountMention(folded, raw: tokens) {
            used.formUnion(a.indices)
            if let match = accounts.first(where: { TextFold.fold($0) == TextFold.fold(a.name) })
                ?? accounts.first(where: { TextFold.fold($0).contains(TextFold.fold(a.name)) }) {
                p.accountName = match
            } else {
                p.mentionedAccount = a.name
                p.flags.insert(.unknownAccount)
            }
        }

        // Verbes de depense : retires du titre.
        for (i, t) in folded.enumerated() where expenseVerbs.contains(t) || (t == "j'ai") { used.insert(i) }

        let rest = tokens.indices.filter { !used.contains($0) }.map { tokens[$0] }
        let title = rest.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        p.title = title

        if let c = guessCategory(rest.joined(separator: " ")) {
            p.category = c
            p.categoryGuessed = true
        } else {
            p.category = fallbackCategory
        }
        if p.title.isEmpty { p.title = p.category == fallbackCategory ? "Dépense" : p.category }
        return p
    }

    static func guessCategory(_ text: String) -> String? {
        let f = " " + TextFold.fold(text).components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ") + " "
        for (cat, words) in categoryKeywords {
            for w in words where f.contains(" " + TextFold.fold(w) + " ") { return cat }
        }
        return nil
    }

    // MARK: Montants

    struct MoneyMatch: Equatable {
        let value: Double
        let indices: [Int]
    }
    struct MoneyScan: Equatable {
        var marked: [MoneyMatch] = []
        var bare: [MoneyMatch] = []
    }

    private static let currencyWords: Set<String> = ["€", "eur", "euro", "euros"]

    /// Repere les montants : « 12€ », « 12,50 € », « €12 », « 12€50 », « 12 euros »,
    /// « 1 200 € ». Les heures (18h), dates (12/10) et priorites (!1) ne comptent pas.
    static func moneyTokens(_ tokens: [String]) -> MoneyScan {
        var scan = MoneyScan()
        var i = 0
        let lower = tokens.map { trimTrailing($0.lowercased()) }
        while i < tokens.count {
            let t = lower[i]
            // « 1 200 € »
            if i + 2 < tokens.count, t.count <= 3, t.allSatisfy(\.isNumber),
               case let (v, marked)? = moneyValue(lower[i + 1]), marked == false, lower[i + 1].count >= 3,
               lower[i + 1].prefix(3).allSatisfy(\.isNumber), currencyWords.contains(lower[i + 2]),
               let head = Double(t) {
                let digits = lower[i + 1].prefix(3)
                let total = head * 1000 + (Double(String(digits)) ?? 0) + (v - (Double(String(digits)) ?? 0))
                scan.marked.append(MoneyMatch(value: round2(total), indices: [i, i + 1, i + 2]))
                i += 3; continue
            }
            if case let (v, marked)? = moneyValue(t) {
                if marked {
                    scan.marked.append(MoneyMatch(value: v, indices: [i])); i += 1; continue
                }
                if i + 1 < tokens.count, currencyWords.contains(lower[i + 1]) {
                    scan.marked.append(MoneyMatch(value: v, indices: [i, i + 1])); i += 2; continue
                }
                if i > 0, lower[i - 1] == "€" {
                    scan.marked.append(MoneyMatch(value: v, indices: [i - 1, i])); i += 1; continue
                }
                scan.bare.append(MoneyMatch(value: v, indices: [i]))
            }
            i += 1
        }
        return scan
    }

    /// Valeur d'un mot, et s'il porte une marque monetaire.
    static func moneyValue(_ token: String) -> (Double, Bool)? {
        var s = trimTrailing(token.lowercased())
        guard !s.isEmpty, !s.hasPrefix("!"), !s.contains("/"), !s.contains(":") else { return nil }
        var marked = false
        if s.hasPrefix("€") { marked = true; s.removeFirst() }
        for suffix in ["euros", "euro", "eur", "€"] where s.hasSuffix(suffix) && s.count > suffix.count {
            marked = true; s.removeLast(suffix.count); break
        }
        // « 12€50 »
        if let r = s.range(of: "€") {
            let a = String(s[..<r.lowerBound]), b = String(s[r.upperBound...])
            guard !a.isEmpty, a.allSatisfy(\.isNumber), b.count == 2, b.allSatisfy(\.isNumber),
                  let v = Double(a + "." + b) else { return nil }
            return (v, true)
        }
        guard let first = s.first, first.isNumber else { return nil }
        guard s.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }) else { return nil }
        let normalized = s.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts[0].count <= 7 else { return nil }
        if parts.count == 2 { guard (1...2).contains(parts[1].count) else { return nil } }
        guard let v = Double(normalized), v > 0 else { return nil }
        return (round2(v), marked)
    }

    // MARK: Dates passees (depense)

    /// « hier », « avant-hier », « aujourd'hui », « lundi » (le dernier), « le 12 »,
    /// « 12/10 ». Par defaut : maintenant.
    static func expenseDate(_ folded: [String], now: Date, calendar cal: Calendar) -> (date: Date, indices: [Int]) {
        let today = cal.startOfDay(for: now)
        func noon(_ d: Date) -> Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d }
        for (i, t) in folded.enumerated() {
            switch t {
            case "hier": return (noon(cal.date(byAdding: .day, value: -1, to: today) ?? today), [i])
            case "avant-hier": return (noon(cal.date(byAdding: .day, value: -2, to: today) ?? today), [i])
            case "aujourd'hui", "aujourdhui": return (now, [i])
            default: break
            }
            if t == "avant", i + 1 < folded.count, folded[i + 1] == "hier" {
                return (noon(cal.date(byAdding: .day, value: -2, to: today) ?? today), [i, i + 1])
            }
            if let wd = TaskCapture.weekday(t) {
                // Le dernier jour de ce nom, aujourd'hui compris.
                for back in 0...6 {
                    if let d = cal.date(byAdding: .day, value: -back, to: today), cal.component(.weekday, from: d) == wd {
                        return (back == 0 ? now : noon(d), [i])
                    }
                }
            }
            if t.contains("/") {
                let p = t.split(separator: "/").compactMap { Int($0) }
                if p.count >= 2, (1...31).contains(p[0]), (1...12).contains(p[1]),
                   let d = pastDate(day: p[0], month: p[1], now: now, calendar: cal) {
                    return (noon(d), [i])
                }
            }
            if t == "le", i + 1 < folded.count, let day = Int(folded[i + 1]), (1...31).contains(day) {
                var month: Int?
                var idx = [i, i + 1]
                if i + 2 < folded.count, let m = TaskCapture.months[folded[i + 2]] { month = m; idx.append(i + 2) }
                if let d = pastDate(day: day, month: month, now: now, calendar: cal) { return (noon(d), idx) }
            }
        }
        return (now, [])
    }

    /// Le jour donne, dans le passe le plus proche (jamais dans le futur).
    static func pastDate(day: Int, month: Int?, now: Date, calendar cal: Calendar) -> Date? {
        var c = cal.dateComponents([.year, .month], from: now)
        c.day = day
        if let month { c.month = month }
        guard var d = cal.date(from: c), cal.component(.day, from: d) == day else { return nil }
        if d > now {
            d = cal.date(byAdding: month == nil ? .month : .year, value: -1, to: d) ?? d
        }
        return d
    }

    // MARK: Comptes

    /// « compte Revolut », « carte Boursorama », « sur Revolut ».
    static func accountMention(_ folded: [String], raw: [String]) -> (name: String, indices: [Int])? {
        for (i, t) in folded.enumerated() where (t == "compte" || t == "carte" || t == "sur") && i + 1 < folded.count {
            let next = raw[i + 1].trimmingCharacters(in: .punctuationCharacters)
            guard !next.isEmpty, moneyValue(next) == nil else { continue }
            // « sur » seul est courant (« sur le marche ») : seulement suivi d'une majuscule.
            if t == "sur", !(next.first?.isUppercase ?? false) { continue }
            return (next, [i, i + 1])
        }
        return nil
    }

    // MARK: Outils

    private static func trimTrailing(_ s: String) -> String {
        var t = s
        while let last = t.last, ",;.!?)".contains(last), t.count > 1 { t.removeLast() }
        return t
    }

    private static func cleanFold(_ s: String) -> String {
        TextFold.fold(trimTrailing(s))
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private static func uniqueValues(_ v: [Double]) -> [Double] {
        var seen = Set<Double>(), out: [Double] = []
        for x in v where seen.insert(x).inserted { out.append(x) }
        return out
    }
}
