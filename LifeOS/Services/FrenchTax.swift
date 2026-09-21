import Foundation

/// Impot sur le revenu francais.
///
/// Sorti de `InvestModule` pour deux raisons: le calcul se teste sans
/// interface, et il etait faux.
///
/// Ce qui n'allait pas:
///   1. Le bareme etait celui de 2024 (revenus 2023), affiche en 2026. Deux
///      ans de retard sur un ecran qui annonce un montant d'impot.
///   2. Le plafonnement du quotient familial n'existait pas. Avec 5 parts,
///      l'ecran promettait une reduction d'impot que l'administration
///      refuse. Plus la famille est nombreuse et le revenu eleve, plus le
///      chiffre etait faux, et toujours dans le sens agreable.
///   3. La decote n'existait pas non plus. Aux revenus modestes, l'ecran
///      annoncait un impot plus gros que le reel.
///
/// Sources du bareme 2026 (revenus 2025), recoupees:
/// service-public.gouv.fr fiche F1419 et LegiFiscal.
enum FrenchTax {

    /// Situation de famille. Elle decide de la part de base et du seuil de
    /// decote, donc on ne peut pas s'en passer: c'etait l'information
    /// manquante de l'ancien ecran.
    enum Status: String, CaseIterable, Identifiable {
        case single = "Célibataire"
        case couple = "Couple"
        var id: String { rawValue }

        /// Parts sans personne a charge.
        var baseParts: Double { self == .single ? 1 : 2 }
        /// En dessous de ce montant d'impot brut, la decote s'applique.
        var decoteCeiling: Double { self == .single ? 1_982 : 3_277 }
        var decoteBase: Double { self == .single ? 897 : 1_483 }
    }

    /// Bareme 2026 sur les revenus 2025, par part.
    /// Les bornes sont les limites SUPERIEURES de chaque tranche.
    static let brackets: [(upTo: Double, rate: Double)] = [
        (11_600, 0.00),
        (29_579, 0.11),
        (84_577, 0.30),
        (181_917, 0.41),
        (.infinity, 0.45),
    ]

    /// Plafond de l'avantage procure par chaque DEMI-part supplementaire.
    static let halfPartCap: Double = 1_807

    /// Taux applique a la derniere tranche atteinte, ce que tout le monde
    /// appelle sa "tranche".
    static func marginalRate(perPartIncome: Double) -> Double {
        for b in brackets where perPartIncome <= b.upTo { return b.rate }
        return brackets.last?.rate ?? 0
    }

    /// Impot d'UNE part, avant tout plafonnement et avant decote.
    static func taxForOnePart(_ perPartIncome: Double) -> Double {
        guard perPartIncome > 0 else { return 0 }
        var tax = 0.0
        var low = 0.0
        for b in brackets {
            if perPartIncome <= low { break }
            tax += (min(perPartIncome, b.upTo) - low) * b.rate
            low = b.upTo
        }
        return tax
    }

    /// Le detail du calcul, pas seulement le total: un ecran qui montre
    /// uniquement le montant final ne permet pas de comprendre pourquoi
    /// ajouter une part ne change presque rien.
    struct Result: Equatable {
        /// Impot apres quotient familial, avant plafonnement.
        let beforeCap: Double
        /// Avantage refuse par le plafonnement du quotient familial.
        let capLoss: Double
        /// Impot apres plafonnement, avant decote.
        let beforeDecote: Double
        let decote: Double
        /// Ce qui est reellement du.
        let total: Double
        let marginalRate: Double
    }

    /// Impot du, quotient familial plafonne et decote comprise.
    ///
    /// `parts` est le nombre TOTAL de parts, base comprise: 2 pour un couple
    /// sans enfant, 2,5 avec un enfant.
    static func compute(income: Double, parts: Double, status: Status) -> Result {
        guard income > 0 else {
            return Result(beforeCap: 0, capLoss: 0, beforeDecote: 0, decote: 0,
                          total: 0, marginalRate: 0)
        }
        let base = status.baseParts
        let totalParts = max(base, parts)

        let withParts = taxForOnePart(income / totalParts) * totalParts
        let atBase = taxForOnePart(income / base) * base

        // Le quotient familial ne peut pas faire gagner plus que le plafond
        // par demi-part supplementaire.
        let extraHalfParts = ((totalParts - base) / 0.5).rounded()
        let maxAdvantage = extraHalfParts * halfPartCap
        let advantage = max(0, atBase - withParts)
        let capped = advantage > maxAdvantage ? atBase - maxAdvantage : withParts
        let capLoss = (capped - withParts).rounded()

        // Decote: elle efface une partie de l'impot des revenus modestes.
        var decote = 0.0
        if capped < status.decoteCeiling {
            decote = min(capped, max(0, status.decoteBase - 0.4525 * capped))
        }

        return Result(beforeCap: withParts.rounded(),
                      capLoss: capLoss,
                      beforeDecote: capped.rounded(),
                      decote: decote.rounded(),
                      total: max(0, capped - decote).rounded(),
                      marginalRate: marginalRate(perPartIncome: income / totalParts))
    }
}
