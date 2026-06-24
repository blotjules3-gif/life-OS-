import SwiftUI

// =====================================================================
// MARK: - CONSTANTS  (tune everything here)
// =====================================================================

private enum BC {
    static let baseFrac: CGFloat = 0.32     // + dense : bulles plus grosses qui se chevauchent

    // --- transparency (luminous jewel-tone glass, NOT washed-out ghosts) ---
    static let coreOpacity: Double = 0.10    // centre : fenêtre claire (le fond traverse)
    static let rimOpacity:  Double = 0.85    // bord : couleur riche et lumineuse
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
    @AppStorage("hiddenCats") private var hiddenRaw = ""   // catégories retirées (vide = tout affiché)
    @State private var editing = false
    @State private var showAdd = false

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }
    private var hiddenCats: [AppCategory] { Layout.allCats.filter { hidden.contains($0.rawValue) } }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in cluster(in: geo.size) }
                .overlay(alignment: .topTrailing) { editButton }
                .overlay(alignment: .bottomTrailing) { if editing { addButton } }
                .background(BubbleMesh().ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AppCategory.self) { $0.destination }
                .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    @ViewBuilder private func cluster(in size: CGSize) -> some View {
        let bubbles = Layout.build(in: size, weights: parseWeights(), hidden: hidden)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxD = bubbles.map { hypot($0.anchor.x - c.x, $0.anchor.y - c.y) }.max() ?? 1

        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                BubbleMesh().ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { exitEdit() }
                    .gesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in enterEdit() })
                ForEach(bubbles) { b in     // sorted small→big ⇒ big drawn on top
                    bubbleView(b, t: t, c: c, maxD: maxD)
                }
            }
        }
    }

    private func bubbleView(_ b: Layout.Spec, t: Double, c: CGPoint, maxD: CGFloat) -> some View {
        let delay = Double(hypot(b.anchor.x - c.x, b.anchor.y - c.y) / max(1, maxD)) * 0.45
        return FixedBubble(
            spec: b, time: t, bloomDelay: delay,
            onTap: b.cat == nil ? nil : {
                if editing { return }
                bump(b.cat!); path.append(b.cat!)
            },
            editing: editing,
            onRemove: b.cat == nil ? nil : { remove(b.cat!) })
    }

    private func enterEdit() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { editing = true }
        Haptics.tap()
    }
    private func exitEdit() {
        if editing { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { editing = false } }
    }

    private var editButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { editing.toggle() }
        } label: {
            Text(editing ? "OK" : "Modifier")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
        .padding(.top, 8).padding(.trailing, 16)
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .padding(.trailing, 22).padding(.bottom, 110)
        .transition(.scale.combined(with: .opacity))
    }

    private var addSheet: some View {
        NavigationStack {
            List {
                if hiddenCats.isEmpty {
                    Text("Toutes les catégories sont déjà affichées.").foregroundStyle(.secondary)
                }
                ForEach(hiddenCats, id: \.self) { cat in
                    Button { add(cat) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: cat.icon).foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Layout.color(cat), in: RoundedRectangle(cornerRadius: 8))
                            Text(Layout.label(cat)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("Ajouter une catégorie").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showAdd = false } } }
        }
    }

    private func remove(_ cat: AppCategory) {
        var h = hidden; h.insert(cat.rawValue)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { hiddenRaw = h.sorted().joined(separator: ",") }
        Haptics.tap()
    }
    private func add(_ cat: AppCategory) {
        var h = hidden; h.remove(cat.rawValue)
        hiddenRaw = h.sorted().joined(separator: ",")
        if hiddenCats.isEmpty { showAdd = false }
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
    var editing: Bool = false
    var onRemove: (() -> Void)? = nil

    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var appeared = false
    @State private var bounce = 0

    var body: some View {
        let r = spec.diameter / 2

        // FIX 2 — gentle bob around the anchor (no velocity, no drift, always returns).
        let bob = BC.bobAmount * spec.bobFactor
        let bx = CGFloat(sin(time * 0.5  + spec.phase))       * bob
        let by = CGFloat(cos(time * 0.42 + spec.phase * 1.3)) * bob
        let dx = drag.width  + (dragging ? 0 : bx)
        let dy = drag.height + (dragging ? 0 : by)

        let wig: Double = (editing && spec.cat != nil) ? sin(time * 7 + spec.phase) * 2.0 : 0

        bubbleBody(r: r)
            .frame(width: spec.diameter, height: spec.diameter)
            .rotationEffect(.degrees(wig))                                       // wiggle façon écran d'accueil iOS
            .overlay(alignment: .topLeading) {
                if editing, let onRemove {
                    Button { onRemove() } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: max(20, r * 0.5)))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: r * 0.22, y: r * 0.22)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: spec.tint.opacity(0.55), radius: r * 0.28)            // halo coloré qui rayonne
            .shadow(color: .black.opacity(0.14), radius: r * 0.10, y: r * 0.10)  // ombre de contact
            .scaleEffect(appeared ? 1 : 0.01)
            .opacity(appeared ? 1 : 0)
            .position(x: spec.anchor.x + dx, y: spec.anchor.y + dy)
            .modifier(DragIfNeeded(enabled: onTap != nil && !editing, r: r,
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
            // A · VOLUME directionnel (haut-gauche CLAIR → bas-droite SOMBRE) = relief 3D
            Circle().fill(LinearGradient(
                stops: [
                    .init(color: t.mix(with: .white, by: 0.60).opacity(spec.rimOp),                  location: 0.00),
                    .init(color: t.mix(with: .white, by: 0.18).opacity(spec.rimOp),                  location: 0.26),
                    .init(color: t.opacity(spec.rimOp),                                              location: 0.52),
                    .init(color: t.mix(with: .black, by: 0.40).opacity(spec.rimOp),                  location: 0.78),
                    .init(color: t.mix(with: .black, by: 0.62).opacity(min(1, spec.rimOp + 0.10)),   location: 1.00)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))

            // B · CŒUR lumineux interne (la bulle brille de l'intérieur), un peu au-dessus du centre
            Circle().fill(RadialGradient(
                colors: [t.mix(with: .white, by: 0.55).opacity(spec.rimOp * 0.85), .clear],
                center: UnitPoint(x: 0.43, y: 0.36), startRadius: 0, endRadius: r * 0.72))

            // 3 · thin WHITE rim light (aucune couleur, AUCUN arc-en-ciel)
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: max(0.8, r * 0.04))

            // 4 · reflets BLANCS nets répartis autour de la sphère (verre mouillé)
            Ellipse().fill(.white.opacity(0.92))            // principal, haut-gauche
                .frame(width: r * 0.42, height: r * 0.28)
                .rotationEffect(.degrees(-32))
                .offset(x: -r * 0.30, y: -r * 0.40)
            Circle().fill(.white.opacity(0.85))             // haut-droite
                .frame(width: r * 0.12, height: r * 0.12)
                .offset(x: r * 0.30, y: -r * 0.26)
            Circle().fill(.white.opacity(0.7))              // bas-gauche
                .frame(width: r * 0.08, height: r * 0.08)
                .offset(x: -r * 0.40, y: r * 0.30)
            Circle().fill(.white.opacity(0.8))              // accroche bas-droite
                .frame(width: r * 0.07, height: r * 0.07)
                .offset(x: r * 0.34, y: r * 0.40)
            Circle().fill(.white.opacity(0.9))              // minuscule près du principal
                .frame(width: r * 0.05, height: r * 0.05)
                .offset(x: -r * 0.14, y: -r * 0.52)

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
        (.admin,        0.22, 0.14, 1.00),   // Documents (très transparent, incolore)
        (.career,       0.50, 0.15, 0.95),   // Travail
        (.social,       0.80, 0.19, 1.15),   // Social
        (.finance,      0.16, 0.33, 0.85),   // Finance
        (.mind,         0.46, 0.34, 1.10),   // Mental
        (.looks,        0.77, 0.38, 1.10),   // Bien-être
        (.invest,       0.13, 0.48, 0.75),   // Bourse (écartée de Sport/Finance)
        (.learning,     0.90, 0.52, 0.78),   // Éducation
        (.fitness,      0.36, 0.57, 1.34),   // Sport — HERO (un poil plus petit)
        (.nutrition,    0.64, 0.58, 1.05),   // Alimentation
        (.sleep,        0.87, 0.66, 0.92),   // Sommeil
        (.productivity, 0.17, 0.71, 0.85),   // Tâches
        (.travel,       0.42, 0.82, 1.10),   // Voyage
        (.home,         0.66, 0.80, 0.85),   // Maison
        (.mobility,     0.84, 0.85, 0.90)    // Transports
    ]

    /// 6–8 sparse fillers in the gaps (x, y, sizeFractionOfBase).
    private static let fillers: [(CGFloat, CGFloat, CGFloat)] = [
        (0.55, 0.32, 0.22), (0.30, 0.50, 0.18), (0.70, 0.58, 0.27),
        (0.50, 0.74, 0.20), (0.88, 0.78, 0.16), (0.27, 0.68, 0.24),
        (0.62, 0.54, 0.15)
    ]

    static let allCats: [AppCategory] = template.map { $0.0 }

    static func build(in size: CGSize, weights: [String: Int], hidden: Set<String> = []) -> [Spec] {
        guard size.width > 0 else { return [] }
        let base = size.width * BC.baseFrac
        let fillerPalette: [Color] = [.cyan, .mint, .pink, .purple, .blue, .teal, .indigo]

        // positions + diamètres des bulles principales (catégories non masquées)
        let active = template.filter { !hidden.contains($0.0.rawValue) }
        let mains: [(cat: AppCategory, center: CGPoint, dia: CGFloat, mult: CGFloat)] = active.map { (cat, fx, fy, mult) in
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
                tint: color(m.cat), icon: m.cat.icon, label: label(m.cat),
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

    static func color(_ c: AppCategory) -> Color {
        c == .admin ? Color(white: 0.78) : c.tint   // Documents = nearly colourless
    }

    static func label(_ c: AppCategory) -> String {
        switch c {
        case .sleep: return "Sommeil";   case .nutrition: return "Alimentation"; case .fitness: return "Sport"
        case .looks: return "Bien-être"; case .mind: return "Mental";            case .productivity: return "Tâches"
        case .finance: return "Finance"; case .invest: return "Bourse";          case .career: return "Travail"
        case .learning: return "Éducation"; case .home: return "Maison";         case .mobility: return "Transports"
        case .social: return "Social";   case .admin: return "Documents";        case .travel: return "Voyage"
        }
    }
}
