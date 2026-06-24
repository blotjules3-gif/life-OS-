import SwiftUI

// MARK: - Constantes (à régler)

private enum Honey {
    static let D: CGFloat = 108          // plus gros = plus dense
    static let G: CGFloat = 8            // serré (les glass indépendants ne fusionnent pas)
    static let MAX_SCALE: Double = 1.12
    static let MIN_SCALE: Double = 0.84
    static let FOCAL_RATIO: CGFloat = 0.62
    static let COLS = 3
    static let ROWS = 5                  // 3 x 5 = 15, format vertical qui remplit l'écran
    static let TOP_PAD: CGFloat = 2      // colle à la Dynamic Island (via safe area)
    static let BOTTOM_PAD: CGFloat = 2   // colle au menu du bas (via safe area)
}

/// Ruche fixe et centrée, **vrai Liquid Glass iOS 26** posé sur un fond MeshGradient
/// (le glass réfracte ce fond → vraies icônes d'app). Bulles rondes indépendantes, plein écran.
struct HoneycombCategoriesView: View {
    @State private var path: [AppCategory] = []

    private static let order: [AppCategory] = [
        .fitness, .nutrition, .looks, .productivity, .mind, .finance, .sleep,
        .learning, .invest, .career, .home, .social, .mobility, .admin, .travel
    ]

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let focal = geo.size.width * Honey.FOCAL_RATIO
                let slots = layout(in: geo.size, safe: geo.safeAreaInsets, focal: focal)
                ZStack {
                    meshBackground.ignoresSafeArea()
                    ForEach(slots) { s in
                        GlassBubble(
                            cat: s.cat, color: color(s.cat), label: shortName(s.cat),
                            baseScale: s.baseScale, delay: s.delay, isCenter: s.isCenter
                        ) { path.append(s.cat) }
                        .position(s.pos)
                    }
                }
            }
            .navigationDestination(for: AppCategory.self) { $0.destination }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Fond MeshGradient pastel (ce que le glass réfracte)

    private var meshBackground: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(0.5, 0.5), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
            ],
            colors: [
                pastel(0.80, 0.88, 1.00), pastel(0.85, 0.95, 1.00), pastel(0.90, 0.86, 1.00),
                pastel(0.84, 0.98, 0.92), pastel(0.97, 0.97, 1.00), pastel(1.00, 0.90, 0.85),
                pastel(0.88, 0.93, 1.00), pastel(0.92, 0.98, 0.95), pastel(0.95, 0.88, 1.00)
            ]
        )
    }
    private func pastel(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b)
    }

    // MARK: Layout 3x5 plein écran + profondeur radiale

    private struct Slot: Identifiable {
        let id: Int
        let cat: AppCategory
        let pos: CGPoint
        let baseScale: CGFloat
        let delay: Double
        let isCenter: Bool
    }

    private func layout(in size: CGSize, safe: EdgeInsets, focal: CGFloat) -> [Slot] {
        let stepX = Honey.D + Honey.G
        // zone réellement utilisable : on respecte la safe area (qui inclut la barre flottante)
        let topY = safe.top + Honey.TOP_PAD + Honey.D / 2
        let bottomY = size.height - safe.bottom - Honey.BOTTOM_PAD - Honey.D / 2
        let stepY = (bottomY - topY) / CGFloat(Honey.ROWS - 1)
        let cx = size.width / 2
        let screenCenter = CGPoint(x: cx, y: (topY + bottomY) / 2)

        var positions: [CGPoint] = []
        for row in 0..<Honey.ROWS {
            for col in 0..<Honey.COLS {
                let x = cx + (CGFloat(col) - 1) * stepX + (row % 2 == 1 ? stepX / 2 : 0) - stepX / 4
                let y = topY + CGFloat(row) * stepY
                positions.append(CGPoint(x: x, y: y))
            }
        }
        let dists = positions.map { hypot($0.x - screenCenter.x, $0.y - screenCenter.y) }
        // les catégories prioritaires vont aux emplacements les plus centraux
        let byDist = (0..<positions.count).sorted { dists[$0] < dists[$1] }
        var catFor = [AppCategory?](repeating: nil, count: positions.count)
        for (k, idx) in byDist.enumerated() where k < Self.order.count { catFor[idx] = Self.order[k] }
        let centerIdx = byDist.first ?? 0
        let maxDist = max(dists.max() ?? 1, 1)

        return (0..<positions.count).compactMap { i in
            guard let cat = catFor[i] else { return nil }
            let t = Double(min(dists[i] / focal, 1))
            let scale = Honey.MIN_SCALE + (Honey.MAX_SCALE - Honey.MIN_SCALE) * (cos(t * .pi) * 0.5 + 0.5)
            return Slot(id: i, cat: cat, pos: positions[i], baseScale: CGFloat(scale),
                        delay: Double(dists[i] / maxDist) * 0.45, isCenter: i == centerIdx)
        }
    }

    // MARK: Couleurs système Apple

    private func color(_ c: AppCategory) -> Color {
        switch c {
        case .fitness: return .red
        case .looks: return .orange
        case .productivity: return .purple
        case .sleep: return .indigo
        case .nutrition: return .green
        case .finance: return .blue
        case .mobility: return .teal
        case .travel: return .cyan
        case .career: return .brown
        case .home: return .blue
        case .social: return .pink
        case .invest: return .mint
        case .learning: return .yellow
        case .mind: return .purple
        case .admin: return .gray
        }
    }

    private func shortName(_ c: AppCategory) -> String {
        switch c {
        case .sleep: return "Sommeil"; case .nutrition: return "Nutrition"; case .fitness: return "Sport"
        case .looks: return "Looks"; case .mind: return "Mental"; case .productivity: return "Focus"
        case .finance: return "Argent"; case .invest: return "Invest"; case .career: return "Carrière"
        case .learning: return "Skills"; case .home: return "Maison"; case .mobility: return "Mobilité"
        case .social: return "Social"; case .admin: return "Admin"; case .travel: return "Voyage"
        }
    }
}

// MARK: - Bulle Liquid Glass (indépendante, ronde, glossy)

private struct GlassBubble: View {
    let cat: AppCategory
    let color: Color
    let label: String
    let baseScale: CGFloat
    let delay: Double
    let isCenter: Bool
    let onTap: () -> Void

    @State private var appeared = false
    @State private var breathe = false
    @State private var pop = false
    @State private var bump = 0

    private var D: CGFloat { Honey.D }

    var body: some View {
        ZStack {
            // 1) Vrai glass iOS 26 qui réfracte le fond
            VStack(spacing: 3) {
                Image(systemName: cat.icon)
                    .font(.system(size: D * 0.42, weight: .semibold))
                    .symbolEffect(.bounce, value: bump)
                if isCenter {
                    Text(label).font(.system(size: D * 0.15, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: D, height: D)
            .glassEffect(.regular.tint(color).interactive(), in: .circle)

            // 2) Gloss vertical (haut plus clair)
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.30), .clear],
                                     startPoint: .top, endPoint: .center))
                .frame(width: D, height: D)
                .allowsHitTesting(false)

            // 3) Liseré spéculaire en haut
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                .frame(width: D, height: D)
                .allowsHitTesting(false)
        }
        .frame(width: D, height: D)
        .shadow(color: color.opacity(0.35), radius: 12, y: 7)   // décollement du fond
        .scaleEffect(currentScale)
        .opacity(appeared ? 1 : 0)
        .contentShape(Circle())
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(delay)) { appeared = true }
            if isCenter {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathe = true }
            }
        }
        .onTapGesture {
            Haptics.soft(); bump += 1
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pop = true }
            Task {
                try? await Task.sleep(for: .milliseconds(170))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
            }
            onTap()
        }
    }

    private var currentScale: CGFloat {
        guard appeared else { return 0.01 }
        let breatheF: CGFloat = (isCenter && breathe) ? 1.03 : 1.0
        let popF: CGFloat = pop ? 1.12 : 1.0
        return baseScale * breatheF * popF
    }
}
