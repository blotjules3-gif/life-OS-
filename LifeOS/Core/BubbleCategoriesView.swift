//
//  BubbleCategoriesView.swift
//
//  Soap-bubble category screen powered by Bubble.metal.
//
//  La MATIÈRE (shader + BubbleStyle) n'est pas modifiée : règle le rendu via les 5 knobs
//  du bloc BubbleStyle. Les features LifeOS (mode édition, drag, compteur d'usage) sont
//  greffées dans BubbleCategoriesView sans toucher au rendu.
//
//  Requires iOS 17+ (SwiftUI Shaders). MeshGradient background uses iOS 18+
//  with an automatic iOS 17 fallback.
//

import SwiftUI

// MARK: - Tunable style (THE 5 KNOBS) — NE PAS TOUCHER pour l'instant

struct BubbleStyle {
    /// Center translucency. LOWER = more see-through. (0.55 glassy ... 0.85 dense)
    var coreAlpha: Double = 0.22        // centre TRÈS transparent (vraie bulle de savon)
    /// Color presence at the rim (Fresnel film). Higher = bolder edge color.
    var rimAlpha: Double = 0.62         // film coloré au bord
    /// Sharpness of the phong sparkle on the rim.
    var specStrength: Double = 1.0
    /// Outer colored bloom (neon glow of the bubble's own color).
    var colorGlow: Double = 0.65        // halo néon de la couleur de la bulle
    /// Outer soft white bloom.
    var whiteGlow: Double = 0.14
}

// MARK: - One bubble

struct BubbleView: View {
    let title: String
    let systemImage: String
    let tint: Color
    var diameter: CGFloat
    var showLabel: Bool = true
    var time: Double = 0
    var seed: Double = 0
    var style: BubbleStyle = BubbleStyle()

    var body: some View {
        let shader = ShaderLibrary.bubble(
            .float2(diameter, diameter),
            .color(tint),
            .float(Float(style.coreAlpha)),
            .float(Float(style.rimAlpha)),
            .float(Float(style.specStrength)),
            .float(Float(time)),
            .float(Float(seed))
        )

        return ZStack {
            Circle()
                .fill(shader)
                .shadow(color: tint.opacity(style.colorGlow), radius: diameter * 0.16)
                .shadow(color: .white.opacity(style.whiteGlow), radius: diameter * 0.10)

            if !title.isEmpty {
                VStack(spacing: diameter * 0.04) {
                    Image(systemName: systemImage)
                        .font(.system(size: diameter * 0.30, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: tint.opacity(0.9), radius: diameter * 0.03)
                        .shadow(color: .black.opacity(0.35), radius: diameter * 0.03, y: diameter * 0.005)
                    if showLabel {
                        Text(title)
                            .font(.system(size: diameter * 0.12, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: tint.opacity(0.9), radius: diameter * 0.025)
                            .shadow(color: .black.opacity(0.4), radius: diameter * 0.03, y: diameter * 0.005)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .offset(y: showLabel ? -diameter * 0.02 : 0)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Category model + fixed composition

struct BubbleCategory: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let anchor: CGPoint   // fractions of the screen (0..1)
    let sizeMul: CGFloat  // multiplier on the base diameter
    var isFiller: Bool = false
}

enum BubbleLayout {
    // Diamètre de base = screenWidth * baseRatio, puis * sizeMul par bulle.
    // baseRatio plus petit = plus d'air entre les bulles.  ←  RÈGLE L'ESPACEMENT ICI
    static let baseRatio: CGFloat = 0.27

    // Couleurs JEWEL TONES vives (réf). sizeMul = taille relative.
    static let categories: [BubbleCategory] = [
        .init(title: "Documents",    systemImage: "folder.fill",               tint: Color(red: 0.74, green: 0.84, blue: 0.97), anchor: .init(x: 0.205, y: 0.150), sizeMul: 0.85),
        .init(title: "Travail",      systemImage: "briefcase.fill",            tint: Color(red: 1.00, green: 0.72, blue: 0.24), anchor: .init(x: 0.460, y: 0.175), sizeMul: 0.95),
        .init(title: "Social",       systemImage: "person.2.fill",             tint: Color(red: 1.00, green: 0.20, blue: 0.55), anchor: .init(x: 0.760, y: 0.215), sizeMul: 1.20),
        .init(title: "Finance",      systemImage: "creditcard.fill",           tint: Color(red: 0.13, green: 0.52, blue: 1.00), anchor: .init(x: 0.165, y: 0.350), sizeMul: 0.95),
        .init(title: "Mental",       systemImage: "brain.head.profile",        tint: Color(red: 0.66, green: 0.32, blue: 0.96), anchor: .init(x: 0.435, y: 0.370), sizeMul: 1.18),
        .init(title: "Bien-être",    systemImage: "face.smiling",              tint: Color(red: 1.00, green: 0.54, blue: 0.10), anchor: .init(x: 0.720, y: 0.415), sizeMul: 1.18),
        .init(title: "Éducation",    systemImage: "graduationcap.fill",        tint: Color(red: 1.00, green: 0.80, blue: 0.18), anchor: .init(x: 0.860, y: 0.560), sizeMul: 0.74),
        .init(title: "Sport",        systemImage: "figure.run",                tint: Color(red: 1.00, green: 0.18, blue: 0.20), anchor: .init(x: 0.300, y: 0.575), sizeMul: 1.55),
        .init(title: "Alimentation", systemImage: "fork.knife",                tint: Color(red: 0.28, green: 0.80, blue: 0.36), anchor: .init(x: 0.580, y: 0.620), sizeMul: 1.05),
        .init(title: "Sommeil",      systemImage: "moon.stars.fill",           tint: Color(red: 0.42, green: 0.40, blue: 0.95), anchor: .init(x: 0.825, y: 0.660), sizeMul: 0.95),
        .init(title: "Tâches",       systemImage: "checklist",                 tint: Color(red: 0.14, green: 0.78, blue: 0.80), anchor: .init(x: 0.165, y: 0.745), sizeMul: 0.95),
        .init(title: "Voyage",       systemImage: "airplane",                  tint: Color(red: 0.20, green: 0.50, blue: 1.00), anchor: .init(x: 0.395, y: 0.815), sizeMul: 1.18),
        .init(title: "Maison",       systemImage: "house.fill",                tint: Color(red: 0.24, green: 0.56, blue: 0.96), anchor: .init(x: 0.635, y: 0.790), sizeMul: 0.92),
        .init(title: "Transports",   systemImage: "tram.fill",                 tint: Color(red: 0.16, green: 0.74, blue: 0.78), anchor: .init(x: 0.815, y: 0.850), sizeMul: 0.95),
        .init(title: "Bourse",       systemImage: "chart.line.uptrend.xyaxis", tint: Color(red: 0.16, green: 0.80, blue: 0.62), anchor: .init(x: 0.150, y: 0.880), sizeMul: 0.72),

        // Micro-bulles blanches (sans glyphe ni label) dans les creux
        .init(title: "", systemImage: "", tint: .white, anchor: .init(x: 0.585, y: 0.300), sizeMul: 0.18, isFiller: true),
        .init(title: "", systemImage: "", tint: .white, anchor: .init(x: 0.300, y: 0.480), sizeMul: 0.15, isFiller: true),
        .init(title: "", systemImage: "", tint: .white, anchor: .init(x: 0.625, y: 0.500), sizeMul: 0.17, isFiller: true),
        .init(title: "", systemImage: "", tint: .white, anchor: .init(x: 0.470, y: 0.700), sizeMul: 0.16, isFiller: true),
        .init(title: "", systemImage: "", tint: .white, anchor: .init(x: 0.930, y: 0.430), sizeMul: 0.13, isFiller: true),
        .init(title: "", systemImage: "", tint: .white, anchor: .init(x: 0.690, y: 0.910), sizeMul: 0.13, isFiller: true),
        .init(title: "", systemImage: "", tint: .white, anchor: .init(x: 0.290, y: 0.905), sizeMul: 0.12, isFiller: true),
    ]
}

// MARK: - The screen (+ features LifeOS : édition, drag, compteur d'usage)

enum CatLayout: String, CaseIterable {
    case organic, tidy, icons, list
    var label: String {
        switch self {
        case .organic: return "Bulles libres"
        case .tidy:    return "Bulles rangées"
        case .icons:   return "Icônes"
        case .list:    return "Liste"
        }
    }
    var symbol: String {
        switch self {
        case .organic: return "circle.hexagonpath"
        case .tidy:    return "circle.grid.3x3.fill"
        case .icons:   return "square.grid.2x2.fill"
        case .list:    return "list.bullet"
        }
    }
}

struct BubbleCategoriesView: View {
    var onSelect: (String) -> Void = { print("tapped \($0)") }
    var style: BubbleStyle = BubbleStyle()

    @AppStorage("bubbleWeights") private var weightsRaw = ""   // compteur d'usage  "titre:count,…"
    @AppStorage("hiddenCats")    private var hiddenRaw = ""    // bulles retirées (par titre)
    @AppStorage("catLayout")     private var layoutRaw = "organic"
    @AppStorage("appTheme")      private var appThemeRaw = "classic"
    @State private var editing = false
    @State private var showAdd = false
    @State private var tappedID: UUID?
    @State private var drag: [UUID: CGSize] = [:]
    @Environment(\.colorScheme) private var scheme

    private var layout: CatLayout { CatLayout(rawValue: layoutRaw) ?? .organic }
    private var theme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .classic }

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }
    private var visible: [BubbleCategory] {
        BubbleLayout.categories.filter { $0.isFiller || !hidden.contains($0.title) }
    }
    private var hiddenList: [BubbleCategory] {
        BubbleLayout.categories.filter { !$0.isFiller && hidden.contains($0.title) }
    }
    // catégories (sans fillers) pour les modes rangé/icônes/liste
    private var mains: [BubbleCategory] {
        BubbleLayout.categories.filter { !$0.isFiller && !hidden.contains($0.title) }
    }
    private var mainsByImportance: [BubbleCategory] {
        mains.sorted { (parseWeights()[$0.title] ?? 0) > (parseWeights()[$1.title] ?? 0) }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            layoutContent
        }
        .overlay(alignment: .topLeading) { layoutSwitcher }
        .overlay(alignment: .topTrailing) { editButton }
        .overlay(alignment: .bottomTrailing) { if editing && (layout == .organic || layout == .tidy) { addButton } }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    @ViewBuilder private var layoutContent: some View {
        switch layout {
        case .organic: bubbleCluster(tidy: false)
        case .tidy:    bubbleCluster(tidy: true)
        case .icons:   iconGrid
        case .list:    listLayout
        }
    }

    // ===== Bouton display : un clic = layout SUIVANT (cycle, pas de dropdown) =====
    private var layoutSwitcher: some View {
        Button {
            let all = CatLayout.allCases
            let next = all[(all.firstIndex(of: layout).map { $0 + 1 } ?? 0) % all.count]
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { layoutRaw = next.rawValue }
            Haptics.tap()
        } label: {
            Image(systemName: layout.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(.top, 8).padding(.leading, 16)
    }

    // ===== Mode 1 & 2 : bulles (libres / rangées) =====
    private func bubbleCluster(tidy: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let base = w * BubbleLayout.baseRatio
            let items = tidy ? mains : visible

            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { if editing { setEditing(false) } }
                        .gesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in setEditing(true) })

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, cat in
                        bubble(cat, index: index, base: base, w: w, h: h, t: t, tidy: tidy)
                    }
                }
            }
        }
    }

    // Une bulle : compteur d'usage (taille), bob, drag + tap, badge − en édition.
    private func bubble(_ cat: BubbleCategory, index: Int, base: CGFloat, w: CGFloat, h: CGFloat, t: Double, tidy: Bool) -> some View {
        let grow = cat.isFiller ? 1.0 : growth(cat.title)
        // rangé : grille 3 colonnes, taille uniforme ; libre : ancres organiques + tailles variées
        let cols = 3
        let gx: [CGFloat] = [0.21, 0.50, 0.79]
        let tidyAnchor = CGPoint(x: gx[index % cols], y: 0.12 + CGFloat(index / cols) * 0.158)
        let d = tidy ? base * 0.92 * grow : base * cat.sizeMul * grow
        let phase = Double(index) * 1.37
        let amp: Double = cat.isFiller ? 6 : 4
        let dv = drag[cat.id] ?? .zero
        let moving = dv != .zero
        let bx = (moving ? 0 : sin(t * 0.5 + phase) * amp) + dv.width
        let by = (moving ? 0 : cos(t * 0.42 + phase * 1.3) * amp) + dv.height
        let wig: Double = (editing && !cat.isFiller) ? sin(t * 7 + phase) * 2.0 : 0
        let a = tidy ? tidyAnchor : (cat.isFiller ? cat.anchor : adjustedAnchor(cat))

        return BubbleView(
            title: cat.title,
            systemImage: cat.systemImage,
            tint: cat.tint,
            diameter: d,
            showLabel: !cat.isFiller,
            time: t,
            seed: Double(index) * 2.1,
            style: cat.isFiller ? fillerStyle : style
        )
        .rotationEffect(.degrees(wig))
        .overlay(alignment: .topLeading) {
            if editing, !cat.isFiller {
                Button { remove(cat.title) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: max(20, d * 0.16)))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .offset(x: d * 0.12, y: d * 0.12)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(tappedID == cat.id ? 1.12 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: tappedID)
        .position(x: a.x * w + bx, y: a.y * h + by)
        .zIndex(moving ? 100 : Double(cat.sizeMul))
        .allowsHitTesting(!cat.isFiller)
        .gesture(dragTap(cat))
    }

    // Drag-suit-le-doigt + tap. Au relâché : retour ressort vers l'ancre. <10pt = tap.
    private func dragTap(_ cat: BubbleCategory) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in drag[cat.id] = v.translation }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height)
                if moved < 10 {
                    if !editing {
                        tappedID = cat.id
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        bump(cat.title)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            tappedID = nil
                            onSelect(cat.title)
                        }
                    }
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { drag[cat.id] = .zero }
            }
    }

    // MARK: combler le vide — décale légèrement vers les bulles retirées
    private func adjustedAnchor(_ cat: BubbleCategory) -> CGPoint {
        guard !hidden.isEmpty else { return cat.anchor }
        var ox: CGFloat = 0, oy: CGFloat = 0
        for h in BubbleLayout.categories where !h.isFiller && hidden.contains(h.title) {
            let dx = h.anchor.x - cat.anchor.x
            let dy = h.anchor.y - cat.anchor.y
            let dist = max(0.001, hypot(dx, dy))
            let pull = 0.22 * max(0, 1 - dist / 0.40)   // plus proche = plus attiré vers le vide
            ox += dx * pull
            oy += dy * pull
        }
        return CGPoint(x: cat.anchor.x + ox, y: cat.anchor.y + oy)
    }

    // MARK: compteur d'usage → taille
    private func growth(_ title: String) -> CGFloat {
        1 + min(CGFloat(parseWeights()[title] ?? 0) * 0.05, 0.6)
    }
    private func parseWeights() -> [String: Int] {
        var m: [String: Int] = [:]
        for p in weightsRaw.split(separator: ",") {
            let kv = p.split(separator: ":")
            if kv.count == 2, let v = Int(kv[1]) { m[String(kv[0])] = v }
        }
        return m
    }
    private func bump(_ title: String) {
        var m = parseWeights()
        m[title, default: 0] += 1
        weightsRaw = m.map { "\($0):\($1)" }.joined(separator: ",")
    }

    // MARK: mode édition
    private func setEditing(_ on: Bool) {
        guard editing != on else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { editing = on }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    private func remove(_ title: String) {
        var s = hidden; s.insert(title)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { hiddenRaw = s.sorted().joined(separator: ",") }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    private func add(_ title: String) {
        var s = hidden; s.remove(title)
        hiddenRaw = s.sorted().joined(separator: ",")
        if hiddenList.isEmpty { showAdd = false }
    }

    private var editButton: some View {
        Button { setEditing(!editing) } label: {
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
                if hiddenList.isEmpty {
                    Text("Toutes les catégories sont déjà affichées.").foregroundStyle(.secondary)
                }
                ForEach(hiddenList) { cat in
                    Button { add(cat.title) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: cat.systemImage).foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(cat.tint, in: RoundedRectangle(cornerRadius: 8))
                            Text(cat.title).foregroundStyle(.primary)
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

    private func tapCategory(_ cat: BubbleCategory) {
        bump(cat.title)
        Haptics.soft()
        onSelect(cat.title)
    }

    // ===== Mode 3 : icônes pro alignées par ligne =====
    private var iconGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 20) {
                ForEach(mains) { cat in
                    Button { tapCategory(cat) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: cat.systemImage)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 66, height: 66)
                                .background(cat.tint.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .shadow(color: cat.tint.opacity(0.4), radius: 8, y: 4)
                            Text(cat.title)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).padding(.top, 58).padding(.bottom, 110)
        }
    }

    // ===== Mode 4 : liste, plus importantes en haut =====
    private var listLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(mainsByImportance) { cat in
                    Button { tapCategory(cat) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: cat.systemImage)
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(cat.tint.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            Text(cat.title).font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 58).padding(.bottom, 110)
        }
    }

    // Fillers are more transparent and almost colorless
    private var fillerStyle: BubbleStyle {
        var s = style
        s.coreAlpha = 0.18
        s.rimAlpha = 0.40
        s.colorGlow = 0.20
        return s
    }

    @ViewBuilder private var background: some View {
        let cols = theme.bubbleBG
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: cols
            )
        } else {
            LinearGradient(colors: [cols[0], cols[4], cols[8]],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Routing : titre de bulle → pôle AppCategory (navigation existante)

extension AppCategory {
    init?(bubbleTitle: String) {
        switch bubbleTitle {
        case "Documents":    self = .admin
        case "Travail":      self = .career
        case "Social":       self = .social
        case "Finance":      self = .finance
        case "Mental":       self = .mind
        case "Bien-être":    self = .looks
        case "Éducation":    self = .learning
        case "Bourse":       self = .invest
        case "Sport":        self = .fitness
        case "Alimentation": self = .nutrition
        case "Sommeil":      self = .sleep
        case "Tâches":       self = .productivity
        case "Voyage":       self = .travel
        case "Maison":       self = .home
        case "Transports":   self = .mobility
        default:             return nil
        }
    }
}

#Preview {
    BubbleCategoriesView()
}
