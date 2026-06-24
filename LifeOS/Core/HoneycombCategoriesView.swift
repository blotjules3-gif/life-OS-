import SwiftUI

// =====================================================================
// MARK: - CONSTANTS  (tune everything here)
// =====================================================================

private enum BC {
    static let baseFrac: CGFloat = 0.32     // + dense : bulles plus grosses qui se chevauchent

    // --- transparency (luminous jewel-tone glass, NOT washed-out ghosts) ---
    static let coreOpacity: Double = 0.15
    static let rimOpacity:  Double = 0.72
    static let docsCore:    Double = 0.06    // Documents = nearly colourless, most transparent
    static let docsRim:     Double = 0.34
    static let fillerCore:  Double = 0.06
    static let fillerRim:   Double = 0.40

    // --- motion: gentle bob AROUND the anchor, going nowhere ---
    static let bobAmount:       CGFloat = 4   // points
    static let bobBigFactor:    CGFloat = 0.7 // big bubbles bob a touch less
    static let bobFillerFactor: CGFloat = 1.4 // fillers bob a touch more
    static let bigThreshold:    CGFloat = 1.10 // sizeMultiplier ≥ this → "big"

    // --- interaction ---
    static let tapThreshold: CGFloat = 10     // movement under this = tap, not drag
    static let growPerTap:   CGFloat = 0.05   // most-used categories grow over time…
    static let growMax:      CGFloat = 0.70   // …up to +70%
}

// =====================================================================
// MARK: - Catégories : composition FIXE de bulles flottantes (zéro physique)
// =====================================================================

struct HoneycombCategoriesView: View {
    @State private var path: [AppCategory] = []
    @AppStorage("bubbleWeights") private var weightsRaw = ""

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let bubbles = Layout.build(in: geo.size, weights: parseWeights())
                let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let maxD = bubbles.map { hypot($0.anchor.x - c.x, $0.anchor.y - c.y) }.max() ?? 1

                // .animation drives the calm bob; placement at rest is ALWAYS the anchor.
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    ZStack {
                        BubbleMesh().ignoresSafeArea()
                        ForEach(bubbles) { b in     // sorted small→big ⇒ big drawn on top
                            FixedBubble(
                                spec: b, time: t,
                                bloomDelay: Double(hypot(b.anchor.x - c.x, b.anchor.y - c.y) / max(1, maxD)) * 0.45,
                                onTap: b.cat == nil ? nil : {
                                    bump(b.cat!)
                                    path.append(b.cat!)
                                })
                        }
                    }
                }
            }
            .background(BubbleMesh().ignoresSafeArea())   // bleed behind the bars
            .toolbar(.hidden, for: .navigationBar)         // no title, immersive
            .navigationDestination(for: AppCategory.self) { $0.destination }
        }
    }

    // MARK: persisted click weights  ("rawValue:count,…")
    private func parseWeights() -> [String: Int] {
        var m: [String: Int] = [:]
        for pair in weightsRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, let v = Int(kv[1]) { m[String(kv[0])] = v }
        }
        return m
    }
    private func bump(_ cat: AppCategory) {
        var m = parseWeights()
        m[cat.rawValue, default: 0] += 1
        weightsRaw = m.map { "\($0):\($1)" }.joined(separator: ",")
    }
}

// =====================================================================
// MARK: - One bubble : anchored, bobs in place, drag springs back
// =====================================================================

private struct FixedBubble: View {
    let spec: Layout.Spec
    let time: Double
    let bloomDelay: Double
    let onTap: (() -> Void)?      // nil for fillers (non-interactive)

    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var appeared = false
    @State private var bounce = 0

    private var iris: [Color] {
        let hues: [Color] = [.pink, .purple, .blue, .cyan, .green, .yellow, .orange, .pink]
        return hues.map { $0.opacity(0.55) }
    }

    var body: some View {
        let r = spec.diameter / 2

        // FIX 2 — gentle bob around the anchor (no velocity, no drift, always returns).
        let bob = BC.bobAmount * spec.bobFactor
        let bx = CGFloat(sin(time * 0.5  + spec.phase))       * bob
        let by = CGFloat(cos(time * 0.42 + spec.phase * 1.3)) * bob
        let dx = drag.width  + (dragging ? 0 : bx)
        let dy = drag.height + (dragging ? 0 : by)

        bubbleBody(r: r)
            .frame(width: spec.diameter, height: spec.diameter)
            .shadow(color: spec.tint.opacity(0.34), radius: r * 0.22)   // coloured glow halo
            .scaleEffect(appeared ? 1 : 0.01)
            .opacity(appeared ? 1 : 0)
            .position(x: spec.anchor.x + dx, y: spec.anchor.y + dy)
            .modifier(DragIfNeeded(enabled: onTap != nil, r: r,
                                   drag: $drag, dragging: $dragging,
                                   onTap: { bounce += 1; Haptics.soft(); onTap?() }))
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(bloomDelay)) {
                    appeared = true
                }
            }
    }

    // The transparent soap-bubble layer stack.
    @ViewBuilder private func bubbleBody(r: CGFloat) -> some View {
        let t = spec.tint
        ZStack {
            // 1 · see-through tinted body — clear centre, saturated rim (Fresnel)
            Circle().fill(RadialGradient(
                stops: [
                    .init(color: t.opacity(spec.coreOp),       location: 0.00),
                    .init(color: t.opacity(spec.rimOp * 0.40), location: 0.60),
                    .init(color: t.opacity(spec.rimOp),        location: 1.00)
                ],
                center: UnitPoint(x: 0.42, y: 0.40), startRadius: 0, endRadius: r))

            // 2 · soft transmission glow (lit from within)
            Circle().fill(RadialGradient(
                colors: [.white.opacity(0.20), .clear],
                center: UnitPoint(x: 0.40, y: 0.37), startRadius: 0, endRadius: r * 0.95))

            // 3 · thin iridescent rainbow rim
            Circle().strokeBorder(AngularGradient(colors: iris, center: .center),
                                  lineWidth: max(0.8, r * 0.05))
                .blur(radius: 0.4)

            // 4 · crisp white specular highlights (sharp, not blurred)
            Ellipse().fill(.white.opacity(0.92))
                .frame(width: r * 0.40, height: r * 0.26)
                .rotationEffect(.degrees(-32))
                .offset(x: -r * 0.30, y: -r * 0.40)
            Circle().fill(.white.opacity(0.80))
                .frame(width: r * 0.11, height: r * 0.11)
                .offset(x: r * 0.22, y: -r * 0.28)

            // 5 · glyph + label (main bubbles only)
            if let icon = spec.icon {
                VStack(spacing: r * 0.05) {
                    Image(systemName: icon)
                        .font(.system(size: r * 0.46, weight: .semibold))
                        .symbolEffect(.bounce, value: bounce)
                    if let label = spec.label, spec.showLabel, r > 30 {
                        Text(label)
                            .font(.system(size: max(9, r * 0.20), weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.55)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Drag-to-rearrange (follows finger) + tap, only when interactive. On release the
/// bubble springs back to its anchor; a move under the threshold counts as a tap.
private struct DragIfNeeded: ViewModifier {
    let enabled: Bool
    let r: CGFloat
    @Binding var drag: CGSize
    @Binding var dragging: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        guard enabled else { return AnyView(content) }
        return AnyView(content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in dragging = true; drag = v.translation }
                .onEnded { v in
                    let moved = hypot(v.translation.width, v.translation.height)
                    if moved < BC.tapThreshold { onTap() }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                        drag = .zero                 // snap back toward the anchor
                    } completion: {
                        dragging = false             // resume bob from rest
                    }
                }
        ))
    }
}

// =====================================================================
// MARK: - Background : full-screen pastel mesh gradient
// =====================================================================

struct BubbleMesh: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2(0, 0),   SIMD2(0.5, 0),   SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(0.5, 0.5), SIMD2(1, 0.5),
                SIMD2(0, 1),   SIMD2(0.5, 1),   SIMD2(1, 1)
            ],
            colors: [
                .init(.sRGB, red: 0.80, green: 0.93, blue: 0.97), // TL pale cyan
                .init(.sRGB, red: 0.95, green: 0.95, blue: 0.99), // top near-white
                .init(.sRGB, red: 0.99, green: 0.92, blue: 0.94), // TR peach/lilac
                .init(.sRGB, red: 0.93, green: 0.92, blue: 0.99), // L pale lilac
                .init(.sRGB, red: 0.99, green: 0.99, blue: 1.00), // luminous centre
                .init(.sRGB, red: 1.00, green: 0.95, blue: 0.92), // R pale peach
                .init(.sRGB, red: 0.85, green: 0.91, blue: 0.99), // BL soft blue
                .init(.sRGB, red: 0.88, green: 0.93, blue: 1.00), // bottom soft blue
                .init(.sRGB, red: 0.93, green: 0.90, blue: 0.99)  // BR pale lilac
            ])
    }
}

// =====================================================================
// MARK: - FIX 1 : hard-coded composition (anchors as fractions of screen)
// =====================================================================

private enum Layout {

    struct Spec: Identifiable {
        let id: Int
        let cat: AppCategory?     // nil = filler
        let anchor: CGPoint       // FIXED position in screen points
        let diameter: CGFloat
        let tint: Color
        let icon: String?
        let label: String?
        let coreOp: Double
        let rimOp: Double
        let bobFactor: CGFloat
        let phase: Double
        let showLabel: Bool       // masqué si la bulle est recouverte par une plus grosse devant
    }

    /// (category, x-fraction, y-fraction, sizeMultiplier) — origin top-left, y down.
    private static let template: [(AppCategory, CGFloat, CGFloat, CGFloat)] = [
        (.admin,        0.24, 0.18, 1.05),   // Documents (very transparent, colourless)
        (.career,       0.50, 0.20, 1.00),   // Travail
        (.social,       0.79, 0.24, 1.15),   // Social
        (.finance,      0.17, 0.39, 0.85),   // Finance
        (.mind,         0.44, 0.41, 1.10),   // Mental
        (.looks,        0.72, 0.45, 1.10),   // Bien-être
        (.learning,     0.88, 0.56, 0.80),   // Éducation
        (.fitness,      0.31, 0.62, 1.40),   // Sport — HERO
        (.nutrition,    0.60, 0.66, 1.05),   // Alimentation
        (.sleep,        0.83, 0.67, 0.95),   // Sommeil
        (.invest,       0.15, 0.60, 0.78),   // Bourse
        (.productivity, 0.18, 0.78, 0.85),   // Tâches
        (.home,         0.64, 0.81, 0.85),   // Maison
        (.travel,       0.40, 0.87, 1.10),   // Voyage
        (.mobility,     0.80, 0.89, 0.90)    // Transports
    ]

    /// 6–8 sparse fillers in the gaps (x, y, sizeFractionOfBase).
    private static let fillers: [(CGFloat, CGFloat, CGFloat)] = [
        (0.55, 0.32, 0.22), (0.30, 0.50, 0.18), (0.70, 0.58, 0.27),
        (0.50, 0.74, 0.20), (0.88, 0.78, 0.16), (0.27, 0.68, 0.24),
        (0.62, 0.54, 0.15)
    ]

    static func build(in size: CGSize, weights: [String: Int]) -> [Spec] {
        guard size.width > 0 else { return [] }
        let base = size.width * BC.baseFrac
        let fillerPalette: [Color] = [.cyan, .mint, .pink, .purple, .blue, .teal, .indigo]

        // positions + diamètres des bulles principales
        let mains: [(cat: AppCategory, center: CGPoint, dia: CGFloat, mult: CGFloat)] = template.map { (cat, fx, fy, mult) in
            let grown = mult * growth(weights[cat.rawValue] ?? 0)
            return (cat, CGPoint(x: fx * size.width, y: fy * size.height), base * grown, mult)
        }

        var out: [Spec] = []
        var id = 0

        for (i, m) in mains.enumerated() {
            // label masqué si le centre est recouvert par une bulle plus GROSSE
            var show = true
            for (j, o) in mains.enumerated() where j != i && o.dia > m.dia * 1.02 {
                let d = hypot(m.center.x - o.center.x, m.center.y - o.center.y)
                if d < o.dia / 2 * 0.9 { show = false; break }
            }
            let isDocs = (m.cat == .admin)
            out.append(Spec(
                id: id, cat: m.cat,
                anchor: m.center, diameter: m.dia,
                tint: tint(m.cat), icon: m.cat.icon, label: label(m.cat),
                coreOp: isDocs ? BC.docsCore : BC.coreOpacity,
                rimOp:  isDocs ? BC.docsRim  : BC.rimOpacity,
                bobFactor: m.mult >= BC.bigThreshold ? BC.bobBigFactor : 1.0,
                phase: Double(id) * 0.9,
                showLabel: show))
            id += 1
        }

        for (i, (fx, fy, frac)) in fillers.enumerated() {
            out.append(Spec(
                id: id, cat: nil,
                anchor: CGPoint(x: fx * size.width, y: fy * size.height),
                diameter: base * frac,
                tint: fillerPalette[i % fillerPalette.count],
                icon: nil, label: nil,
                coreOp: BC.fillerCore, rimOp: BC.fillerRim,
                bobFactor: BC.bobFillerFactor,
                phase: Double(id) * 0.9,
                showLabel: false))
            id += 1
        }

        // draw order: small first → big last (big on top)
        return out.sorted { $0.diameter < $1.diameter }
    }

    private static func growth(_ count: Int) -> CGFloat {
        1 + min(CGFloat(count) * BC.growPerTap, BC.growMax)
    }

    private static func tint(_ c: AppCategory) -> Color {
        c == .admin ? Color(white: 0.78) : c.tint   // Documents = nearly colourless
    }

    private static func label(_ c: AppCategory) -> String {
        switch c {
        case .sleep: return "Sommeil";   case .nutrition: return "Alimentation"; case .fitness: return "Sport"
        case .looks: return "Bien-être"; case .mind: return "Mental";            case .productivity: return "Tâches"
        case .finance: return "Finance"; case .invest: return "Bourse";          case .career: return "Travail"
        case .learning: return "Éducation"; case .home: return "Maison";         case .mobility: return "Transports"
        case .social: return "Social";   case .admin: return "Documents";        case .travel: return "Voyage"
        }
    }
}
