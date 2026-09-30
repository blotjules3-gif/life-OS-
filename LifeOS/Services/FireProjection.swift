import Foundation

/// Projection d'epargne investie, pure et testable.
///
/// Ce que le simulateur precedent ne faisait pas, et que ce type fait :
/// - un rendement NEGATIF est permis (une decennie perdue existe) ;
/// - les frais annuels sont retires du rendement ;
/// - l'inflation donne la valeur en euros d'aujourd'hui, pas seulement le chiffre nominal ;
/// - trois scenarios cote a cote, avec leurs hypotheses ecrites ;
/// - le capital de depart vient des PLACEMENTS : une residence ou une voiture ne
///   rapportent pas le rendement d'un portefeuille, les compter gonflait la courbe.
enum FireProjection {

    struct Point: Equatable {
        let year: Int
        let nominal: Double
        /// Meme montant, en euros d'aujourd'hui.
        let real: Double
        /// Somme versee depuis le debut (capital de depart compris).
        let invested: Double
    }

    struct Scenario: Identifiable, Equatable {
        let id: String
        let label: String
        /// Rendement annuel brut suppose, en %.
        let annualReturn: Double
        let points: [Point]
        var final: Point { points.last ?? Point(year: 0, nominal: 0, real: 0, invested: 0) }
    }

    /// Ecart des scenarios autour du rendement central, en points de %.
    static let pessimisticGap = -4.0
    static let optimisticGap = 2.0

    static func run(start: Double, monthly: Double, annualReturn: Double,
                    fees: Double, inflation: Double, years: Int) -> [Point] {
        let start = max(0, start), monthly = max(0, monthly), years = max(0, years)
        // Rendement net de frais, compose mensuellement. Plancher a -99 % pour ne jamais
        // prendre la racine d'un nombre negatif.
        let net = max(-0.99, (annualReturn - fees) / 100)
        let monthlyRate = pow(1 + net, 1.0 / 12) - 1
        let infl = max(-0.99, inflation / 100)
        var capital = start, invested = start
        var out = [Point(year: 0, nominal: capital, real: capital, invested: invested)]
        guard years > 0 else { return out }
        for year in 1...years {
            for _ in 0..<12 {
                capital = capital * (1 + monthlyRate) + monthly
                invested += monthly
            }
            let deflator = pow(1 + infl, Double(year))
            out.append(Point(year: year, nominal: capital, real: capital / deflator, invested: invested))
        }
        return out
    }

    static func scenarios(start: Double, monthly: Double, annualReturn: Double,
                          fees: Double, inflation: Double, years: Int) -> [Scenario] {
        [("pessimiste", "Pessimiste", annualReturn + pessimisticGap),
         ("central", "Central", annualReturn),
         ("optimiste", "Optimiste", annualReturn + optimisticGap)].map { id, label, r in
            Scenario(id: id, label: label, annualReturn: r,
                     points: run(start: start, monthly: monthly, annualReturn: r,
                                 fees: fees, inflation: inflation, years: years))
        }
    }

    /// Revenu mensuel qu'autorise la regle des 4 %, sur la valeur REELLE.
    static func safeMonthlyIncome(_ point: Point) -> Double { point.real * 0.04 / 12 }
}
