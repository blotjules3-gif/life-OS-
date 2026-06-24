import SwiftUI

// MARK: - Constantes (à régler)

private enum Honey {
    static let D: CGFloat = 92
    static let G: CGFloat = 18
    static let MAX_SCALE: Double = 1.15
    static let MIN_SCALE: Double = 0.80
    static let FOCAL_RATIO: CGFloat = 0.62
}

/// Ruche **fixe et centrée** (aucun scroll), en vrai **Liquid Glass iOS 26**.
/// Chaque bulle est une icône d'app Apple : glass teinté d'une couleur système, ronde.
struct HoneycombCategoriesView: View {
    @State private var path: [AppCategory] = []

    private var hexSize: CGFloat { (Honey.D + Honey.G) / CGFloat(3).squareRoot() }

    private static let order: [AppCategory] = [
        .fitness, .nutrition, .looks, .productivity, .mind, .finance, .sleep,
        .learning, .invest, .career, .home, .social, .mobility, .admin, .travel
    ]

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let focal = geo.size.width * Honey.FOCAL_RATIO
                let items = layout(focal: focal)
                ZStack {
                    Theme.bg.ignoresSafeArea()
                    GlassEffectContainer(spacing: 20) {
                        ZStack {
                            ForEach(items) { item in
                                GlassBubble(
                                    cat: item.cat,
                                    color: color(item.cat),
                                    label: shortName(item.cat),
                                    baseScale: item.baseScale,
                                    delay: item.delay,
                                    isCenter: item.isCenter
                                ) {
                                    path.append(item.cat)
                                }
                                .position(x: center.x + item.pos.x, y: center.y + item.pos.y)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: AppCategory.self) { $0.destination }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Layout fixe (honeycomb centré, échelle radiale statique)

    private struct Item: Identifiable {
        let id: String
        let cat: AppCategory
        let pos: CGPoint
        let baseScale: CGFloat
        let delay: Double
        let isCenter: Bool
    }

    private func layout(focal: CGFloat) -> [Item] {
        let cellList = cells
        let positions = (0..<Self.order.count).map { pixel(cellList[$0]) }
        let dists = positions.map { hypot($0.x, $0.y) }
        let maxDist = max(dists.max() ?? 1, 1)
        return Self.order.enumerated().map { i, cat in
            let d = dists[i]
            let t = Double(min(d / focal, 1))
            let scale = Honey.MIN_SCALE + (Honey.MAX_SCALE - Honey.MIN_SCALE) * (cos(t * .pi) * 0.5 + 0.5)
            return Item(
                id: cat.rawValue,
                cat: cat,
                pos: positions[i],
                baseScale: CGFloat(scale),
                delay: Double(d / maxDist) * 0.4,    // bloom du centre vers l'extérieur
                isCenter: i == 0
            )
        }
    }

    // MARK: Couleurs système Apple (icônes = vibe app iOS)

    private func color(_ c: AppCategory) -> Color {
        switch c {
        case .fitness: return .red          // Music
        case .looks: return .orange
        case .productivity: return .purple  // Podcasts
        case .sleep: return .indigo
        case .nutrition: return .green      // Phone / Messages
        case .finance: return .blue         // App Store
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

    // MARK: Géométrie hexagonale (cluster centré)

    private var cells: [(q: Int, r: Int)] {
        var result: [(Int, Int)] = [(0, 0)]
        let dirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
        var ring = 1
        while result.count < Self.order.count {
            var hex = (dirs[4].0 * ring, dirs[4].1 * ring)
            for side in 0..<6 {
                for _ in 0..<ring {
                    result.append(hex)
                    hex = (hex.0 + dirs[side].0, hex.1 + dirs[side].1)
                }
            }
            ring += 1
        }
        return result
    }
    private func pixel(_ cell: (q: Int, r: Int)) -> CGPoint {
        let s3 = CGFloat(3).squareRoot()
        return CGPoint(x: hexSize * (s3 * CGFloat(cell.q) + s3 / 2 * CGFloat(cell.r)),
                       y: hexSize * (1.5 * CGFloat(cell.r)))
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

// MARK: - Bulle Liquid Glass animée

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

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: cat.icon)
                .font(.system(size: Honey.D * 0.4, weight: .semibold))
                .symbolEffect(.bounce, value: bump)
            if isCenter {
                Text(label).font(.system(size: Honey.D * 0.15, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: Honey.D, height: Honey.D)
        .glassEffect(.regular.tint(color).interactive(), in: .circle)
        .scaleEffect(currentScale)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(delay)) { appeared = true }
            if isCenter {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathe = true }
            }
        }
        .onTapGesture {
            Haptics.soft()
            bump += 1
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
