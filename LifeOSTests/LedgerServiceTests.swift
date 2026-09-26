import XCTest
import SwiftData
@testable import LifeOS

/// Le scenario exact demande dans l'audit : 100 → 80 → 70 → 100.
///
/// Il vaut la peine d'etre ecrit parce que l'ancien code echouait a DEUX endroits :
/// modifier une operation n'annulait pas l'ancien montant, et supprimer n'en rendait
/// rien. Le solde derivait donc en silence, sur de l'argent.
@MainActor
final class LedgerServiceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Account.self, Txn.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    func testAddEditDeleteKeepsBalanceExact() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Courant", kind: "Courant", balance: 100)
        ctx.insert(acc)
        XCTAssertEqual(acc.balance, 100, accuracy: 0.0001, "solde d'ouverture")

        let t = LedgerService.addTransaction(ctx, amount: -20, category: "Courses", account: acc, note: "")
        XCTAssertEqual(acc.balance, 80, accuracy: 0.0001, "apres -20")

        LedgerService.updateTransaction(ctx, t, amount: -30)
        XCTAssertEqual(acc.balance, 70, accuracy: 0.0001,
                       "apres modification a -30 : l'ancien -20 ne doit pas rester compte")

        LedgerService.deleteTransaction(ctx, t)
        XCTAssertEqual(acc.balance, 100, accuracy: 0.0001,
                       "apres suppression : l'argent doit revenir")
    }

    /// Deplacer une operation touche DEUX comptes.
    func testMovingATransactionUpdatesBothAccounts() throws {
        let ctx = try makeContext()
        let a = Account(name: "A", kind: "Courant", balance: 100)
        let b = Account(name: "B", kind: "Courant", balance: 100)
        ctx.insert(a); ctx.insert(b)

        let t = LedgerService.addTransaction(ctx, amount: -40, category: "X", account: a, note: "")
        XCTAssertEqual(a.balance, 60, accuracy: 0.0001)
        XCTAssertEqual(b.balance, 100, accuracy: 0.0001)

        LedgerService.updateTransaction(ctx, t, account: b)
        XCTAssertEqual(a.balance, 100, accuracy: 0.0001, "le compte d'origine est recredite")
        XCTAssertEqual(b.balance, 60, accuracy: 0.0001, "le compte d'arrivee est debite")
    }

    /// Renommer un compte ne doit plus orpheliner son historique.
    func testRenamingAnAccountKeepsItsTransactions() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Courant", kind: "Courant", balance: 100)
        ctx.insert(acc)
        LedgerService.addTransaction(ctx, amount: -25, category: "X", account: acc, note: "")

        acc.name = "Compte principal"
        LedgerService.recompute(ctx, account: acc)
        XCTAssertEqual(acc.balance, 75, accuracy: 0.0001,
                       "le rattachement se fait par identifiant, pas par nom")
    }

    /// Cent centimes ajoutes un par un doivent faire exactement un euro.
    func testMoneyDoesNotDriftOverManySmallAmounts() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Courant", kind: "Courant", balance: 0)
        ctx.insert(acc)
        for _ in 0..<100 {
            LedgerService.addTransaction(ctx, amount: 0.01, category: "X", account: acc, note: "")
        }
        XCTAssertEqual(acc.balance, 1.00, accuracy: 0.0000001,
                       "en Double cette somme donne 1.0000000000000007")
    }

    /// Supprimer un compte ne laisse pas d'operations orphelines.
    func testDeletingAnAccountRemovesItsTransactions() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Courant", kind: "Courant", balance: 50)
        ctx.insert(acc)
        LedgerService.addTransaction(ctx, amount: -10, category: "X", account: acc, note: "")
        LedgerService.deleteAccount(ctx, acc)
        let left = (try? ctx.fetch(FetchDescriptor<Txn>())) ?? []
        XCTAssertTrue(left.isEmpty, "les operations du compte supprime doivent partir avec lui")
    }
}

/// Migration depuis un magasin d'AVANT le passage aux centimes.
///
/// C'est le scenario bloquant signale par la revue, et c'etait un vrai defaut de ma
/// part : `amount` etait devenu une propriete CALCULEE, donc SwiftData supprimait la
/// colonne et toutes les operations deja enregistrees repartaient a 0.
@MainActor
final class LedgerMigrationTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Account.self, Txn.self])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
    }

    /// Une operation "ancienne" : montant dans l'ancienne colonne, centimes a 0,
    /// rattachement par NOM. Elle doit survivre intacte.
    func testOldTransactionKeepsItsAmount() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Courant", kind: "Courant", balance: 80)
        acc.openingBalanceMigrationVersion = 0 // legacy stored account
        ctx.insert(acc)

        let old = Txn(category: "Courses", account: "Courant", note: "avant maj")
        old.amount = -20            // ancienne colonne uniquement
        old.amountCents = 0         // comme apres une mise a jour de schema
        old.accountID = nil
        ctx.insert(old)

        LedgerService.migrateIfNeeded(ctx)

        XCTAssertEqual(old.amountCents, -2000, "le montant doit etre converti, pas perdu")
        XCTAssertEqual(old.accountID, acc.id, "rattachement par identifiant stable")
        XCTAssertEqual(acc.openingBalance, 100, accuracy: 0.0001,
                       "80 affiche - (-20) d'operations = 100 d'ouverture")
        LedgerService.recompute(ctx, account: acc)
        XCTAssertEqual(acc.balance, 80, accuracy: 0.0001,
                       "le solde affiche a l'utilisateur ne doit pas changer")
    }

    /// Le cas que la revue a signale nommement : compte avec un solde et AUCUNE
    /// operation. L'ancienne version sortait tot et laissait `openingBalance` a 0,
    /// donc le premier recalcul ramenait le solde a zero.
    func testAccountWithBalanceButNoTransactionsIsNotWiped() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Épargne", kind: "Épargne", balance: 500)
        acc.openingBalance = 0      // valeur par defaut apres migration de schema
        acc.openingBalanceMigrationVersion = 0 // legacy stored account
        ctx.insert(acc)

        LedgerService.migrateIfNeeded(ctx)
        LedgerService.recompute(ctx, account: acc)

        XCTAssertEqual(acc.balance, 500, accuracy: 0.0001, "500 EUR ne doivent pas disparaitre")
        XCTAssertEqual(acc.openingBalance, 500, accuracy: 0.0001)
    }

    /// Deux comptes portant le meme nom : le rattachement doit etre deterministe
    /// plutot que reparti au hasard.
    func testDuplicateAccountNamesAreDeterministic() throws {
        let ctx = try makeContext()
        let a1 = Account(name: "Courant", kind: "Courant", balance: 100)
        let a2 = Account(name: "Courant", kind: "Cash", balance: 50)
        ctx.insert(a1); ctx.insert(a2)
        let t = Txn(category: "X", account: "Courant", note: "")
        t.amount = -10; t.amountCents = 0; t.accountID = nil
        ctx.insert(t)

        LedgerService.migrateIfNeeded(ctx)
        XCTAssertTrue(t.accountID == a1.id || t.accountID == a2.id)
        XCTAssertNotNil(t.accountID, "l'operation doit etre rattachee a un seul compte")
    }

    /// Une operation dont le compte n'existe plus ne doit pas faire echouer la
    /// migration ni corrompre les autres soldes.
    func testOrphanTransactionDoesNotBreakMigration() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Courant", kind: "Courant", balance: 100)
        acc.openingBalanceMigrationVersion = 0 // legacy stored account
        ctx.insert(acc)
        let orphan = Txn(category: "X", account: "Compte supprimé", note: "")
        orphan.amount = -33; orphan.amountCents = 0; orphan.accountID = nil
        ctx.insert(orphan)

        LedgerService.migrateIfNeeded(ctx)
        XCTAssertNil(orphan.accountID, "aucun compte ne correspond")
        XCTAssertEqual(orphan.amountCents, -3300, "son montant est quand meme converti")
        LedgerService.recompute(ctx, account: acc)
        XCTAssertEqual(acc.balance, 100, accuracy: 0.0001,
                       "une operation orpheline ne doit pas entrer dans ce solde")
    }

    /// La migration ne doit pas etre destructrice si elle tourne deux fois.
    func testMigrationIsIdempotent() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Courant", kind: "Courant", balance: 80)
        acc.openingBalanceMigrationVersion = 0 // legacy stored account
        ctx.insert(acc)
        let t = Txn(category: "X", account: "Courant", note: "")
        t.amount = -20; t.amountCents = 0; t.accountID = nil
        ctx.insert(t)

        LedgerService.migrateIfNeeded(ctx)
        let opening = acc.openingBalance
        LedgerService.migrateIfNeeded(ctx)
        LedgerService.recompute(ctx, account: acc)

        XCTAssertEqual(acc.openingBalance, opening, accuracy: 0.0001, "pas de derive au second passage")
        XCTAssertEqual(acc.balance, 80, accuracy: 0.0001)
        XCTAssertEqual(t.amountCents, -2000, "la conversion ne doit pas etre appliquee deux fois")
    }
    func testMigrationRunsIndependentlyForRestoredStores() throws {
        for _ in 0..<2 {
            let ctx = try makeContext()
            let acc = Account(name: "Restored", balance: 80)
            acc.openingBalance = 0
            acc.openingBalanceMigrationVersion = 0
            ctx.insert(acc)
            let txn = Txn(amount: -20, category: "X", account: acc.name, note: "")
            ctx.insert(txn)
            LedgerService.migrateIfNeeded(ctx)
            try ctx.save()
            LedgerService.recompute(ctx, account: acc)
            XCTAssertEqual(acc.balance, 80, accuracy: 0.0001)
            XCTAssertEqual(acc.openingBalance, 100, accuracy: 0.0001)
            XCTAssertEqual(acc.openingBalanceMigrationVersion, 1)
        }
    }

    func testMigrationDoesNotRebaseNewAccountAfterTransaction() throws {
        let ctx = try makeContext()
        let acc = Account(name: "New", balance: 100)
        ctx.insert(acc)
        LedgerService.addTransaction(ctx, amount: -20, category: "X", account: acc, note: "")
        LedgerService.migrateIfNeeded(ctx)
        XCTAssertEqual(acc.openingBalance, 100, accuracy: 0.0001)
        XCTAssertEqual(acc.balance, 80, accuracy: 0.0001)
    }

}
