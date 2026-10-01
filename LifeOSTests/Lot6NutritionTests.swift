import XCTest
import SwiftData
@testable import LifeOS

/// Lot 6 Nutrition : Zerø, Fridgy, Bringo, WaterMind, SuppSafe, Figue.
final class Lot6FastingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testOverlapAndSecondActiveFastAreRefused() {
        let past = FastingRules.Span(start: now.addingTimeInterval(-30 * 3600), end: now.addingTimeInterval(-14 * 3600))
        // Chevauche le jeune passe.
        XCTAssertNotNil(FastingRules.validate(start: now.addingTimeInterval(-20 * 3600), end: now.addingTimeInterval(-2 * 3600),
                                              others: [past], now: now))
        // Juste apres : accepte.
        XCTAssertNil(FastingRules.validate(start: now.addingTimeInterval(-14 * 3600), end: now.addingTimeInterval(-1 * 3600),
                                           others: [past], now: now))
        // Deux jeunes en cours : refuse.
        let running = FastingRules.Span(start: now.addingTimeInterval(-3600), end: nil)
        XCTAssertEqual(FastingRules.validate(start: now, end: nil, others: [running], now: now), "Un jeûne est déjà en cours.")
    }

    func testEditedTimesMustBeCoherent() {
        XCTAssertNotNil(FastingRules.validate(start: now, end: now.addingTimeInterval(-60), others: [], now: now))
        XCTAssertNotNil(FastingRules.validate(start: now.addingTimeInterval(3600), end: nil, others: [], now: now))
        XCTAssertNotNil(FastingRules.validate(start: now.addingTimeInterval(-200 * 3600), end: now, others: [], now: now))
        // Debut avant minuit, fin le lendemain : accepte, duree 18 h.
        let start = now.addingTimeInterval(-18 * 3600)
        XCTAssertNil(FastingRules.validate(start: start, end: now, others: [], now: now))
    }

    func testStreakCountsConsecutiveReachedDays() {
        let cal = Calendar.current
        func day(_ back: Int) -> Date { cal.date(byAdding: .day, value: -back, to: now)! }
        XCTAssertEqual(FastingRules.streak([(day(0), true), (day(1), true), (day(2), true), (day(4), true)], now: now), 3)
        // Rien aujourd'hui mais hier : la serie tient encore.
        XCTAssertEqual(FastingRules.streak([(day(1), true), (day(2), true)], now: now), 2)
        // Objectif manque = la serie casse.
        XCTAssertEqual(FastingRules.streak([(day(0), true), (day(1), false), (day(2), true)], now: now), 1)
        XCTAssertEqual(FastingRules.streak([(day(3), true)], now: now), 0)
    }

    func testCustomTargetLabel() {
        XCTAssertEqual(FastingRules.label(forTarget: 16), "16:8")
        XCTAssertEqual(FastingRules.label(forTarget: 36), "36 h")
        XCTAssertTrue(FastingRules.customRange.contains(72))
    }

    @MainActor
    func testNotePersists() throws {
        let c = try ModelContainer(for: FastingSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let s = FastingSession(start: now.addingTimeInterval(-16 * 3600), end: now, targetHours: 16)
        s.note = "facile"
        c.mainContext.insert(s); try c.mainContext.save()
        XCTAssertEqual(try c.mainContext.fetch(FetchDescriptor<FastingSession>()).first?.note, "facile")
    }
}

final class Lot6PantryTests: XCTestCase {
    func testFilterAndSortByExpiry() {
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        let rows = [PantryOps.Row(name: "Yaourt", category: "Laitier", location: "Frigo", expiry: d.addingTimeInterval(5 * 86400)),
                    PantryOps.Row(name: "Riz", category: "Féculent", location: "Placard", expiry: nil),
                    PantryOps.Row(name: "Lait", category: "Laitier", location: "Frigo", expiry: d.addingTimeInterval(86400)),
                    PantryOps.Row(name: "Pâtes", category: "Féculent", location: "Placard", expiry: d.addingTimeInterval(90 * 86400))]
        XCTAssertEqual(PantryOps.filterSort(rows, location: nil, category: nil, sort: .expiry), [2, 0, 3, 1], "sans date a la fin")
        XCTAssertEqual(PantryOps.filterSort(rows, location: "Frigo", category: nil, sort: .name), [2, 0])
        XCTAssertEqual(PantryOps.filterSort(rows, location: nil, category: "Féculent", sort: .name), [3, 1])
    }

    func testAlertDateIsBeforeExpiryAndNeverInThePast() {
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
        let expiry = cal.date(byAdding: .day, value: 3, to: now)!
        let at = PantryOps.alertDate(expiry: expiry, daysBefore: 1, now: now)!
        XCTAssertEqual(cal.dateComponents([.day], from: cal.startOfDay(for: at), to: cal.startOfDay(for: expiry)).day, 1)
        XCTAssertEqual(cal.component(.hour, from: at), 9)
        XCTAssertNil(PantryOps.alertDate(expiry: now, daysBefore: 2, now: now))
    }

    @MainActor
    func testEditedItemKeepsNewValues() throws {
        let c = try ModelContainer(for: PantryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let it = PantryItem(name: "Lait", quantity: "1", category: "Laitier", location: "Frigo")
        c.mainContext.insert(it); try c.mainContext.save()
        it.quantity = "2 L"; it.alertDaysBefore = 3; it.stableID = "abc"
        try c.mainContext.save()
        let back = try c.mainContext.fetch(FetchDescriptor<PantryItem>()).first!
        XCTAssertEqual(back.quantity, "2 L"); XCTAssertEqual(back.alertDaysBefore, 3)
        XCTAssertEqual(PantryOps.notificationID(back.stableID), "pantry.abc")
    }
}

final class Lot6ShoppingTests: XCTestCase {
    func testCompatibleQuantitiesMerge() {
        XCTAssertEqual(ShoppingUnits.merged(existing: ("500", "g"), adding: ("1", "kg")), "1500")
        XCTAssertEqual(ShoppingUnits.merged(existing: ("1", "L"), adding: ("50", "cl")), "1,5")
        XCTAssertEqual(ShoppingUnits.merged(existing: ("2", ""), adding: ("1", "")), "3")
        // Incompatibles ou texte libre : on ne devine pas.
        XCTAssertNil(ShoppingUnits.merged(existing: ("2", ""), adding: ("1", "kg")))
        XCTAssertNil(ShoppingUnits.merged(existing: ("un peu", ""), adding: ("1", "")))
    }

    func testMemoryRecentsFavouritesAndPendingExcluded() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var m = ShoppingMemory.record([], name: "Lait", aisle: "Crèmerie", unit: "L", now: t0)
        m = ShoppingMemory.record(m, name: "Pain", aisle: "Boulangerie", unit: "", now: t0.addingTimeInterval(10))
        m = ShoppingMemory.record(m, name: "lait", aisle: "Mon rayon", unit: "L", now: t0.addingTimeInterval(20))
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m.first { $0.name == "Lait" }?.count, 2)
        XCTAssertEqual(m.first { $0.name == "Lait" }?.aisle, "Mon rayon", "le rayon choisi est retenu")
        m = ShoppingMemory.setFavorite(m, name: "Pain", aisle: "Boulangerie", unit: "", on: true)
        XCTAssertEqual(ShoppingMemory.suggestions(m, query: "", toBuy: []).map(\.name), ["Pain", "Lait"])
        XCTAssertEqual(ShoppingMemory.suggestions(m, query: "", toBuy: ["pain"]).map(\.name), ["Lait"])
        XCTAssertEqual(ShoppingMemory.suggestions(m, query: "la", toBuy: []).map(\.name), ["Lait"])
        XCTAssertEqual(ShoppingMemory.decode(ShoppingMemory.encode(m)), m)
    }

    func testMemoryCapKeepsFavourites() {
        var m = ShoppingMemory.setFavorite([], name: "Vieux favori", aisle: "Divers", unit: "", on: true)
        for i in 0..<(ShoppingMemory.cap + 5) {
            m = ShoppingMemory.record(m, name: "Article \(i)", aisle: "Divers", unit: "", now: Date(timeIntervalSince1970: Double(10_000 + i)))
        }
        XCTAssertEqual(m.count, ShoppingMemory.cap)
        XCTAssertTrue(m.contains { $0.name == "Vieux favori" })
    }
}

final class Lot6WaterTests: XCTestCase {
    func testCountedFollowsUserPercentAndDefaultsAreFull() {
        XCTAssertTrue(WaterMath.defaults.allSatisfy { $0.percent == 100 }, "aucun coefficient invente par defaut")
        XCTAssertEqual(WaterMath.counted(volume: 250, percent: 100), 250)
        XCTAssertEqual(WaterMath.counted(volume: 250, percent: 80), 200)
        XCTAssertEqual(WaterMath.counted(volume: 250, percent: 150), 250)
        XCTAssertEqual(WaterMath.volume(amountML: 300, volumeML: 0), 300, "anciennes prises")
        XCTAssertEqual(WaterMath.decode(""), WaterMath.defaults)
    }

    func testGoalSuggestionOnlyWithARealWeight() {
        XCTAssertNil(WaterMath.knownWeight(latestVital: nil, profileKg: 0, setupKg: nil))
        XCTAssertEqual(WaterMath.knownWeight(latestVital: 68, profileKg: 80, setupKg: 75), 68)
        XCTAssertEqual(WaterMath.knownWeight(latestVital: nil, profileKg: 0, setupKg: 70), 70)
        let s = WaterMath.suggestedGoal(weightKg: 70)!
        XCTAssertEqual(s.low, 2100); XCTAssertEqual(s.high, 2500); XCTAssertEqual(s.suggested, 2500)
        XCTAssertEqual(WaterMath.suggestedGoal(weightKg: 200)?.high, 5000, "borne a l'ecran")
    }

    @MainActor
    func testEditedEntryChangesTodayTotal() throws {
        let c = try ModelContainer(for: WaterEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let e = WaterEntry(amountML: 250); e.volumeML = 250
        c.mainContext.insert(e); try c.mainContext.save()
        e.volumeML = 300; e.amountML = WaterMath.counted(volume: 300, percent: 100); e.beverage = "Thé"
        try c.mainContext.save()
        let all = try c.mainContext.fetch(FetchDescriptor<WaterEntry>())
        XCTAssertEqual(all.reduce(0) { $0 + $1.amountML }, 300)
        XCTAssertEqual(all.first?.beverage, "Thé")
    }
}

final class Lot6SupplementTests: XCTestCase {
    func testTimesParsingAndLegacyFallback() {
        XCTAssertEqual(SupplementSchedule.parseTimes("20:00, 08:30,25:00,08:30"),
                       [.init(hour: 8, minute: 30), .init(hour: 20, minute: 0)])
        XCTAssertEqual(SupplementSchedule.times(raw: "", hour: 9, minute: 15), [.init(hour: 9, minute: 15)])
        XCTAssertEqual(SupplementSchedule.formatTimes([.init(hour: 20, minute: 0), .init(hour: 8, minute: 5)]), "08:05,20:00")
    }

    func testOneNotificationPerDoseAndChosenDays() {
        let daily = SupplementSchedule.slots(stableID: "X", times: [.init(hour: 8, minute: 0), .init(hour: 20, minute: 0)],
                                             daysRaw: "", confirm: false)
        XCTAssertEqual(daily.map(\.id), ["supp.X.t0", "supp.X.t1"])
        XCTAssertTrue(daily.allSatisfy { $0.weekday == nil })
        // Lundi et mercredi : un rappel hebdomadaire par jour, weekday Calendar (lun = 2).
        let weekly = SupplementSchedule.slots(stableID: "X", times: [.init(hour: 8, minute: 0)], daysRaw: "1,3", confirm: true)
        XCTAssertEqual(weekly.filter { !$0.isConfirm }.compactMap(\.weekday), [2, 4])
        XCTAssertEqual(weekly.filter(\.isConfirm).first?.hour, 9)
        XCTAssertEqual(weekly.filter(\.isConfirm).first?.minute, 30)
        // Tous les ids partagent le prefixe remplace d'un coup : renommer n'en laisse aucun.
        XCTAssertTrue((daily + weekly).allSatisfy { $0.id.hasPrefix(SupplementSchedule.baseID("X")) })
        // Verification qui passe minuit : le jour suivant.
        let late = SupplementSchedule.slots(stableID: "X", times: [.init(hour: 23, minute: 30)], daysRaw: "7", confirm: true)
        XCTAssertEqual(late.first { $0.isConfirm }?.weekday, 2, "dimanche 23h30 -> verif lundi 1h")
    }

    func testDueDays() {
        let cal = Calendar.current
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 5; c.hour = 10   // lundi
        let monday = cal.date(from: c)!
        XCTAssertTrue(SupplementSchedule.isDue(on: monday, daysRaw: "1,3"))
        XCTAssertFalse(SupplementSchedule.isDue(on: monday, daysRaw: "2,4"))
        XCTAssertTrue(SupplementSchedule.isDue(on: monday, daysRaw: ""))
    }

    func testStockRefillAndAdherence() {
        XCTAssertEqual(SupplementSchedule.stock(after: 10, unitsPerDose: 2, taken: true, undo: false), 8)
        XCTAssertEqual(SupplementSchedule.stock(after: 1, unitsPerDose: 2, taken: true, undo: false), 0)
        XCTAssertEqual(SupplementSchedule.stock(after: 8, unitsPerDose: 2, taken: true, undo: true), 10)
        XCTAssertEqual(SupplementSchedule.stock(after: 8, unitsPerDose: 2, taken: false, undo: false), 8, "sautee ne touche pas au stock")
        XCTAssertEqual(SupplementSchedule.daysLeft(stock: 30, unitsPerDose: 1, timesPerDay: 2, daysRaw: ""), 15)
        XCTAssertTrue(SupplementSchedule.needsRefill(trackStock: true, stock: 7, threshold: 7))
        XCTAssertFalse(SupplementSchedule.needsRefill(trackStock: false, stock: 0, threshold: 7))
        XCTAssertEqual(SupplementSchedule.adherence(states: ["taken", "taken", "skipped", "taken"]), 0.75)
        XCTAssertNil(SupplementSchedule.adherence(states: []))
    }

    @MainActor
    func testHistoryKeepsNameAfterRenameAndDelete() throws {
        let c = try ModelContainer(for: Supplement.self, SupplementDose.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        let s = Supplement(name: "Magnésium"); s.stableID = "S1"
        ctx.insert(s)
        ctx.insert(SupplementDose(supplementKey: "S1", name: s.name, day: .now, hour: 8, minute: 0, state: "taken"))
        try ctx.save()
        s.name = "Magnésium bisglycinate"; try ctx.save()
        ctx.delete(s); try ctx.save()
        let d = try ctx.fetch(FetchDescriptor<SupplementDose>())
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.name, "Magnésium")
        XCTAssertEqual(d.first?.supplementKey, "S1")
    }
}

final class Lot6DietTests: XCTestCase {
    func testPersonalAllergenWithSeverityAndPlural() {
        let p = [PersonalAllergen(word: "kiwi", severity: 3)]
        let f = DietGuard.check("Salade de kiwis", flags: [], personal: p)
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f.first?.severity, 3)
        XCTAssertFalse(f.first!.isTrace)
        XCTAssertTrue(DietGuard.check("Salade de fruits", flags: [], personal: p).isEmpty)
    }

    /// « Peut contenir » n'est ni un ingredient ni « sans risque » : signale a part.
    func testMayContainIsATraceNotAnIngredient() {
        let text = "Sucre, cacao. Peut contenir des traces de noisettes."
        let f = DietGuard.check(text, flags: ["Sans fruits à coque"], personal: [])
        XCTAssertEqual(f.count, 1)
        XCTAssertTrue(f[0].isTrace)
        XCTAssertTrue(f[0].label.hasPrefix("Traces possibles"))
        // L'ancien test (AllergenChecker seul) le disait incompatible sans distinction.
        XCTAssertTrue(AllergenChecker.check(text, against: ["Sans fruits à coque"]).first!.hasPrefix("Incompatible"))
        // Ingredient reel : incompatible.
        XCTAssertFalse(DietGuard.check("pâte de noisette", flags: ["Sans fruits à coque"], personal: []).first!.isTrace)
    }

    func testJournalEntriesAreFlaggedReadOnly() {
        let names = ["Croque jambon", "Salade verte", "Tarte au kiwi"]
        let hits = DietGuard.journal(names, flags: ["Sans porc"], personal: [.init(word: "kiwi", severity: 2)])
        XCTAssertEqual(hits.map(\.index), [0, 2])
        XCTAssertEqual(DietGuard.decode(DietGuard.encode([.init(word: "lupin", severity: 1)])).first?.word, "lupin")
    }
}
