import CoreGraphics
import Foundation

/// Geometrie du visage, sans Vision: des points entrent, des mesures sortent.
/// Separe de la vue pour etre teste sur des points synthetiques.
///
/// **Le defaut corrige (28 septembre).** L'ancienne symetrie prenait le milieu des
/// deux yeux comme axe, puis comparait la distance de chaque oeil a ce milieu. Ces
/// deux distances sont egales par definition: la composante "ecartement" valait
/// toujours zero. L'axe vient maintenant de la ligne mediane du visage (arete du
/// nez en secours), independante des points compares.
///
/// Tous les points doivent etre dans un repere ISOTROPE (pixels de l'image), sinon
/// un axe incline et les rapports largeur/hauteur sont faux.
enum FaceGeometry {

    struct Landmarks {
        var contour: [CGPoint]
        var medianLine: [CGPoint] = []
        var noseCrest: [CGPoint] = []
        var leftEye: [CGPoint] = []
        var rightEye: [CGPoint] = []
        var leftBrow: [CGPoint] = []
        var rightBrow: [CGPoint] = []
        var outerLips: [CGPoint] = []
        var nose: [CGPoint] = []
    }

    /// Une droite: un point et une direction unitaire.
    struct Axis: Equatable {
        let point: CGPoint
        let direction: CGVector
    }

    enum SymmetryResult: Equatable {
        /// Ecart miroir moyen, en fraction de la largeur du visage (0 = parfait).
        case measured(deviation: Double, pairs: Int)
        /// Tete trop tournee: la mesure serait celle de la pose, pas du visage.
        case poseTooTurned(yawDegrees: Double)
        /// Ni ligne mediane ni arete du nez, ou pas assez de paires.
        case unavailable
    }

    /// Au dela, un cote parait plus etroit a cause de la perspective seule.
    static let maxYawDegrees = 12.0

    // MARK: - Axe

    /// Droite des moindres carres x = a*y + b (l'axe est proche de la verticale,
    /// donc on regresse x sur y pour rester stable quand il est vertical).
    static func fitAxis(_ pts: [CGPoint]) -> Axis? {
        guard pts.count >= 2 else { return nil }
        let n = CGFloat(pts.count)
        let my = pts.reduce(0) { $0 + $1.y } / n
        let mx = pts.reduce(0) { $0 + $1.x } / n
        let syy = pts.reduce(0) { $0 + ($1.y - my) * ($1.y - my) }
        guard syy > 1e-9 else { return nil }
        let sxy = pts.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) }
        let a = sxy / syy
        let len = (a * a + 1).squareRoot()
        return Axis(point: CGPoint(x: mx, y: my), direction: CGVector(dx: a / len, dy: 1 / len))
    }

    /// Symetrique de `p` par rapport a l'axe.
    static func mirror(_ p: CGPoint, across axis: Axis) -> CGPoint {
        let vx = p.x - axis.point.x, vy = p.y - axis.point.y
        let d = axis.direction
        let t = vx * d.dx + vy * d.dy
        let projX = axis.point.x + t * d.dx, projY = axis.point.y + t * d.dy
        return CGPoint(x: 2 * projX - p.x, y: 2 * projY - p.y)
    }

    // MARK: - Symetrie

    static func symmetry(_ lm: Landmarks, yawDegrees: Double?) -> SymmetryResult {
        if let yaw = yawDegrees, abs(yaw) > maxYawDegrees { return .poseTooTurned(yawDegrees: yaw) }
        let axisPts = lm.medianLine.count >= 2 ? lm.medianLine : lm.noseCrest
        guard let axis = fitAxis(axisPts), let width = faceWidth(lm, axis: axis), width > 0 else {
            return .unavailable
        }

        var pairs: [(CGPoint, CGPoint)] = []
        if let l = center(lm.leftEye), let r = center(lm.rightEye) { pairs.append((l, r)) }
        if let l = center(lm.leftBrow), let r = center(lm.rightBrow) { pairs.append((l, r)) }
        if let corners = mouthCorners(lm.outerLips, axis: axis) { pairs.append(corners) }
        // Contour: le point i et son jumeau n-1-i, en laissant le menton (milieu).
        let c = lm.contour
        if c.count >= 5 {
            for i in 0..<(c.count / 2 - 1) { pairs.append((c[i], c[c.count - 1 - i])) }
        }
        guard pairs.count >= 2 else { return .unavailable }

        let total = pairs.reduce(0.0) { acc, pair in
            let m = mirror(pair.1, across: axis)
            return acc + Double(hypot(m.x - pair.0.x, m.y - pair.0.y))
        }
        return .measured(deviation: total / Double(pairs.count) / Double(width), pairs: pairs.count)
    }

    /// Ancienne formule, gardee pour le test qui prouve qu'elle etait aveugle.
    static func legacyEyeSpacingDeviation(leftEye: CGPoint, rightEye: CGPoint) -> CGFloat {
        let midX = (leftEye.x + rightEye.x) / 2
        return abs(abs(leftEye.x - midX) - abs(rightEye.x - midX))
    }

    // MARK: - Rapports (mesures, pas des notes)

    /// Largeur du visage mesuree perpendiculairement a l'axe (une tete penchee ne
    /// change donc pas la largeur).
    static func faceWidth(_ lm: Landmarks, axis: Axis) -> CGFloat? {
        guard lm.contour.count > 2 else { return nil }
        let nx = axis.direction.dy, ny = -axis.direction.dx   // normale a l'axe
        let proj = lm.contour.map { ($0.x - axis.point.x) * nx + ($0.y - axis.point.y) * ny }
        guard let lo = proj.min(), let hi = proj.max() else { return nil }
        return hi - lo
    }

    struct Ratios: Equatable {
        var eyeSpacing: Double?      // distance inter oculaire / largeur du visage
        var thirds: Double?          // (sourcils -> base du nez) / (base du nez -> menton)
        var widthToHeight: Double?   // largeur / (sourcils -> levre haute)
    }

    /// Les mesures se font dans le repere de l'axe: "hauteur" = le long de l'axe.
    static func ratios(_ lm: Landmarks) -> Ratios {
        let axisPts = lm.medianLine.count >= 2 ? lm.medianLine : lm.noseCrest
        let axis = fitAxis(axisPts) ?? Axis(point: .zero, direction: CGVector(dx: 0, dy: 1))
        guard let width = faceWidth(lm, axis: axis), width > 0 else { return Ratios() }
        let along: (CGPoint) -> CGFloat = { ($0.x - axis.point.x) * axis.direction.dx + ($0.y - axis.point.y) * axis.direction.dy }

        var r = Ratios()
        if let l = center(lm.leftEye), let rt = center(lm.rightEye) {
            r.eyeSpacing = Double(hypot(l.x - rt.x, l.y - rt.y) / width)
        }
        let brows = [center(lm.leftBrow), center(lm.rightBrow)].compactMap { $0 }
        let browH = brows.isEmpty ? nil : brows.map(along).reduce(0, +) / CGFloat(brows.count)
        let chin = lm.contour.map(along).min()
        let noseBase = lm.nose.map(along).min()
        if let b = browH, let n = noseBase, let c = chin {
            let mid = abs(b - n), low = abs(n - c)
            if mid > 0, low > 0 { r.thirds = Double(mid / low) }
        }
        if let b = browH, let lipTop = lm.outerLips.map(along).max() {
            let h = abs(b - lipTop)
            if h > 0 { r.widthToHeight = Double(width / h) }
        }
        return r
    }

    // MARK: - Aides

    static func center(_ pts: [CGPoint]) -> CGPoint? {
        guard !pts.isEmpty else { return nil }
        let n = CGFloat(pts.count)
        return CGPoint(x: pts.reduce(0) { $0 + $1.x } / n, y: pts.reduce(0) { $0 + $1.y } / n)
    }

    /// Les deux coins de la bouche: les points les plus eloignes de l'axe, un de
    /// chaque cote.
    private static func mouthCorners(_ lips: [CGPoint], axis: Axis) -> (CGPoint, CGPoint)? {
        guard lips.count >= 4 else { return nil }
        let nx = axis.direction.dy, ny = -axis.direction.dx
        let side: (CGPoint) -> CGFloat = { ($0.x - axis.point.x) * nx + ($0.y - axis.point.y) * ny }
        guard let a = lips.min(by: { side($0) < side($1) }),
              let b = lips.max(by: { side($0) < side($1) }),
              side(a) < 0, side(b) > 0 else { return nil }
        return (a, b)
    }
}
