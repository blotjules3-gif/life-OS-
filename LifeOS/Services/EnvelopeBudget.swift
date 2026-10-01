import Foundation
import SwiftData

// MARK: - Budget par enveloppes (Ynabi)
//
// Avant (audit du 1er oct.) : une enveloppe portait un seul montant `spent`, change par
// des boutons +10 / -10 et remis a zero au changement de mois. Le mois precedent etait
// perdu, et une depense saisie dans Bankino n'y apparaissait jamais.
// Maintenant la depense d'un mois se CALCULE : ecritures de l'enveloppe datees dans ce
// mois + operations bancaires de la categorie liee. Rien n'est remis a zero, donc
// chaque mois passe reste consultable, et une correction retroactive change bien le
// mois concerne.

enum EnvelopeMath {
    /// Numero de mois continu (annee * 12 + mois), pour comparer et reculer d'un mois
    /// sans se tromper au passage d'annee.
    static func monthKey(_ d: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month], from: d)
        return (c.year ?? 0) * 12 + (c.month ?? 1) - 1
    }

    static func startOfMonth(_ key: Int, calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: key / 12, month: key % 12 + 1, day: 1)) ?? .distantPast
    }

    /// Depense d'un mois, en centimes : ecritures de l'enveloppe + depenses bancaires
    /// (montants negatifs) de la categorie comptee. Les revenus de la categorie ne
    /// diminuent pas la depense : un remboursement se saisit comme ecriture negative.
    static func spentCents(month: Int, entries: [(date: Date, cents: Int)],
                           txns: [(date: Date, cents: Int)], calendar: Calendar = .current) -> Int {
        let fromEntries = entries.filter { monthKey($0.date, calendar: calendar) == month }.reduce(0) { $0 + $1.cents }
        let fromTxns = txns.filter { monthKey($0.date, calendar: calendar) == month && $0.cents < 0 }.reduce(0) { $0 - $1.cents }
        return fromEntries + fromTxns
    }

    /// Disponible du mois, en centimes. Sans report : budget - depense du mois.
    /// Avec report : on part du premier mois et on reporte le reste, positif OU negatif
    /// (un depassement se rattrape le mois suivant, comme dans YNAB).
    static func availableCents(month: Int, firstMonth: Int, budgetCents: Int, carryOver: Bool,
                               spentByMonth: (Int) -> Int) -> Int {
        guard carryOver, firstMonth < month else { return budgetCents - spentByMonth(month) }
        var carried = 0
        for m in firstMonth...month {
            carried = carried + budgetCents - spentByMonth(m)
        }
        return carried
    }
}

/// Lien entre une enveloppe et les donnees stockees.
@MainActor
enum EnvelopeBudget {
    static func cents(_ euros: Double) -> Int { Int((euros * 100).rounded()) }

    static func spentCents(_ e: Envelope, month: Int, entries: [EnvelopeEntry], txns: [Txn]) -> Int {
        let mine = entries.filter { $0.envelopeUID == e.uid }.map { (date: $0.date, cents: $0.amountCents) }
        let bank = txns.filter { $0.category == e.countedCategory }.map { (date: $0.date, cents: $0.amountCents) }
        return EnvelopeMath.spentCents(month: month, entries: mine, txns: bank)
    }

    static func availableCents(_ e: Envelope, month: Int, entries: [EnvelopeEntry], txns: [Txn]) -> Int {
        let first = EnvelopeMath.monthKey(e.createdAt == .distantPast ? .now : e.createdAt)
        return EnvelopeMath.availableCents(month: month, firstMonth: first, budgetCents: cents(e.monthlyBudget),
                                           carryOver: e.carryOver) { m in spentCents(e, month: m, entries: entries, txns: txns) }
    }

    /// Enveloppes depassees ce mois-ci (carte recap de la categorie Finances).
    static func overspentCount(_ envelopes: [Envelope], entries: [EnvelopeEntry], txns: [Txn], now: Date = .now) -> Int {
        let m = EnvelopeMath.monthKey(now)
        return envelopes.filter { $0.monthlyBudget > 0 && availableCents($0, month: m, entries: entries, txns: txns) < 0 }.count
    }
}

/// Migration une fois, sans rien perdre de ce qui existe encore : identifiant stable,
/// mois de depart, et l'ancien montant `spent` converti en UNE ecriture datee. Les mois
/// anterieurs n'ont jamais ete enregistres par l'ancienne version : on ne les invente pas.
@MainActor
enum EnvelopeMigration {
    static let legacyNote = "Montant saisi avant la mise à jour. Les mois précédents n'étaient pas enregistrés."

    /// Rend true si quelque chose a change (a enregistrer).
    @discardableResult
    static func run(_ ctx: ModelContext, now: Date = .now) -> Bool {
        let envelopes = (try? ctx.fetch(FetchDescriptor<Envelope>())) ?? []
        var changed = false
        for e in envelopes {
            if e.uid == nil { e.uid = UUID(); changed = true }
            if e.createdAt == .distantPast {
                e.createdAt = e.periodStart == .distantPast ? now : e.periodStart
                changed = true
            }
            if !e.migratedSpent, let uid = e.uid {
                if e.spent != 0 {
                    // Date : dans le mois auquel le montant se rapportait, sinon aujourd'hui.
                    let date = e.periodStart == .distantPast ? now : max(e.periodStart, EnvelopeMath.startOfMonth(EnvelopeMath.monthKey(e.periodStart)))
                    ctx.insert(EnvelopeEntry(envelopeUID: uid, date: date, amountCents: EnvelopeBudget.cents(e.spent), note: legacyNote))
                    e.spent = 0
                }
                e.migratedSpent = true
                changed = true
            }
        }
        return changed
    }
}
