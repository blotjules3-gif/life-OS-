import XCTest
import SwiftData
@testable import LifeOS

/// Le journal alimentaire ne doit jamais annoncer un succes qu'il n'a pas eu.
///
/// Avant `FoodLogService`, un echec d'enregistrement affichait "Ajoute au journal",
/// effacait la saisie, et laissait l'objet non enregistre dans le contexte.
@MainActor
final class FoodLogServiceTests: XCTestCase {

    // Le contexte ne garde pas son conteneur en vie : on le garde ici.
    private var container: ModelContainer!

    private func makeContext() throws -> ModelContext {
        let schema = Schema([FoodEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func count(_ ctx: ModelContext) throws -> Int {
        try ctx.fetchCount(FetchDescriptor<FoodEntry>())
    }

    private struct Boom: Error {}

    private let draft = FoodLogService.Draft(name: "Poulet riz", calories: 610,
                                             protein: 45, carbs: 62, fat: 18)

    func testLogWritesEveryLine() throws {
        let ctx = try makeContext()
        var second = draft; second.name = "Yaourt"; second.calories = 120
        let saved = try FoodLogService.log([draft, second], in: ctx)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(try count(ctx), 2)
        let total = try ctx.fetch(FetchDescriptor<FoodEntry>()).caloriesToday
        XCTAssertEqual(total, 730, "le total du jour vient des lignes ecrites")
    }

    func testFailedSaveLeavesNothingBehind() throws {
        let ctx = try makeContext()
        XCTAssertThrowsError(try FoodLogService.log([draft], in: ctx, saver: { _ in throw Boom() })) { err in
            guard case FoodLogService.LogError.saveFailed = err else {
                return XCTFail("attendu saveFailed, recu \(err)")
            }
        }
        // Le point qui comptait : rien ne doit rester en attente, sinon le prochain
        // save d'un autre ecran l'ecrirait en douce.
        try ctx.save()
        XCTAssertEqual(try count(ctx), 0)
    }

    func testRetryAfterFailureWritesExactlyOnce() throws {
        let ctx = try makeContext()
        _ = try? FoodLogService.log([draft], in: ctx, saver: { _ in throw Boom() })
        try FoodLogService.log([draft], in: ctx)
        XCTAssertEqual(try count(ctx), 1, "un echec puis une reussite = une seule ligne")
    }

    func testInvalidDraftsAreRefusedBeforeAnyWrite() throws {
        let ctx = try makeContext()
        var noName = draft; noName.name = "   "
        var negative = draft; negative.calories = -5
        var nan = draft; nan.protein = .nan
        for bad in [noName, negative, nan] {
            XCTAssertThrowsError(try FoodLogService.log([draft, bad], in: ctx))
        }
        XCTAssertThrowsError(try FoodLogService.log([], in: ctx))
        XCTAssertEqual(try count(ctx), 0, "un lot avec une ligne invalide n'ecrit rien")
    }

    func testEditRecalculatesTheDayAndRevertsOnFailure() throws {
        let ctx = try makeContext()
        let e = try FoodLogService.log([draft], in: ctx)[0]

        var edited = draft; edited.calories = 400
        try FoodLogService.update(e, to: edited, in: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FoodEntry>()).caloriesToday, 400)

        var broken = draft; broken.calories = 999
        XCTAssertThrowsError(try FoodLogService.update(e, to: broken, in: ctx, saver: { _ in throw Boom() }))
        XCTAssertEqual(e.calories, 400, "un echec de modification remet l'ancienne valeur")
    }

    func testDeleteRemovesFromTheDay() throws {
        let ctx = try makeContext()
        let e = try FoodLogService.log([draft], in: ctx)[0]
        try FoodLogService.delete(e, in: ctx)
        XCTAssertEqual(try count(ctx), 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FoodEntry>()).caloriesToday, 0)
    }

    func testHistoricalMealDoesNotCountToday() throws {
        let ctx = try makeContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        var old = draft; old.date = FoodLogService.mealDate(day: yesterday)
        try FoodLogService.log([old, draft], in: ctx)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FoodEntry>()).caloriesToday, 610,
                       "le repas d'hier reste dans l'historique mais pas dans le jour")
    }

    /// Autour de minuit : un repas date "aujourd'hui" a 23:59 et un autre a 00:01
    /// le lendemain ne doivent pas se melanger.
    func testMealDateKeepsTheChosenDayAtAnyHour() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 0, minute: 0))!
        let lateNow = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 23, minute: 59))!
        let earlyNow = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 0, minute: 1))!
        for now in [lateNow, earlyNow] {
            let d = FoodLogService.mealDate(day: day, now: now, calendar: cal)
            XCTAssertEqual(cal.component(.day, from: d), 27)
        }
    }
}
