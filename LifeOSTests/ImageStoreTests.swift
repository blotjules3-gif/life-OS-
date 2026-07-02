import XCTest
@testable import LifeOS

final class ImageStoreTests: XCTestCase {
    private var savedFilenames: [String] = []

    override func tearDown() {
        super.tearDown()
        // Nettoyage : supprimer les fichiers créés pendant les tests
        for name in savedFilenames {
            ImageStore.delete(name)
        }
        savedFilenames.removeAll()
    }

    // MARK: - Save

    func testSaveReturnsNonEmptyFilename() {
        let data = UIImage(systemName: "star")!.jpegData(compressionQuality: 0.8)!
        let name = ImageStore.save(data, prefix: "test")
        savedFilenames.append(name)
        XCTAssertFalse(name.isEmpty, "Le nom de fichier ne doit pas être vide")
    }

    func testSaveFilenameContainsPrefix() {
        let data = Data(repeating: 0xFF, count: 100)
        let name = ImageStore.save(data, prefix: "myprefix")
        savedFilenames.append(name)
        XCTAssertTrue(name.hasPrefix("myprefix-"), "Le nom doit commencer par le préfixe")
    }

    func testSaveCreatesFileOnDisk() {
        let data = Data(repeating: 0xAB, count: 256)
        let name = ImageStore.save(data, prefix: "disktest")
        savedFilenames.append(name)
        let url = ImageStore.dir.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Le fichier doit exister sur disque après save()")
    }

    // MARK: - Load

    func testLoadReturnNilForUnknownFilename() {
        let result = ImageStore.load("fichier_qui_nexiste_pas.jpg")
        XCTAssertNil(result, "load() doit retourner nil pour un nom inexistant")
    }

    func testLoadReturnNilForNilFilename() {
        let result = ImageStore.load(nil)
        XCTAssertNil(result, "load(nil) doit retourner nil")
    }

    // MARK: - Delete

    func testDeleteNilIsNoOp() {
        // Ne doit pas crasher
        ImageStore.delete(nil)
    }

    func testDeleteRemovesFile() {
        let data = Data(repeating: 0x01, count: 64)
        let name = ImageStore.save(data, prefix: "deltest")
        let url = ImageStore.dir.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        ImageStore.delete(name)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Le fichier doit être supprimé")
    }

    func testDeleteNonExistentFileIsNoOp() {
        // Ne doit pas crasher
        ImageStore.delete("fichier_fantome_\(UUID().uuidString).jpg")
    }

    // MARK: - Save → Load roundtrip

    func testSaveLoadRoundtrip() throws {
        let original = UIImage(systemName: "heart.fill")!
        let data = original.jpegData(compressionQuality: 1.0)!
        let name = ImageStore.save(data, prefix: "roundtrip")
        savedFilenames.append(name)
        let loaded = ImageStore.load(name)
        XCTAssertNotNil(loaded, "load() doit retourner une image après save()")
    }
}
