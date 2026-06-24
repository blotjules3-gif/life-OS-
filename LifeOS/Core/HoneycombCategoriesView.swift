import SwiftUI

// =====================================================================
// MARK: - CONSTANTS  (tout se règle ici — transparence en haut)
// =====================================================================

private enum BC {
    static let baseFrac: CGFloat = 0.30          // baseDiameter = screenWidth * 0.30

    // --- TRANSPARENCE : bulle de savon ~70% transparente (RÈGLE ICI) ---
    static let coreOpacity: Double = 0.40        // centre : transparent (le fond traverse) mais coloré
    static let rimOpacity:  Double = 0.72        // bord : film de savon, couleur bien présente
    static let docsCore:    Double = 0.12        // Documents = quasi incolore
    static let docsRim:     Double = 0.32
    static let fillerCore:  Double = 0.05        // micro-bulles = verre clair
    static let fillerRim:   Double = 0.22

    // --- reflets blancs & glow ---
    static let glossOpacity: Double = 0.95       // reflet verni (goutte de verre)
    static let innerGlowOp:  Double = 0.42       // halo blanc INTÉRIEUR au bord
    static let whiteBloomOp: Double = 0.38       // bloom blanc EXTÉRIEUR
    static let glow1Op: Double = 0.62            // glow néon couleur (serré)
    static let glow1R:  CGFloat = 0.30
    static let glow2Op: Double = 0.40            // bloom couleur (large)
    static let glow2R:  CGFloat = 0.58

    // --- mouvement : léger bob autour de l'ancre, sans dérive ---
    static let bobAmount:       CGFloat = 4
    static let bobBigFactor:    CGFloat = 0.7
    static let bobFillerFactor: CGFloat = 1.4
    static let bigThreshold:    CGFloat = 1.10

    // --- interaction ---
    static let tapThreshold: CGFloat = 10
    static let growPerTap:   CGFloat = 0.05
    static let growMax:      CGFloat = 0.60
}

// =====================================================================
// MARK: - Catégories : composition FIXE de bulles de savon (zéro physique)
// =====================================================================

struct HoneycombCategoriesView: View {
    @State private var path: [AppCategory] = []
    @AppStorage("bubbleWeights") private var weightsRaw = ""
    @AppStorage("hiddenCats") private var hiddenRaw = ""     // catégories retirées (vide = tout affiché)
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
                ForEach(bubbles) { b in     // sorted small→big ⇒ gros dessinés au-dessus
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

    // MARK: édition

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
    private func enterEdit() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { editing = true }
        Haptics.tap()
    }
    private func exitEdit() {
        if editing { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { editing = false } }
    }

    // MARK: poids de clics persistés ("rawValue:count,…")
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
// MARK: - Une bulle : ancrée, bob sur place, drag retour ressort
// =====================================================================

private struct FixedBubble: View {
    let spec: Layout.Spec
    let time: Double
    let bloomDelay: Double
    let onTap: (() -> Void)?
    var editing: Bool = false
    var onRemove: (() -> Void)? = nil

    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var appeared = false
    @State private var bounce = 0

    var body: some View {
        let r = spec.diameter / 2

        // bob doux autour de l'ancre (pas de vitesse, pas de dérive, revient toujours)
        let bob = BC.bobAmount * spec.bobFactor
        let bx = CGFloat(sin(time * 0.5  + spec.phase))       * bob
        let by = CGFloat(cos(time * 0.42 + spec.phase * 1.3)) * bob
        let dx = drag.width  + (dragging ? 0 : bx)
        let dy = drag.height + (dragging ? 0 : by)
        let wig: Double = (editing && spec.cat != nil) ? sin(time * 7 + spec.phase) * 2.0 : 0

        bubbleBody(r: r)
            .frame(width: spec.diameter, height: spec.diameter)
            .rotationEffect(.degrees(wig))
            .overlay(alignment: .topLeading) { removeBadge(r: r) }
            .shadow(color: .white.opacity(BC.whiteBloomOp), radius: r * 0.20)        // bloom blanc doux
            .shadow(color: spec.tint.opacity(BC.glow1Op), radius: r * BC.glow1R)     // glow néon couleur
            .shadow(color: spec.tint.opacity(BC.glow2Op), radius: r * BC.glow2R)     // bloom couleur large
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

    @ViewBuilder private func removeBadge(r: CGFloat) -> some View {
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

    // Bulle de savon TRANSLUCIDE : centre transparent, film de savon au bord,
    // volume 3D par ombrage blanc/noir, halo blanc intérieur, reflets blancs vernis.
    @ViewBuilder private func bubbleBody(r: CGFloat) -> some View {
        let t = spec.tint

        ZStack {
            // A · CORPS translucide : centre TRÈS transparent → bord film de savon (radial)
            Circle().fill(RadialGradient(
                stops: [
                    .init(color: t.opacity(spec.coreOp),        location: 0.00),
                    .init(color: t.opacity(spec.rimOp * 0.66),  location: 0.60),
                    .init(color: t.opacity(spec.rimOp),         location: 1.00)
                ],
                center: UnitPoint(x: 0.42, y: 0.38), startRadius: 0, endRadius: r))

            // B · VOLUME 3D : ombrage directionnel BLANC/NOIR (garde la translucidité)
            Circle().fill(LinearGradient(
                colors: [.white.opacity(0.16), .clear, .black.opacity(0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing))

            // C · GLOW BLANC INTÉRIEUR : halo doux juste à l'intérieur du bord
            Circle().strokeBorder(.white.opacity(BC.innerGlowOp), lineWidth: r * 0.11)
                .blur(radius: r * 0.09)

            // D · REFLET VERNI concentré (goutte de verre, net)
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(BC.glossOpacity), .white.opacity(0.0)],
                                     center: .center, startRadius: 0, endRadius: r * 0.50))
                .frame(width: r * 0.90, height: r * 0.68)
                .offset(x: -r * 0.10, y: -r * 0.40)
                .blur(radius: r * 0.02)

            // E · hotspot blanc net
            Ellipse().fill(.white)
                .frame(width: r * 0.28, height: r * 0.18)
                .rotationEffect(.degrees(-25))
                .offset(x: -r * 0.30, y: -r * 0.45)
                .blur(radius: r * 0.015)

            // F · arc lumineux blanc sur le rebord haut
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.0)],
                               startPoint: .top, endPoint: .center),
                lineWidth: max(1, r * 0.04))

            // G · accroche blanche douce sur le rebord bas
            Ellipse().fill(.white.opacity(0.45))
                .frame(width: r * 0.50, height: r * 0.13)
                .offset(y: r * 0.72)
                .blur(radius: r * 0.06)

            // H · glyphe + label (bulles principales)
            if let icon = spec.icon {
                VStack(spacing: r * 0.05) {
                    Image(systemName: icon)
                        .font(.system(size: r * 0.44, weight: .semibold))
                        .symbolEffect(.bounce, value: bounce)
                    if let label = spec.label, spec.showLabel, r > 30 {
                        Text(label)
                            .font(.system(size: max(9, r * 0.19), weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.55)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)   // lisible sur fond translucide
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Drag-pour-réorganiser + tap, seulement quand interactif. Au relâché : retour ressort.
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
                        drag = .zero
                    } completion: {
                        dragging = false
                    }
                }
        ))
    }
}

// =====================================================================
// MARK: - Fond : dégradé pastel clair plein écran
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
                .init(.sRGB, red: 0.84, green: 0.92, blue: 0.99),
                .init(.sRGB, red: 0.93, green: 0.95, blue: 1.00),
                .init(.sRGB, red: 0.97, green: 0.93, blue: 0.97),
                .init(.sRGB, red: 0.92, green: 0.94, blue: 1.00),
                .init(.sRGB, red: 0.98, green: 0.99, blue: 1.00),
                .init(.sRGB, red: 0.98, green: 0.95, blue: 0.96),
                .init(.sRGB, red: 0.86, green: 0.92, blue: 1.00),
                .init(.sRGB, red: 0.90, green: 0.94, blue: 1.00),
                .init(.sRGB, red: 0.93, green: 0.92, blue: 0.99)
            ])
    }
}

// =====================================================================
// MARK: - Composition codée en dur (cluster organique, espacé, tailles variées)
// =====================================================================

private enum Layout {

    struct Spec: Identifiable {
        let id: Int
        let cat: AppCategory?
        let anchor: CGPoint
        let diameter: CGFloat
        let tint: Color
        let icon: String?
        let label: String?
        let coreOp: Double
        let rimOp: Double
        let bobFactor: CGFloat
        let phase: Double
        let showLabel: Bool
    }

    /// Cluster ORGANIQUE espacé, tailles variées (3ᵉ nombre = multiplicateur de taille).
    /// Sport ~1.40 (héros) · grosses ~1.12-1.18 · moyennes ~0.92-0.96 · petites ~0.78-0.86.
    /// Positions écartées pour que CHAQUE bulle soit entièrement visible.
    private static let template: [(AppCategory, CGFloat, CGFloat, CGFloat)] = [
        (.admin,        0.215, 0.170, 0.96),   // Documents (très transparent)
        (.career,       0.475, 0.185, 0.92),   // Travail
        (.social,       0.785, 0.215, 1.18),   // Social (grosse)
        (.finance,      0.160, 0.350, 0.92),   // Finance
        (.mind,         0.445, 0.370, 1.14),   // Mental (grosse)
        (.looks,        0.735, 0.405, 1.16),   // Bien-être (grosse)
        (.learning,     0.870, 0.540, 0.86),   // Éducation (bien dégagée à droite)
        (.fitness,      0.300, 0.560, 1.40),   // Sport — HÉROS
        (.nutrition,    0.585, 0.625, 1.12),   // Alimentation (grosse)
        (.sleep,        0.835, 0.665, 0.96),   // Sommeil
        (.productivity, 0.170, 0.715, 0.96),   // Tâches
        (.home,         0.625, 0.780, 0.96),   // Maison (bien dégagée)
        (.travel,       0.390, 0.810, 1.16),   // Voyage (grosse)
        (.mobility,     0.820, 0.835, 0.96),   // Transports
        (.invest,       0.150, 0.850, 0.80)    // Bourse (visible, coin bas-gauche)
    ]

    /// ~9 micro-bulles blanches translucides dans les creux (x, y, fractionDeBase).
    private static let fillers: [(CGFloat, CGFloat, CGFloat)] = [
        (0.350, 0.255, 0.20), (0.625, 0.150, 0.13),
        (0.605, 0.475, 0.18), (0.120, 0.520, 0.13),
        (0.905, 0.395, 0.12), (0.490, 0.705, 0.16),
        (0.910, 0.745, 0.15), (0.265, 0.885, 0.14),
        (0.625, 0.900, 0.13)
    ]

    static let allCats: [AppCategory] = template.map { $0.0 }

    static func build(in size: CGSize, weights: [String: Int], hidden: Set<String> = []) -> [Spec] {
        guard size.width > 0 else { return [] }
        let base = size.width * BC.baseFrac
        var out: [Spec] = []
        var id = 0

        // bulles principales (catégories non masquées)
        let active = template.filter { !hidden.contains($0.0.rawValue) }
        let mains: [(cat: AppCategory, center: CGPoint, dia: CGFloat, mult: CGFloat)] = active.map { (cat, fx, fy, mult) in
            let grown = mult * growth(weights[cat.rawValue] ?? 0)
            return (cat, CGPoint(x: fx * size.width, y: fy * size.height), base * grown, mult)
        }

        for (i, m) in mains.enumerated() {
            // label masqué seulement si le centre est recouvert par une bulle plus GROSSE
            var show = true
            for (j, o) in mains.enumerated() where j != i && o.dia > m.dia * 1.02 {
                let d = hypot(m.center.x - o.center.x, m.center.y - o.center.y)
                if d < o.dia / 2 * 0.85 { show = false; break }
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

        for (fx, fy, frac) in fillers {
            out.append(Spec(
                id: id, cat: nil,
                anchor: CGPoint(x: fx * size.width, y: fy * size.height),
                diameter: base * frac,
                tint: .white,
                icon: nil, label: nil,
                coreOp: BC.fillerCore, rimOp: BC.fillerRim,
                bobFactor: BC.bobFillerFactor,
                phase: Double(id) * 0.9,
                showLabel: false))
            id += 1
        }

        // ordre de dessin : petites d'abord → grosses au-dessus
        return out.sorted { $0.diameter < $1.diameter }
    }

    private static func growth(_ count: Int) -> CGFloat {
        1 + min(CGFloat(count) * BC.growPerTap, BC.growMax)
    }

    /// Couleurs JEWEL TONES vives (comme la référence).
    static func color(_ c: AppCategory) -> Color {
        switch c {
        case .fitness:      return Color(red: 1.00, green: 0.20, blue: 0.22)   // rouge vif
        case .social:       return Color(red: 1.00, green: 0.20, blue: 0.55)   // fuchsia
        case .career:       return Color(red: 1.00, green: 0.72, blue: 0.24)   // ambre/or
        case .finance:      return Color(red: 0.13, green: 0.52, blue: 1.00)   // bleu électrique
        case .mind:         return Color(red: 0.66, green: 0.32, blue: 0.96)   // violet riche
        case .looks:        return Color(red: 1.00, green: 0.54, blue: 0.10)   // orange vif
        case .learning:     return Color(red: 1.00, green: 0.80, blue: 0.18)   // jaune/or
        case .nutrition:    return Color(red: 0.28, green: 0.80, blue: 0.36)   // vert vif
        case .sleep:        return Color(red: 0.56, green: 0.42, blue: 0.96)   // violet doux
        case .productivity: return Color(red: 0.14, green: 0.78, blue: 0.74)   // teal
        case .travel:       return Color(red: 0.20, green: 0.50, blue: 1.00)   // bleu électrique
        case .home:         return Color(red: 0.24, green: 0.56, blue: 0.96)   // bleu
        case .mobility:     return Color(red: 0.16, green: 0.74, blue: 0.78)   // teal
        case .invest:       return Color(red: 0.18, green: 0.80, blue: 0.58)   // menthe
        case .admin:        return Color(red: 0.74, green: 0.84, blue: 0.97)   // bleu pâle (verre)
        }
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
