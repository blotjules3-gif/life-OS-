import SwiftUI

// =====================================================================
// MARK: - CONSTANTS  (tout se règle ici)
// =====================================================================

private enum BC {
    static let baseFrac: CGFloat = 0.30          // baseDiameter = screenWidth * 0.30

    // --- matériau (verre verni, couleur VIVE) ---
    static let bodyOpacity:   Double = 0.92      // corps : couleur pleine et présente
    static let docsOpacity:   Double = 0.42      // Documents = pâle translucide
    static let fillerOpacity: Double = 0.26      // fillers = bulles de verre claires
    static let litMix:        Double = 0.35      // côté éclairé : teinte + un peu de blanc
    static let darkMix:       Double = 0.45      // côté ombre : teinte assombrie
    static let glossOpacity:  Double = 0.95      // gros reflet blanc verni

    // --- glow néon (chaque bulle rayonne sa couleur) ---
    static let glow1Op: Double = 0.70
    static let glow1R:  CGFloat = 0.30
    static let glow2Op: Double = 0.42
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
// MARK: - Catégories : composition FIXE de bulles vernies (zéro physique)
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
            .shadow(color: spec.tint.opacity(BC.glow1Op), radius: r * BC.glow1R)   // glow néon serré
            .shadow(color: spec.tint.opacity(BC.glow2Op), radius: r * BC.glow2R)   // bloom large
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

    // Verre coloré verni : volume 3D + couleur vive + gros reflet blanc brillant.
    @ViewBuilder private func bubbleBody(r: CGFloat) -> some View {
        let t = spec.tint
        let op = spec.bodyOp
        let lit  = t.mix(with: .white, by: BC.litMix)
        let dark = t.mix(with: .black, by: BC.darkMix)

        ZStack {
            // A · VOLUME directionnel — cœur PLEINEMENT SATURÉ (clair haut-gauche → sombre bas-droite)
            Circle().fill(LinearGradient(
                stops: [
                    .init(color: lit.opacity(op),                  location: 0.00),
                    .init(color: t.opacity(op),                    location: 0.45),
                    .init(color: t.opacity(op),                    location: 0.62),
                    .init(color: dark.opacity(min(1, op + 0.08)),  location: 1.00)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))

            // B · cœur lumineux interne (lit from within)
            Circle().fill(RadialGradient(
                colors: [lit.opacity(op * 0.55), .clear],
                center: UnitPoint(x: 0.42, y: 0.34), startRadius: 0, endRadius: r * 0.70))

            // C · GROS REFLET VERNI BLANC en haut (le look mouillé/brillant)
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(BC.glossOpacity), .white.opacity(0.0)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: r * 1.25, height: r * 0.95)
                .offset(y: -r * 0.42)
                .blur(radius: r * 0.04)

            // D · hotspot blanc net
            Ellipse().fill(.white)
                .frame(width: r * 0.32, height: r * 0.20)
                .rotationEffect(.degrees(-25))
                .offset(x: -r * 0.30, y: -r * 0.46)
                .blur(radius: r * 0.015)

            // E · arc lumineux blanc sur le rebord haut
            Circle().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.0)],
                               startPoint: .top, endPoint: .center),
                lineWidth: max(1, r * 0.05))

            // F · accroche blanche douce sur le rebord bas (la lumière fait le tour)
            Ellipse().fill(.white.opacity(0.5))
                .frame(width: r * 0.55, height: r * 0.14)
                .offset(y: r * 0.72)
                .blur(radius: r * 0.06)

            // G · glyphe + label (bulles principales)
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
                .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Drag-pour-réorganiser + tap, seulement quand interactif. Au relâché : retour ressort
/// vers l'ancre ; un mouvement sous le seuil = tap.
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
// MARK: - Composition codée en dur (grille serrée, Sport centré comme la réf)
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
        let bodyOp: Double
        let bobFactor: CGFloat
        let phase: Double
        let showLabel: Bool
    }

    /// (catégorie, x-fraction, y-fraction, multiplicateur de taille) — origine haut-gauche.
    /// Grille 5×3 : colonne centrale plus grosse (Social, Sport héros, Bien-être, Voyage).
    private static let template: [(AppCategory, CGFloat, CGFloat, CGFloat)] = [
        (.admin,        0.215, 0.160, 1.00),   // Documents
        (.social,       0.500, 0.145, 1.20),   // Social (gros)
        (.career,       0.785, 0.160, 1.02),   // Travail
        (.finance,      0.200, 0.330, 1.00),   // Finance
        (.fitness,      0.500, 0.350, 1.45),   // Sport — HÉROS centré
        (.mind,         0.800, 0.330, 1.02),   // Mental
        (.learning,     0.205, 0.500, 1.00),   // Éducation
        (.looks,        0.500, 0.510, 1.10),   // Bien-être
        (.nutrition,    0.795, 0.500, 1.05),   // Alimentation
        (.productivity, 0.205, 0.665, 1.00),   // Tâches
        (.travel,       0.500, 0.680, 1.15),   // Voyage (gros)
        (.sleep,        0.795, 0.665, 1.02),   // Sommeil
        (.invest,       0.215, 0.825, 0.82),   // Bourse (petite)
        (.home,         0.470, 0.835, 1.00),   // Maison
        (.mobility,     0.760, 0.825, 1.02)    // Transports
    ]

    /// Petits fillers blancs translucides dans les creux (x, y, fractionDeBase).
    private static let fillers: [(CGFloat, CGFloat, CGFloat)] = [
        (0.345, 0.250, 0.26), (0.655, 0.245, 0.20),
        (0.345, 0.430, 0.16), (0.660, 0.430, 0.24),
        (0.350, 0.595, 0.18), (0.655, 0.590, 0.15),
        (0.360, 0.760, 0.22), (0.640, 0.760, 0.16)
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
                bodyOp: isDocs ? BC.docsOpacity : BC.bodyOpacity,
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
                bodyOp: BC.fillerOpacity,
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

    /// Couleurs JEWEL TONES vives (comme la référence), pas les teintes système ternes.
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
