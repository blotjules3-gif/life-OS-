import SwiftUI

/// Accueil en nuage de bulles : chaque pôle est une bulle dont la taille = son importance.
/// Tap = ouvrir le pôle · appui long = ajuster l'importance.
struct BubbleHomeView: View {
    @AppStorage("bubbleImportance") private var impRaw = ""

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let bubbles = layout()
                let box = boundingBox(bubbles)
                let avail = CGSize(width: geo.size.width - 24, height: geo.size.height - 24)
                let scale = min(1, min(box.width == 0 ? 1 : avail.width / box.width,
                                       box.height == 0 ? 1 : avail.height / box.height))
                ZStack {
                    ForEach(bubbles) { b in
                        bubbleView(b)
                            .position(x: geo.size.width / 2 + (b.center.x - box.midX),
                                      y: geo.size.height / 2 + (b.center.y - box.midY))
                    }
                }
                .scaleEffect(scale)
            }
            .navigationTitle("Mes pôles")
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("Appuie sur une bulle · reste appuyé pour ajuster l'importance")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
                    .background(Theme.bg)
            }
            .background(Theme.bg)
        }
    }

    // MARK: Bulle

    private func bubbleView(_ b: Bubble) -> some View {
        NavigationLink {
            b.cat.destination
        } label: {
            ZStack {
                Circle()
                    .fill(b.cat.tint.gradient)
                    .shadow(color: b.cat.tint.opacity(0.45), radius: 10, y: 5)
                VStack(spacing: b.radius > 56 ? 5 : 2) {
                    Image(systemName: b.cat.icon)
                        .font(.system(size: b.radius * 0.42, weight: .semibold))
                    if b.radius > 48 {
                        Text(shortName(b.cat))
                            .font(.system(size: max(10, b.radius * 0.20), weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.horizontal, 4)
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(width: b.radius * 2, height: b.radius * 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Section("Importance de \(shortName(b.cat))") {
                Button { setImportance(b.cat, 3) } label: { Label("Grande", systemImage: "circle.fill") }
                Button { setImportance(b.cat, 2) } label: { Label("Moyenne", systemImage: "circle") }
                Button { setImportance(b.cat, 1) } label: { Label("Petite", systemImage: "smallcircle.filled.circle") }
            }
        }
    }

    private func shortName(_ c: AppCategory) -> String {
        switch c {
        case .sleep: return "Sommeil"
        case .nutrition: return "Nutrition"
        case .fitness: return "Sport"
        case .looks: return "Looks"
        case .mind: return "Mental"
        case .productivity: return "Focus"
        case .finance: return "Argent"
        case .invest: return "Invest"
        case .career: return "Carrière"
        case .learning: return "Skills"
        case .home: return "Maison"
        case .mobility: return "Mobilité"
        case .social: return "Social"
        case .admin: return "Admin"
        case .travel: return "Voyage"
        case .cycle: return "Cycle"
        case .medical: return "Médical"
        }
    }

    // MARK: Importance

    private static let defaults: [AppCategory: Int] = [
        .fitness: 3, .nutrition: 3, .looks: 3,
        .productivity: 2, .mind: 2, .finance: 2, .sleep: 2, .learning: 2,
        .invest: 1, .career: 1, .home: 1, .social: 1, .mobility: 1, .admin: 1, .travel: 1
    ]
    private func importance(_ c: AppCategory) -> Int {
        parse()[c.rawValue] ?? Self.defaults[c] ?? 1
    }
    private func setImportance(_ c: AppCategory, _ v: Int) {
        var m = parse(); m[c.rawValue] = v
        impRaw = m.map { "\($0):\($1)" }.joined(separator: ",")
        Haptics.tap()
    }
    private func parse() -> [String: Int] {
        var m: [String: Int] = [:]
        for pair in impRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, let v = Int(kv[1]) { m[String(kv[0])] = v }
        }
        return m
    }
    private func radius(_ c: AppCategory) -> CGFloat { 36 + CGFloat(importance(c)) * 13 }

    // MARK: Packing

    private struct Bubble: Identifiable {
        let cat: AppCategory
        let radius: CGFloat
        var center: CGPoint
        var id: String { cat.rawValue }
    }

    /// Empilement glouton en spirale : les grosses bulles au centre, le reste autour.
    private func layout() -> [Bubble] {
        let sorted = AppCategory.allCases
            .map { (cat: $0, r: radius($0)) }
            .sorted { $0.r > $1.r }
        var placed: [(CGPoint, CGFloat)] = []
        let pad: CGFloat = 5
        var result: [Bubble] = []
        for item in sorted {
            let r = item.r
            var pos = CGPoint.zero
            if !placed.isEmpty {
                var found: CGPoint? = nil
                var ring: CGFloat = 0
                while found == nil && ring < 4000 {
                    ring += 10
                    let steps = max(10, Int(ring / 6))
                    for i in 0..<steps {
                        let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
                        let p = CGPoint(x: cos(a) * ring, y: sin(a) * ring)
                        let ok = !placed.contains { hypot($0.0.x - p.x, $0.0.y - p.y) < $0.1 + r + pad }
                        if ok { found = p; break }
                    }
                }
                pos = found ?? .zero
            }
            placed.append((pos, r))
            result.append(Bubble(cat: item.cat, radius: r, center: pos))
        }
        return result
    }

    private func boundingBox(_ bubbles: [Bubble]) -> CGRect {
        guard !bubbles.isEmpty else { return .zero }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for b in bubbles {
            minX = min(minX, b.center.x - b.radius); maxX = max(maxX, b.center.x + b.radius)
            minY = min(minY, b.center.y - b.radius); maxY = max(maxY, b.center.y + b.radius)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
