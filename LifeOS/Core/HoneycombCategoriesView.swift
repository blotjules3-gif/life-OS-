import SwiftUI
import UIKit

// MARK: - Constantes (à régler)

private enum Bub {
    static let baseR: CGFloat = 46
    static let MIN_R: CGFloat = 34
    static let MAX_R: CGFloat = 92
    static let GROWTH_K: CGFloat = 0.6
    static let PAD: CGFloat = 6
    static let CENTER_PULL: CGFloat = 0.004   // gravité très douce vers le centre
    static let FLOAT_AMP: Double = 5
    static let FS: Double = 0.6               // petit + lent = flottement subtil
    static let TAP_THRESHOLD: CGFloat = 10    // < 10pt de déplacement = tap
    static let FILLERS = 8
    // Translucidité (régler ici) — bas = plus transparent
    static let FILL_CENTER_OPACITY: Double = 0.10
    static let FILL_MID_OPACITY: Double = 0.28
    static let FILL_RIM_OPACITY: Double = 0.55
    static let IRIDESCENCE_OPACITY: Double = 0.40
    static let HALO_OPACITY: Double = 0.50
    static let HALO_RADIUS_RATIO: CGFloat = 0.22
}

// MARK: - Vue principale

struct HoneycombCategoriesView: View {
    @State private var sim = BubbleSim()
    @State private var path: [AppCategory] = []
    @AppStorage("bubbleWeights") private var weightsRaw = ""

    private static let mains: [AppCategory] = [
        .fitness, .nutrition, .looks, .productivity, .mind, .finance, .sleep,
        .learning, .invest, .career, .home, .social, .mobility, .admin, .travel
    ]

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let bounds = CGRect(
                    x: 10, y: geo.safeAreaInsets.top + 6,
                    width: geo.size.width - 20,
                    height: geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 12
                )
                ZStack {
                    BubbleMesh().ignoresSafeArea()
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let frame = sim.frame(t: t, bounds: bounds, weights: parseWeights(), mains: Self.mains)
                        ZStack {
                            ForEach(frame) { b in
                                GelBubble(b: b)
                                    .position(b.pos)
                                    .gesture(b.isFiller ? nil : gesture(for: b))
                            }
                        }
                    }
                }
                .coordinateSpace(.named("sim"))
            }
            .navigationDestination(for: AppCategory.self) { $0.destination }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func gesture(for b: BubbleSim.B) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("sim"))
            .onChanged { v in
                if hypot(v.translation.width, v.translation.height) > Bub.TAP_THRESHOLD {
                    sim.draggingID = b.id
                    sim.dragTarget = v.location
                }
            }
            .onEnded { v in
                let travel = hypot(v.translation.width, v.translation.height)
                sim.draggingID = nil
                if travel < Bub.TAP_THRESHOLD, let cat = b.cat {
                    bumpWeight(cat)
                    Haptics.soft()
                    path.append(cat)
                }
            }
    }

    // MARK: Usage persistant

    private func parseWeights() -> [String: Int] {
        var m: [String: Int] = [:]
        for pair in weightsRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, let v = Int(kv[1]) { m[String(kv[0])] = v }
        }
        return m
    }
    private func bumpWeight(_ cat: AppCategory) {
        var m = parseWeights()
        m[cat.rawValue, default: 0] += 1
        weightsRaw = m.map { "\($0):\($1)" }.joined(separator: ",")
        sim.setWeight(id: cat.rawValue, weight: m[cat.rawValue]!)
    }
}

// MARK: - Fond mesh pastel

struct BubbleMesh: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(0.5, 0.5), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
            ],
            colors: [
                .init(.sRGB, red: 0.82, green: 0.90, blue: 1.00),
                .init(.sRGB, red: 0.88, green: 0.95, blue: 1.00),
                .init(.sRGB, red: 0.92, green: 0.88, blue: 1.00),
                .init(.sRGB, red: 0.86, green: 0.98, blue: 0.95),
                .init(.sRGB, red: 0.98, green: 0.97, blue: 1.00),
                .init(.sRGB, red: 1.00, green: 0.93, blue: 0.90),
                .init(.sRGB, red: 0.90, green: 0.95, blue: 1.00),
                .init(.sRGB, red: 0.94, green: 0.98, blue: 0.96),
                .init(.sRGB, red: 0.95, green: 0.90, blue: 1.00)
            ]
        )
    }
}

// MARK: - Sphère de gel glossy

struct GelBubble: View {
    let b: BubbleSim.B
    @State private var appeared = false
    @State private var bump = 0

    private var D: CGFloat { b.radius * 2 }

    var body: some View {
        let c = b.color
        ZStack {
            // 1. cœur gel translucide (volume, lumière en haut à gauche)
            Circle()
                .fill(RadialGradient(
                    colors: [c.brightnessAdjusted(0.45), c, c.brightnessAdjusted(-0.28)],
                    center: UnitPoint(x: 0.32, y: 0.28),
                    startRadius: 1, endRadius: D * 0.72))
                .opacity(b.isFiller ? 0.45 : 0.86)
            // 2. ombre basse droite (rondeur)
            Circle()
                .fill(RadialGradient(colors: [.clear, .black.opacity(0.22)],
                                     center: UnitPoint(x: 0.74, y: 0.8),
                                     startRadius: D * 0.1, endRadius: D * 0.62))
                .blendMode(.multiply)
            // 3. reflet large diffus
            Ellipse().fill(.white).opacity(0.7)
                .frame(width: D * 0.5, height: D * 0.34)
                .blur(radius: D * 0.05)
                .offset(x: -D * 0.16, y: -D * 0.22)
            // 4. point chaud net
            Circle().fill(.white).opacity(0.9)
                .frame(width: D * 0.1, height: D * 0.1)
                .blur(radius: 0.5)
                .offset(x: -D * 0.22, y: -D * 0.26)
            // 5. liseré
            Circle().stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.05)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
        }
        .clipShape(Circle())
        .overlay {
            // 7+8. glyphe + label (seulement bulles principales)
            if !b.isFiller, let icon = b.icon {
                VStack(spacing: D * 0.03) {
                    Image(systemName: icon)
                        .font(.system(size: D * 0.4, weight: .semibold))
                        .symbolEffect(.bounce, value: bump)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    if let label = b.label, D > 70 {
                        Text(label)
                            .font(.system(size: D * 0.13, weight: .semibold))
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .frame(width: D, height: D)
        .shadow(color: c.opacity(0.55), radius: D * 0.12, y: D * 0.04)   // bloom coloré
        .shadow(color: .black.opacity(0.12), radius: 6, y: 4)             // décollement
        .scaleEffect(appeared ? 1 : 0.01)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(b.appearDelay)) { appeared = true }
        }
        .onChange(of: b.weight) { _, _ in bump += 1 }
    }
}

// MARK: - Simulation physique (classe simple : pilotée par TimelineView)

final class BubbleSim {
    struct B: Identifiable {
        let id: String
        let color: Color
        let icon: String?
        let label: String?
        let isFiller: Bool
        let cat: AppCategory?
        var anchor: CGPoint
        var pos: CGPoint
        var radius: CGFloat
        var targetRadius: CGFloat
        var weight: Int
        var phase: Double
        let appearDelay: Double
        var seedR: CGFloat
    }

    private(set) var bubbles: [B] = []
    var bounds: CGRect = .zero
    var draggingID: String?
    var dragTarget: CGPoint = .zero
    private var started = false

    /// Ensure + tick + tri (gros au-dessus), renvoyé pour le rendu.
    func frame(t: TimeInterval, bounds: CGRect, weights: [String: Int], mains: [AppCategory]) -> [B] {
        self.bounds = bounds
        ensure(weights: weights, mains: mains)
        tick(t: t)
        return bubbles.sorted { $0.radius < $1.radius }
    }

    func setWeight(id: String, weight: Int) {
        guard let i = bubbles.firstIndex(where: { $0.id == id }) else { return }
        bubbles[i].weight = weight
        bubbles[i].targetRadius = radius(for: bubbles[i].seedR, weight: weight)
    }

    private func radius(for seed: CGFloat, weight: Int) -> CGFloat {
        min(Bub.MAX_R, max(Bub.MIN_R, seed * sqrt(1 + CGFloat(weight) * Bub.GROWTH_K)))
    }

    private func ensure(weights: [String: Int], mains: [AppCategory]) {
        // n'initialise que quand le layout est valide (sinon random(in:) plante)
        guard !started, bounds.width > 120, bounds.height > 200 else { return }
        started = true
        let cx = bounds.midX, cy = bounds.midY
        var arr: [B] = []
        let cols = 3
        let rows = Int(ceil(Double(mains.count) / Double(cols)))
        for (i, cat) in mains.enumerated() {
            let col = i % cols, row = i / cols
            let x = bounds.minX + bounds.width * (CGFloat(col) + 0.5) / CGFloat(cols) + .random(in: -16...16)
            let y = bounds.minY + bounds.height * (CGFloat(row) + 0.6) / CGFloat(rows) + .random(in: -16...16)
            let seed = Self.seed(cat)
            let w = weights[cat.rawValue] ?? 0
            let r = radius(for: seed, weight: w)
            let d = hypot(x - cx, y - cy)
            arr.append(B(id: cat.rawValue, color: Self.color(cat), icon: cat.icon, label: Self.label(cat),
                         isFiller: false, cat: cat, anchor: CGPoint(x: x, y: y), pos: CGPoint(x: x, y: y),
                         radius: r, targetRadius: r, weight: w, phase: .random(in: 0...6.28),
                         appearDelay: Double(d / max(bounds.width, bounds.height)) * 0.5, seedR: seed))
        }
        let palette: [Color] = [.pink, .blue, .green, .orange, .purple, .mint, .cyan, .yellow]
        for k in 0..<Bub.FILLERS {
            let x = CGFloat.random(in: bounds.minX + 20...bounds.maxX - 20)
            let y = CGFloat.random(in: bounds.minY + 20...bounds.maxY - 20)
            let r = CGFloat.random(in: 9...20)
            arr.append(B(id: "filler\(k)", color: palette.randomElement()!, icon: nil, label: nil,
                         isFiller: true, cat: nil, anchor: CGPoint(x: x, y: y), pos: CGPoint(x: x, y: y),
                         radius: r, targetRadius: r, weight: 0, phase: .random(in: 0...6.28),
                         appearDelay: .random(in: 0...0.4), seedR: r))
        }
        bubbles = arr
    }

    private func tick(t: TimeInterval) {
        guard started else { return }
        let cx = bounds.midX, cy = bounds.midY
        for i in bubbles.indices {
            // croissance douce du rayon
            bubbles[i].radius += (bubbles[i].targetRadius - bubbles[i].radius) * 0.12
            if bubbles[i].id == draggingID { bubbles[i].anchor = dragTarget; continue }
            // gravité très douce vers le centre
            bubbles[i].anchor.x += (cx - bubbles[i].anchor.x) * Bub.CENTER_PULL
            bubbles[i].anchor.y += (cy - bubbles[i].anchor.y) * Bub.CENTER_PULL
        }
        // répulsion (packing organique, jamais de fusion)
        for _ in 0..<2 {
            for a in bubbles.indices {
                for b in bubbles.indices where b > a {
                    let dx = bubbles[a].anchor.x - bubbles[b].anchor.x
                    let dy = bubbles[a].anchor.y - bubbles[b].anchor.y
                    var dist = hypot(dx, dy); if dist < 0.01 { dist = 0.01 }
                    let minD = bubbles[a].radius + bubbles[b].radius + Bub.PAD
                    if dist < minD {
                        let push = (minD - dist) / 2
                        let nx = dx / dist, ny = dy / dist
                        if bubbles[a].id != draggingID { bubbles[a].anchor.x += nx * push; bubbles[a].anchor.y += ny * push }
                        if bubbles[b].id != draggingID { bubbles[b].anchor.x -= nx * push; bubbles[b].anchor.y -= ny * push }
                    }
                }
            }
        }
        // clamp + flottement subtil
        for i in bubbles.indices {
            let r = bubbles[i].radius
            bubbles[i].anchor.x = min(max(bubbles[i].anchor.x, bounds.minX + r), bounds.maxX - r)
            bubbles[i].anchor.y = min(max(bubbles[i].anchor.y, bounds.minY + r), bounds.maxY - r)
            let fx = sin(t * Bub.FS + bubbles[i].phase) * Bub.FLOAT_AMP
            let fy = cos(t * Bub.FS * 0.9 + bubbles[i].phase) * Bub.FLOAT_AMP
            bubbles[i].pos = CGPoint(x: bubbles[i].anchor.x + fx, y: bubbles[i].anchor.y + fy)
        }
    }

    // MARK: Données catégories

    static func color(_ c: AppCategory) -> Color {
        switch c {
        case .fitness: return .red;        case .looks: return .orange
        case .productivity: return .teal;  case .sleep: return .indigo
        case .nutrition: return .green;    case .finance: return .blue
        case .mobility: return .cyan;      case .travel: return .blue
        case .career: return .brown;       case .home: return .blue
        case .social: return .pink;        case .invest: return .mint
        case .learning: return .yellow;    case .mind: return .purple
        case .admin: return .gray
        }
    }
    static func label(_ c: AppCategory) -> String {
        switch c {
        case .sleep: return "Sommeil"; case .nutrition: return "Alimentation"; case .fitness: return "Sport"
        case .looks: return "Beauté"; case .mind: return "Mental"; case .productivity: return "Tâches"
        case .finance: return "Finance"; case .invest: return "Bourse"; case .career: return "Travail"
        case .learning: return "Éducation"; case .home: return "Maison"; case .mobility: return "Transports"
        case .social: return "Social"; case .admin: return "Documents"; case .travel: return "Voyage"
        }
    }
    static func seed(_ c: AppCategory) -> CGFloat {
        switch c {
        case .fitness: return 66; case .social: return 58; case .nutrition: return 54; case .mind: return 54
        case .looks: return 52; case .travel: return 52; case .finance: return 50; case .productivity: return 50
        case .sleep: return 50; case .career: return 48; case .mobility: return 48; case .learning: return 46
        case .home: return 46; case .admin: return 44; case .invest: return 42
        }
    }
}

// MARK: - Ajustement de luminosité

extension Color {
    func brightnessAdjusted(_ delta: CGFloat) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: Double(max(0, min(1, b + delta))), opacity: Double(a))
    }
}
