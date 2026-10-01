import XCTest
import SwiftData
@testable import LifeOS

/// Budget par enveloppes (Ynabi), audit du build 52 : l'ancien `spent` etait remis a zero
/// chaque mois et le mois precedent perdu. La depense d'un mois se calcule maintenant
/// depuis des ecritures datees et les operations Bankino de la categorie : chaque mois
/// reste consultable, une correction retroactive change le bon mois, le report est un
/// choix. Les dates sont injectees (on ne peut pas attendre le mois suivant).
@MainActor
final class EnvelopeRolloverTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? .distantPast
    }
    private func key(_ y: Int, _ m: Int) -> Int { EnvelopeMath.monthKey(date(y, m, 1), calendar: cal) }

    func testEachMonthKeepsItsOwnSpending() {
        let entries = [(date: date(2026, 3, 5), cents: 12_000), (date: date(2026, 4, 2), cents: 3_000)]
        XCTAssertEqual(EnvelopeMath.spentCents(month: key(2026, 3), entries: entries, txns: [], calendar: cal), 12_000,
                       "mars reste consultable apres le passage en avril")
        XCTAssertEqual(EnvelopeMath.spentCents(month: key(2026, 4), entries: entries, txns: [], calendar: cal), 3_000)
    }

    func testYearBoundary() {
        XCTAssertEqual(key(2026, 12) + 1, key(2027, 1))
        let entries = [(date: date(2026, 12, 31), cents: 500), (date: date(2027, 1, 1), cents: 700)]
        XCTAssertEqual(EnvelopeMath.spentCents(month: key(2027, 1), entries: entries, txns: [], calendar: cal), 700)
    }

    func testBankExpensesOfTheCategoryCountButIncomeDoesNot() {
        let txns = [(date: date(2026, 3, 10), cents: -4_550), (date: date(2026, 3, 11), cents: 10_000)]
        XCTAssertEqual(EnvelopeMath.spentCents(month: key(2026, 3), entries: [], txns: txns, calendar: cal), 4_550)
    }

    func testRefundEntryLowersTheMonth() {
        let entries = [(date: date(2026, 3, 5), cents: 8_000), (date: date(2026, 3, 20), cents: -2_000)]
        XCTAssertEqual(EnvelopeMath.spentCents(month: key(2026, 3), entries: entries, txns: [], calendar: cal), 6_000)
    }

    func testWithoutCarryOverEveryMonthStartsFromTheBudget() {
        let spent = [key(2026, 1): 25_000, key(2026, 2): 0]
        let feb = EnvelopeMath.availableCents(month: key(2026, 2), firstMonth: key(2026, 1), budgetCents: 10_000,
                                              carryOver: false) { spent[$0] ?? 0 }
        XCTAssertEqual(feb, 10_000, "un dépassement de janvier ne rend pas février rouge")
    }

    func testCarryOverMovesLeftoverAndOverspendToNextMonths() {
        let spent = [key(2026, 1): 6_000, key(2026, 2): 13_000, key(2026, 3): 2_000]
        func avail(_ m: Int) -> Int {
            EnvelopeMath.availableCents(month: m, firstMonth: key(2026, 1), budgetCents: 10_000, carryOver: true) { spent[$0] ?? 0 }
        }
        XCTAssertEqual(avail(key(2026, 1)), 4_000)
        XCTAssertEqual(avail(key(2026, 2)), 1_000, "4 000 reportés + 10 000 - 13 000")
        XCTAssertEqual(avail(key(2026, 3)), 9_000)
        XCTAssertEqual(avail(key(2026, 6)), 39_000, "trois mois sans dépense après mars : le reste s'accumule")
    }

    // Migration : rien de ce qui existe n'est perdu, rien d'ancien n'est inventé.

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Envelope.self, EnvelopeEntry.self, Txn.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testMigrationConvertsTheOldAmountOnceAndKeepsIt() throws {
        let c = try container()
        let ctx = ModelContext(c)
        let old = Envelope(name: "Courses", monthlyBudget: 400, spent: 120, periodStart: date(2026, 3, 1))
        old.uid = nil; old.createdAt = .distantPast; old.migratedSpent = false   // une enveloppe d'avant la mise à jour
        ctx.insert(old)
        XCTAssertTrue(EnvelopeMigration.run(ctx, now: date(2026, 3, 20)))
        let entries = try ctx.fetch(FetchDescriptor<EnvelopeEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.amountCents, 12_000)
        XCTAssertEqual(entries.first?.envelopeUID, old.uid)
        XCTAssertTrue(entries.first!.note.contains("n'étaient pas enregistrés"))
        XCTAssertEqual(old.spent, 0)
        XCTAssertFalse(EnvelopeMigration.run(ctx, now: date(2026, 3, 21)), "une seule fois")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<EnvelopeEntry>()).count, 1)
    }

    func testEditingAPastEntryChangesOnlyThatMonth() throws {
        let c = try container()
        let ctx = ModelContext(c)
        let e = Envelope(name: "Loisirs", monthlyBudget: 100)
        ctx.insert(e)
        let march = EnvelopeEntry(envelopeUID: e.uid!, date: date(2026, 3, 10), amountCents: 5_000)
        let april = EnvelopeEntry(envelopeUID: e.uid!, date: date(2026, 4, 10), amountCents: 2_000)
        ctx.insert(march); ctx.insert(april)
        march.amountCents = 9_000   // correction rétroactive
        let all = try ctx.fetch(FetchDescriptor<EnvelopeEntry>())
        let mine = all.map { (date: $0.date, cents: $0.amountCents) }
        XCTAssertEqual(EnvelopeMath.spentCents(month: key(2026, 3), entries: mine, txns: [], calendar: cal), 9_000)
        XCTAssertEqual(EnvelopeMath.spentCents(month: key(2026, 4), entries: mine, txns: [], calendar: cal), 2_000)
    }
}
