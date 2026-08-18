import XCTest
import SwiftData
@testable import LifeOS

@MainActor
final class DataEraserTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        // Schéma minimal pour tester l'erase (le vrai schéma LocalStore avec
        // ses relations non-Optional crash en config in-memory).
        let schema = Schema([MoodEntry.self, Habit.self, HabitCompletion.self, TodoItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: exportBackup

    func testExportBackup_returnsValidJSON() {
        context.insert(MoodEntry(score: 4))
        context.insert(Habit(name: "Test habit"))
        try? context.save()

        guard let data = DataEraser.exportBackup(container: container) else {
            XCTFail("export ne devrait pas être nil")
            return
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["exportedAt"])
        XCTAssertNotNil(json?["version"])
        XCTAssertNotNil(json?["entityCounts"])
    }

    func testExportBackup_countsEntities() {
        for _ in 0..<3 {
            context.insert(MoodEntry(score: 3))
        }
        try? context.save()

        guard let data = DataEraser.exportBackup(container: container),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let counts = json["entityCounts"] as? [String: Int] else {
            XCTFail("export malformé")
            return
        }
        XCTAssertEqual(counts["moods"], 3)
    }

    // MARK: eraseAllData

    func testEraseAllData_clearsSwiftDataEntities() {
        context.insert(MoodEntry(score: 4))
        context.insert(Habit(name: "Test"))
        context.insert(TodoItem(title: "Task"))
        try? context.save()

        XCTAssertGreaterThan(fetchCount(MoodEntry.self), 0)

        DataEraser.eraseAllData(container: container)

        XCTAssertEqual(fetchCount(MoodEntry.self), 0)
        XCTAssertEqual(fetchCount(Habit.self), 0)
        XCTAssertEqual(fetchCount(TodoItem.self), 0)
    }

    // MARK: eraseAndKeepOnboarding

    func testEraseKeepOnboarding_preservesKeyUserDefaults() {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.onboardingDone)
        UserDefaults.standard.set("dark", forKey: AppStorageKeys.appTheme)
        UserDefaults.standard.set("Jules", forKey: AppStorageKeys.userName)

        DataEraser.eraseAndKeepOnboarding(container: container)

        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppStorageKeys.onboardingDone))
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppStorageKeys.appTheme), "dark")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppStorageKeys.userName), "Jules")
    }

    // MARK: Helper

    private func fetchCount<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
    }
}
