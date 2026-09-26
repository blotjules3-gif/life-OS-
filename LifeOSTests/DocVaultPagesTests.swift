import XCTest
@testable import LifeOS

/// Le scanner ne gardait que `imageOfPage(at: 0)` : un contrat de cinq pages etait
/// enregistre comme une page et les quatre autres disparaissaient sans message.
/// Ces controles portent sur le MODELE, qui est la partie testable sans camera.
final class DocVaultPagesTests: XCTestCase {

    func testFivePageDocumentKeepsEveryPage() {
        let pages = (1...5).map { "doc-\($0).jpg" }
        let d = DocVault(title: "Contrat", category: "Contrat", filename: pages.first, note: "", pageFilenames: pages)
        XCTAssertEqual(d.pageCount, 5)
        XCTAssertEqual(d.allPages, pages, "l'ordre du scan doit etre conserve")
        XCTAssertEqual(d.allPages.last, "doc-5.jpg", "la derniere page ne doit pas etre perdue")
    }

    /// Les fiches enregistrees avant ce correctif n'ont qu'un `filename`.
    /// Elles doivent continuer a s'ouvrir, avec une page.
    func testOldSinglePageRecordStillReadable() {
        let d = DocVault(title: "Ancien", category: "Identité", filename: "doc-old.jpg", note: "")
        XCTAssertEqual(d.pageCount, 1)
        XCTAssertEqual(d.allPages, ["doc-old.jpg"])
    }

    func testDocumentWithNoImageHasNoPages() {
        let d = DocVault(title: "Texte seul", category: "Impôts", filename: nil, note: "texte")
        XCTAssertEqual(d.pageCount, 0)
        XCTAssertTrue(d.allPages.isEmpty)
    }

    /// Le texte reconnu couvre tout le document, donc une information en DERNIERE page
    /// (date d'expiration, montant) doit etre trouvable.
    func testRecognisedTextSpansAllPages() {
        let joined = ["page un", "page deux", "expire le 31/12/2027"].joined(separator: "\n\n")
        let d = DocVault(title: "Contrat", category: "Contrat", filename: "a.jpg", note: joined,
                         pageFilenames: ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertTrue(d.note.contains("31/12/2027"), "le texte de la derniere page doit etre present")
        XCTAssertEqual(d.pageCount, 3)
    }
}
