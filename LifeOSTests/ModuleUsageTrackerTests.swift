import XCTest
@testable import LifeOS

final class ModuleUsageTrackerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset entre chaque test pour isoler
        ModuleUsageTracker.shared.reset()
    }

    override func tearDown() {
        ModuleUsageTracker.shared.reset()
        super.tearDown()
    }

    func testTrack_incrementsCount() {
        ModuleUsageTracker.shared.track(.fitness)
        let report = ModuleUsageTracker.shared.report()
        let fitness = report.first { $0.module == .fitness }
        XCTAssertEqual(fitness?.count, 1)
    }

    func testTrack_antiDuplicateWithin60s() {
        ModuleUsageTracker.shared.track(.fitness)
        ModuleUsageTracker.shared.track(.fitness) // même seconde → skip
        let report = ModuleUsageTracker.shared.report()
        let fitness = report.first { $0.module == .fitness }
        XCTAssertEqual(fitness?.count, 1, "anti-doublon 60s doit empêcher un 2e incrément immédiat")
    }

    func testReport_sortedByCountDescending() {
        ModuleUsageTracker.shared.track(.fitness)
        // Simule 3 ouvertures fitness espacées via manipulation UserDefaults directe
        UserDefaults.standard.set(3, forKey: "module_usage_fitness")
        UserDefaults.standard.set(Date().addingTimeInterval(-3600), forKey: "module_usage_fitness_last")
        UserDefaults.standard.set(1, forKey: "module_usage_nutrition")
        UserDefaults.standard.set(Date().addingTimeInterval(-3600), forKey: "module_usage_nutrition_last")

        let report = ModuleUsageTracker.shared.report()
        // Top devrait être fitness (3)
        XCTAssertEqual(report.first?.module, .fitness)
    }

    func testReset_clearsAllData() {
        ModuleUsageTracker.shared.track(.fitness)
        ModuleUsageTracker.shared.track(.sleep)
        ModuleUsageTracker.shared.reset()
        let report = ModuleUsageTracker.shared.report()
        XCTAssertTrue(report.allSatisfy { $0.count == 0 }, "reset doit tout remettre à 0")
    }

    func testUnusedModules_returnsAllWhenNothingTracked() {
        let unused = ModuleUsageTracker.shared.unusedModules()
        XCTAssertEqual(unused.count, AppCategory.allCases.count,
                       "avant tout track, tous les modules sont unused")
    }

    func testCoreModules_returnsEmptyByDefault() {
        let core = ModuleUsageTracker.shared.coreModules()
        XCTAssertTrue(core.isEmpty, "aucune ouverture → aucun module core")
    }

    func testTextReport_containsAllModules() {
        let text = ModuleUsageTracker.shared.textReport()
        for cat in AppCategory.allCases {
            XCTAssertTrue(text.contains(cat.rawValue), "textReport doit contenir \(cat.rawValue)")
        }
    }
}
