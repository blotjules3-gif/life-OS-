import Foundation

/// Lecture d'une annonce immobiliere collee en texte.
///
/// Le but: eviter de resaisir a la main le prix, la surface et les charges
/// qui sont deja ecrits dans l'annonce. On colle le texte, on obtient une
/// fiche pre-remplie, on corrige, on enregistre.
///
/// Ce qui n'est PAS fait, volontairement: estimer un loyer quand l'annonce
/// n'en donne pas. Un loyer invente se retrouverait dans le cashflow et dans
/// le rendement, donc dans une decision d'achat. Champ laisse vide, l'ecran
/// le dit.
enum ListingParser {

    /// Une fiche pre-remplie. Tout est optionnel: une annonce de vente ne
    /// porte pas de loyer, une annonce de location pas de prix d'achat.
    /// `Identifiable` sans UUID: l'identite est le contenu lu. Un UUID
    /// stocke casserait l'egalite entre deux lectures de la meme annonce.
    struct Draft: Equatable, Identifiable {
        var id: String { "\(name)|\(value)|\(monthlyRent)|\(surface)" }

        var name: String = ""
        var value: Double = 0          // prix affiche
        var monthlyRent: Double = 0
        var monthlyCharges: Double = 0
        var surface: Double = 0        // m2, sert a calculer le prix au m2
        var city: String = ""

        var isEmpty: Bool { name.isEmpty && value == 0 && monthlyRent == 0 }

        /// Prix au metre carre, seulement quand les deux sont connus.
        var pricePerM2: Double? {
            guard value > 0, surface > 0 else { return nil }
            return value / surface
        }
    }

    static let systemPrompt = """
    Tu extrais les chiffres d'une annonce immobilière. Réponds UNIQUEMENT par \
    un objet JSON, sans texte autour et sans balises de code. \
    Clés attendues : "name" (titre court, type de bien et ville), \
    "city" (la ville seule), "value" (prix de vente en euros, nombre), \
    "monthlyRent" (loyer mensuel en euros, nombre), \
    "monthlyCharges" (charges mensuelles en euros, nombre), \
    "surface" (surface habitable en m², nombre). \
    Mets 0 pour tout chiffre qui n'est PAS écrit dans l'annonce. \
    N'estime rien, n'invente rien : un prix au m² moyen du quartier n'est pas \
    une donnée de l'annonce. Les charges annuelles doivent être divisées par 12.
    """

    /// Lit la reponse du modele. Pure, donc testable sans reseau.
    ///
    /// Tolere les balises de code et le bavardage autour du JSON: les modeles
    /// repondent souvent "Voici le resultat :" malgre la consigne, et refuser
    /// ces reponses ferait echouer l'import pour rien.
    static func parse(_ raw: String) -> Draft? {
        guard let slice = jsonSlice(raw),
              let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var d = Draft()
        d.name = string(obj["name"])
        d.city = string(obj["city"])
        d.value = number(obj["value"])
        d.monthlyRent = number(obj["monthlyRent"])
        d.monthlyCharges = number(obj["monthlyCharges"])
        d.surface = number(obj["surface"])

        // Pas de conversion annuel vers mensuel ici, volontairement. J'avais
        // ecrit la regle "charges superieures au loyer, donc annuelles": avec
        // 300 de loyer et 400 de charges, un cas banal en petite surface, elle
        // divisait par douze en silence. La consigne du modele demande deja la
        // conversion, et l'utilisateur relit la fiche. Mieux vaut un chiffre
        // recopie qu'un chiffre corrige a tort sans que personne le voie.

        if d.name.isEmpty, !d.city.isEmpty { d.name = "Bien · \(d.city)" }
        return d.isEmpty ? nil : d
    }

    /// Le premier objet JSON complet du texte, accolades equilibrees.
    private static func jsonSlice(_ raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < raw.endIndex {
            let c = raw[i]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(raw[start...i]) }
                }
            }
            i = raw.index(after: i)
        }
        return nil
    }

    private static func string(_ v: Any?) -> String {
        guard let s = v as? String else { return "" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Accepte un nombre ou une chaine: les modeles rendent parfois "250 000 €".
    private static func number(_ v: Any?) -> Double {
        if let d = v as? Double { return max(0, d) }
        if let i = v as? Int { return max(0, Double(i)) }
        guard let s = v as? String else { return 0 }
        // On garde chiffres, virgule et point. Les espaces insecables des
        // montants francais ("250 000") disparaissent ainsi tout seuls.
        let cleaned = s.filter { $0.isNumber || $0 == "," || $0 == "." }
        // Le point francais est un separateur de MILLIERS, pas un decimal:
        // "250.000" vaut 250 000, et le lire comme 250 diviserait un prix
        // d'achat par mille sans que rien ne le signale.
        let parts = cleaned.replacingOccurrences(of: ",", with: ".")
            .split(separator: ".", omittingEmptySubsequences: false)
        let normalised: String
        if parts.count <= 1 {
            normalised = parts.first.map(String.init) ?? ""
        } else if parts.dropFirst().allSatisfy({ $0.count == 3 }) {
            normalised = parts.joined()                      // que des milliers
        } else {
            // Le dernier groupe n'a pas trois chiffres: c'est la partie
            // decimale, tout ce qui precede est l'entier.
            normalised = parts.dropLast().joined() + "." + parts[parts.count - 1]
        }
        return max(0, Double(normalised) ?? 0)
    }
}
