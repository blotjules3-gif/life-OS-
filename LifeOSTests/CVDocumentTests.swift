import XCTest
import PDFKit
@testable import LifeOS

/// Le CV exporte est un vrai document: texte lisible, accents, pages, sections vides retirees.
final class CVDocumentTests: XCTestCase {

    private func fields(experienceLines: Int) -> CVDocument.Fields {
        var f = CVDocument.Fields()
        f.name = "Hélène Dupré"; f.title = "Développeuse iOS"; f.contact = "helene@exemple.fr · Lyon"
        f.summary = "Huit ans d'expérience, applications grand public."
        f.experience = (1...experienceLines).map { "Poste \($0) · Société Évasion · 2018–2020 : réalisation de fonctionnalités, tests et publication." }
            .joined(separator: "\n")
        f.skills = "Swift, SwiftUI, accessibilité, anglais courant"
        return f
    }

    func testTextIsSelectableWithAccents() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: CVDocument.pdf(fields(experienceLines: 3))))
        let text = try XCTUnwrap(pdf.string)
        for word in ["Hélène Dupré", "Développeuse iOS", "EXPÉRIENCE", "COMPÉTENCES", "Évasion"] {
            XCTAssertTrue(text.contains(word), "« \(word) » absent du PDF")
        }
        XCTAssertFalse(text.contains("FORMATION"), "section vide retirée")
        XCTAssertEqual(pdf.pageCount, 1)
    }

    func testLongExperienceFlowsOntoMorePages() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: CVDocument.pdf(fields(experienceLines: 80))))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.contains("Poste 80") == true, "la dernière ligne n'est pas perdue")
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CVDocument.pageSize)
    }

    func testEmptyCVIsDetected() {
        XCTAssertTrue(CVDocument.Fields().isEmpty)
        XCTAssertFalse(fields(experienceLines: 1).isEmpty)
    }
}
