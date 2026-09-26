import Foundation
import SwiftData

/// Seul chemin d'ecriture autorise pour l'argent.
///
/// POURQUOI CE SERVICE EXISTE
///
/// Avant, chaque ecran touchait le solde lui meme :
/// - ajouter une operation faisait `acc.balance += v`
/// - supprimer une operation faisait `ctx.delete(t)` et ne remettait RIEN
/// - modifier une operation n'annulait pas l'ancien montant
///
/// Le solde affiche divergeait donc des operations reelles, sans rien signaler. C'est la
/// pire categorie de bug : silencieux, cumulatif, et sur de l'argent.
///
/// La correction n'est pas de "penser a remettre" a chaque endroit. Le solde est
/// DERIVE : `openingBalance + somme des operations du compte`. Il est recalcule apres
/// chaque ecriture. Une derive devient structurellement impossible, meme si un futur
/// ecran oublie quelque chose, tant qu'il passe par ici.
///
/// Les montants sont en CENTIMES entiers. Une somme de Double accumule des erreurs de
/// virgule flottante, et un solde faux d'un centime est un bug.
@MainActor
enum LedgerService {

    // MARK: - Ecritures

    @discardableResult
    static func addTransaction(_ ctx: ModelContext, amount: Double, category: String,
                               account: Account, note: String, date: Date = .now) -> Txn {
        let t = Txn(date: date, amount: amount, category: category,
                    account: account.name, note: note, accountID: account.id)
        t.setAmount(amount)   // garde l'ancienne colonne d'accord avec les centimes
        ctx.insert(t)
        recompute(ctx, account: account)
        return t
    }

    /// Modifier passe par ici : le recalcul repart des operations, donc l'ancien montant
    /// ne peut pas rester compte en double.
    static func updateTransaction(_ ctx: ModelContext, _ txn: Txn,
                                  amount: Double? = nil, category: String? = nil,
                                  note: String? = nil, date: Date? = nil,
                                  account: Account? = nil) {
        let previousID = txn.accountID
        if let amount { txn.setAmount(amount) }
        if let category { txn.category = category }
        if let note { txn.note = note }
        if let date { txn.date = date }
        if let account { txn.accountID = account.id; txn.account = account.name }
        // Un deplacement de compte touche DEUX soldes, pas un.
        if let previousID, previousID != txn.accountID { recompute(ctx, accountID: previousID) }
        recompute(ctx, accountID: txn.accountID)
    }

    static func deleteTransaction(_ ctx: ModelContext, _ txn: Txn) {
        let accountID = txn.accountID
        ctx.delete(txn)
        recompute(ctx, accountID: accountID)
    }

    /// Supprimer un compte ne doit pas laisser ses operations derriere : elles
    /// compteraient encore dans les totaux par categorie sans appartenir a rien.
    static func deleteAccount(_ ctx: ModelContext, _ account: Account) {
        for t in transactions(ctx, accountID: account.id) { ctx.delete(t) }
        ctx.delete(account)
    }

    // MARK: - Calcul

    static func recompute(_ ctx: ModelContext, account: Account) {
        let cents = transactions(ctx, accountID: account.id).reduce(0) { $0 + $1.amountCents }
        account.balance = account.openingBalance + Double(cents) / 100.0
    }

    static func recompute(_ ctx: ModelContext, accountID: UUID?) {
        guard let accountID, let acc = account(ctx, id: accountID) else { return }
        recompute(ctx, account: acc)
    }

    static func recomputeAll(_ ctx: ModelContext) {
        for a in (try? ctx.fetch(FetchDescriptor<Account>())) ?? [] { recompute(ctx, account: a) }
    }

    // MARK: - Reprise des donnees existantes

    /// Rattache les anciennes operations (liees par NOM) a un identifiant stable, puis
    /// reconstruit les soldes d'ouverture pour que le solde affiche aujourd'hui soit
    /// conserve. Sans ca la correction changerait les soldes de l'utilisateur.
    static func migrateIfNeeded(_ ctx: ModelContext) {
        let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        let all = (try? ctx.fetch(FetchDescriptor<Txn>())) ?? []

        // ETAPE 1 — convertir les anciens montants AVANT tout calcul.
        //
        // `amountCents` est arrive avec une valeur par defaut de 0. Une operation
        // enregistree avant la mise a jour n'a donc que son ancienne colonne `amount`
        // remplie. Sans cette conversion, tous les historiques repartent a zero et les
        // soldes recalcules sont faux. C'est la premiere chose a faire, avant le
        // rattachement et avant le recalcul.
        for t in all where t.amountCents == 0 && t.amount != 0 {
            t.amountCents = Int((t.amount * 100).rounded())
        }

        guard !accounts.isEmpty else { return }

        // ETAPE 2 — rattacher par identifiant. Les doublons de nom sont explicites :
        // le premier compte portant ce nom gagne, et on le note plutot que de repartir
        // les operations au hasard.
        var byName: [String: Account] = [:]
        for a in accounts where byName[a.name] == nil { byName[a.name] = a }

        var orphans = 0
        for t in all where t.accountID == nil {
            if let match = byName[t.account] { t.accountID = match.id }
            else { orphans += 1 }   // compte disparu : l'operation reste sans rattachement
        }

        // ETAPE 3 — reconstruire les soldes d'ouverture.
        //
        // Ceci doit tourner pour TOUS les comptes, pas seulement quand il reste des
        // operations a rattacher. Un compte cree avec 500 EUR et AUCUNE operation aurait
        // garde `openingBalance = 0` (la valeur par defaut), et le premier recalcul
        // aurait ramene son solde a 0. Le solde affiche aujourd'hui fait foi.
        let flagKey = "ledger.openingBalancesRebuilt.v1"
        if !UserDefaults.standard.bool(forKey: flagKey) {
            for a in accounts {
                let cents = all.filter { $0.accountID == a.id }.reduce(0) { $0 + $1.amountCents }
                a.openingBalance = a.balance - Double(cents) / 100.0
            }
            UserDefaults.standard.set(true, forKey: flagKey)
        }

        if orphans > 0 {
            // Visible plutot que silencieux : ces operations comptent encore dans les
            // totaux par categorie mais n'appartiennent a aucun compte.
            print("LedgerService: \(orphans) operation(s) sans compte correspondant")
        }
    }

    // MARK: - Lecture

    static func account(_ ctx: ModelContext, id: UUID) -> Account? {
        (try? ctx.fetch(FetchDescriptor<Account>()))?.first { $0.id == id }
    }

    static func transactions(_ ctx: ModelContext, accountID: UUID) -> [Txn] {
        ((try? ctx.fetch(FetchDescriptor<Txn>())) ?? []).filter { $0.accountID == accountID }
    }
}
