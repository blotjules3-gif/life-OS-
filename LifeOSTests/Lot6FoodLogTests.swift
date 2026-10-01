import XCTest
import SwiftData
@testable import LifeOS

/// Lot 6, journal Yumzio: jour passe, recherche hors ligne, recents, favoris,
/// aliments perso, repas enregistres, copie de la veille, micronutriments.
@MainActor
final class Lot6FoodLogTests: XCTestCase {

    private var container: ModelContainer!
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: .now) }
    private var yesterday: Date { cal.date(byAdding: .day, value: -1, to: today)! }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([FoodEntry.self, FoodMicros.self, FavoriteFood.self, CustomFood.self, SavedMeal.self])
        container = try ModelContainer(for: schema,
                                       configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    override func tearDown() {
        StubURLProtocol.routes = []; StubURLProtocol.failWith = nil; StubURLProtocol.requested = []
        super.tearDown()
    }

    // MARK: Totaux du jour (widget, coach)

    /// Avant: CalAIView envoyait au widget les totaux du jour SELECTIONNE.
    func testTodayTotalsIgnoreTheDayBeingViewed() throws {
        let ctx = try makeContext()
        try FoodLogService.log([.init(name: "Hier soir", calories: 900, protein: 40, date: at(yesterday, 20)),
                                .init(name: "Ce matin", calories: 300, protein: 12, date: at(today, 8))], in: ctx)
        let all = try ctx.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(FoodJournal.totals(all, day: .now).kcal, 300)
        XCTAssertEqual(FoodJournal.totals(all, day: yesterday).kcal, 900)
        XCTAssertEqual(FoodJournal.totals(all, day: .now).protein, 12)
    }

    // MARK: Ajout sur un jour passe

    func testLineForPastDayLandsOnThatDay() throws {
        let ctx = try makeContext()
        let food = Per100Food(name: "Riz", brand: "", kcal: 130, protein: 2.7, carbs: 28, fat: 0.3, micros: .unknown)
        let line = FoodJournal.line(food, grams: 200, meal: "Dîner",
                                    date: FoodLogService.mealDate(day: yesterday))
        try FoodJournal.log([line], in: ctx)
        let all = try ctx.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(FoodJournal.totals(all, day: yesterday).kcal, 260)
        XCTAssertEqual(FoodJournal.totals(all, day: .now).kcal, 0, "un repas d'hier ne compte pas aujourd'hui")
    }

    // MARK: Navigation par jour

    func testDayNavigationNeverGoesPastToday() {
        XCTAssertEqual(FoodJournal.shift(today, by: 1), today)
        XCTAssertEqual(FoodJournal.shift(today, by: -1), yesterday)
        let tenAgo = cal.date(byAdding: .day, value: -10, to: today)!
        let strip = FoodJournal.stripDays(selected: tenAgo)
        XCTAssertEqual(strip.count, 7)
        XCTAssertTrue(strip.contains(tenAgo), "la bande suit le jour choisi, pas seulement la semaine en cours")
        XCTAssertLessThanOrEqual(strip.last!, today)
        XCTAssertEqual(FoodJournal.stripDays(selected: today).last, today)
        XCTAssertEqual(FoodJournal.dayTitle(today), "Aujourd'hui")
        XCTAssertEqual(FoodJournal.dayTitle(yesterday), "Hier")
    }

    // MARK: Recherche: hors ligne, panne, aucun resultat

    func testSearchClassificationSeparatesOfflineServerAndEmpty() {
        let offline = ProductCatalog.networkMessage(URLError(.notConnectedToInternet))
        XCTAssertEqual(FoodSearchService.classify(.unavailable(offline)), .offline(offline))
        XCTAssertEqual(FoodSearchService.classify(.unavailable("La base produit ne répond pas (erreur 503).")),
                       .serverError("La base produit ne répond pas (erreur 503)."))
        XCTAssertEqual(FoodSearchService.classify(.results([], hasMore: false)), .noResults)
        let noEnergy = CatalogProduct(barcode: "1", source: .food, name: "Sans valeurs")
        XCTAssertEqual(FoodSearchService.classify(.results([noEnergy], hasMore: false)), .onlyUnknownEnergy(1))
    }

    /// Le vieux chemin rendait [] hors ligne, d'ou "Aucun produit".
    func testOfflineSearchIsReportedAsOffline() async {
        let saved = ProductCatalog.session
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        ProductCatalog.session = URLSession(configuration: c)
        defer { ProductCatalog.session = saved }

        StubURLProtocol.failWith = URLError(.notConnectedToInternet)
        let old = await FoodSearchService.search("nutella")
        XCTAssertTrue(old.isEmpty, "l'ancienne API ne sait dire que 'vide'")
        guard case .offline = await FoodSearchService.outcome("nutella") else { return XCTFail("attendu hors ligne") }

        StubURLProtocol.failWith = nil
        StubURLProtocol.routes = [(match: "openfoodfacts", status: 503, body: Data("{}".utf8))]
        guard case .serverError = await FoodSearchService.outcome("nutella") else { return XCTFail("attendu panne serveur") }
    }

    // MARK: Recents

    func testRecentsAreDistinctAndMostRecentFirst() throws {
        let ctx = try makeContext()
        try FoodLogService.log([.init(name: "Yaourt", calories: 100, date: at(yesterday, 8)),
                                .init(name: "Pomme", calories: 80, date: at(yesterday, 16)),
                                .init(name: "yaourt", calories: 120, date: at(today, 8))], in: ctx)
        let r = FoodJournal.recents(try ctx.fetch(FetchDescriptor<FoodEntry>()))
        XCTAssertEqual(r.map(\.name), ["yaourt", "Pomme"])
        XCTAssertEqual(r.first?.calories, 120, "la derniere portion mangee est reprise")
    }

    // MARK: Copier la veille

    func testCopyPreviousDayKeepsTimeMealAndMicros() throws {
        let ctx = try makeContext()
        try FoodJournal.log([
            JournalLine(draft: .init(name: "Muesli", calories: 350, protein: 10, meal: "Petit-déj", date: at(yesterday, 7, 30)),
                        micros: .init(fiber: 6, sugars: nil, salt: 0.1)),
            JournalLine(draft: .init(name: "Pâtes", calories: 600, meal: "Déjeuner", date: at(yesterday, 12, 45))),
        ], in: ctx)
        let entries = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let idx = FoodJournal.microsIndex(try ctx.fetch(FetchDescriptor<FoodMicros>()))

        let breakfast = FoodJournal.copyLines(from: entries, micros: idx, sourceDay: yesterday, toDay: today, meal: "Petit-déj")
        XCTAssertEqual(breakfast.count, 1)
        XCTAssertEqual(breakfast[0].draft.date, at(today, 7, 30))
        XCTAssertEqual(breakfast[0].micros, .init(fiber: 6, sugars: nil, salt: 0.1))

        let day = FoodJournal.copyLines(from: entries, micros: idx, sourceDay: yesterday, toDay: today)
        try FoodJournal.log(day, in: ctx)
        let all = try ctx.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(FoodJournal.totals(all, day: .now).kcal, 950)
        XCTAssertEqual(FoodJournal.totals(all, day: yesterday).kcal, 950, "la veille n'est pas deplacee")
    }

    // MARK: Aliments perso et portions

    func testCustomFoodPortionScalesAndKeepsUnknownMicros() throws {
        let ctx = try makeContext()
        let c = CustomFood(name: "Gratin maison", kcalPer100: 150, proteinPer100: 6, carbsPer100: 12, fatPer100: 8,
                           microsPer100: .init(fiber: 2, sugars: nil, salt: 0.8), portionGrams: 250, portionLabel: "1 part")
        ctx.insert(c); try ctx.save()
        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<CustomFood>()).first)
        XCTAssertEqual(fetched.per100.defaultGrams, 250)
        let line = FoodJournal.line(fetched.per100, grams: 125, meal: "Dîner", date: .now)
        XCTAssertEqual(line.draft.calories, 188)
        XCTAssertEqual(line.draft.protein, 7.5, accuracy: 0.001)
        XCTAssertEqual(line.micros.fiber ?? -1, 2.5, accuracy: 0.001)
        XCTAssertNil(line.micros.sugars, "inconnu reste inconnu, jamais 0")
    }

    func testCustomFoodValidationAndParsing() {
        XCTAssertNotNil(FoodJournal.validateCustom(name: " ", kcal: 100, protein: 1, carbs: 1, fat: 1, portion: 100))
        XCTAssertNotNil(FoodJournal.validateCustom(name: "X", kcal: 1200, protein: 1, carbs: 1, fat: 1, portion: 100))
        XCTAssertNotNil(FoodJournal.validateCustom(name: "X", kcal: 400, protein: 60, carbs: 30, fat: 20, portion: 100))
        XCTAssertNotNil(FoodJournal.validateCustom(name: "X", kcal: 100, protein: 1, carbs: 1, fat: 1, portion: 0))
        XCTAssertNil(FoodJournal.validateCustom(name: "X", kcal: 100, protein: 5, carbs: 10, fat: 3, portion: 150))
        XCTAssertEqual(FoodJournal.parse("12,5"), .value(12.5))
        XCTAssertEqual(FoodJournal.parse(""), .empty)
        XCTAssertEqual(FoodJournal.parse("abc"), .invalid)
        XCTAssertEqual(FoodJournal.parse("-3"), .invalid)
    }

    // MARK: Repas enregistres et favoris

    func testSavedMealRoundTripsAndLogsEveryLine() throws {
        let ctx = try makeContext()
        try FoodJournal.log([
            JournalLine(draft: .init(name: "Pain", calories: 200, meal: "Petit-déj", date: at(yesterday, 8)),
                        micros: .init(fiber: 3, sugars: 1, salt: 0.5)),
            JournalLine(draft: .init(name: "Café", calories: 5, meal: "Petit-déj", date: at(yesterday, 8, 5))),
        ], in: ctx)
        let entries = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let items = FoodJournal.savedItems(from: entries, micros: FoodJournal.microsIndex(try ctx.fetch(FetchDescriptor<FoodMicros>())))
        ctx.insert(SavedMeal(name: "Petit-déj habituel", items: items)); try ctx.save()

        let meal = try XCTUnwrap(try ctx.fetch(FetchDescriptor<SavedMeal>()).first)
        XCTAssertEqual(meal.items.map(\.name), ["Pain", "Café"])
        XCTAssertEqual(meal.calories, 205)
        XCTAssertEqual(meal.items[0].fiber, 3)
        XCTAssertNil(meal.items[1].fiber)

        try FoodJournal.log(FoodJournal.lines(from: meal.items, day: today, mealName: "Collation"), in: ctx)
        let todayRows = try ctx.fetch(FetchDescriptor<FoodEntry>()).filter { cal.isDateInToday($0.date) }
        XCTAssertEqual(todayRows.count, 2)
        XCTAssertTrue(todayRows.allSatisfy { $0.meal == "Collation" })
    }

    func testFavoritePersistsWithItsPortion() throws {
        let ctx = try makeContext()
        ctx.insert(FavoriteFood(name: "Skyr", calories: 95, protein: 16, carbs: 6, fat: 0.3,
                                micros: .init(fiber: nil, sugars: 5, salt: 0.1)))
        try ctx.save()
        let f = try XCTUnwrap(try ctx.fetch(FetchDescriptor<FavoriteFood>()).first)
        XCTAssertEqual(f.calories, 95)
        XCTAssertEqual(f.micros, .init(fiber: nil, sugars: 5, salt: 0.1))
    }

    // MARK: Micronutriments

    func testDayMicroTotalNeverTurnsUnknownIntoZero() {
        XCTAssertEqual(FoodJournal.microTotal([nil, nil]).label, "inconnu")
        let mixed = FoodJournal.microTotal([2, nil, 3])
        XCTAssertEqual(mixed.known, 5)
        XCTAssertEqual(mixed.unknownCount, 1)
        XCTAssertEqual(mixed.label, "≥ 5.0 g")
        XCTAssertEqual(FoodJournal.microTotal([0]).label, "0.0 g", "un vrai zero reste affiche")
        XCTAssertEqual(FoodJournal.microText(nil), "inconnu")
    }

    func testFoodProductKeepsMicrosUnknownWhenTheBaseHasNone() throws {
        var p = CatalogProduct(barcode: "3017620422003", source: .food, name: "Pâte à tartiner")
        p.nutriments = .init(energyKcal: 539, proteins: 6.3, carbohydrates: 57.5, sugars: 56.3, fat: 30.9,
                             saturatedFat: 10.6, fiber: nil, salt: 0.107)
        let f = try XCTUnwrap(FoodProduct(p))
        XCTAssertEqual(f.sugars, 56.3)
        XCTAssertNil(f.fiber)
        XCTAssertNil(f.per100.micros.fiber)
    }

    private struct Boom: Error {}

    func testFailedJournalWriteLeavesNoLineAndNoMicros() throws {
        let ctx = try makeContext()
        XCTAssertThrowsError(try FoodJournal.log([JournalLine(draft: .init(name: "Soupe", calories: 120),
                                                              micros: .init(fiber: 3, sugars: nil, salt: 1))],
                                                 in: ctx, saver: { _ in throw Boom() }))
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<FoodEntry>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<FoodMicros>()), 0)
    }

    func testEditedLineKeepsItsMicrosAndDeleteCleansThem() throws {
        let ctx = try makeContext()
        let e = try XCTUnwrap(try FoodJournal.log([JournalLine(draft: .init(name: "Lentilles", calories: 230, date: at(today, 12)),
                                                                micros: .init(fiber: 8, sugars: nil, salt: nil))], in: ctx).first)
        let oldKey = FoodJournal.microsKey(e)
        try FoodLogService.update(e, to: .init(name: "Lentilles corail", calories: 230, date: at(yesterday, 12)), in: ctx)
        try FoodJournal.updateMicros(oldKey: oldKey, newKey: FoodJournal.microsKey(e),
                                     values: .init(fiber: 8, sugars: 1, salt: nil), in: ctx)
        let idx = FoodJournal.microsIndex(try ctx.fetch(FetchDescriptor<FoodMicros>()))
        XCTAssertEqual(idx[FoodJournal.microsKey(e)], .init(fiber: 8, sugars: 1, salt: nil))
        XCTAssertEqual(idx.count, 1)

        let key = FoodJournal.microsKey(e)
        try FoodLogService.delete(e, in: ctx)
        let micros = try ctx.fetch(FetchDescriptor<FoodMicros>())
        XCTAssertEqual(FoodJournal.orphanKeys(micros: micros, entries: []), [key])
        try FoodJournal.updateMicros(oldKey: key, newKey: key, values: .unknown, in: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<FoodMicros>()), 0)
    }
}
