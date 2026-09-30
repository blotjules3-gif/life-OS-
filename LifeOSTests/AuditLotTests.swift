import XCTest
import SwiftUI
@testable import LifeOS

/// Lot de l'audit du 30 sept. : quatre apparences, deuxieme onglet, simulateur
/// d'investissement, progression de charge, annexes cosmetiques CosIng.
final class ThemePaletteTests: XCTestCase {
    override func tearDown() { UserDefaults.standard.removeObject(forKey: AppStorageKeys.appPalette); super.tearDown() }

    private func luminance(_ c: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ x: CGFloat) -> Double { let v = Double(x); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    private func chroma(_ c: Color) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return max(r, g, b) - min(r, g, b)
    }

    func testNeutralKeepsLuminanceSoContrastIsIdentical() {
        UserDefaults.standard.set("color", forKey: AppStorageKeys.appPalette)
        let colored = [Theme.fitness, Theme.nutrition, Theme.energy, Theme.finance, Theme.danger, Color(hex: 0xFF5BA0)]
        let lums = colored.map(luminance)
        XCTAssertGreaterThan(colored.map(chroma).max() ?? 0, 0.3, "contrôle : la palette couleurs a bien des teintes")
        UserDefaults.standard.set("neutral", forKey: AppStorageKeys.appPalette)
        let neutral = [Theme.fitness, Theme.nutrition, Theme.energy, Theme.finance, Theme.danger, Color(hex: 0xFF5BA0)]
        for (c, l) in zip(neutral, lums) {
            XCTAssertLessThan(chroma(c), 0.01, "le neutre ne garde aucune teinte")
            XCTAssertEqual(luminance(c), l, accuracy: 0.004, "même luminance, donc même contraste")
        }
    }

    func testDefaultPaletteIsColor() {
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.appPalette)
        XCTAssertFalse(Theme.neutralPalette)
        XCTAssertGreaterThan(chroma(Theme.fitness), 0.5)
    }
}

final class SecondTabTests: XCTestCase {
    override func tearDown() { UserDefaults.standard.removeObject(forKey: AppStorageKeys.secondTab); super.tearDown() }

    func testUnknownValueFallsBackToWakeUp() {
        UserDefaults.standard.set("n'importe quoi", forKey: AppStorageKeys.secondTab)
        XCTAssertEqual(SecondTab.current, .wakeup)
        XCTAssertEqual(AppTab.wakeup.label, "Réveil")
    }

    func testEveryChoiceIsAValidDestination() {
        for t in SecondTab.allCases where t != .wakeup {
            XCTAssertNotNil(t.category, "\(t) doit ouvrir une vraie catégorie")
        }
        UserDefaults.standard.set("nutrition", forKey: AppStorageKeys.secondTab)
        XCTAssertEqual(AppTab.wakeup.label, "Nutrition")
        XCTAssertEqual(AppTab.wakeup.icon, "fork.knife")
    }

    func testWakeUpStaysReachableFromSleep() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let hub = try String(contentsOf: root.appendingPathComponent("LifeOS/Core/CategoryHub.swift"), encoding: .utf8)
        XCTAssertTrue(hub.contains("WakeUpView(embedded: true)"), "le Réveil doit rester ouvrable depuis Sommeil")
    }
}

final class FireProjectionTests: XCTestCase {
    func testNegativeReturnLosesMoney() {
        let p = FireProjection.run(start: 10_000, monthly: 0, annualReturn: -5, fees: 0, inflation: 0, years: 10)
        XCTAssertLessThan(p.last!.nominal, 10_000)
        XCTAssertEqual(p.last!.nominal, 10_000 * pow(0.95, 10), accuracy: 1)
    }

    func testFeesAndInflationReduceTheResult() {
        let base = FireProjection.run(start: 0, monthly: 500, annualReturn: 7, fees: 0, inflation: 0, years: 20).last!
        let fees = FireProjection.run(start: 0, monthly: 500, annualReturn: 7, fees: 1, inflation: 0, years: 20).last!
        let infl = FireProjection.run(start: 0, monthly: 500, annualReturn: 7, fees: 0, inflation: 2, years: 20).last!
        XCTAssertLessThan(fees.nominal, base.nominal)
        XCTAssertEqual(infl.nominal, base.nominal, accuracy: 0.01)
        XCTAssertEqual(infl.real, base.nominal / pow(1.02, 20), accuracy: 1)
        XCTAssertEqual(base.invested, 500 * 12 * 20, accuracy: 0.01)
    }

    func testScenariosAreOrderedAndLabelled() {
        let s = FireProjection.scenarios(start: 1_000, monthly: 100, annualReturn: 6, fees: 0.5, inflation: 2, years: 15)
        XCTAssertEqual(s.map(\.id), ["pessimiste", "central", "optimiste"])
        XCTAssertLessThan(s[0].final.real, s[1].final.real)
        XCTAssertLessThan(s[1].final.real, s[2].final.real)
        XCTAssertEqual(s[0].annualReturn, 2)
    }

    func testZeroYearsAndNegativeInputsAreSafe() {
        let p = FireProjection.run(start: -50, monthly: -10, annualReturn: -200, fees: 5, inflation: 0, years: 0)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].nominal, 0)
    }
}

final class StrengthProgressionTests: XCTestCase {
    typealias S = StrengthProgression
    private let t = S.Target(sets: 3, repLow: 8, repHigh: 10)
    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: -offset, to: .now)! }
    private func session(_ offset: Int, _ w: Double, _ reps: [Int], rpe: Double = 8) -> [S.LoggedSet] {
        reps.enumerated().map { i, r in .init(date: day(offset).addingTimeInterval(Double(i) * 60), exercise: "Rowing barre", weight: w, reps: r, rpe: rpe) }
    }

    func testTargetParsing() {
        XCTAssertEqual(S.target(from: "Développé couché barre 4×10"), .init(sets: 4, repLow: 8, repHigh: 10))
        XCTAssertEqual(S.target(from: "Squat barre 5×5"), .init(sets: 5, repLow: 5, repHigh: 5))
        XCTAssertNil(S.target(from: "Tapis de course 15 min"))
    }

    func testFirstSessionUsesProfileMaxOrAsks() {
        let p = S.next(exercise: "Développé couché barre", target: t, history: [], profile1RM: 100)
        XCTAssertEqual(p.decision, .start)
        XCTAssertEqual(p.weight!, 100 / (1 + 12.0 / 30), accuracy: 0.5)
        XCTAssertNil(S.next(exercise: "Curl marteau", target: t, history: []).weight)
    }

    func testAllTopRepsEasyIncreases() {
        let p = S.next(exercise: "Rowing barre", target: t, history: session(2, 60, [10, 10, 10], rpe: 8))
        XCTAssertEqual(p.decision, .increase)
        XCTAssertEqual(p.weight, 62.5)
        XCTAssertEqual(p.reps, 8)
    }

    func testTopRepsAtMaximumEffortHolds() {
        let p = S.next(exercise: "Rowing barre", target: t, history: session(2, 60, [10, 10, 10], rpe: 10))
        XCTAssertEqual(p.decision, .hold)
        XCTAssertEqual(p.weight, 60)
    }

    func testMissOnceRepeatsMissTwiceDeloads() {
        let once = S.next(exercise: "Rowing barre", target: t, history: session(2, 60, [7, 6, 6]))
        XCTAssertEqual(once.decision, .repeatLoad)
        let twice = S.next(exercise: "Rowing barre", target: t, history: session(2, 60, [7, 6, 6]) + session(5, 60, [7, 7, 6]))
        XCTAssertEqual(twice.decision, .deload)
        XCTAssertEqual(twice.weight, 54)
    }

    func testInRangeAddsOneRep() {
        let p = S.next(exercise: "Rowing barre", target: t, history: session(1, 60, [9, 8, 8]))
        XCTAssertEqual(p.decision, .addRep)
        XCTAssertEqual(p.reps, 10)
        XCTAssertEqual(p.weight, 60)
    }

    func testOnlyTheSameExerciseCounts() {
        let other = [S.LoggedSet(date: day(1), exercise: "Curl marteau", weight: 12, reps: 12, rpe: 7)]
        XCTAssertEqual(S.next(exercise: "Rowing barre", target: t, history: other).decision, .start)
    }

    func testWeeklyVolumeAndRecovery() {
        let sets = session(1, 60, [10, 10, 10]) + session(9, 60, [10, 10, 10])
            + [S.LoggedSet(date: day(1), exercise: "Rowing barre", weight: 20, reps: 10, rpe: 5)]
        XCTAssertEqual(S.weeklyHardSets(sets)["Dos"], 3, "échauffement (effort 5) et séance de J-9 exclus")
        XCTAssertEqual(S.hoursSince(group: "Dos", in: sets)!, 24, accuracy: 1)
        XCTAssertNil(S.hoursSince(group: "Mollets", in: sets))
    }
}

final class CosmeticAnnexTests: XCTestCase {
    private func cosmetic(_ ingredients: String) -> ProductScore.Result {
        var p = CatalogProduct(barcode: "1", source: .beauty, name: "Test")
        p.ingredientsText = ingredients
        return ProductScore.cosmetic(p)
    }

    func testAnnexesAreLoaded() {
        XCTAssertGreaterThan(CosmeticRegulation.entries.count, 300, "cosing_annexes.tsv doit être dans le bundle")
        XCTAssertGreaterThan(ProductScore.watchListCount, 300)
        XCTAssertEqual(CosmeticRegulation.lookup("linalool")?.kind, .allergen)
    }

    func testProhibitedAnnexIIIngredientIsHigh() {
        let r = cosmetic("Aqua, Glycerin, Cetearyl Alcohol, 2-Naphthol")
        XCTAssertTrue(r.flags.contains { $0.code == "2-naphthol" && $0.level == .high }, "\(r.flags)")
    }

    func testRestrictedIsReportedWithoutPenalty() {
        let r = cosmetic("Aqua, Glycerin, Cetearyl Alcohol, Salicylic Acid")
        XCTAssertEqual(r.value, 100)
        XCTAssertTrue(r.components.flatMap(\.details).contains { $0.contains("annexe III") && $0.contains("salicylic acid") })
    }

    func testAllergenFromAnnexCostsSensitivityPoints() {
        let r = cosmetic("Aqua, Glycerin, Cetearyl Alcohol, Cinnamal")
        XCTAssertTrue(r.flags.contains { $0.code == "cinnamal" && $0.level == .sensitivity })
        XCTAssertEqual(r.value, 97)
    }
}
