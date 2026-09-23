//
//  CategoryHub.swift
//
//  Hub de catégorie DATA-DRIVEN : les outils d'un pôle sont décrits en données
//  (CategoryTool) puis rendus dans le MÊME mode d'affichage que la grille de
//  catégories (bulles libres / bulles rangées / icônes / liste), piloté par le
//  même @AppStorage(AppStorageKeys.catLayout). Ouvrir une catégorie reprend donc le visuel actif.
//
//  Aucun module n'est modifié : on référence simplement leurs vues détail.
//

import SwiftUI

// MARK: - Modèle d'outil

struct CategoryTool: Identifiable, Hashable {
    let id = UUID()
    let icon: String
    /// Nom ecrit dans le code. Le nom affiche vient de Notion s'il existe.
    let defaultTitle: String
    var title: String { ToolNames.name(for: alias) ?? defaultTitle }
    var subtitle: String = ""
    /// Nom descriptif d'origine ("Langues", "Medicaments"). Les outils portent
    /// maintenant un nom proche de l'app qu'ils remplacent ("Trilingo" pour
    /// Duolingo); celui-ci reste cherchable pour qui tape ce qu'il veut faire.
    var alias: String = ""
    var tint: Color = Theme.accent
    var fullScreen: Bool = false        // true = présenté en plein écran (cache la barre LifeOS)
    let dest: () -> AnyView

    init<V: View>(_ icon: String, _ title: String, _ subtitle: String = "",
                  alias: String = "",
                  tint: Color = Theme.accent, fullScreen: Bool = false,
                  @ViewBuilder dest: @escaping () -> V) {
        self.icon = icon; self.defaultTitle = title; self.subtitle = subtitle; self.alias = alias
        self.tint = tint; self.fullScreen = fullScreen
        self.dest = { AnyView(dest()) }
    }

    static func == (l: CategoryTool, r: CategoryTool) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Fond thématique partagé (extrait de BubbleCategoriesView pour cohérence)

struct ThemedBubbleBackground: View {
    let theme: AppTheme
    var body: some View {
        let cols = theme.bubbleBG
        ZStack {
            if theme.isNike {
                // NIKE : aplat + grille technique fine (motif Swiss).
                cols[0]
                TechGrid(spacing: 46)
            } else if theme.isGlass {
                // VERRE : fond d'écran doux et flou, wallpaper unique de toute l'app.
                GlassBackdrop()
            } else if theme == .gothic {
                Color(hex: 0x050506)
                RadialGradient(colors: [.clear, Color.black.opacity(0.7)],
                               center: .center, startRadius: 60, endRadius: 520)
            } else if #available(iOS 18.0, *) {
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
}

// MARK: - Taille des bulles (réglable, partagée grille + sous-catégories)

enum BubbleSize: String, CaseIterable {
    case small, medium, large
    var factor: CGFloat { self == .small ? 0.80 : (self == .large ? 1.22 : 1.0) }
    // Diamètre absolu (fraction de la largeur d'écran) pour la grille de catégories :
    // 3 tailles NETTES. Petite/Moyenne/Grande — rien entre les deux.
    var widthFraction: CGFloat { self == .small ? 0.255 : (self == .large ? 0.405 : 0.315) }
    var rank: Double { self == .small ? 0 : (self == .large ? 2 : 1) }
    var label: String { self == .small ? "Petite" : (self == .large ? "Grande" : "Moyenne") }
    var symbol: String { self == .small ? "circle" : (self == .large ? "circle.fill" : "circle.lefthalf.filled") }
    var next: BubbleSize { self == .small ? .medium : (self == .medium ? .large : .small) }
}

// MARK: - Hub générique : rend les outils dans le mode d'affichage actif

struct CategoryHubView: View {
    let category: AppCategory
    /// Observe pour redessiner quand des noms arrivent de Notion.
    @AppStorage(ToolNames.storageKey) private var toolNamesRaw = ""

    // Les sous-catégories sont verrouillées en bulles libres (voir `layout`).
    @AppStorage(AppStorageKeys.appTheme)   private var appThemeRaw = "classic"
    @AppStorage(AppStorageKeys.bubbleSize) private var bubbleSizeRaw = "medium"
    @State private var cover: CategoryTool?
    @State private var showSetup = false

    // Les sous-catégories restent TOUJOURS en bulles libres (choix verrouillé).
    private var layout: CatLayout { .organic }
    private var theme: AppTheme   { AppTheme(rawValue: appThemeRaw) ?? .classic }
    private var tools: [CategoryTool] { category.tools }
    private var sizeFactor: CGFloat { BubbleSize(rawValue: bubbleSizeRaw)?.factor ?? 1.0 }

    var body: some View {
        content
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(layout == .list ? .large : .inline)
            .fullScreenCover(item: $cover) { $0.dest() }
            .toolbar {
                if CategorySetup.hasFlow(category) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSetup = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Réglages du module")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fullScreenCover(isPresented: $showSetup) { setupFlow }
            .onAppear {
                if CategorySetup.shouldAutoPrompt(category) {
                    CategorySetup.markPrompted(category)
                    showSetup = true
                }
            }
    }

    @ViewBuilder private var setupFlow: some View {
        CategoryFlowView(category: category)
    }

    @ViewBuilder private var content: some View {
        dashboardLayout
    }

    // MARK: - Dashboard Layout

    private var dashboardLayout: some View {
        ZStack {
            ThemedBubbleBackground(theme: theme).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    categoryHeader

                    CategoryRecapCard(category: category)

                    shortcutsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
    }

    private var categoryHeader: some View {
        HStack(spacing: 16) {
            IconBadge(icon: category.icon, tint: category.tint, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("\(tools.count) module\(tools.count > 1 ? "s" : "") & raccourcis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Raccourcis & Outils")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(tools.count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(category.tint.opacity(0.15))
                    .foregroundStyle(category.tint)
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(tools) { tool in
                    toolLink(tool) {
                        dashboardToolCard(tool)
                    }
                }
            }
        }
    }

    private func dashboardToolCard(_ tool: CategoryTool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(icon: tool.icon, tint: themedTint(tool), size: 36)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if !tool.subtitle.isEmpty {
                    Text(tool.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // Navigation : push normal, ou plein écran pour les outils fullScreen.
    @ViewBuilder
    private func toolLink<L: View>(_ tool: CategoryTool, @ViewBuilder label: () -> L) -> some View {
        if tool.fullScreen {
            Button { Haptics.soft(); cover = tool } label: { label() }.buttonStyle(PressableButtonStyle())
        } else {
            NavigationLink { tool.dest().floatingBarClearance() } label: { label() }.buttonStyle(PressableButtonStyle())
        }
    }

    // ===== Mode Liste (rendu natif identique à l'ancien hub) =====
    private var listLayout: some View {
        List {
            ForEach(tools) { tool in
                if tool.fullScreen {
                    Button { Haptics.soft(); cover = tool } label: { rowLabel(tool, chevron: true) }
                        .buttonStyle(.plain)
                } else {
                    NavigationLink { tool.dest().floatingBarClearance() } label: { rowLabel(tool, chevron: false) }
                }
            }
        }
    }

    private func rowLabel(_ tool: CategoryTool, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            IconBadge(icon: tool.icon, tint: themedTint(tool), size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title).font(.body).foregroundStyle(.primary)
                if !tool.subtitle.isEmpty {
                    Text(tool.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            if chevron {
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // ===== Mode Icônes =====
    private var iconGrid: some View {
        ZStack {
            ThemedBubbleBackground(theme: theme).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 22) {
                    ForEach(tools) { tool in
                        toolLink(tool) {
                            VStack(spacing: 9) {
                                IconBadge(icon: tool.icon, tint: themedTint(tool), size: 66)
                                Text(tool.title)
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
                                    .frame(height: 30, alignment: .top)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 120)
            }
        }
    }

    // ===== Modes Bulles (libres / rangées) =====
    @ViewBuilder
    private func bubbleCluster(tidy: Bool) -> some View {
        ZStack {
            ThemedBubbleBackground(theme: theme).ignoresSafeArea()
            GeometryReader { geo in
                if tidy { tidyGrid(geo) } else { organicCluster(geo) }
            }
        }
    }

    // ≤6 outils → cercle/anneau centré (sobre, tient sur un écran, pas de scroll).
    // >6 outils → quinconce vertical à GROSSES bulles (taille du cas à 5), scrollable :
    // on ne rapetisse PAS les bulles, on défile.
    @ViewBuilder
    private func organicCluster(_ geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let availH = geo.size.height
        if tools.count <= 6 {
            let placed = ringLayout(count: tools.count, w: w, availH: availH)
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { i, tool in
                        let p = placed.indices.contains(i) ? placed[i] : (CGPoint(x: w/2, y: availH/2), 60.0)
                        let bobx = CGFloat(sin(t * 0.5 + Double(i) * 1.3)) * 2
                        let boby = CGFloat(cos(t * 0.42 + Double(i) * 1.1)) * 2
                        toolLink(tool) {
                            toolBubble(tool, diameter: p.1, index: i, base: p.1, t: t)
                        }
                        .position(x: p.0.x + bobx, y: p.0.y + boby)
                    }
                }
                .frame(width: w, height: availH)
            }
        } else {
            let (placed, contentH) = honeycombLayout(count: tools.count, w: w, availH: availH)
            ScrollView(showsIndicators: false) {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(tools.enumerated()), id: \.element.id) { i, tool in
                            let p = placed.indices.contains(i) ? placed[i] : (CGPoint(x: w/2, y: 60), 60.0)
                            let bobx = CGFloat(sin(t * 0.5 + Double(i) * 1.3)) * 2
                            let boby = CGFloat(cos(t * 0.42 + Double(i) * 1.1)) * 2
                            toolLink(tool) {
                                toolBubble(tool, diameter: p.1, index: i, base: p.1, t: t)
                            }
                            .position(x: p.0.x + bobx, y: p.0.y + boby)
                        }
                    }
                    .frame(width: w, height: contentH)
                }
            }
        }
    }

    // Quinconce vertical (rangées 3,2,3,2…) à GROSSES bulles fixes, centré, scrollable.
    private func honeycombLayout(count: Int, w: CGFloat, availH: CGFloat) -> ([(CGPoint, CGFloat)], CGFloat) {
        let n = max(count, 1)
        let side: CGFloat = 14
        let gap: CGFloat = 14
        let d = max((w - side * 2 - gap * 2) / 3, 80) * sizeFactor   // 3 par rangée = grosses bulles

        // Rangées en quinconce 3,2,3,2… puis rééquilibrage si la dernière est seule.
        var rows: [Int] = []
        var rem = n
        var big = true
        while rem > 0 { let c = min(big ? 3 : 2, rem); rows.append(c); rem -= c; big.toggle() }
        if rows.count >= 2, rows[rows.count - 1] == 1 {
            rows[rows.count - 2] -= 1; rows[rows.count - 1] = 2
        }

        let rowH = d + gap * 0.5
        var result: [(CGPoint, CGFloat)] = []
        var y = d / 2 + 18
        for c in rows {
            let rowW = CGFloat(c) * d + CGFloat(c - 1) * gap
            let startX = (w - rowW) / 2
            for col in 0..<c {
                let x = startX + CGFloat(col) * (d + gap) + d / 2
                result.append((CGPoint(x: x, y: y), d))
            }
            y += rowH
        }
        let contentH = max(availH, y + d / 2 + 130)   // +130 = dégage la barre d'onglets flottante
        return (result, contentH)
    }

    // Calcule centre + diamètre de chaque outil en anneaux concentriques, puis met le
    // tout à l'échelle pour tenir (centré) dans l'espace dispo. Renvoie [(centre, d)].
    private func ringLayout(count: Int, w: CGFloat, availH: CGFloat) -> [(CGPoint, CGFloat)] {
        let n = max(count, 1)
        let gap: CGFloat = 12
        // On part d'un GRAND diamètre ; l'auto-échelle (étape 3) le réduit juste ce qu'il
        // faut pour que le cluster tienne. Peu d'outils = grosses bulles qui remplissent.
        var d = w * 0.42 * sizeFactor

        // 1) Répartition en anneaux : ≤6 = un seul cercle ; sinon centre + anneaux (6,12,18…).
        var hasCenter = false
        var ringCounts: [Int] = []
        if n == 1 {
            hasCenter = true
        } else if n <= 6 {
            ringCounts = [n]
        } else {
            hasCenter = true
            var rem = n - 1
            for cap in [6, 12, 18, 24] {
                if rem <= 0 { break }
                let take = min(cap, rem); ringCounts.append(take); rem -= take
            }
        }

        // 2) Rayon de chaque anneau : tient compte de l'écart sur l'anneau ET de la
        //    séparation radiale avec l'anneau précédent (zéro chevauchement).
        func radii(for dd: CGFloat) -> [CGFloat] {
            var rs: [CGFloat] = []
            var prev: CGFloat = 0
            for (m, k) in ringCounts.enumerated() {
                let chordR = k > 1 ? (dd + gap) / (2 * CGFloat(sin(Double.pi / Double(k)))) : 0
                let radialMin = (hasCenter || m > 0) ? prev + dd + gap : chordR
                let R = max(chordR, radialMin)
                rs.append(R); prev = R
            }
            return rs
        }

        // 3) Mise à l'échelle pour que le cluster entier tienne dans le cercle dispo.
        let maxRadius = min(w, availH) * 0.5 * 0.92
        var rs = radii(for: d)
        let outer = (rs.last ?? 0) + d / 2
        if outer > maxRadius {
            let s = maxRadius / outer
            d *= s
            rs = rs.map { $0 * s }
        }

        // 4) Placement : centre + anneaux, légèrement remonté pour l'équilibre visuel.
        let cx = w / 2
        let cy = availH * 0.46
        var result: [(CGPoint, CGFloat)] = []
        var idx = 0
        if hasCenter {
            result.append((CGPoint(x: cx, y: cy), d)); idx += 1
        }
        for (m, k) in ringCounts.enumerated() {
            let R = rs[m]
            let phase = (m % 2 == 0 ? 0.0 : Double.pi / Double(max(k, 1))) - Double.pi / 2
            for j in 0..<k {
                let a = phase + 2 * Double.pi * Double(j) / Double(k)
                let x = cx + CGFloat(cos(a)) * R
                let y = cy + CGFloat(sin(a)) * R
                result.append((CGPoint(x: x, y: y), d))
                idx += 1
            }
        }
        return result
    }

    // Disposition rangée (mode "Bulles rangées").
    private func tidyGrid(_ geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let availH = geo.size.height
        let cols = tools.count <= 4 ? 2 : 3
        let rows = Int(ceil(Double(tools.count) / Double(cols)))
        let cellW = w / CGFloat(cols)
        let d = cellW * 0.84 * sizeFactor
        let rowH = cellW * 1.02
        let blockH = CGFloat(rows) * rowH
        let contentH = max(availH, blockH + 110)
        let startY = max(30, (contentH - blockH) / 2 - 24)

        return ScrollView(showsIndicators: false) {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { i, tool in
                        let x = (CGFloat(i % cols) + 0.5) * cellW
                        let y = startY + (CGFloat(i / cols) + 0.5) * rowH
                        toolLink(tool) {
                            toolBubble(tool, diameter: d, index: i, base: cellW * 0.84, t: t)
                        }
                        .position(x: x, y: y)
                    }
                }
                .frame(width: w, height: contentH)
            }
            .frame(width: w, height: contentH)
        }
    }

    @ViewBuilder
    private func toolBubble(_ tool: CategoryTool, diameter d: CGFloat, index i: Int, base: CGFloat, t: Double) -> some View {
        if theme == .gothic {
            ChromeCategoryButton(
                title: tool.title,
                sfSymbolName: tool.icon,
                assetName: ChromeCategoryButton.asset(for: d, base: base, index: i),
                size: d,
                showLabel: true,
                pressed: false,
                time: t,
                phase: Double(i) * 1.7
            )
        } else {
            BubbleView(
                title: tool.title,
                systemImage: tool.icon,
                tint: bubbleTint(tool),
                diameter: d,
                showLabel: true,
                time: t,
                seed: Double(i) * 2.1,
                style: bubbleStyle
            )
        }
    }

    private var bubbleStyle: BubbleStyle {
        var s = BubbleStyle()
        if theme == .gothic { s.metal = 1; s.colorGlow = 0; s.whiteGlow = 0 }
        return s
    }

    // Teinte selon le thème (même logique que la grille de catégories).
    /// Couleur de la BULLE des sous-categories: noire, glyphe blanc dessus.
    ///
    /// Separee de themedTint volontairement. themedTint habille les petites
    /// pastilles des modes liste et icones, ou la couleur sert a distinguer
    /// les outils d'un coup d'oeil. Les grosses bulles, elles, sont deja
    /// distinguees par leur glyphe et leur libelle: les teinter en plus donnait
    /// un patchwork. Le noir fait ressortir le fond du theme.
    ///
    /// Les themes decoratifs gardent leur palette, c'est tout leur interet.
    private func bubbleTint(_ tool: CategoryTool) -> Color {
        switch theme {
        case .system, .classic, .dark, .volt, .glass: return Color(hex: 0x0E0E11)
        case .pinky, .gothic, .cloud:                 return themedTint(tool)
        }
    }

    private func themedTint(_ tool: CategoryTool) -> Color {
        switch theme {
        case .system, .classic, .dark, .volt, .glass: return tool.tint
        case .pinky:  return [Color(hex: 0xFF4F9D), Color(hex: 0xFF77B5), Color(hex: 0xF06EA9),
                              Color(hex: 0xFF8AC4), Color(hex: 0xE85C9E)][stableIndex(tool) % 5]
        case .gothic: return [Color(hex: 0xAEB7C4), Color(hex: 0xC6CED9), Color(hex: 0x99A3B2),
                              Color(hex: 0xD2D8E1), Color(hex: 0xB4BCC8)][stableIndex(tool) % 5]
        case .cloud:  return [Color(hex: 0xC3D2E8), Color(hex: 0xD2DEEE), Color(hex: 0xB7C8E2),
                              Color(hex: 0xCBD8EC), Color(hex: 0xDCE5F2)][stableIndex(tool) % 5]
        }
    }
    private func stableIndex(_ tool: CategoryTool) -> Int { tools.firstIndex(of: tool) ?? 0 }
}

// MARK: - Données : outils par catégorie (référencent les vues détail des modules)

extension AppCategory {
    var tools: [CategoryTool] {
        switch self {
        case .sleep:        return sleepTools
        case .nutrition:    return nutritionTools
        case .fitness:      return fitnessTools
        case .looks:        return looksTools
        case .mind:         return mindTools
        case .productivity: return productivityTools
        case .finance:      return financeTools
        case .invest:       return investTools
        case .career:       return careerTools
        case .learning:     return learningTools
        case .home:         return homeTools
        case .mobility:     return mobilityTools
        case .social:       return socialTools
        case .admin:        return adminTools
        case .travel:       return travelTools
        case .cycle:        return cycleTools
        case .medical:      return medicalTools
        }
    }
}

private let medicalTools: [CategoryTool] = [
    // Pointait sur MedicalHubView: toucher "Médicaments" ouvrait un second
    // menu contenant... Médicaments, plus les trois outils deja listes juste
    // en dessous. La liste des traitements etait donc a un cran de plus que
    // tout le reste de la categorie, et le sous-titre mentait.
    .init("pills.fill", "MediSûr", "Traitements en cours et rappels", alias: "Médicaments",  tint: .init(hex: 0xE84C4C)) { MedicationView() },
    .init("stethoscope", "Doctolink", "Agenda médical et suivi", alias: "Rendez-vous",          tint: .init(hex: 0xE84C4C)) { AppointmentsView() },
    .init("waveform.path.ecg", "Maple Health", "Poids, tension, glycémie…", alias: "Carnet de santé",        tint: .init(hex: 0xE84C4C)) { VitalsView() },
    .init("syringe.fill", "Mon Espace Vaccin", "Historique et rappels", alias: "Vaccinations",            tint: .init(hex: 0xE84C4C)) { VaccinationView() },
]

private let cycleTools: [CategoryTool] = [
    .init("calendar.badge.clock", "Floé", "Règles · durée · prédiction", alias: "Suivi du cycle", tint: .cycleTint) { CycleTrackerView() },
    .init("waveform.path.ecg", "Klue", "Crampes, humeur, énergie, peau", alias: "Symptômes", tint: .cycleTint) { CycleSymptomsView() },
    .init("chart.bar.fill", "Floé Stats", "Régularité · durée moyenne", alias: "Historique", tint: .cycleTint) { CycleHistoryView() },
]

private let sleepTools: [CategoryTool] = [
    .init("bed.double.fill", "Sleep Circle", "Cycles de 90 min · réveil léger", alias: "Heure de coucher optimale", tint: .sleepTint) { BedtimeCalculatorView() },
    .init("powersleep", "Pzazz", "Sieste calibrée 20 ou 90 min", alias: "Power nap", tint: .sleepTint) { PowerNapView() },
    .init("moon.zzz.fill", "Rize", "Rappel + lumière bleue + mode nuit", alias: "Coucher progressif", tint: .sleepTint) { WindDownView() },
    .init("cloud.moon.fill", "Awaken", "Note vocale + texte + humeur", alias: "Journal de rêves", tint: .sleepTint) { DreamJournalView() },
    .init("heart.text.square.fill", "Whoosh", "HRV + FC repos (Apple Santé)", alias: "Score de récupération", tint: .sleepTint) { RecoveryScoreView() },
]

private let nutritionTools: [CategoryTool] = [
    .init("timer", "Zerø", "16:8, 18:6, OMAD — façon Zero", alias: "Jeûne intermittent", tint: .nutriTint) { FastingView() },
    .init("chart.pie.fill", "Yumzio", "Journal du jour + objectifs", alias: "Calories & macros", tint: .nutriTint) { CalAIView() },
    .init("refrigerator.fill", "Fridgy", "Inventaire + idées repas", alias: "Mon frigo", tint: .nutriTint) { FridgeView() },
    .init("cart.fill", "Bringo", "Par rayon, cochable", alias: "Liste de courses", tint: .nutriTint) { ShoppingListView() },
    .init("drop.fill", "WaterMind", "Suivi + rappels", alias: "Hydratation", tint: .nutriTint) { HydrationView() },
    .init("pills.fill", "SuppSafe", "Rappels personnalisés", alias: "Compléments", tint: .nutriTint) { SupplementsView() },
    .init("allergens", "Figue", "Halal, vegan, sans gluten…", alias: "Allergènes & régimes", tint: .nutriTint) { DietProfileView() },
    .init("camera.viewfinder", "Cal Eye", "Caméra + estimation on-device", alias: "Calories par photo", tint: .nutriTint) { PhotoCalorieView() },
    .init("barcode.viewfinder", "Yuko", "Yuka + prix + alternative", alias: "Scan code-barres santé", tint: .nutriTint) { ScanProductView() },
]

private let fitnessTools: [CategoryTool] = [
    .init("calendar", "Fitbot", "Ta semaine + rappels muscu", alias: "Programme de sport", tint: .fitTint) { GymProgramView() },
    .init("figure.walk", "Stepometer", "Aujourd'hui + 7 jours (Santé)", alias: "Compteur de pas", tint: .fitTint) { StepsView() },
    .init("dumbbell.fill", "Hevvy", "Charges, volume, 1RM, courbe", alias: "Muscu & progression", tint: .fitTint) { StrengthView() },
    .init("timer", "TabaTime", "Minuteur sportif plein écran", alias: "HIIT / Tabata", tint: .fitTint, fullScreen: true) { TabataView() },
    .init("figure.cooldown", "GOMOB", "Routines guidées", alias: "Mobilité & stretching", tint: .fitTint) { MobilityRoutineView() },
    .init("flame.fill", "Streakz", "Régularité d'entraînement", alias: "Streaks & habitudes", tint: .fitTint) { StreaksView() },
]

private let looksTools: [CategoryTool] = [
    .init("face.dashed", "Umaxx", "Symétrie, tiers, ratios — Vision", alias: "Analyse faciale", tint: .looksTint) { FaceAnalysisView() },
    .init("infinity", "TrueSkin", "Matin/soir + rappels", alias: "Routine skincare", tint: .looksTint) { SkincareView() },
    .init("camera.fill", "Progrez", "Suivi visuel daté", alias: "Photos avant / après", tint: .looksTint) { ProgressPhotoGalleryView() },
    .init("mouth.fill", "Mewing Klub", "Rappels + minuteur", alias: "Mewing & posture", tint: .looksTint) { MewingPostureView() },
    .init("tshirt.fill", "Wearing", "Suggestion selon météo", alias: "Garde-robe & outfits", tint: .looksTint) { WardrobeView() },
]

private let mindTools: [CategoryTool] = [
    .init("wind", "Breathwerk", "Box breathing, 365…", alias: "Respiration & cohérence", tint: .mindTint) { BreathingView() },
    .init("leaf.fill", "Headplace", "Minuteur silencieux guidé", alias: "Méditation", tint: .mindTint) { MeditationView() },
    .init("water.waves", "Endlo", "Bruit blanc/rose/brun + minuteur", alias: "Sons relaxants", tint: .mindTint) { SoundscapeView() },
    .init("face.smiling.inverse", "Daylia", "Journal quotidien", alias: "Humeur & gratitude", tint: .mindTint) { MoodJournalView() },
    .init("hourglass", "Opale", "Usage & objectifs", alias: "Détox écran", tint: .mindTint) { ScreenDetoxView() },
    .init("sun.horizon.fill", "Fabuleux", "Motivation + ta journée", alias: "Briefing du matin", tint: .mindTint) { MorningBriefingView() },
]

private let productivityTools: [CategoryTool] = [
    .init("checklist", "Todoo", "Priorités, projets, échéances", alias: "To-do intelligente", tint: .prodTint) { TodoView() },
    .init("calendar.day.timeline.left", "Structurd", "L'app remplit ta journée", alias: "Time-blocking auto", tint: .prodTint) { TimeBlockView() },
    .init("square.grid.3x3.fill", "Habitly", "Streaks & régularité", alias: "Habit tracker", tint: .prodTint) { HabitTrackerView() },
    .init("timer", "Forêt", "25 min concentration", alias: "Focus / Pomodoro", tint: .prodTint) { FocusTimerView() },
    .init("note.text", "Notio", "Capture rapide + tags", alias: "Notes & second cerveau", tint: .prodTint) { NotesView() },
]

private let financeTools: [CategoryTool] = [
    .init("building.columns.fill", "Bankino", "Solde + transactions + alertes", alias: "Comptes & dépenses", tint: .finTint) { AccountsView() },
    .init("tray.2.fill", "Ynabi", "Catégorise et plafonne", alias: "Budget par enveloppes", tint: .finTint) { BudgetView() },
    .init("repeat.circle.fill", "Pocket Money", "Détecte les oubliés + résilie", alias: "Abonnements", tint: .finTint) { SubscriptionsView() },
    .init("person.2.circle.fill", "Quadricount", "Tricount intégré", alias: "Split entre potes", tint: .finTint) { SplitView() },
    .init("target", "Kapital", "Projection temps restant", alias: "Objectifs d'épargne", tint: .finTint) { SavingsView() },
    .init("link.circle.fill", "Linxa", "Tous tes comptes agrégés", alias: "Solde global", tint: .finTint) { BankOverviewView() },
]

private let investTools: [CategoryTool] = [
    .init("chart.pie.fill", "Finario", "Actions + crypto en un dashboard", alias: "Portefeuille", tint: .investTint) { PortfolioView() },
    .init("chart.line.uptrend.xyaxis", "Kubero", "Patrimoine + projection", alias: "Net worth & FIRE", tint: .investTint) { NetWorthView() },
    .init("house.fill", "Horizo", "Biens, loyers, cashflow", alias: "Immobilier", tint: .investTint) { RealEstateView() },
    .init("percent", "Impôts+", "Impôt sur le revenu (FR)", alias: "Simulateur fiscalité", tint: .investTint) { TaxSimulatorView() },
]

private let careerTools: [CategoryTool] = [
    .init("tray.full.fill", "Huntly", "Pipeline par statut", alias: "Suivi des candidatures", tint: .careerTint) { ApplicationsView() },
    .init("doc.text.fill", "Zetty", "Remplis → exporte", alias: "Générateur de CV", tint: .careerTint) { CVBuilderView() },
    .init("checklist.checked", "LinkedUp", "Gap + plan pour combler", alias: "Compétences manquantes", tint: .careerTint) { SkillGapView() },
    .init("mic.fill", "Yoodly", "Entraînement entretien", alias: "Mock interview", tint: .careerTint) { MockInterviewView() },
    .init("magnifyingglass", "Welcome to the Djob", "Offres réelles selon tes compétences", alias: "Matching d'offres", tint: .careerTint) { JobMatchView() },
]

private let learningTools: [CategoryTool] = [
    .init("character.bubble.fill", "Trilingo", "Vocabulaire en répétition espacée", alias: "Langues", tint: .learnTint) { LanguagesView() },
    .init("rectangle.on.rectangle.angled", "Anko", "Répétition espacée (SM-2)", alias: "Flashcards", tint: .learnTint) { FlashcardsView() },
    .init("lightbulb.max.fill", "Headwave", "Une pépite par jour", alias: "Micro-learning du jour", tint: .learnTint) { MicroLearningView() },
    .init("books.vertical.fill", "Blinklist", "Tes idées clés — Blinkist", alias: "Résumés de livres", tint: .learnTint) { BookSummariesView() },
    .init("chart.bar.fill", "Coursia", "Skill → jalons", alias: "Plan de montée en compétence", tint: .learnTint) { SkillPlanView() },
]

private let homeTools: [CategoryTool] = [
    .init("calendar.badge.exclamationmark", "NoGaspi", "Ce qui périme bientôt", alias: "Anti-gaspi & péremption", tint: .homeTint) { AntiWasteView() },
    .init("frying.pan.fill", "SuperCuisto", "Cuisine ce que tu as", alias: "Recettes avec les restes", tint: .homeTint) { LeftoverRecipesView() },
    .init("checklist", "Sweepo", "Réparties couple / coloc", alias: "Tâches ménagères", tint: .homeTint) { ChoresView() },
    .init("pawprint.fill", "12pets", "Gamelle, véto, vaccins", alias: "Mes animaux", tint: .homeTint) { PetsView() },
    .init("wrench.and.screwdriver.fill", "HomeZen", "Filtres, révisions, plantes", alias: "Maintenance récurrente", tint: .homeTint) { MaintenanceView() },
]

private let mobilityTools: [CategoryTool] = [
    .init("car.fill", "Fuelo", "Assurance, révision, carburant", alias: "Ma voiture", tint: .mobTint) { VehicleListView() },
    .init("leaf.arrow.circlepath", "CityMappr", "Empreinte + budget par mode", alias: "Trajets & CO₂", tint: .mobTint) { TripCO2View() },
    .init("parkingsign.circle.fill", "Park Maps", "Mémorise la place de ta voiture", alias: "Où ai-je garé ?", tint: .mobTint) { ParkingView() },
]

private let socialTools: [CategoryTool] = [
    .init("person.crop.circle.badge.clock", "Dexo", "Qui relancer", alias: "CRM personnel", tint: .socialTint) { CRMView() },
    .init("gift.fill", "Hipp", "Rappels + idées", alias: "Anniversaires & cadeaux", tint: .socialTint) { BirthdaysView() },
    .init("calendar.badge.plus", "Partyful", "Organise tes événements", alias: "Sorties & events", tint: .socialTint) { EventsView() },
]

private let adminTools: [CategoryTool] = [
    .init("lock.doc.fill", "Digicoffre", "ID, contrats, garanties", alias: "Coffre-fort documents", tint: .adminTint) { DocVaultView() },
    .init("bell.badge.fill", "Papernid", "Impôts, assurance, abos", alias: "Échéances", tint: .adminTint) { DeadlinesView() },
    .init("envelope.fill", "Lettre-Public", "Résiliation, attestation…", alias: "Générateur de courriers", tint: .adminTint) { LetterGeneratorView() },
    .init("doc.viewfinder.fill", "Adobo Scan", "OCR auto · range tout seul", alias: "Scan & classement", tint: .adminTint) { DocScanView() },
]

private let travelTools: [CategoryTool] = [
    .init("map.fill", "TripUp", "Itinéraire + budget + valise", alias: "Mes voyages", tint: .travelTint) { TripsView() },
    .init("coloncurrencysign.circle.fill", "Xchange", "12 devises, hors-ligne, repères rapides", alias: "Convertisseur", tint: .travelTint) { CurrencyConverterView() },
    .init("character.bubble.fill", "iTraduis", "5 langues, prononcées à voix haute", alias: "Phrases de voyage", tint: .travelTint) { PhrasebookView() },
    .init("globe", "Goggle Traduction", "12 langues, hors-ligne (Apple Translation)", alias: "Traduction", tint: .travelTint) { TranslationView() },
    .init("airplane.circle.fill", "Flighto", "Compte à rebours & statut", alias: "Suivi des vols", tint: .travelTint) { FlightTrackerView() },
]
