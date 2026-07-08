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
    /// 1 = rendu chrome liquide (thème Argent), 0 = bulle de savon.
    var metal: Double = 0
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

    // `time` varies every frame so the shader cannot be fully cached;
    // extracting it here avoids allocating shader args inside the view builder.
    private var bubbleShader: Shader {
        ShaderLibrary.bubble(
            .float2(diameter, diameter),
            .color(tint),
            .float(Float(style.coreAlpha)),
            .float(Float(style.rimAlpha)),
            .float(Float(style.specStrength)),
            .float(Float(time)),
            .float(Float(seed)),
            .float(Float(style.metal))
        )
    }

    var body: some View {
        let shader = bubbleShader
        let isMetal = style.metal > 0
        let glyphGlow = isMetal ? Color.black : tint     // halo noir sur chrome (lisibilité)

        return ZStack {
            Circle()
                .fill(shader)
                .shadow(color: tint.opacity(style.colorGlow), radius: diameter * 0.16)
                .shadow(color: .white.opacity(style.whiteGlow), radius: diameter * 0.10)
                // ombre de contact réaliste sous la goutte de métal
                .shadow(color: .black.opacity(isMetal ? 0.55 : 0),
                        radius: diameter * 0.06, y: diameter * 0.05)

            if !title.isEmpty {
                VStack(spacing: diameter * 0.04) {
                    Image(systemName: systemImage)
                        .font(.system(size: diameter * 0.30, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: glyphGlow.opacity(0.9), radius: diameter * 0.03)
                        .shadow(color: .black.opacity(isMetal ? 0.7 : 0.35), radius: diameter * 0.025, y: diameter * 0.005)
                    if showLabel {
                        Text(title)
                            .font(.system(size: diameter * 0.12, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: glyphGlow.opacity(0.9), radius: diameter * 0.025)
                            .shadow(color: .black.opacity(isMetal ? 0.75 : 0.4), radius: diameter * 0.025, y: diameter * 0.005)
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
    static let baseRatio: CGFloat = 0.300

    // Composition riche et dense : grosses gouttes, priorités dominantes
    // (Sport/Social/Mental/Voyage), longs labels agrandis pour que le texte tienne dedans.
    // 3 TAILLES EXACTES : grande (1.5) / moyenne (1.0) / petite (0.7). Le diamètre
    // réel vient de BubbleSize.widthFraction ; sizeMul ne sert plus qu'à dire à quelle
    // des 3 classes appartient la catégorie par défaut. L'ordre forme 5 rangées de 3
    // (grande + moyenne + petite, décalées) — voir packOrganic() qui calcule le placement
    // serré (bulles qui se touchent, sans chevauchement) tenant sur UN seul écran.
    static let categories: [BubbleCategory] = [
        // Rangée 1
        .init(title: "Social",       systemImage: "person.2.fill",             tint: Color(red: 1.00, green: 0.20, blue: 0.55), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.5),
        .init(title: "Bien-être",    systemImage: "face.smiling",              tint: Color(red: 1.00, green: 0.54, blue: 0.10), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.0),
        .init(title: "Éducation",    systemImage: "graduationcap.fill",        tint: Color(red: 1.00, green: 0.80, blue: 0.18), anchor: .init(x: 0.0, y: 0.0), sizeMul: 0.7),
        // Rangée 2
        .init(title: "Tâches",       systemImage: "checklist",                 tint: Color(red: 0.14, green: 0.78, blue: 0.80), anchor: .init(x: 0.0, y: 0.0), sizeMul: 0.7),
        .init(title: "Mental",       systemImage: "brain.head.profile",        tint: Color(red: 0.66, green: 0.32, blue: 0.96), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.5),
        .init(title: "Documents",    systemImage: "folder.fill",               tint: Color(red: 0.74, green: 0.84, blue: 0.97), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.0),
        // Rangée 3
        .init(title: "Travail",      systemImage: "briefcase.fill",            tint: Color(red: 1.00, green: 0.72, blue: 0.24), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.0),
        .init(title: "Sommeil",      systemImage: "moon.stars.fill",           tint: Color(red: 0.42, green: 0.40, blue: 0.95), anchor: .init(x: 0.0, y: 0.0), sizeMul: 0.7),
        .init(title: "Sport",        systemImage: "figure.run",                tint: Color(red: 1.00, green: 0.18, blue: 0.20), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.5),
        // Rangée 4
        .init(title: "Alimentation", systemImage: "fork.knife",                tint: Color(red: 0.28, green: 0.80, blue: 0.36), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.5),
        .init(title: "Transports",   systemImage: "tram.fill",                 tint: Color(red: 0.16, green: 0.74, blue: 0.78), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.0),
        .init(title: "Maison",       systemImage: "house.fill",                tint: Color(red: 0.24, green: 0.56, blue: 0.96), anchor: .init(x: 0.0, y: 0.0), sizeMul: 0.7),
        // Rangée 5
        .init(title: "Bourse",       systemImage: "chart.line.uptrend.xyaxis", tint: Color(red: 0.16, green: 0.80, blue: 0.62), anchor: .init(x: 0.0, y: 0.0), sizeMul: 0.7),
        .init(title: "Voyage",       systemImage: "airplane",                  tint: Color(red: 0.20, green: 0.50, blue: 1.00), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.5),
        .init(title: "Finance",      systemImage: "creditcard.fill",           tint: Color(red: 0.13, green: 0.52, blue: 1.00), anchor: .init(x: 0.0, y: 0.0), sizeMul: 1.0),
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
    @AppStorage("catSizes")      private var catSizesRaw = ""    // "titre:s|m|l,…" — taille par catégorie
    @AppStorage("catOffsets")    private var catOffsetsRaw = ""  // "titre:dx:dy,…" — (legacy, plus utilisé)
    @AppStorage("catAnchors")    private var catAnchorsRaw = ""  // "titre:fx:fy,…" — position ancrée (fraction)
    @AppStorage("catColors")     private var catColorsRaw = ""   // "titre:RRGGBB,…" — couleur perso par catégorie
    @State private var editing = false
    @State private var showAdd = false
    @State private var showCatIntake = false
    @State private var tappedID: UUID?
    @State private var drag: [UUID: CGSize] = [:]
    @State private var colorEditTarget: ColorEditTarget?
    @State private var sizePickerTarget: BubbleSizePickerTarget?

    private struct ColorEditTarget: Identifiable { let id = UUID(); let title: String; let initial: Color }
    @Environment(\.colorScheme) private var scheme

    private var layout: CatLayout { CatLayout(rawValue: layoutRaw) ?? .organic }
    private var theme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .classic }
    // Taille INDIVIDUELLE par catégorie. 3 classes exactes (petite/moyenne/grande).
    // Défaut = la classe codée dans sizeMul (1.5 grande / 1.0 moyenne / 0.7 petite) ;
    // l'appui long écrit un override qui prime.
    private func catSizeOverride(_ title: String) -> BubbleSize? {
        for p in catSizesRaw.split(separator: ",") {
            let kv = p.split(separator: ":")
            if kv.count == 2, String(kv[0]) == title { return BubbleSize(rawValue: String(kv[1])) }
        }
        return nil
    }
    private func defaultSize(_ sizeMul: CGFloat) -> BubbleSize {
        sizeMul >= 1.3 ? .large : (sizeMul >= 0.9 ? .medium : .small)
    }
    private func effectiveSize(_ cat: BubbleCategory) -> BubbleSize {
        catSizeOverride(cat.title) ?? defaultSize(cat.sizeMul)
    }
    private func setCatSize(_ title: String, _ size: BubbleSize) {
        var m: [String: String] = [:]
        for p in catSizesRaw.split(separator: ",") { let kv = p.split(separator: ":"); if kv.count == 2 { m[String(kv[0])] = String(kv[1]) } }
        m[title] = size.rawValue
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { catSizesRaw = m.map { "\($0):\($1)" }.joined(separator: ",") }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    // Position déplacée (offset px) par catégorie
    private func offsetsMap() -> [String: CGSize] {
        var m: [String: CGSize] = [:]
        for p in catOffsetsRaw.split(separator: ",") {
            let f = p.split(separator: ":")
            if f.count == 3, let dx = Double(f[1]), let dy = Double(f[2]) { m[String(f[0])] = CGSize(width: dx, height: dy) }
        }
        return m
    }
    private func catOffset(_ title: String) -> CGSize { offsetsMap()[title] ?? .zero }
    private func writeOffsets(_ m: [String: CGSize]) {
        catOffsetsRaw = m.map { "\($0.key):\(Int($0.value.width)):\(Int($0.value.height))" }.joined(separator: ",")
    }
    private func addCatOffset(_ title: String, _ delta: CGSize) {
        var m = offsetsMap(); let cur = m[title] ?? .zero
        m[title] = CGSize(width: cur.width + delta.width, height: cur.height + delta.height)
        writeOffsets(m)
    }
    private func resetCatOffset(_ title: String) { var m = offsetsMap(); m[title] = nil; writeOffsets(m) }

    // Position ANCRÉE (fraction d'écran) d'une bulle déplacée par l'utilisateur. Le packing
    // l'utilise comme position préférée + ressort fort → les voisines sont repoussées.
    private func anchorsMap() -> [String: CGPoint] {
        var m: [String: CGPoint] = [:]
        for p in catAnchorsRaw.split(separator: ",") {
            let f = p.split(separator: ":")
            if f.count == 3, let fx = Double(f[1]), let fy = Double(f[2]) { m[String(f[0])] = CGPoint(x: fx, y: fy) }
        }
        return m
    }
    private func writeAnchors(_ m: [String: CGPoint]) {
        catAnchorsRaw = m.map { "\($0.key):\(String(format: "%.4f", $0.value.x)):\(String(format: "%.4f", $0.value.y))" }
            .joined(separator: ",")
    }
    private func setAnchor(_ title: String, _ frac: CGPoint) { var m = anchorsMap(); m[title] = frac; writeAnchors(m) }
    private func removeAnchor(_ title: String) { var m = anchorsMap(); m[title] = nil; writeAnchors(m) }
    private func hasAnchor(_ title: String) -> Bool { anchorsMap()[title] != nil }

    // Couleur PERSO par catégorie (prime sur la couleur du thème). "titre:RRGGBB".
    private func colorsMap() -> [String: String] {
        var m: [String: String] = [:]
        for p in catColorsRaw.split(separator: ",") {
            let kv = p.split(separator: ":")
            if kv.count == 2 { m[String(kv[0])] = String(kv[1]) }
        }
        return m
    }
    private func catColorOverride(_ title: String) -> Color? {
        guard let hex = colorsMap()[title], let v = UInt(hex, radix: 16) else { return nil }
        return Color(hex: v)
    }
    private func hasCatColor(_ title: String) -> Bool { colorsMap()[title] != nil }
    private func setCatColor(_ title: String, _ color: Color) {
        var m = colorsMap(); m[title] = color.hexString
        catColorsRaw = m.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    private func removeCatColor(_ title: String) {
        var m = colorsMap(); m[title] = nil
        catColorsRaw = m.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }

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
        .overlay(alignment: .topLeading) { if !theme.isModern { layoutSwitcher } }
        .overlay(alignment: .topTrailing) { if !theme.isModern { editButton } }
        .overlay(alignment: .bottomTrailing) { if !theme.isModern && editing && (layout == .organic || layout == .tidy) { addButton } }
        .sheet(isPresented: $showAdd) { addSheet }
        .sheet(item: $colorEditTarget) { target in
            CategoryColorSheet(
                title: target.title,
                initial: target.initial,
                onSave: { setCatColor(target.title, $0) },
                onReset: hasCatColor(target.title) ? { removeCatColor(target.title) } : nil
            )
            .presentationDetents([.height(320), .medium])
        }
        .sheet(item: $sizePickerTarget) { target in
            BubbleSizePickerSheet(
                categoryTitle: target.title,
                categoryTint: target.tint,
                selection: target.current,
                onSelect: { setCatSize(target.title, $0) }
            )
        }
        .fullScreenCover(isPresented: $showCatIntake) { IntakeHubView() }
    }

    // Barre de progression du remplissage des catégories → ouvre les pôles à compléter.
    private var catProgressHeader: some View {
        Button { showCatIntake = true } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text("Complète ton profil")
                        .font(.system(size: 13, weight: .black)).textCase(.uppercase).kerning(0.3)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(CategorySetup.doneCount)/\(CategorySetup.flows.count)")
                        .monoLabel(11).foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10)).frame(height: 8)
                        Capsule().fill(Color.accentColor)
                            .frame(width: max(8, geo.size.width * CategorySetup.fraction), height: 8)
                    }
                }
                .frame(height: 8)
                Text("Touche pour remplir les pôles qui te manquent")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            .card(padding: 14, elevated: true)
        }
        .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder private var layoutContent: some View {
        if theme.isModern {
            nikeGrid   // Nike / Verre : grille de tuiles (plus de bulles pastel)
        } else {
            switch layout {
            case .organic: bubbleCluster(tidy: false)
            case .tidy:    bubbleCluster(tidy: true)
            case .icons:   iconGrid
            case .list:    listLayout
            }
        }
    }

    // MARK: - Grille NIKE (thèmes modernes) : tuiles noir & blanc, index mono, volt
    private var nikeGrid: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Catégories")
                    .font(.system(size: 34, weight: .black)).textCase(.uppercase).kerning(-1)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                if CategorySetup.fraction < 1.0 { catProgressHeader }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(mains.enumerated()), id: \.element.id) { i, cat in
                        Button { tapCategory(cat) } label: { nikeTile(cat, index: i) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 66).padding(.bottom, 120)
        }
    }

    private func nikeTile(_ cat: BubbleCategory, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(String(format: "%02d", index + 1)).monoLabel(12).foregroundStyle(.secondary)
                Spacer()
                IconBadge(icon: cat.systemImage, size: 42)
            }
            Spacer(minLength: 20)
            Text(cat.title)
                .font(.system(size: 18, weight: .black)).textCase(.uppercase).kerning(-0.3)
                .foregroundStyle(.primary)
                .lineLimit(2).minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: 132, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, elevated: true)
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
        .accessibilityLabel("Changer la disposition")
        .padding(.top, Theme.space8).padding(.leading, 16)
    }

    // ===== Mode 1 & 2 : bulles (libres / rangées) =====
    private func bubbleCluster(tidy: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let base = w * BubbleLayout.baseRatio
            let items = mains
            // Placement SERRÉ calculé : bulles tangentes (elles se touchent), aucun
            // chevauchement, tout tient sur UN écran entre les boutons et le menu.
            let packed = tidy ? [:] : packOrganic(items, w: w, h: h)

            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { if editing { setEditing(false) } }
                        .gesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in setEditing(true) })

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, cat in
                        bubble(cat, index: index, base: base, w: w, h: h, t: t, tidy: tidy, packed: packed)
                    }
                }
            }
        }
    }

    // Placement ALÉATOIRE organique (mode « Bulles libres ») : on éparpille les bulles
    // (scatter pseudo-aléatoire stable, déterministe), puis on les repousse les unes des
    // autres (relaxation) jusqu'à ZÉRO chevauchement — elles peuvent se TOUCHER mais
    // jamais se cacher. Tout reste dans la bande [sous les boutons … au-dessus du menu
    // flottant]. 3 tailles exactes conservées. Renvoie centre + diamètre par catégorie.
    private func packOrganic(_ items: [BubbleCategory], w: CGFloat, h: CGFloat) -> [UUID: (CGPoint, CGFloat)] {
        let topInset: CGFloat = 88       // sous les boutons Modifier / layout
        let bottomInset: CGFloat = 116   // dégage la barre d'onglets flottante (incluse dans h)
        let sideInset: CGFloat = 12
        let gap: CGFloat = 18            // marge mini entre bulles → elles NE se touchent PAS
        let minX = sideInset, maxX = w - sideInset
        let minY = topInset, maxY = max(h - bottomInset, topInset + 1)
        let areaW = maxX - minX, areaH = maxY - minY

        let n = items.count
        guard n > 0 else { return [:] }

        // Diamètres bruts (3 tailles) → échelle pour viser une densité qui laisse de
        // l'AIR entre les bulles (densité plus basse = plus d'espace visible).
        var dias = items.map { w * effectiveSize($0).widthFraction }
        let rawArea = dias.reduce(0) { $0 + .pi * ($1 * 0.5) * ($1 * 0.5) }
        let density: CGFloat = 0.58
        let areaScale = min(1, (density * areaW * areaH / max(rawArea, 1)).squareRoot())
        dias = dias.map { $0 * areaScale }

        // PRNG déterministe (pas de Math.random → stable entre rendus).
        func rnd(_ i: Int, _ s: Int) -> CGFloat {
            let v = sin(Double(i) * 12.9898 + Double(s) * 78.233) * 43758.5453
            return CGFloat(v - v.rounded(.down))
        }

        // Position PRÉFÉRÉE de chaque bulle : son ancre si l'utilisateur l'a déplacée
        // (ressort fort), sinon une position éparpillée stable (ressort faible).
        let anchors = anchorsMap()
        var px = [CGFloat](repeating: 0, count: n)
        var py = [CGFloat](repeating: 0, count: n)
        var anchored = [Bool](repeating: false, count: n)
        var cx = [CGFloat](repeating: 0, count: n)
        var cy = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            let r = dias[i] * 0.5
            if let a = anchors[items[i].title] {
                px[i] = min(max(a.x * w, minX + r), maxX - r)
                py[i] = min(max(a.y * h, minY + r), maxY - r)
                anchored[i] = true
            } else {
                px[i] = minX + r + rnd(i, 1) * max(areaW - 2 * r, 1)
                py[i] = minY + r + rnd(i, 2) * max(areaH - 2 * r, 1)
            }
            cx[i] = px[i]; cy[i] = py[i]
        }

        // Relaxation force-dirigée : répulsion (anti-chevauchement) + ressort vers la
        // position préférée. Déplacer une bulle (ancre) repousse donc ses voisines.
        for _ in 0..<300 {
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = cx[j] - cx[i], dy = cy[j] - cy[i]
                    var dist = (dx * dx + dy * dy).squareRoot()
                    if dist < 0.0001 { dist = 0.0001 }
                    let minDist = dias[i] * 0.5 + dias[j] * 0.5 + gap
                    if dist < minDist {
                        let push = (minDist - dist) * 0.5
                        let ux = dx / dist, uy = dy / dist
                        cx[i] -= ux * push; cy[i] -= uy * push
                        cx[j] += ux * push; cy[j] += uy * push
                    }
                }
            }
            for i in 0..<n {
                let k: CGFloat = anchored[i] ? 0.16 : 0.05   // ancrée = tient sa place
                cx[i] += (px[i] - cx[i]) * k
                cy[i] += (py[i] - cy[i]) * k
                let r = dias[i] * 0.5
                cx[i] = min(max(cx[i], minX + r), maxX - r)
                cy[i] = min(max(cy[i], minY + r), maxY - r)
            }
        }

        // PASSE FINALE — séparation pure (sans ressort). Garantit l'espace mini même
        // entre bulles ancrées qui ont grossi : le non-chevauchement gagne TOUJOURS.
        // Les voisines sont repoussées vers l'extérieur jusqu'à dégager le `gap`.
        for _ in 0..<260 {
            var maxOverlap: CGFloat = 0
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = cx[j] - cx[i], dy = cy[j] - cy[i]
                    var dist = (dx * dx + dy * dy).squareRoot()
                    if dist < 0.0001 { dist = 0.0001 }
                    let minDist = dias[i] * 0.5 + dias[j] * 0.5 + gap
                    let overlap = minDist - dist
                    if overlap > 0 {
                        maxOverlap = max(maxOverlap, overlap)
                        // séparation symétrique le long de l'axe ; si superposées
                        // parfaitement, on écarte sur un axe déterministe.
                        let ux = dist > 0.001 ? dx / dist : (rnd(i + j, 7) - 0.5)
                        let uy = dist > 0.001 ? dy / dist : (rnd(i + j, 8) - 0.5)
                        let push = overlap * 0.5
                        cx[i] -= ux * push; cy[i] -= uy * push
                        cx[j] += ux * push; cy[j] += uy * push
                    }
                }
            }
            for i in 0..<n {
                let r = dias[i] * 0.5
                cx[i] = min(max(cx[i], minX + r), maxX - r)
                cy[i] = min(max(cy[i], minY + r), maxY - r)
            }
            if maxOverlap < 0.5 { break }   // convergé : plus aucun chevauchement
        }

        var result: [UUID: (CGPoint, CGFloat)] = [:]
        for i in 0..<n { result[items[i].id] = (CGPoint(x: cx[i], y: cy[i]), dias[i]) }
        return result
    }

    // Une bulle : compteur d'usage (taille), bob, drag + tap, badge − en édition.
    private func bubble(_ cat: BubbleCategory, index: Int, base: CGFloat, w: CGFloat, h: CGFloat, t: Double, tidy: Bool, packed: [UUID: (CGPoint, CGFloat)]) -> some View {
        // Taille + centre : mode libre = packing calculé (tangent, 3 tailles) ;
        // mode rangé = grille 3 colonnes uniforme.
        let cols = 3
        let gx: [CGFloat] = [0.21, 0.50, 0.79]
        let d: CGFloat
        let cx: CGFloat
        let cy: CGFloat
        if !tidy, let p = packed[cat.id] {
            d = p.1; cx = p.0.x; cy = p.0.y
        } else {
            d = base * 0.92
            cx = gx[index % cols] * w
            cy = 96 + CGFloat(index / cols) * (base * 0.92 + 14)
        }
        let phase = Double(index) * 1.37
        let amp: Double = 2.5
        let dv = drag[cat.id] ?? .zero
        let moving = dv != .zero
        let bx = (moving ? 0 : sin(t * 0.5 + phase) * amp) + dv.width
        let by = (moving ? 0 : cos(t * 0.42 + phase * 1.3) * amp) + dv.height
        let wig: Double = (editing && !cat.isFiller) ? sin(t * 7 + phase) * 2.0 : 0

        return Group {
            if theme == .gothic {
                // Thème Argent : goutte de CHROME basée sur un asset PNG réaliste
                ChromeCategoryButton(
                    title: cat.isFiller ? "" : cat.title,
                    sfSymbolName: cat.isFiller ? "" : cat.systemImage,
                    assetName: ChromeCategoryButton.asset(for: d, base: base, index: index),
                    size: d,
                    showLabel: !cat.isFiller,
                    pressed: tappedID == cat.id,
                    time: t,
                    phase: Double(index) * 1.7
                )
            } else {
                BubbleView(
                    title: cat.title,
                    systemImage: cat.systemImage,
                    tint: cat.isFiller ? cat.tint : themedTint(cat),
                    diameter: d,
                    showLabel: !cat.isFiller,
                    time: t,
                    seed: Double(index) * 2.1,
                    style: cat.isFiller ? fillerStyle : themedStyle
                )
            }
        }
        .rotationEffect(.degrees(wig))
        .overlay(alignment: .topLeading) {
            if editing, !cat.isFiller {
                Button { remove(cat.title) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: max(20, d * 0.16)))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .accessibilityLabel("Retirer \(cat.title)")
                .buttonStyle(.plain)
                .offset(x: d * 0.12, y: d * 0.12)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(theme == .gothic ? 1.0 : (tappedID == cat.id ? 1.12 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: tappedID)
        // Bande verticale : on descend sous les boutons (haut) et on laisse de l'air en bas.
        .position(x: cx + bx, y: cy + by)   // l'ancre est déjà intégrée dans cx/cy (packing)
        .zIndex(moving ? 100 : effectiveSize(cat).rank)
        .allowsHitTesting(!cat.isFiller)
        .onTapGesture {
            guard !cat.isFiller, !editing else { return }
            tappedID = cat.id
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            bump(cat.title)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { tappedID = nil; onSelect(cat.title) }
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in if !cat.isFiller { drag[cat.id] = v.translation } }
                .onEnded { v in
                    guard !cat.isFiller else { return }
                    // Nouvelle position absolue → ancre (fraction). Le packing s'anime
                    // et repousse les voisines pour laisser la place.
                    let nx = cx + v.translation.width
                    let ny = cy + v.translation.height
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                        setAnchor(cat.title, CGPoint(x: nx / w, y: ny / h))
                        drag[cat.id] = .zero
                    }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
        )
        .contextMenu {
            if !cat.isFiller {
                // Ouvre le sélecteur premium (sheet dédié) au lieu d'un sous-menu système.
                Button {
                    sizePickerTarget = BubbleSizePickerTarget(
                        title: cat.title,
                        tint: themedTint(cat),
                        current: effectiveSize(cat)
                    )
                } label: {
                    Label("Taille de la bulle…", systemImage: "circle.grid.2x1.fill")
                }
                Section("Couleur") {
                    Button {
                        colorEditTarget = ColorEditTarget(title: cat.title, initial: themedTint(cat))
                    } label: { Label("Couleur personnalisée…", systemImage: "paintpalette.fill") }
                    if hasCatColor(cat.title) {
                        Button { removeCatColor(cat.title) } label: {
                            Label("Couleur par défaut", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                if hasAnchor(cat.title) {
                    Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { removeAnchor(cat.title) } } label: {
                        Label("Replacer automatiquement", systemImage: "arrow.counterclockwise")
                    }
                }
                Button(role: .destructive) { remove(cat.title) } label: { Label("Supprimer", systemImage: "trash") }
            }
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
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
        .padding(.top, Theme.space8).padding(.trailing, Theme.pad)
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .accessibilityLabel("Ajouter une catégorie")
        .padding(.trailing, Theme.space24).padding(.bottom, 110)
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
                                .accessibilityHidden(true)
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

    // Couleur des bulles selon le thème : Clair/Sombre = multicolore (couleur de catégorie),
    // les 3 autres thèmes = teinte unique déclinée (rose / argent / nuage).
    func themedTint(_ cat: BubbleCategory) -> Color {
        if let custom = catColorOverride(cat.title) { return custom }   // couleur perso = priorité absolue
        if theme == .classic || theme == .dark { return cat.tint }
        let idx = BubbleLayout.categories.firstIndex { $0.id == cat.id } ?? 0
        switch theme {
        case .pinky:
            return [Color(hex: 0xFF4F9D), Color(hex: 0xFF77B5), Color(hex: 0xF06EA9),
                    Color(hex: 0xFF8AC4), Color(hex: 0xE85C9E)][idx % 5]
        case .gothic:
            return [Color(hex: 0xAEB7C4), Color(hex: 0xC6CED9), Color(hex: 0x99A3B2),
                    Color(hex: 0xD2D8E1), Color(hex: 0xB4BCC8)][idx % 5]
        case .cloud:
            return [Color(hex: 0xC3D2E8), Color(hex: 0xD2DEEE), Color(hex: 0xB7C8E2),
                    Color(hex: 0xCBD8EC), Color(hex: 0xDCE5F2)][idx % 5]
        default:
            return cat.tint
        }
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
                                .background(themedTint(cat).gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .shadow(color: themedTint(cat).opacity(0.4), radius: 8, y: 4)
                            Text(cat.title)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.space20).padding(.top, Theme.space48 + Theme.space8 + Theme.space4).padding(.bottom, 110)
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
                                .background(themedTint(cat).gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .accessibilityHidden(true)
                            Text(cat.title).font(.system(size: 16, weight: .medium)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pad).padding(.top, Theme.space48 + Theme.space8 + Theme.space4).padding(.bottom, 110)
        }
    }

    // Style des bulles principales selon le thème (chrome liquide en Argent)
    private var themedStyle: BubbleStyle {
        var s = style
        if theme == .gothic { s.metal = 1; s.colorGlow = 0; s.whiteGlow = 0 }
        return s
    }
    // Fillers are more transparent and almost colorless
    private var fillerStyle: BubbleStyle {
        var s = style
        s.coreAlpha = 0.18
        s.rimAlpha = 0.40
        s.colorGlow = 0.20
        if theme == .gothic { s.metal = 1; s.colorGlow = 0; s.whiteGlow = 0 }
        return s
    }

    // Fond partagé avec les hubs de catégorie (voir CategoryHub.swift) pour rester cohérent.
    private var background: some View { ThemedBubbleBackground(theme: theme) }
}

// MARK: - Éditeur de couleur d'une bulle

private struct CategoryColorSheet: View {
    let title: String
    @State private var color: Color
    let onSave: (Color) -> Void
    let onReset: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: Color, onSave: @escaping (Color) -> Void, onReset: (() -> Void)?) {
        self.title = title
        self._color = State(initialValue: initial)
        self.onSave = onSave
        self.onReset = onReset
    }

    private let presets: [Color] = [
        Color(hex: 0xFF3B30), Color(hex: 0xFF9500), Color(hex: 0xFFCC00), Color(hex: 0x34C759),
        Color(hex: 0x00C7BE), Color(hex: 0x30B0C7), Color(hex: 0x007AFF), Color(hex: 0x5856D6),
        Color(hex: 0xAF52DE), Color(hex: 0xFF2D92), Color(hex: 0xA2845E), Color(hex: 0x8E8E93)
    ]
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Circle()
                        .fill(color.gradient)
                        .frame(width: 78, height: 78)
                        .shadow(color: color.opacity(0.5), radius: 12)
                        .padding(.top, 10)

                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(Array(presets.enumerated()), id: \.offset) { _, c in
                            Button { color = c; Haptics.soft() } label: {
                                Circle().fill(c)
                                    .frame(height: 40)
                                    .overlay(Circle().stroke(.white, lineWidth: color.hexString == c.hexString ? 3 : 0))
                                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ColorPicker("Couleur sur mesure", selection: $color, supportsOpacity: false)
                        .font(.subheadline.weight(.medium))

                    if let onReset {
                        Button(role: .destructive) { onReset(); dismiss() } label: {
                            Label("Rétablir la couleur d'origine", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("OK") { onSave(color); dismiss() } }
            }
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
