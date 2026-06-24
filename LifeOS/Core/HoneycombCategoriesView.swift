import SwiftUI

// MARK: - Constantes (à régler pour le feeling)

private enum Honey {
    static let D: CGFloat = 96          // diamètre de base d'une bulle
    static let G: CGFloat = 16          // espace entre bulles
    static let MAX_SCALE: CGFloat = 1.18
    static let MIN_SCALE: CGFloat = 0.42
    static let FOCAL_RATIO: CGFloat = 0.52   // FOCAL_RADIUS = largeur écran * ce ratio
    static let MAX_OPACITY_DROP: CGFloat = 0.35
    static let LABEL_FROM: CGFloat = 0.85    // le label apparaît au-dessus de cette échelle
    static let USAGE_BOOST: CGFloat = 0.22   // grossissement max lié à l'usage
}

/// Grille « ruche » façon Apple Watch, en SwiftUI natif.
/// Effet signature : chaque bulle grossit selon sa proximité du centre de l'écran.
struct HoneycombCategoriesView: View {
    @AppStorage("catOrder") private var orderRaw = ""
    @AppStorage("catUsage") private var usageRaw = ""

    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var dragging: AppCategory?
    @State private var dragOffset: CGSize = .zero
    @State private var path: [AppCategory] = []

    private var hexSize: CGFloat { (Honey.D + Honey.G) / CGFloat(3).squareRoot() }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let focal = geo.size.width * Honey.FOCAL_RATIO
                ZStack {
                    Theme.bg.ignoresSafeArea()
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                    ForEach(orderedCats, id: \.self) { cat in
                        bubble(cat, screenCenter: c, focal: focal)
                    }
                }
                .clipped()
            }
            .navigationDestination(for: AppCategory.self) { $0.destination }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Bulle

    private func bubble(_ cat: AppCategory, screenCenter c: CGPoint, focal: CGFloat) -> some View {
        let slot = slotPos(cat)
        let isDragging = dragging == cat
        let off = isDragging ? dragOffset : .zero
        // position relative au centre de l'écran
        let dx = slot.x + pan.width + off.width
        let dy = slot.y + pan.height + off.height
        let dist = (slot.x.isFinite ? hypot(dx, dy) : 0)
        let t = min(dist / focal, 1)
        let fisheye = Honey.MIN_SCALE + (Honey.MAX_SCALE - Honey.MIN_SCALE) * (cos(t * .pi) * 0.5 + 0.5)
        let scale = (isDragging ? Honey.MAX_SCALE * 1.05 : fisheye) * usageScale(cat)
        let opacity = isDragging ? 1 : 1 - Honey.MAX_OPACITY_DROP * t
        let labelOpacity = max(0, min(1, (fisheye - Honey.LABEL_FROM) / (Honey.MAX_SCALE - Honey.LABEL_FROM)))

        return VStack(spacing: 3) {
            Image(systemName: cat.icon)
                .font(.system(size: Honey.D * 0.34, weight: .semibold))
            Text(shortName(cat))
                .font(.system(size: Honey.D * 0.15, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.6)
                .opacity(Double(labelOpacity))
        }
        .foregroundStyle(.white)
        .frame(width: Honey.D, height: Honey.D)
        .background(vivid(cat).gradient, in: Circle())
        .shadow(color: vivid(cat).opacity(0.45), radius: isDragging ? 18 : 10, y: 6)
        .scaleEffect(scale)
        .opacity(opacity)
        .position(x: c.x + dx, y: c.y + dy)
        .zIndex(isDragging ? 100 : Double(scale))
        .onTapGesture {
            guard dragging == nil else { return }
            bumpUsage(cat); path.append(cat)
        }
        .gesture(reorderGesture(cat))
        .animation(.spring(duration: 0.35), value: orderRaw)
    }

    // MARK: Gestes

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                pan = CGSize(width: lastPan.width + v.translation.width,
                             height: lastPan.height + v.translation.height)
            }
            .onEnded { _ in
                let clamped = clampPan(pan)
                lastPan = clamped
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { pan = clamped }
            }
    }

    private func reorderGesture(_ cat: AppCategory) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture())
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    if dragging == nil { dragging = cat; Haptics.tap() }
                    dragOffset = drag.translation
                }
            }
            .onEnded { value in
                if case .second(_, let drag?) = value { drop(cat, translation: drag.translation) }
                withAnimation(.spring) { dragging = nil; dragOffset = .zero }
            }
    }

    private func drop(_ cat: AppCategory, translation: CGSize) {
        var order = orderedCats
        guard let from = order.firstIndex(of: cat) else { return }
        let dropped = CGPoint(x: slotPos(cat).x + translation.width, y: slotPos(cat).y + translation.height)
        let target = (0..<order.count).min { a, b in
            dist(pixel(cells[a]), dropped) < dist(pixel(cells[b]), dropped)
        } ?? from
        let item = order.remove(at: from)
        order.insert(item, at: min(target, order.count))
        orderRaw = order.map { $0.rawValue }.joined(separator: ",")
        Haptics.success()
    }

    // MARK: Couleurs Apple vives

    private func vivid(_ c: AppCategory) -> Color {
        switch c {
        case .sleep: return Color(uiColor: .systemIndigo)
        case .nutrition: return Color(uiColor: .systemGreen)
        case .fitness: return Color(uiColor: .systemRed)
        case .looks: return Color(uiColor: .systemOrange)
        case .mind: return Color(uiColor: .systemPurple)
        case .productivity: return Color(uiColor: .systemBlue)
        case .finance: return Color(uiColor: .systemTeal)
        case .invest: return Color(uiColor: .systemMint)
        case .career: return Color(uiColor: .systemBrown)
        case .learning: return Color(uiColor: .systemYellow)
        case .home: return Color(uiColor: .systemCyan)
        case .mobility: return Color(uiColor: .systemTeal)
        case .social: return Color(uiColor: .systemPink)
        case .admin: return Color(uiColor: .systemGray)
        case .travel: return Color(uiColor: .systemBlue)
        }
    }

    // MARK: Ordre & usage

    private static let defaultOrder: [AppCategory] = [
        .fitness, .nutrition, .looks, .productivity, .mind, .finance, .sleep,
        .learning, .invest, .career, .home, .social, .mobility, .admin, .travel
    ]
    private var orderedCats: [AppCategory] {
        let saved = orderRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
        if saved.isEmpty { return Self.defaultOrder }
        return saved + AppCategory.allCases.filter { !saved.contains($0) }
    }
    private func slotPos(_ cat: AppCategory) -> CGPoint {
        guard let i = orderedCats.firstIndex(of: cat), i < cells.count else { return .zero }
        return pixel(cells[i])
    }
    private func usage(_ cat: AppCategory) -> Int {
        for pair in usageRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, kv[0] == Substring(cat.rawValue), let v = Int(kv[1]) { return v }
        }
        return 0
    }
    private func usageScale(_ cat: AppCategory) -> CGFloat {
        1 + min(CGFloat(usage(cat)), 15) / 15 * Honey.USAGE_BOOST
    }
    private func bumpUsage(_ cat: AppCategory) {
        var m: [String: Int] = [:]
        for pair in usageRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, let v = Int(kv[1]) { m[String(kv[0])] = v }
        }
        m[cat.rawValue, default: 0] += 1
        usageRaw = m.map { "\($0):\($1)" }.joined(separator: ",")
    }

    // MARK: Géométrie hexagonale (cluster circulaire, façon Apple Watch)

    private var cells: [(q: Int, r: Int)] {
        var result: [(Int, Int)] = [(0, 0)]
        let dirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
        var ring = 1
        while result.count < AppCategory.allCases.count {
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
        let x = hexSize * (s3 * CGFloat(cell.q) + s3 / 2 * CGFloat(cell.r))
        let y = hexSize * (1.5 * CGFloat(cell.r))
        return CGPoint(x: x, y: y)
    }
    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func clampPan(_ p: CGSize) -> CGSize {
        let xs = cells.prefix(orderedCats.count).map { abs(pixel($0).x) }
        let ys = cells.prefix(orderedCats.count).map { abs(pixel($0).y) }
        let maxX = (xs.max() ?? 0) + 40
        let maxY = (ys.max() ?? 0) + 40
        return CGSize(width: min(maxX, max(-maxX, p.width)),
                      height: min(maxY, max(-maxY, p.height)))
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
