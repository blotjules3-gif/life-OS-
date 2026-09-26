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
