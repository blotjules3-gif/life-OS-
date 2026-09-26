import Foundation

/// Partage de depenses, en CENTIMES entiers.
///
/// Deux defauts corriges ici, tous les deux visibles par l'utilisateur :
///
/// 1. **Le partage perdait des centimes.** `10 € / 3` valait `3,333...` et les trois
///    parts ne redonnaient pas 10 €. On repartit maintenant le reste : deux personnes
///    paient 3,34 € et une 3,33 €, total exactement 10,00 €.
///
/// 2. **Le remboursement envoyait toute la plus grosse dette au plus gros crediteur**,
///    puis tronquait le montant avec `Int()`. Avec des soldes -100 / +60 / +40 ca
///    affichait "doit 100 a X", ce qui est faux : il faut DEUX virements. Et 99,99 €
///    s'affichait 99 €.
enum SettlementCalculator {

    struct Transfer: Equatable {
        let from: String
        let to: String
        let cents: Int
        var amount: Double { Double(cents) / 100.0 }
    }

    /// Repartit un montant en parts entieres dont la somme est EXACTEMENT le montant.
    /// Le reste va aux premieres parts, une unite chacune.
    static func split(totalCents: Int, between count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let base = totalCents / count
        let remainder = totalCents % count
        // `remainder` suit le signe du total en Swift, ce qui garde un remboursement
        // negatif coherent.
        let step = totalCents < 0 ? -1 : 1
        return (0..<count).map { i in base + (i < abs(remainder) ? step : 0) }
    }

    /// Qui paie qui, en minimisant le nombre de virements.
    ///
    /// Algorithme glouton : le plus endette rembourse le plus crediteur, on solde le plus
    /// petit des deux, et on recommence. Il produit au plus n-1 virements.
    static func settle(balancesCents: [String: Int]) -> [Transfer] {
        var debtors  = balancesCents.filter { $0.value < 0 }.map { ($0.key, -$0.value) }.sorted { $0.1 > $1.1 }
        var creditors = balancesCents.filter { $0.value > 0 }.map { ($0.key,  $0.value) }.sorted { $0.1 > $1.1 }
        var out: [Transfer] = []
        var i = 0, j = 0
        while i < debtors.count && j < creditors.count {
            let pay = min(debtors[i].1, creditors[j].1)
            if pay > 0 { out.append(Transfer(from: debtors[i].0, to: creditors[j].0, cents: pay)) }
            debtors[i].1 -= pay
            creditors[j].1 -= pay
            if debtors[i].1 == 0 { i += 1 }
            if creditors[j].1 == 0 { j += 1 }
        }
        return out
    }

    /// Phrase affichee. Plus de troncature : on formate en euros avec les centimes.
    static func hint(balancesCents: [String: Int], locale: Locale = Locale(identifier: "fr_FR")) -> String {
        let transfers = settle(balancesCents: balancesCents)
        guard !transfers.isEmpty else { return "Tout est équilibré" }
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "EUR"; f.locale = locale
        return transfers.map { t in
            let amount = f.string(from: NSNumber(value: t.amount)) ?? "\(t.amount)"
            return "\(t.from) doit \(amount) à \(t.to)."
        }.joined(separator: "\n")
    }
}
