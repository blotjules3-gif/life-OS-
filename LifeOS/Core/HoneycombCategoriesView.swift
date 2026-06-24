import SwiftUI

// MARK: - Constantes (à régler)

private enum Honey {
    static let D: CGFloat = 88            // diamètre de base d'une bulle
    static let G: CGFloat = 16            // espacement
    static let MAX_SCALE: Double = 1.25
    static let MIN_SCALE: Double = 0.60   // les bords restent lisibles
    static let FOCAL_RATIO: CGFloat = 0.60
    static let OPACITY_DROP: Double = 0.25
    static let COLS = 4
    static let ROWS = 4                    // pair : les coutures hex s'alignent
}

/// Grille « ruche » façon Apple Watch, à **défilement infini** (tiling toroïdal).
/// Le champ d'icônes se répète dans toutes les directions : jamais de vide.
struct HoneycombCategoriesView: View {
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var path: [AppCategory] = []

    private var stepX: CGFloat { Honey.D + Honey.G }
    private var stepY: CGFloat { (Honey.D + Honey.G) * 0.8660254 }
    private var tileW: CGFloat { CGFloat(Honey.COLS) * stepX }
    private var tileH: CGFloat { CGFloat(Honey.ROWS) * stepY }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let focal = geo.size.width * Honey.FOCAL_RATIO
                ZStack {
                    Theme.bg.ignoresSafeArea()
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                    ForEach(instances(in: geo.size, center: center)) { inst in
                        lensedBubble(inst, center: center, focal: focal)
                    }
                }
                .clipped()
            }
            .navigationDestination(for: AppCategory.self) { $0.destination }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Bulle + lentille

    private func lensedBubble(_ inst: BubbleInstance, center: CGPoint, focal: CGFloat) -> some View {
        let dx = inst.x - center.x
        let dy = inst.y - center.y
        let t = Double(min(hypot(dx, dy) / focal, 1))
        let scale = Honey.MIN_SCALE + (Honey.MAX_SCALE - Honey.MIN_SCALE) * (cos(t * .pi) * 0.5 + 0.5)
        let opacity = 1 - Honey.OPACITY_DROP * t
        let labelOpacity = max(0, min(1, (scale - (Honey.MAX_SCALE - 0.12)) / 0.12))

        return glassBubble(inst.cat, labelOpacity: labelOpacity)
            .scaleEffect(CGFloat(scale))
            .opacity(opacity)
            .position(x: inst.x, y: inst.y)
            .zIndex(scale)
            .onTapGesture { path.append(inst.cat) }
    }

    /// Look liquid-glass, parfaitement rond.
    private func glassBubble(_ cat: AppCategory, labelOpacity: Double) -> some View {
        ZStack {
            Circle().fill(color(cat))
            Circle().fill(
                LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom)
            )
            Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1)
            VStack(spacing: 2) {
                Image(systemName: cat.icon).font(.system(size: Honey.D * 0.34, weight: .semibold))
                Text(shortName(cat)).font(.system(size: Honey.D * 0.15, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.6).opacity(labelOpacity)
            }
            .foregroundStyle(.white)
        }
        .frame(width: Honey.D, height: Honey.D)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
    }

    // MARK: Pan (infini + fling)

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                pan = CGSize(width: lastPan.width + v.translation.width,
                             height: lastPan.height + v.translation.height)
            }
            .onEnded { v in
                let flingX = (v.predictedEndTranslation.width - v.translation.width) * 0.28
                let flingY = (v.predictedEndTranslation.height - v.translation.height) * 0.28
                let target = CGSize(width: pan.width + flingX, height: pan.height + flingY)
                lastPan = target
                withAnimation(.easeOut(duration: 0.45)) { pan = target }
            }
    }

    // MARK: Tiling toroïdal + culling

    private struct BubbleInstance: Identifiable {
        let id: String
        let cat: AppCategory
        let x: CGFloat
        let y: CGFloat
    }

    /// Une tuile honeycomb de toutes les catégories (16 mailles, la dernière reboucle).
    private var tile: [(cat: AppCategory, bx: CGFloat, by: CGFloat)] {
        let cats = Self.order
        var out: [(AppCategory, CGFloat, CGFloat)] = []
        for row in 0..<Honey.ROWS {
            for col in 0..<Honey.COLS {
                let idx = row * Honey.COLS + col
                let cat = cats[idx % cats.count]
                let x = CGFloat(col) * stepX + (row % 2 == 1 ? stepX / 2 : 0) - tileW / 2
                let y = CGFloat(row) * stepY - tileH / 2
                out.append((cat, x, y))
            }
        }
        return out
    }

    /// Toutes les copies visibles à l'écran (le reste est cullé).
    private func instances(in size: CGSize, center: CGPoint) -> [BubbleInstance] {
        let px = pan.width - (pan.width / tileW).rounded() * tileW
        let py = pan.height - (pan.height / tileH).rounded() * tileH
        let margin = Honey.D
        var out: [BubbleInstance] = []
        let slots = tile
        for m in -2...2 {
            for n in -2...2 {
                for (i, slot) in slots.enumerated() {
                    let x = center.x + slot.bx + px + CGFloat(m) * tileW
                    let y = center.y + slot.by + py + CGFloat(n) * tileH
                    if x > -margin && x < size.width + margin && y > -margin && y < size.height + margin {
                        out.append(BubbleInstance(id: "\(i)_\(m)_\(n)", cat: slot.cat, x: x, y: y))
                    }
                }
            }
        }
        return out
    }

    // MARK: Couleurs système Apple

    private func color(_ c: AppCategory) -> Color {
        switch c {
        case .fitness: return .red
        case .looks: return .orange
        case .learning: return .yellow
        case .nutrition: return .green
        case .invest: return .mint
        case .finance: return .teal
        case .home: return .cyan
        case .productivity: return .blue
        case .sleep: return .indigo
        case .mind: return .purple
        case .social: return .pink
        case .career: return .brown
        case .mobility: return Color(uiColor: .systemTeal)
        case .admin: return .gray
        case .travel: return Color(uiColor: .systemBlue)
        }
    }

    private static let order: [AppCategory] = [
        .fitness, .nutrition, .looks, .productivity, .mind, .finance, .sleep,
        .learning, .invest, .career, .home, .social, .mobility, .admin, .travel
    ]

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
