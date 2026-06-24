import SwiftUI

/// Grille « ruche » façon Apple Watch : nid d'abeille hexagonal pannable dans tous les sens,
/// effet fisheye (centre gros / bords petits), taille auto selon l'usage, tri par appui long + glisser.
struct HoneycombCategoriesView: View {
    @AppStorage("catOrder") private var orderRaw = ""
    @AppStorage("catUsage") private var usageRaw = ""

    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var dragging: AppCategory?
    @State private var dragOffset: CGSize = .zero
    @State private var path: [AppCategory] = []

    private let hexSize: CGFloat = 47       // circumrayon de la maille
    private let baseRadius: CGFloat = 33

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Theme.bg.ignoresSafeArea()
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                    ForEach(orderedCats, id: \.self) { cat in
                        bubble(cat, center: center)
                    }
                }
                .clipped()
            }
            .navigationDestination(for: AppCategory.self) { $0.destination }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Bulle

    private func bubble(_ cat: AppCategory, center: CGPoint) -> some View {
        let slot = slotPos(cat)
        let isDragging = dragging == cat
        let offset = isDragging ? dragOffset : .zero
        let screen = CGPoint(x: center.x + pan.width + slot.x + offset.width,
                             y: center.y + pan.height + slot.y + offset.height)
        let dist = hypot(screen.x - center.x, screen.y - center.y)
        let fisheye = max(0.42, 1 - dist / 320)
        let diameter = baseRadius * 2 * usageScale(cat) * (isDragging ? 1.25 : fisheye)

        return ZStack {
            Circle().fill(cat.tint.gradient)
                .shadow(color: cat.tint.opacity(isDragging ? 0.6 : 0.4), radius: isDragging ? 16 : 9, y: 5)
            VStack(spacing: diameter > 64 ? 4 : 1) {
                Image(systemName: cat.icon).font(.system(size: diameter * 0.34, weight: .semibold))
                if diameter > 60 {
                    Text(shortName(cat)).font(.system(size: max(9, diameter * 0.15), weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .position(screen)
        .zIndex(isDragging ? 10 : 1)
        .onTapGesture {
            guard dragging == nil else { return }
            bumpUsage(cat); path.append(cat)
        }
        .gesture(reorderGesture(cat))
        .animation(.easeOut(duration: 0.18), value: pan)
        .animation(.spring(duration: 0.3), value: orderRaw)
    }

    // MARK: Gestes

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in pan = CGSize(width: lastPan.width + v.translation.width, height: lastPan.height + v.translation.height) }
            .onEnded { _ in lastPan = clampPan(pan); pan = lastPan }
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
                dragging = nil; dragOffset = .zero
            }
    }

    private func drop(_ cat: AppCategory, translation: CGSize) {
        var order = orderedCats
        guard let from = order.firstIndex(of: cat) else { return }
        let dropped = CGPoint(x: slotPos(cat).x + translation.width, y: slotPos(cat).y + translation.height)
        // slot cible = maille la plus proche du point lâché
        let target = (0..<order.count).min { a, b in
            dist(pixel(cells[a]), dropped) < dist(pixel(cells[b]), dropped)
        } ?? from
        let item = order.remove(at: from)
        order.insert(item, at: min(target, order.count))
        orderRaw = order.map { $0.rawValue }.joined(separator: ",")
        Haptics.success()
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
        1 + min(CGFloat(usage(cat)), 15) / 15 * 0.55
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

    // MARK: Géométrie hexagonale

    /// Mailles en spirale depuis le centre (axial coords).
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
        let maxX = hexSize * 4, maxY = hexSize * 5
        return CGSize(width: min(maxX, max(-maxX, p.width)), height: min(maxY, max(-maxY, p.height)))
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
