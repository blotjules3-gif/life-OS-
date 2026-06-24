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
    var coreAlpha: Double = 0.72
    /// Color presence at the rim (Fresnel film). Higher = bolder edge color.
    var rimAlpha: Double = 0.96
    /// Sharpness of the phong sparkle on the rim.
    var specStrength: Double = 1.0
    /// Outer colored bloom (neon glow of the bubble's own color).
    var colorGlow: Double = 0.55
    /// Outer soft white bloom.
    var whiteGlow: Double = 0.22
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
                        .shadow(color: .black.opacity(0.18), radius: diameter * 0.02)
                    if showLabel {
                        Text(title)
                            .font(.system(size: diameter * 0.12, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.22), radius: diameter * 0.02)
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
    // Base diameter = screenWidth * baseRatio, then * sizeMul per bubble.
    static let baseRatio: CGFloat = 0.30

    static let categories: [BubbleCategory] = [
        .init(title: "Documents",    systemImage: "folder.fill",               tint: .gray,   anchor: .init(x: 0.22, y: 0.17), sizeMul: 1.05),
        .init(title: "Travail",      systemImage: "briefcase.fill",            tint: .brown,  anchor: .init(x: 0.49, y: 0.20), sizeMul: 0.95),
        .init(title: "Social",       systemImage: "person.2.fill",             tint: .pink,   anchor: .init(x: 0.78, y: 0.24), sizeMul: 1.18),
        .init(title: "Finance",      systemImage: "creditcard.fill",           tint: .blue,   anchor: .init(x: 0.17, y: 0.41), sizeMul: 0.82),
        .init(title: "Mental",       systemImage: "brain.head.profile",        tint: .purple, anchor: .init(x: 0.44, y: 0.41), sizeMul: 1.12),
        .init(title: "Bien-être",    systemImage: "face.smiling",              tint: .orange, anchor: .init(x: 0.73, y: 0.46), sizeMul: 1.12),
        .init(title: "Éducation",    systemImage: "graduationcap.fill",        tint: .yellow, anchor: .init(x: 0.87, y: 0.60), sizeMul: 0.74),
        .init(title: "Bourse",       systemImage: "chart.line.uptrend.xyaxis", tint: .teal,   anchor: .init(x: 0.13, y: 0.61), sizeMul: 0.74),
        .init(title: "Sport",        systemImage: "figure.run",                tint: .red,    anchor: .init(x: 0.31, y: 0.64), sizeMul: 1.45),
        .init(title: "Alimentation", systemImage: "fork.knife",                tint: .green,  anchor: .init(x: 0.61, y: 0.66), sizeMul: 1.05),
        .init(title: "Sommeil",      systemImage: "moon.stars.fill",           tint: .indigo, anchor: .init(x: 0.84, y: 0.70), sizeMul: 0.92),
        .init(title: "Tâches",       systemImage: "checklist",                 tint: .cyan,   anchor: .init(x: 0.17, y: 0.80), sizeMul: 0.86),
        .init(title: "Voyage",       systemImage: "airplane",                  tint: .blue,   anchor: .init(x: 0.43, y: 0.88), sizeMul: 1.12),
        .init(title: "Maison",       systemImage: "house.fill",                tint: .blue,   anchor: .init(x: 0.67, y: 0.84), sizeMul: 0.84),
        .init(title: "Transports",   systemImage: "tram.fill",                 tint: .mint,   anchor: .init(x: 0.82, y: 0.90), sizeMul: 0.90),

        // Filler bubbles (no glyph, no label) to fill the gaps
        .init(title: "", systemImage: "", tint: .blue,   anchor: .init(x: 0.55, y: 0.31), sizeMul: 0.22, isFiller: true),
        .init(title: "", systemImage: "", tint: .pink,   anchor: .init(x: 0.30, y: 0.50), sizeMul: 0.18, isFiller: true),
        .init(title: "", systemImage: "", tint: .purple, anchor: .init(x: 0.70, y: 0.58), sizeMul: 0.16, isFiller: true),
        .init(title: "", systemImage: "", tint: .green,  anchor: .init(x: 0.50, y: 0.76), sizeMul: 0.20, isFiller: true),
        .init(title: "", systemImage: "", tint: .teal,   anchor: .init(x: 0.27, y: 0.69), sizeMul: 0.15, isFiller: true),
        .init(title: "", systemImage: "", tint: .indigo, anchor: .init(x: 0.93, y: 0.46), sizeMul: 0.17, isFiller: true),
    ]
}

// MARK: - The screen (+ features LifeOS : édition, drag, compteur d'usage)

struct BubbleCategoriesView: View {
    var onSelect: (String) -> Void = { print("tapped \($0)") }
    var style: BubbleStyle = BubbleStyle()

    @AppStorage("bubbleWeights") private var weightsRaw = ""   // compteur d'usage  "titre:count,…"
    @AppStorage("hiddenCats")    private var hiddenRaw = ""    // bulles retirées (par titre)
    @State private var editing = false
    @State private var showAdd = false
    @State private var tappedID: UUID?
    @State private var drag: [UUID: CGSize] = [:]

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }
    private var visible: [BubbleCategory] {
        BubbleLayout.categories.filter { $0.isFiller || !hidden.contains($0.title) }
    }
    private var hiddenList: [BubbleCategory] {
        BubbleLayout.categories.filter { !$0.isFiller && hidden.contains($0.title) }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let base = w * BubbleLayout.baseRatio

            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    background.ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { if editing { setEditing(false) } }
                        .gesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in setEditing(true) })

                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, cat in
                        bubble(cat, index: index, base: base, w: w, h: h, t: t)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) { editButton }
        .overlay(alignment: .bottomTrailing) { if editing { addButton } }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    // Une bulle : compteur d'usage (taille), bob, drag + tap, badge − en édition.
    private func bubble(_ cat: BubbleCategory, index: Int, base: CGFloat, w: CGFloat, h: CGFloat, t: Double) -> some View {
        let grow = cat.isFiller ? 1.0 : growth(cat.title)
        let d = base * cat.sizeMul * grow
        let phase = Double(index) * 1.37
        let amp: Double = cat.isFiller ? 6 : 4
        let dv = drag[cat.id] ?? .zero
        let moving = dv != .zero
        let bx = (moving ? 0 : sin(t * 0.5 + phase) * amp) + dv.width
        let by = (moving ? 0 : cos(t * 0.42 + phase * 1.3) * amp) + dv.height
        let wig: Double = (editing && !cat.isFiller) ? sin(t * 7 + phase) * 2.0 : 0

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
        .position(x: cat.anchor.x * w + bx, y: cat.anchor.y * h + by)
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

    // Fillers are more transparent and almost colorless
    private var fillerStyle: BubbleStyle {
        var s = style
        s.coreAlpha = 0.18
        s.rimAlpha = 0.40
        s.colorGlow = 0.20
        return s
    }

    @ViewBuilder private var background: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    Color(red: 0.86, green: 0.93, blue: 0.99), Color(red: 0.95, green: 0.95, blue: 0.99), Color(red: 0.99, green: 0.92, blue: 0.95),
                    Color(red: 0.90, green: 0.96, blue: 0.97), Color.white,                                Color(red: 0.97, green: 0.93, blue: 0.99),
                    Color(red: 0.88, green: 0.93, blue: 0.99), Color(red: 0.92, green: 0.95, blue: 0.99), Color(red: 0.90, green: 0.94, blue: 0.98)
                ]
            )
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.94, blue: 0.99),
                    Color.white,
                    Color(red: 0.95, green: 0.93, blue: 0.99)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
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
