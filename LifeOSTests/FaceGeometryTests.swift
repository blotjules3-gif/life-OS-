import XCTest
import CoreGraphics
@testable import LifeOS

/// Symetrie du visage sur des points synthetiques, sans photo ni Vision.
final class FaceGeometryTests: XCTestCase {

    /// Un visage parfaitement symetrique autour de x = 0, largeur 200 px.
    private func symmetricFace() -> FaceGeometry.Landmarks {
        func pair(_ x: CGFloat, _ y: CGFloat) -> [CGPoint] { [CGPoint(x: -x, y: y), CGPoint(x: x, y: y)] }
        // Contour d'une oreille a l'autre par le menton (y bas = menton, comme Vision).
        let left: [CGPoint] = [(100, 200), (95, 150), (85, 100), (65, 55), (35, 20)].map { CGPoint(x: -$0.0, y: $0.1) }
        let right = left.reversed().map { CGPoint(x: -$0.x, y: $0.y) }
        let contour = left + [CGPoint(x: 0, y: 0)] + right
        func blob(_ c: CGPoint) -> [CGPoint] {
            [CGPoint(x: c.x - 10, y: c.y), CGPoint(x: c.x + 10, y: c.y),
             CGPoint(x: c.x, y: c.y - 4), CGPoint(x: c.x, y: c.y + 4)]
        }
        return .init(
            contour: contour,
            medianLine: (0...6).map { CGPoint(x: 0, y: CGFloat($0) * 40) },
            noseCrest: [CGPoint(x: 0, y: 170), CGPoint(x: 0, y: 110)],
            leftEye: blob(CGPoint(x: -45, y: 190)), rightEye: blob(CGPoint(x: 45, y: 190)),
            leftBrow: blob(CGPoint(x: -45, y: 215)), rightBrow: blob(CGPoint(x: 45, y: 215)),
            outerLips: pair(30, 60) + [CGPoint(x: 0, y: 70), CGPoint(x: 0, y: 50)],
            nose: pair(15, 105) + [CGPoint(x: 0, y: 100)])
    }

    private func transform(_ f: FaceGeometry.Landmarks, _ t: (CGPoint) -> CGPoint) -> FaceGeometry.Landmarks {
        .init(contour: f.contour.map(t), medianLine: f.medianLine.map(t), noseCrest: f.noseCrest.map(t),
              leftEye: f.leftEye.map(t), rightEye: f.rightEye.map(t),
              leftBrow: f.leftBrow.map(t), rightBrow: f.rightBrow.map(t),
              outerLips: f.outerLips.map(t), nose: f.nose.map(t))
    }

    private func deviation(_ f: FaceGeometry.Landmarks, yaw: Double? = 0) -> Double? {
        if case .measured(let d, _) = FaceGeometry.symmetry(f, yawDegrees: yaw) { return d }
        return nil
    }

    func testPerfectlySymmetricFaceMeasuresZero() throws {
        XCTAssertEqual(try XCTUnwrap(deviation(symmetricFace())), 0, accuracy: 1e-9)
    }

    /// Une tete penchee n'est pas un visage asymetrique.
    func testHeadTiltIsNotAsymmetry() throws {
        let a = 15.0 * .pi / 180
        let tilted = transform(symmetricFace()) {
            CGPoint(x: $0.x * cos(a) - $0.y * sin(a) + 500, y: $0.x * sin(a) + $0.y * cos(a) + 300)
        }
        XCTAssertEqual(try XCTUnwrap(deviation(tilted)), 0, accuracy: 1e-6)
    }

    /// Le defaut du brief: un oeil deplace vers l'exterieur. L'ancienne formule
    /// ne le voyait pas (zero par construction), la nouvelle le mesure.
    func testShiftedEyeIsDetectedWhereTheOldFormulaWasBlind() throws {
        var f = symmetricFace()
        f.rightEye = f.rightEye.map { CGPoint(x: $0.x + 12, y: $0.y) }
        let d = try XCTUnwrap(deviation(f))
        XCTAssertGreaterThan(d, 0.005, "un oeil decale de 6 % de la largeur doit se voir")

        let l = try XCTUnwrap(FaceGeometry.center(f.leftEye)), r = try XCTUnwrap(FaceGeometry.center(f.rightEye))
        XCTAssertEqual(FaceGeometry.legacyEyeSpacingDeviation(leftEye: l, rightEye: r), 0,
                       "controle negatif: l'ancienne formule rend zero sur ce meme visage")
    }

    func testMoreAsymmetryMeasuresMore() throws {
        var small = symmetricFace(), big = symmetricFace()
        small.rightBrow = small.rightBrow.map { CGPoint(x: $0.x, y: $0.y + 4) }
        big.rightBrow = big.rightBrow.map { CGPoint(x: $0.x, y: $0.y + 16) }
        XCTAssertLessThan(try XCTUnwrap(deviation(small)), try XCTUnwrap(deviation(big)))
    }

    func testTurnedHeadIsNotMeasured() {
        XCTAssertEqual(FaceGeometry.symmetry(symmetricFace(), yawDegrees: 25), .poseTooTurned(yawDegrees: 25))
        XCTAssertEqual(FaceGeometry.symmetry(symmetricFace(), yawDegrees: -20), .poseTooTurned(yawDegrees: -20))
        XCTAssertNotNil(deviation(symmetricFace(), yaw: 8))
    }

    func testNoAxisMeansNoNumber() {
        var f = symmetricFace()
        f.medianLine = []; f.noseCrest = []
        XCTAssertEqual(FaceGeometry.symmetry(f, yawDegrees: 0), .unavailable)
    }

    func testNoseCrestIsTheFallbackAxis() throws {
        var f = symmetricFace()
        f.medianLine = []
        XCTAssertEqual(try XCTUnwrap(deviation(f)), 0, accuracy: 1e-9)
    }

    func testRatiosDoNotChangeWithTilt() throws {
        let a = 20.0 * .pi / 180
        let straight = FaceGeometry.ratios(symmetricFace())
        let tilted = FaceGeometry.ratios(transform(symmetricFace()) {
            CGPoint(x: $0.x * cos(a) - $0.y * sin(a), y: $0.x * sin(a) + $0.y * cos(a))
        })
        XCTAssertEqual(try XCTUnwrap(straight.eyeSpacing), 90.0 / 200.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(tilted.eyeSpacing), try XCTUnwrap(straight.eyeSpacing), accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(tilted.thirds), try XCTUnwrap(straight.thirds), accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(tilted.widthToHeight), try XCTUnwrap(straight.widthToHeight), accuracy: 1e-6)
    }

    /// Le texte affiche ne doit jamais redevenir une note de beaute.
    func testMetricTextMakesNoBeautyClaim() throws {
        let text = try XCTUnwrap(FaceAnalyzer.metrics(symmetricFace(), yawDegrees: 3))
            .map { "\($0.title) \($0.value) \($0.note)" }.joined(separator: " ").lowercased()
        for word in ["beau", "idéal", "attirant", "harmonie", "/100"] {
            XCTAssertFalse(text.contains(word), "mot interdit: \(word)")
        }
    }
}
