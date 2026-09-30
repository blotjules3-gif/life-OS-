import XCTest
import SwiftData
@testable import LifeOS

/// Preuve de reconstruction: une base remplie, sauvegardee, puis restauree
/// ailleurs, doit revenir identique, fichiers compris.
final class FullBackupTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fullbackup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func locations(_ name: String) throws -> FullBackup.Locations {
        let base = root.appendingPathComponent(name)
        let loc = FullBackup.Locations(store: base.appendingPathComponent("support/default.store"),
                                       documents: base.appendingPathComponent("documents"),
                                       support: base.appendingPathComponent("support"))
        try FileManager.default.createDirectory(at: loc.documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: loc.support, withIntermediateDirectories: true)
        return loc
    }

    @MainActor
    private func container(_ loc: FullBackup.Locations) throws -> ModelContainer {
        try ModelContainer(for: LocalStore.schema,
                           configurations: [ModelConfiguration(schema: LocalStore.schema, url: loc.store)])
    }

    /// Remplit une base avec des types que l'ancien JSON oubliait (documents,
    /// voyages, cycles) et des types qu'il couvrait.
    @MainActor
    private func seed(_ loc: FullBackup.Locations) throws -> ModelContainer {
        let c = try container(loc)
        let ctx = c.mainContext
        try Data("page-1".utf8).write(to: loc.documents.appendingPathComponent("doc-a.jpg"))
        try FileManager.default.createDirectory(at: loc.documents.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("note".utf8).write(to: loc.documents.appendingPathComponent("sub/x.bin"))
        ctx.insert(DocVault(title: "Bail", category: "Logement", filename: "doc-a.jpg", note: "texte", pageFilenames: ["doc-a.jpg"]))
        ctx.insert(Trip(destination: "Lisbonne", start: .now, end: .now.addingTimeInterval(86_400)))
        ctx.insert(CycleEntry(date: .now))
        ctx.insert(FoodEntry(name: "Pomme", calories: 52))
        let h = Habit(name: "Lire")
        ctx.insert(h)
        try ctx.save()
        return c
    }

    @MainActor
    func testBackupThenRestoreRebuildsEverything() throws {
        let a = try locations("a")
        let seeded = try seed(a)
        let archive = root.appendingPathComponent("b.\(FullBackup.fileExtension)")
        let made = try FullBackup.make(at: a, defaults: ["standard": ["userName": "Test", "dev.apiKey": "sk-secret"]],
                                       appVersion: "t", to: archive)
        XCTAssertGreaterThanOrEqual(made.totalRows, 5)
        XCTAssertEqual(made.fileCount, 2)
        _ = seeded

        // Restauration sur un "autre appareil" qui avait deja ses propres donnees.
        let b = try locations("b")
        try Data("ancien".utf8).write(to: b.documents.appendingPathComponent("old.jpg"))
        do { let other = try container(b); other.mainContext.insert(FoodEntry(name: "Autre", calories: 1)); try other.mainContext.save() }

        _ = try FullBackup.stageRestore(from: archive, at: b)
        var restoredDefaults: [String: [String: Any]] = [:]
        let aside = try XCTUnwrap(try FullBackup.applyPendingRestore(at: b) { restoredDefaults = $0 })

        // Garder le container en vie: un context seul ne le retient pas (piege SwiftData).
        let restoredContainer = try container(b)
        let restored = restoredContainer.mainContext
        XCTAssertEqual(try restored.fetch(FetchDescriptor<DocVault>()).map(\.title), ["Bail"])
        XCTAssertEqual(try restored.fetch(FetchDescriptor<Trip>()).map(\.destination), ["Lisbonne"])
        XCTAssertEqual(try restored.fetchCount(FetchDescriptor<CycleEntry>()), 1)
        XCTAssertEqual(try restored.fetch(FetchDescriptor<FoodEntry>()).map(\.name), ["Pomme"])
        XCTAssertEqual(try restored.fetchCount(FetchDescriptor<Habit>()), 1)

        XCTAssertEqual(try Data(contentsOf: b.documents.appendingPathComponent("doc-a.jpg")), Data("page-1".utf8))
        XCTAssertEqual(try Data(contentsOf: b.documents.appendingPathComponent("sub/x.bin")), Data("note".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.documents.appendingPathComponent("old.jpg").path))

        // L'etat precedent est mis de cote, jamais efface.
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.appendingPathComponent("documents/old.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.appendingPathComponent("default.store").path))

        XCTAssertEqual(restoredDefaults["standard"]?["userName"] as? String, "Test")
        XCTAssertNil(restoredDefaults["standard"]?["dev.apiKey"], "un secret ne doit jamais entrer dans la sauvegarde")
        XCTAssertFalse(FullBackup.hasPendingRestore(at: b))
    }

    @MainActor
    func testOneFlippedByteIsRefusedAndNothingIsStaged() throws {
        let a = try locations("a")
        let keep = try seed(a); _ = keep
        let archive = root.appendingPathComponent("b.\(FullBackup.fileExtension)")
        _ = try FullBackup.make(at: a, defaults: [:], appVersion: "t", to: archive)

        var bytes = try Data(contentsOf: archive)
        bytes[20] ^= 0xFF          // dans la base, juste apres l'en-tete
        try bytes.write(to: archive)

        let b = try locations("b")
        XCTAssertThrowsError(try FullBackup.stageRestore(from: archive, at: b)) {
            guard case .corrupted = $0 as? FullBackup.Failure else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(FullBackup.hasPendingRestore(at: b))
        XCTAssertNil(try FullBackup.applyPendingRestore(at: b) { _ in })
    }

    func testForeignFileIsNotABackup() throws {
        let f = root.appendingPathComponent("x.pdf")
        try Data(repeating: 7, count: 500).write(to: f)
        XCTAssertThrowsError(try FullBackup.readManifest(f)) { XCTAssertEqual($0 as? FullBackup.Failure, .notABackup) }
    }

    func testNewerFormatGivesAClearMessage() throws {
        let file = root.appendingPathComponent("in.txt")
        try Data("x".utf8).write(to: file)
        let archive = root.appendingPathComponent("n.\(FullBackup.fileExtension)")
        let m = FullBackup.Manifest(format: FullBackup.formatVersion + 1, createdAt: .now, appVersion: "future",
                                    entries: [], rowCounts: [:])
        _ = try FullBackup.writeArchive(files: [("db/default.store", file)], manifest: m, to: archive)
        XCTAssertThrowsError(try FullBackup.readManifest(archive)) {
            XCTAssertEqual($0 as? FullBackup.Failure, .newerFormat(FullBackup.formatVersion + 1))
        }
    }

    func testPathsCannotEscapeTheRestoreFolder() {
        XCTAssertTrue(FullBackup.isSafe("documents/a/b.jpg"))
        XCTAssertFalse(FullBackup.isSafe("../etc/x"))
        XCTAssertFalse(FullBackup.isSafe("documents/../../x"))
        XCTAssertFalse(FullBackup.isSafe("/abs"))
    }

    func testSecretsAreRecognised() {
        for k in ["dev.apiKey", "openai_api_key", "authToken", "clientSecret"] { XCTAssertTrue(FullBackup.isSecretKey(k), k) }
        for k in ["userName", "appTheme", "waterGoal"] { XCTAssertFalse(FullBackup.isSecretKey(k), k) }
    }
}

// MARK: - Racine, retour arriere, fichiers de l'utilisateur

final class FullBackupSafetyTests: XCTestCase {

    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fbsafe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        FullBackup.mover = { try FileManager.default.moveItem(at: $0, to: $1) }
        try? FileManager.default.removeItem(at: root)
    }

    private func loc(_ name: String) throws -> FullBackup.Locations {
        let base = root.appendingPathComponent(name)
        let l = FullBackup.Locations(store: base.appendingPathComponent("support/default.store"),
                                     documents: base.appendingPathComponent("documents"),
                                     support: base.appendingPathComponent("support"))
        try FileManager.default.createDirectory(at: l.documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: l.support, withIntermediateDirectories: true)
        return l
    }

    /// Le dossier personnel de l'utilisateur n'est JAMAIS parcouru ni vide.
    func testUsersOwnFoldersAreRefused() throws {
        // Cas du Mac sans sandbox, joue avec un faux dossier personnel.
        let home = root.appendingPathComponent("Users/manon")
        for p in [home, home.appendingPathComponent("Documents"), home.appendingPathComponent("Desktop"),
                  root.appendingPathComponent("elsewhere/Documents")] {
            XCTAssertThrowsError(try FullBackup.checkRoot(p, unsandboxedMac: true, home: home.path)) {
                guard case .unsafeRoot = $0 as? FullBackup.Failure else { return XCTFail("\($0)") }
            }
        }
        let own = home.appendingPathComponent("Library/Application Support/\(AppPaths.bundleFolder)/Documents")
        XCTAssertNoThrow(try FullBackup.checkRoot(own, unsandboxedMac: true, home: home.path))
        XCTAssertThrowsError(try FullBackup.checkRoot(URL(fileURLWithPath: "/")))
        XCTAssertNoThrow(try FullBackup.checkRoot(root.appendingPathComponent("a/documents")), "iPhone: dossier prive de l'app")
    }

    /// Prepare une restauration en attente (fichiers bruts, sans archive).
    private func stagePending(_ l: FullBackup.Locations) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: l.pending.appendingPathComponent("db"), withIntermediateDirectories: true)
        try Data("NEW-DB".utf8).write(to: l.pending.appendingPathComponent(FullBackup.databaseEntry))
        try fm.createDirectory(at: l.pending.appendingPathComponent("documents"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: l.pending.appendingPathComponent("documents/new.jpg"))
        fm.createFile(atPath: l.pendingMarker.path, contents: Data())
        try Data("OLD-DB".utf8).write(to: l.store)
        try Data("old".utf8).write(to: l.documents.appendingPathComponent("old.jpg"))
    }

    /// Echec a l'aller: tout revient, la copie de securite peut partir.
    func testForwardFailureRestoresEverything() throws {
        let l = try loc("a")
        try stagePending(l)
        FullBackup.mover = { from, to in
            if from.lastPathComponent == "new.jpg" { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: from, to: to)
        }
        XCTAssertThrowsError(try FullBackup.applyPendingRestore(at: l) { _ in }) {
            guard case .io = $0 as? FullBackup.Failure else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try Data(contentsOf: l.store), Data("OLD-DB".utf8))
        XCTAssertEqual(try Data(contentsOf: l.documents.appendingPathComponent("old.jpg")), Data("old".utf8))
    }

    /// Echec a l'aller PUIS au retour: rien n'est supprime, l'erreur dit ou est la copie.
    func testRollbackFailureKeepsTheSafetyCopy() throws {
        let l = try loc("b")
        try stagePending(l)
        var forwardDone = false
        FullBackup.mover = { from, to in
            if from.lastPathComponent == "new.jpg" { forwardDone = true; throw CocoaError(.fileWriteOutOfSpace) }
            // Au retour, le document d'origine refuse de revenir.
            if forwardDone && to.lastPathComponent == "old.jpg" && to.path.contains("/documents/") && !to.path.contains("LifeOSBackup") {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.moveItem(at: from, to: to)
        }
        var message = ""
        XCTAssertThrowsError(try FullBackup.applyPendingRestore(at: l) { _ in }) {
            guard case .rollbackIncomplete(let m) = $0 as? FullBackup.Failure else { return XCTFail("\($0)") }
            message = m
        }
        XCTAssertTrue(message.contains("old.jpg"))
        let asides = try FileManager.default.contentsOfDirectory(atPath: l.support.path).filter { $0.hasPrefix("LifeOSBackup-restore-") }
        XCTAssertEqual(asides.count, 1, "la copie de securite doit rester")
        let kept = l.support.appendingPathComponent(asides[0]).appendingPathComponent("documents/old.jpg")
        XCTAssertEqual(try Data(contentsOf: kept), Data("old".utf8), "le fichier d'origine existe toujours")
    }

    /// Hors sandbox, seuls les fichiers crees par LifeOS quittent ~/Documents.
    func testMigrationMovesOnlyLifeOSFiles() throws {
        let legacy = root.appendingPathComponent("Documents"), target = root.appendingPathComponent("private/Documents")
        let fm = FileManager.default
        try fm.createDirectory(at: legacy.appendingPathComponent("Codex"), withIntermediateDirectories: true)
        let mine = ["analytics.jsonl", "doc-\(UUID().uuidString).jpg", "dream-1790000000.m4a"]
        let theirs = ["Untitled.mp4", "doc-vacances.jpg", "notes.txt", "Codex"]
        for n in mine + theirs where n != "Codex" { try Data(n.utf8).write(to: legacy.appendingPathComponent(n)) }
        let moved = AppPaths.migrateOwnedFiles(from: legacy, to: target)
        XCTAssertEqual(Set(moved), Set(mine))
        for n in theirs { XCTAssertTrue(fm.fileExists(atPath: legacy.appendingPathComponent(n).path), "\(n) ne doit pas bouger") }
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("Untitled.mp4")), Data("Untitled.mp4".utf8))
    }
}
