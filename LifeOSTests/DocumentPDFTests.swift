import XCTest
import PDFKit
@testable import LifeOS

/// L'export d'un document doit etre UN vrai PDF, une page par page scannee,
/// sans deformer l'image.
final class DocumentPDFTests: XCTestCase {

    private func image(_ w: CGFloat, _ h: CGFloat, _ color: UIColor = .red) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { c in
            color.setFill(); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    func testOnePDFPagePerImage() throws {
        let data = try DocumentPDF.data(pages: [image(100, 140), image(140, 100), image(50, 50)])
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 3)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, DocumentPDF.pageSize)
    }

    func testNoPagesIsAnErrorNotAnEmptyFile() {
        XCTAssertThrowsError(try DocumentPDF.data(pages: [])) {
            XCTAssertEqual($0 as? DocumentPDF.Failure, .noPages)
        }
    }

    func testFitKeepsAspectAndStaysInside() {
        let box = CGRect(x: 18, y: 18, width: 559, height: 806)
        for size in [CGSize(width: 1000, height: 200), CGSize(width: 200, height: 1000), CGSize(width: 10, height: 10)] {
            let r = DocumentPDF.fit(size, in: box)
            XCTAssertEqual(r.width / r.height, size.width / size.height, accuracy: 0.001)
            XCTAssertTrue(box.insetBy(dx: -0.5, dy: -0.5).contains(r))
        }
    }

    func testWriteProducesReadableFileWithSafeName() throws {
        let url = try DocumentPDF.write(pages: [image(10, 20)], title: "Bail / 2026: v2")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertEqual(PDFDocument(url: url)?.pageCount, 1)
    }

    func testRotateSwapsDimensions() {
        let r = image(30, 80).rotatedClockwise()
        XCTAssertEqual(r.size.width, 80); XCTAssertEqual(r.size.height, 30)
    }
}
