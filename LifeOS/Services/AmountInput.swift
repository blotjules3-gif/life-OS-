import Foundation

/// Lecture d'un montant tape a la main.
///
/// L'ancien `parseAmount` rendait 0 pour tout ce qu'il ne comprenait pas:
/// "abc", "1 234,56" ou "12 €" enregistraient 0 € sans rien dire. Ici un
/// montant est vide, valide, ou invalide AVEC une explication, et un formulaire
/// ne peut pas valider un montant invalide.
enum AmountInput {

    enum Parsed: Equatable {
        case empty
        case valid(Double)
        case invalid(String)

        var value: Double? { if case .valid(let v) = self { return v } else { return nil } }
        var message: String? { if case .invalid(let m) = self { return m } else { return nil } }
    }

    struct Rules {
        var required = true
        var allowNegative = false
        var allowZero = false
        static let positive = Rules()
        static let optional = Rules(required: false, allowZero: true)
        static let signed = Rules(allowNegative: true, allowZero: true)
    }

    static let example = "Exemple : 12,50 ou 1 234,50"

    static func parse(_ raw: String, rules: Rules = .positive) -> Parsed {
        // Espaces (y compris insecables et fines insecables) et symboles monetaires.
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["\u{00A0}", "\u{202F}", " ", "€", "EUR", "eur", "$", "£"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        if s.isEmpty {
            return rules.required ? .invalid("Montant obligatoire. \(example)") : .empty
        }
        var negative = false
        if s.hasPrefix("-") || s.hasPrefix("−") { negative = true; s.removeFirst() }
        else if s.hasPrefix("+") { s.removeFirst() }

        guard !s.isEmpty, s.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }),
              s.first!.isNumber || s.first == "," || s.first == "."
        else { return .invalid("« \(raw.trimmingCharacters(in: .whitespaces)) » n'est pas un montant. \(example)") }

        guard let normalized = normalize(s), let v = Double(normalized), v.isFinite else {
            return .invalid("« \(raw.trimmingCharacters(in: .whitespaces)) » n'est pas un montant lisible. \(example)")
        }
        let value = negative ? -v : v
        if value < 0 && !rules.allowNegative { return .invalid("Le montant doit être positif.") }
        if value == 0 && !rules.allowZero { return .invalid("Le montant doit être supérieur à 0.") }
        if abs(value) >= 1_000_000_000 { return .invalid("Montant trop grand.") }
        return .valid(value)
    }

    /// Chiffres + separateurs -> format "1234.56", ou nil si ambigu ou mal forme.
    /// Le DERNIER separateur present des deux est le separateur decimal; un seul
    /// type de separateur repete plusieurs fois est un separateur de milliers.
    private static func normalize(_ s: String) -> String? {
        let commas = s.filter { $0 == "," }.count
        let dots = s.filter { $0 == "." }.count
        func groupedOK(_ intPart: Substring, sep: Character) -> Bool {
            let groups = intPart.split(separator: sep, omittingEmptySubsequences: false)
            guard let first = groups.first, (1...3).contains(first.count) else { return false }
            return groups.dropFirst().allSatisfy { $0.count == 3 }
        }
        switch (commas, dots) {
        case (0, 0):
            return s
        case (_, 0) where commas > 1:
            return groupedOK(Substring(s), sep: ",") ? s.replacingOccurrences(of: ",", with: "") : nil
        case (0, _) where dots > 1:
            return groupedOK(Substring(s), sep: ".") ? s.replacingOccurrences(of: ".", with: "") : nil
        case (1, 0):
            return s.replacingOccurrences(of: ",", with: ".")
        case (0, 1):
            return s
        default:
            // Les deux: le dernier est decimal, l'autre groupe les milliers.
            guard let lastComma = s.lastIndex(of: ","), let lastDot = s.lastIndex(of: ".") else { return nil }
            let decimalSep: Character = lastComma > lastDot ? "," : "."
            let groupSep: Character = decimalSep == "," ? "." : ","
            guard s.filter({ $0 == decimalSep }).count == 1,
                  let d = s.lastIndex(of: decimalSep) else { return nil }
            let intPart = s[..<d], frac = s[s.index(after: d)...]
            guard !frac.contains(groupSep), groupedOK(intPart, sep: groupSep) else { return nil }
            return intPart.replacingOccurrences(of: String(groupSep), with: "") + "." + frac
        }
    }
}
