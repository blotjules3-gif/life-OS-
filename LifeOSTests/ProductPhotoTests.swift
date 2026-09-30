import XCTest
import Vision
@testable import LifeOS

/// Detourage sur fond blanc. La photo d'essai est un vrai cliche Open Food Facts
/// (pot de skyr pose sur une table), telecharge une fois et joint au test.
final class ProductPhotoTests: XCTestCase {

    private func sample() throws -> UIImage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "skyr-table", withExtension: "jpg"))
        return try XCTUnwrap(UIImage(contentsOfFile: url.path))
    }

    func testProductIsCutOutOnWhiteAndFramedSquare() throws {
        #if targetEnvironment(simulator)
        // Le simulateur n'a pas le detourage de Vision (verifie le 28 sept 2026:
        // la requete ne rend aucun sujet). Le test tourne sur Mac et sur iPhone.
        throw XCTSkip("Détourage Vision absent du simulateur")
        #else
        let img = try sample()
        guard let out = ProductPhoto.onWhite(img) else {
            // Vision n'a pas pu tourner: on le dit clairement plutot que de passer.
            return XCTFail("Detourage indisponible sur cet appareil de test")
        }
        XCTAssertEqual(out.size.width, out.size.height, accuracy: 1, "cadre carre")
        let px = try corner(out)
        XCTAssertGreaterThan(px, 245, "coin blanc, plus de table derriere")
        #endif
    }

    func testCacheKeyIsStablePerURL() {
        let a = ProductPhoto.cacheURL(for: URL(string: "https://x/1.jpg")!)
        XCTAssertEqual(a, ProductPhoto.cacheURL(for: URL(string: "https://x/1.jpg")!))
        XCTAssertNotEqual(a, ProductPhoto.cacheURL(for: URL(string: "https://x/2.jpg")!))
    }

    /// Luminosite moyenne du pixel en haut a gauche (0...255).
    private func corner(_ image: UIImage) throws -> Double {
        let cg = try XCTUnwrap(image.cgImage)
        var p = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(data: &p, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: -CGFloat(cg.height) + 1, width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (Double(p[0]) + Double(p[1]) + Double(p[2])) / 3
    }
}
