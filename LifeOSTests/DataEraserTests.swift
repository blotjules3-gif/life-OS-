import XCTest
import SwiftData
@testable import LifeOS

/// L'effacement part d'un inventaire unique et ne laisse rien revenir.
@MainActor
final class DataEraserTests: XCTestCase {

    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("erase-\(UUID().uuidString)")
        for d in ["docs", "support", "caches"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testEveryModelTypeOfTheSchemaIsCovered() {
        XCTAssertEqual(LocalStore.modelTypes.count, LocalStore.schema.entities.count)
        let names = Set(LocalStore.modelTypes.map { String(describing: $0) })
        XCTAssertTrue(names.contains("ProfileField") && names.contains("ProfileFieldRevision"), "les deux oublies de l'audit")
    }

    func testEraseRemovesDataFilesBackupsPendingRestoreAndSettings() throws {
        let store = root.appendingPathComponent("support/default.store")
        let container = try ModelContainer(for: LocalStore.schema,
                                           configurations: [ModelConfiguration(schema: LocalStore.schema, url: store)])
        let ctx = container.mainContext
        ctx.insert(FoodEntry(name: "Pomme", calories: 52))
        ctx.insert(Habit(name: "Lire"))
        ctx.insert(Trip(destination: "Lisbonne"))
        ctx.insert(ProfileField(fieldID: "age", category: "identite", valueString: "30", valueType: "int", confidence: 1, source: "test"))
        try ctx.save()

        let docs = root.appendingPathComponent("docs"), support = root.appendingPathComponent("support")
        try Data("x".utf8).write(to: docs.appendingPathComponent("doc-1.jpg"))
        try FileManager.default.createDirectory(at: docs.appendingPathComponent("Yuko"), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: docs.appendingPathComponent("Yuko/history.json"))
        try FileManager.default.createDirectory(at: support.appendingPathComponent("LifeOSBackup-restore-1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support.appendingPathComponent("LifeOSPendingRestore"), withIntermediateDirectories: true)
        try Data().write(to: support.appendingPathComponent("LifeOSPendingRestore/READY"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("caches/Yuko"), withIntermediateDirectories: true)

        let suite = "erase-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.set("Theo", forKey: AppStorageKeys.userName); ud.set(2000, forKey: AppStorageKeys.waterGoal)
        let inv = DataEraser.StorageInventory(documents: docs, support: support, caches: root.appendingPathComponent("caches"),
                                              defaults: ud, groupDefaults: nil, defaultsDomain: suite)

        let report = DataEraser.eraseAndKeepOnboarding(container: container, inventory: inv)
        XCTAssertTrue(report.succeeded, "\(report.failures)")

        for t in LocalStore.modelTypes { XCTAssertEqual(try DataEraser.count(t, ctx), 0, "\(t)") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: docs.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("LifeOSPendingRestore").path),
                       "sinon la restauration ramenerait tout au prochain lancement")
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("LifeOSBackup-restore-1").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("caches/Yuko").path))
        XCTAssertEqual(ud.string(forKey: AppStorageKeys.userName), "Theo", "gardé par 'recommencer à zéro'")
        XCTAssertNil(ud.object(forKey: AppStorageKeys.waterGoal))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path), "la base elle-même reste, vide")

        // "Relance": une nouvelle ouverture de la base ne fait rien revenir.
        let reopened = try ModelContainer(for: LocalStore.schema,
                                          configurations: [ModelConfiguration(schema: LocalStore.schema, url: store)])
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<FoodEntry>()), 0)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    /// Un dossier trop large n'est jamais vide: l'etape echoue et le rapport le dit.
    func testRefusesToEmptyARootThatIsNotLifeOS() throws {
        let container = try ModelContainer(for: LocalStore.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let inv = DataEraser.StorageInventory(documents: URL(fileURLWithPath: "/"), support: root.appendingPathComponent("support"),
                                              caches: root.appendingPathComponent("caches"), defaults: UserDefaults(suiteName: "e-\(UUID())")!,
                                              groupDefaults: nil, defaultsDomain: nil)
        let report = DataEraser.eraseAllData(container: container, inventory: inv)
        XCTAssertFalse(report.succeeded)
        XCTAssertTrue(report.failures.contains { $0.hasPrefix("fichiers") })
    }
}
