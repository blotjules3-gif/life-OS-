#if DEBUG
import SwiftUI

/// Banc d'essai des materiaux, en DEBUG uniquement (absent des builds Release).
///
/// Il existe pour une raison precise : on ne peut pas juger un materiau adaptatif en
/// lisant du code. `glassEffect` rend differemment selon l'OS, le fond, les reglages
/// d'accessibilite et la plateforme. Ce banc met les variantes cote a cote, au meme
/// format, sur le meme fond, et affiche quelle BRANCHE est reellement prise.
///
/// Lancement : argument `-glassGallery`.
struct GlassGallery: View {
    enum Backdrop: String, CaseIterable, Identifiable {
        case white = "blanc", grey = "gris clair", content = "contenu (diagnostic)"
        var id: String { rawValue }
    }
    /// Pilotable au lancement : le simulateur ne sait pas cliquer sur le selecteur.
    @State private var backdrop: Backdrop = {
        let a = ProcessInfo.processInfo.arguments
        if a.contains("-bgWhite") { return .white }
        if a.contains("-bgContent") { return .content }
        return .grey
    }()
    @State private var phase: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        ZStack {
            backdropView.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    diagnostics
                    Picker("Fond", selection: $backdrop) {
                        ForEach(Backdrop.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    group("1. style natif .glass") {
                        NativeGlassButton(title: "Nouvelle tâche")
                    }
                    group("2. bouton nu + verre interactif natif") {
                        Button("Nouvelle tâche") {}
                            .buttonStyle(.plain)
                            .padding(.horizontal, 22).frame(height: 52)
                            .interactiveGlassIfAvailable()
                    }
                    group("3. composant partage de l'app") {
                        Text("Nouvelle tâche")
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .raisedSurface(Capsule(), .raised)
                    }
                    group("4. panneau verre regular, sans teinte") {
                        Text("Panneau d'information")
                            .frame(maxWidth: .infinity).frame(height: 92)
                            .raisedSurface(RoundedRectangle(cornerRadius: 26, style: .continuous), .floating)
                    }
                    group("5. verre clear (diagnostic seulement)") {
                        Text("Comparaison clear")
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .clearGlassIfAvailable()
                    }
                    group("6. imbrication : carte > tuile > bouton") {
                        VStack(spacing: 12) {
                            Text("Carte exterieure").font(.system(size: 13, weight: .semibold))
                            VStack(spacing: 10) {
                                Text("Tuile interieure").font(.system(size: 12))
                                Text("Bouton")
                                    .padding(.horizontal, 18).frame(height: 38)
                                    .raisedSurface(Capsule(), .nested)
                            }
                            .padding(12)
                            .raisedSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), .nested)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .raisedSurface(RoundedRectangle(cornerRadius: 26, style: .continuous), .floating)
                    }
                }
                .padding(18)
                .padding(.bottom, 60)
            }
        }
        .foregroundStyle(.primary)
    }

    /// Ce bloc est le but du banc : savoir ce qui tourne VRAIMENT, pas ce qu'on croit.
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DIAGNOSTIC").font(.system(size: 10, weight: .bold)).kerning(1)
            Text(Self.osLine).font(.system(size: 12, design: .monospaced))
            Text("branche surface: \(Self.surfaceBranch)").font(.system(size: 12, design: .monospaced))
            Text("reduceTransparency: \(reduceTransparency ? "OUI" : "non")  ·  reduceMotion: \(reduceMotion ? "OUI" : "non")")
                .font(.system(size: 12, design: .monospaced))
            Text("colorScheme: \(colorScheme == .dark ? "sombre" : "clair")  ·  bold text: \(legibilityWeight == .bold ? "OUI" : "non")")
                .font(.system(size: 12, design: .monospaced))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    static var osLine: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "OS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    /// Reproduit la condition exacte de `RaisedSurface`.
    static var surfaceBranch: String {
        if UIAccessibility.isReduceTransparencyEnabled { return "REPLI (reduce transparency)" }
        if #available(iOS 26.0, macCatalyst 26.0, *) { return "VERRE NATIF glassEffect" }
        return "REPLI (.ultraThinMaterial + filet 0.5pt + ombre)"
    }

    @ViewBuilder private var backdropView: some View {
        switch backdrop {
        case .white: Color.white
        case .grey:  Theme.bg
        case .content:
            ZStack {
                Theme.bg
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(0..<30, id: \.self) { i in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill([Color.red, .blue, .green, .orange, .purple][i % 5])
                                .frame(width: 60, height: 30)
                            Text("Contenu \(i) sous le materiau").font(.system(size: 16))
                        }
                    }
                }
                .padding()
                .offset(y: reduceMotion ? 0 : phase)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) { phase = -160 }
                }
            }
        }
    }

    @ViewBuilder private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            c()
        }
    }
}

// MARK: - Ponts de disponibilite (le banc doit compiler sous iOS 17)

/// Vrai `.buttonStyle(.glass)` quand l'OS le propose. Pas de faux-semblant : sous iOS 26
/// le banc afficherait autrement un bouton ordinaire en pretendant tester le style natif.
private struct NativeGlassButton: View {
    let title: String
    var body: some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            Button(title) {}.buttonStyle(.glass)
        } else {
            Button(title) {}.buttonStyle(.bordered)
        }
    }
}
private extension View {
    @ViewBuilder func interactiveGlassIfAvailable() -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else { background(.ultraThinMaterial, in: Capsule()) }
    }
    @ViewBuilder func clearGlassIfAvailable() -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            glassEffect(.clear, in: .capsule)
        } else { background(.thinMaterial, in: Capsule()) }
    }
}
#endif
