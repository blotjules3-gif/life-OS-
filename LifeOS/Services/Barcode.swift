import Foundation

/// Codes-barres produits (GTIN): EAN-8, UPC-A (12), EAN-13, GTIN-14.
///
/// Pourquoi (audit du 29 sept): le code etait seulement reduit aux chiffres puis
/// accepte de 6 a 14 caracteres. Un UPC-A scanne en 12 chiffres, un GTIN-14 avec
/// son zero de tete ou un EAN-13 lu avec un zero en trop ne retrouvaient pas la
/// fiche que la recherche par nom, elle, trouvait. On garde le code d'origine, on
/// calcule une forme canonique et quelques equivalences LEGITIMES (jamais une
/// troncature arbitraire).
enum Barcode {
    struct Normalized: Equatable {
        /// Ce que la camera ou le clavier a donne.
        let raw: String
        /// Chiffres ASCII seulement.
        let digits: String
        /// Forme sous laquelle les bases rangent le produit (EAN-13, ou EAN-8).
        let canonical: String
        /// Formes a essayer, dans l'ordre (canonique d'abord), sans doublon.
        let candidates: [String]
        /// nil = longueur sans chiffre de controle standard (code interne).
        let checksumValid: Bool?
        let kind: String
    }

    static func normalize(_ raw: String) -> Normalized? {
        // `isNumber` accepte aussi les chiffres arabes ou devanagari: seuls 0-9 comptent.
        let digits = String(raw.filter { $0.isASCII && $0.isNumber })
        guard (6...14).contains(digits.count) else { return nil }
        var canonical = digits
        var kind: String
        switch digits.count {
        case 8: kind = "EAN-8"
        case 12: kind = "UPC-A"; canonical = "0" + digits
        case 13: kind = "EAN-13"
        case 14:
            kind = "GTIN-14"
            // Un GTIN-14 de conditionnement unitaire commence par 0: c'est l'EAN-13.
            if digits.hasPrefix("0") { canonical = String(digits.dropFirst()) }
        default: kind = "code interne"
        }
        let checksum: Bool? = [8, 12, 13, 14].contains(digits.count) ? checksumOK(digits) : nil
        var cands = [canonical, digits]
        // EAN-13 rangee parfois en UPC-A (12 chiffres) dans la base.
        if canonical.count == 13, canonical.hasPrefix("0") { cands.append(String(canonical.dropFirst())) }
        // Zeros de tete en trop devant un EAN-8 valide ("00000" + 8 chiffres).
        if canonical.count == 13, canonical.hasPrefix("00000") {
            let short = String(canonical.suffix(8))
            if checksumOK(short) { cands.append(short) }
        }
        var seen = Set<String>()
        return Normalized(raw: raw, digits: digits, canonical: canonical,
                          candidates: cands.filter { seen.insert($0).inserted }, checksumValid: checksum, kind: kind)
    }

    /// Chiffre de controle GTIN (modulo 10, poids 3 et 1 depuis la droite).
    static func checksumOK(_ digits: String) -> Bool {
        let d = digits.compactMap { $0.wholeNumberValue }
        guard d.count >= 8, d.count == digits.count else { return false }
        let body = d.dropLast()
        let sum = body.reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10 == d.last!
    }
}

/// Ce qui s'est passe pendant une recherche par code: affiche quand le produit
/// n'est pas trouve, et journalise (sans photo, sans donnee personnelle).
struct LookupTrace: Equatable {
    struct Attempt: Equatable {
        let code: String
        let base: String
        let status: Int
        let outcome: String
    }
    var raw = ""
    var normalized: Barcode.Normalized?
    var attempts: [Attempt] = []
    var usedCache = false
    var usedLegacy = false
    /// Aucune base n'a pu dire "absent" pour la forme canonique: recherche a refaire.
    var incomplete = false

    /// Resume lisible: codes essayes, bases interrogees, reponses.
    var summary: String {
        guard let n = normalized else { return "Code invalide : il faut 8, 12, 13 ou 14 chiffres." }
        var parts = ["\(n.kind) \(n.digits)"]
        if n.checksumValid == false { parts.append("chiffre de contrôle faux (mauvaise lecture ?)") }
        if n.candidates.count > 1 { parts.append("formes essayées : " + n.candidates.joined(separator: ", ")) }
        let bases = Set(attempts.map(\.base)).sorted()
        if !bases.isEmpty { parts.append("bases : " + bases.joined(separator: ", ")) }
        if usedCache { parts.append("fiche retrouvée dans le cache de l'appareil") }
        if incomplete { parts.append("recherche incomplète") }
        return parts.joined(separator: " · ")
    }
}
