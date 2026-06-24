import SwiftUI
import UIKit

// MARK: - Constantes

private enum Bub {
    static let MIN_R: CGFloat = 30
    static let MAX_R: CGFloat = 94
    static let GROWTH_K: CGFloat = 0.6
    static let PAD: CGFloat = 5
    static let CENTER_PULL: CGFloat = 0.004
    static let FLOAT_AMP: Double = 5
    static let FS: Double = 0.6
    static let TAP_THRESHOLD: CGFloat = 10
    static let FILLERS = 9
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
                    x: 8, y: geo.safeAreaInsets.top + 4,
                    width: geo.size.width - 16,
                    height: geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 8
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
                    bumpWeight(cat); Haptics.soft(); path.append(cat)
                }
            }
    }

    private func parseWeights() -> [String: Int] {
        var m: [String: Int] = [:]
        for pair in weightsRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, let v = Int(kv[1]) { m[String(kv[0])] = v }
        }
        return m
    }
    private func bumpWeight(_ cat: AppCategory) {
        var m = parseWeights(); m[cat.rawValue, default: 0] += 1
        weightsRaw = m.map { "\($0):\($1)" }.joined(separator: ",")
        sim.setWeight(id: cat.rawValue, weight: m[cat.rawValue]!)
    }
}

// MARK: - Fond mesh (centre presque blanc, coins pastel très pâles)

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
                .init(.sRGB, red: 0.85, green: 0.95, blue: 0.99),   // cyan très pâle (haut-gauche)
                .init(.sRGB, red: 0.95, green: 0.97, blue: 1.00),
                .init(.sRGB, red: 0.96, green: 0.92, blue: 0.99),   // lilas/rose pâle (haut-droite)
                .init(.sRGB, red: 0.93, green: 0.98, blue: 1.00),
                .init(.sRGB, red: 0.99, green: 0.99, blue: 1.00),   // centre presque blanc
                .init(.sRGB, red: 0.98, green: 0.95, blue: 1.00),
                .init(.sRGB, red: 0.90, green: 0.95, blue: 1.00),   // bleu pâle (bas)
                .init(.sRGB, red: 0.92, green: 0.96, blue: 1.00),
                .init(.sRGB, red: 0.93, green: 0.94, blue: 1.00)
            ]
        )
    }
}

// MARK: - Bulle de savon (anatomie 11 couches)

struct GelBubble: View {
    let b: BubbleSim.B
    @State private var appeared = false
    @State private var bump = 0

    private var D: CGFloat { b.radius * 2 }

    // opacités du corps selon le type
    private var stops: [Gradient.Stop] {
        let c = b.color
        if b.isFiller {
            return [.init(color: c.opacity(0.12), location: 0), .init(color: c.opacity(0.16), location: 0.6),
                    .init(color: c.opacity(0.28), location: 1)]
        }
        if b.cat == .admin {   // Documents : quasi incolore mais visible
            return [.init(color: c.opacity(0.06), location: 0), .init(color: c.opacity(0.16), location: 0.45),
                    .init(color: c.opacity(0.30), location: 0.80), .init(color: c.opacity(0.45), location: 1)]
        }
        // saturé au bord, plus clair au centre (garde la transparence mais la couleur ressort)
        return [.init(color: c.opacity(0.22), location: 0), .init(color: c.opacity(0.48), location: 0.45),
                .init(color: c.opacity(0.70), location: 0.80), .init(color: c.opacity(0.88), location: 1)]
    }
    private var iridOpacity: Double { b.cat == .admin ? 0.6 : (b.isFiller ? 0.45 : 0.4) }

    var body: some View {
        let c = b.color
        ZStack {
            clippedBody
            rimLayers
            speculars
        }
        .frame(width: D, height: D)
        .overlay { glyphLabel }
        // Couche 0 : halo coloré qui bave sur le fond (centre transparent préservé)
        .shadow(color: c.opacity(0.5), radius: D * 0.22)
        .scaleEffect(appeared ? 1 : 0.01)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(b.appearDelay)) { appeared = true }
        }
        .onChange(of: b.weight) { _, _ in bump += 1 }
    }

    // Couches 1,2,3,7,8 (clippées au cercle)
    private var clippedBody: some View {
        let c = b.color
        return ZStack {
            // 1. corps transparent teinté (centre clair, bord saturé ≤ 0.58)
            Circle().fill(RadialGradient(gradient: Gradient(stops: stops),
                                         center: UnitPoint(x: 0.38, y: 0.32),
                                         startRadius: 0, endRadius: D * 0.75))
            // 2. glow de transmission (bas-droite, opposé au reflet)
            Ellipse().fill(RadialGradient(colors: [.white.opacity(0.16), .clear],
                                          center: .center, startRadius: 0, endRadius: D * 0.25))
                .frame(width: D * 0.5, height: D * 0.5).blur(radius: D * 0.15)
                .offset(x: D * 0.12, y: D * 0.24)
            // 3. croissant d'ombre interne (bas-droite, volume)
            Circle().trim(from: 0.04, to: 0.22)
                .stroke(c.brightnessAdjusted(-0.35).opacity(0.15),
                        style: StrokeStyle(lineWidth: D * 0.12, lineCap: .round))
                .blur(radius: D * 0.03)
            // 7. reflet spéculaire principal (doux mais lisible)
            Ellipse().fill(RadialGradient(colors: [.white.opacity(0.9), .clear],
                                          center: .center, startRadius: 0, endRadius: D * 0.17))
                .frame(width: D * 0.34, height: D * 0.26).blur(radius: D * 0.04)
                .offset(x: -D * 0.16, y: -D * 0.22)
            // 8. points spéculaires nets (verre mouillé)
            Circle().fill(.white).opacity(0.95).frame(width: D * 0.06, height: D * 0.06)
                .offset(x: -D * 0.04, y: -D * 0.28)
            Circle().fill(.white).opacity(0.85).frame(width: D * 0.04, height: D * 0.04)
                .offset(x: -D * 0.23, y: -D * 0.10)
            Circle().fill(.white).opacity(0.7).frame(width: D * 0.025, height: D * 0.025)
                .offset(x: -D * 0.10, y: -D * 0.32)
        }
        .clipShape(Circle())
    }

    // Couches 4,5,6 (rebords)
    private var rimLayers: some View {
        ZStack {
            // 4. rebord irisé (rainbow savon)
            Circle().strokeBorder(
                AngularGradient(colors: [Color(hue: 0.92, saturation: 0.7, brightness: 1),
                                         .cyan, .yellow, .mint, .purple,
                                         Color(hue: 0.92, saturation: 0.7, brightness: 1)],
                                center: .center),
                lineWidth: D * 0.015)
                .opacity(iridOpacity).blur(radius: 0.5)
            // 5. catch lumineux du rebord haut-gauche (glint net)
            Circle().trim(from: 0.55, to: 0.72)
                .stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.0)],
                                       startPoint: .topTrailing, endPoint: .bottomLeading),
                        style: StrokeStyle(lineWidth: D * 0.02, lineCap: .round))
                .opacity(0.85)
            // 6. catch faible du rebord bas-droit
            Circle().trim(from: 0.05, to: 0.18)
                .stroke(.white, style: StrokeStyle(lineWidth: D * 0.012, lineCap: .round))
                .opacity(0.4)
        }
    }

    @ViewBuilder private var speculars: some View { EmptyView() }

    // Couches 9,10
    @ViewBuilder private var glyphLabel: some View {
        if !b.isFiller, let icon = b.icon {
            VStack(spacing: D * 0.02) {
                Image(systemName: icon)
                    .font(.system(size: D * 0.40, weight: .semibold))
                    .symbolEffect(.bounce, value: bump)
                    .shadow(color: .black.opacity(0.3), radius: D * 0.02)
                if let label = b.label, D > 64 {
                    Text(label)
                        .font(.system(size: D * 0.13, weight: .semibold))
                        .shadow(color: .black.opacity(0.4), radius: D * 0.02)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(.white)
            .offset(y: -D * 0.02)
        }
    }
}

// MARK: - Simulation physique

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
        let palette: [Color] = [.pink, .blue, .green, .orange, .purple, .mint, .cyan, .yellow, .teal]
        for k in 0..<Bub.FILLERS {
            let x = CGFloat.random(in: bounds.minX + 24...bounds.maxX - 24)
            let y = CGFloat.random(in: bounds.minY + 24...bounds.maxY - 24)
            let r = CGFloat.random(in: 14...28)
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
            bubbles[i].radius += (bubbles[i].targetRadius - bubbles[i].radius) * 0.12
            if bubbles[i].id == draggingID { bubbles[i].anchor = dragTarget; continue }
            bubbles[i].anchor.x += (cx - bubbles[i].anchor.x) * Bub.CENTER_PULL
            bubbles[i].anchor.y += (cy - bubbles[i].anchor.y) * Bub.CENTER_PULL
        }
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
        for i in bubbles.indices {
            let r = bubbles[i].radius
            bubbles[i].anchor.x = min(max(bubbles[i].anchor.x, bounds.minX + r), bounds.maxX - r)
            bubbles[i].anchor.y = min(max(bubbles[i].anchor.y, bounds.minY + r), bounds.maxY - r)
            let fx = sin(t * Bub.FS + bubbles[i].phase) * Bub.FLOAT_AMP
            let fy = cos(t * Bub.FS * 0.9 + bubbles[i].phase) * Bub.FLOAT_AMP
            bubbles[i].pos = CGPoint(x: bubbles[i].anchor.x + fx, y: bubbles[i].anchor.y + fy)
        }
    }

    // Couleurs système Apple (mapping de la référence)
    static func color(_ c: AppCategory) -> Color {
        switch c {
        case .fitness: return .red
        case .mind: return .purple
        case .social: return .pink
        case .looks: return .orange
        case .finance: return .blue
        case .travel: return .blue
        case .nutrition: return .green
        case .sleep: return .indigo
        case .learning: return .yellow
        case .home: return .blue
        case .mobility: return .teal
        case .productivity: return .teal
        case .career: return .brown
        case .invest: return .mint
        case .admin: return Color(white: 0.7)   // Documents : gris très pâle
        }
    }
    static func label(_ c: AppCategory) -> String {
        switch c {
        case .sleep: return "Sommeil"; case .nutrition: return "Alimentation"; case .fitness: return "Sport"
        case .looks: return "Bien-être"; case .mind: return "Mental"; case .productivity: return "Tâches"
        case .finance: return "Finance"; case .invest: return "Bourse"; case .career: return "Travail"
        case .learning: return "Éducation"; case .home: return "Maison"; case .mobility: return "Transports"
        case .social: return "Social"; case .admin: return "Documents"; case .travel: return "Voyage"
        }
    }
    // Hiérarchie de taille (Sport = hero MAX)
    static func seed(_ c: AppCategory) -> CGFloat {
        switch c {
        case .fitness: return 94
        case .social: return 80; case .mind: return 78; case .looks: return 78; case .travel: return 76
        case .nutrition: return 62; case .finance: return 60; case .sleep: return 60; case .home: return 58
        case .mobility: return 58; case .productivity: return 58; case .learning: return 56
        case .career: return 58; case .admin: return 58; case .invest: return 50
        }
    }
}

// MARK: - Ajustement luminosité

extension Color {
    func brightnessAdjusted(_ delta: CGFloat) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: Double(max(0, min(1, b + delta))), opacity: Double(a))
    }
}
