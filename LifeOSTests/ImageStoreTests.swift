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

    func testSaveReturnsNonEmptyFilename() throws {
        let data = UIImage(systemName: "star")!.jpegData(compressionQuality: 0.8)!
        // save rend desormais un optionnel: nil signifie que l'ecriture a
        // echoue, et l'appelant ne doit surtout pas enregistrer de nom.
        let name = try XCTUnwrap(ImageStore.save(data, prefix: "test"))
        savedFilenames.append(name)
        XCTAssertFalse(name.isEmpty, "Le nom de fichier ne doit pas être vide")
    }

    func testSaveFilenameContainsPrefix() throws {
        let data = Data(repeating: 0xFF, count: 100)
        let name = try XCTUnwrap(ImageStore.save(data, prefix: "myprefix"))
        savedFilenames.append(name)
        XCTAssertTrue(name.hasPrefix("myprefix-"), "Le nom doit commencer par le préfixe")
    }

    func testSaveCreatesFileOnDisk() throws {
        let data = Data(repeating: 0xAB, count: 256)
        let name = try XCTUnwrap(ImageStore.save(data, prefix: "disktest"))
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

    func testDeleteRemovesFile() throws {
        let data = Data(repeating: 0x01, count: 64)
        let name = try XCTUnwrap(ImageStore.save(data, prefix: "deltest"))
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
        let name = try XCTUnwrap(ImageStore.save(data, prefix: "roundtrip"))
        savedFilenames.append(name)
        let loaded = ImageStore.load(name)
        XCTAssertNotNil(loaded, "load() doit retourner une image après save()")
    }

    /// Le contrat qui manquait, et qui a coute un document perdu:
    /// quand l'ecriture echoue, save doit rendre nil et PAS un nom de
    /// fichier. Sinon l'appelant enregistre une fiche qui pointe vers rien.
    func testSaveReturnsNilWhenWriteFails() throws {
        // Un prefixe contenant une barre oblique force un chemin invalide.
        let data = Data(repeating: 0x01, count: 32)
        let name = ImageStore.save(data, prefix: "dossier/inexistant/x")
        if let name { savedFilenames.append(name) }
        XCTAssertNil(name, "une ecriture impossible doit rendre nil")
    }

}
