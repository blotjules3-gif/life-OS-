import SwiftUI

/// Petite courbe d'un cours, sans axes. Partagee app + widgets (pas de Charts dans
/// l'extension pour rester leger). Moins de 2 points : rien n'est dessine.
struct StockSparkline: View {
    let values: [Double]
    /// Ligne de reference (cloture de la veille), en pointilles, si elle tombe dans l'echelle.
    var baseline: Double? = nil
    var color: Color
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let pts = Self.points(values, in: geo.size, baseline: baseline)
            ZStack {
                if let y = pts.baselineY {
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                }
                if pts.line.count >= 2 {
                    Path { p in
                        p.move(to: pts.line[0])
                        for pt in pts.line.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Pure : points a l'echelle de `size` (haut = maximum).
    static func points(_ values: [Double], in size: CGSize, baseline: Double?) -> (line: [CGPoint], baselineY: CGFloat?) {
        guard values.count >= 2, size.width > 0, size.height > 0 else { return ([], nil) }
        var lo = values.min() ?? 0, hi = values.max() ?? 0
        if let b = baseline { lo = min(lo, b); hi = max(hi, b) }
        let span = hi - lo
        func y(_ v: Double) -> CGFloat {
            span > 0 ? CGFloat(1 - (v - lo) / span) * size.height : size.height / 2
        }
        let step = size.width / CGFloat(values.count - 1)
        let line = values.enumerated().map { CGPoint(x: CGFloat($0.offset) * step, y: y($0.element)) }
        return (line, baseline.map(y))
    }
}
