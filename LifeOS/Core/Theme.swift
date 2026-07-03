import SwiftUI
import UIKit

/// Design system de LifeOS — langage NIKE : noir & blanc haute intensité, accent VOLT,
/// coins nets, typographie grasse/majuscule, labels techniques monospace, grilles.
enum Theme {
    // Surfaces système adaptatives (bright = blanc cassé / dark = noir pur — voir AppTheme.bubbleBG).
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let bg2 = Color(uiColor: .tertiarySystemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let stroke = Color.primary.opacity(0.16)
    static let textPrimary = Color.primary
    // UIColor.secondaryLabel meets ≥3:1 on system backgrounds in both light and dark
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary  = Color(uiColor: .tertiaryLabel)
    static let accent = Color.accentColor

    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 11
    static let pad: CGFloat = 16
    static let padWide: CGFloat = 28   // onboarding / large content areas

    // MARK: - Système typographique (Dynamic Type — scales avec les préférences d'accessibilité)
    static let fontDisplay   = Font.system(size: 46, weight: .bold, design: .rounded)
    static let fontHero      = Font.system(size: 36, weight: .semibold, design: .rounded)
    static let fontTitle     = Font.title.bold()
    static let fontTitle2    = Font.title2.bold()
    static let fontTitle3    = Font.title3.bold()
    static let fontHeadline  = Font.headline
    static let fontBody      = Font.body
    static let fontCallout   = Font.callout
    static let fontSub       = Font.subheadline
    static let fontFootnote  = Font.footnote
    static let fontCaption   = Font.caption
    static let fontCaption2  = Font.caption2

    // MARK: - Palette sémantique (remplace les Color(hex:) éparpillés)

    // Catégories de modules
    static let fitness      = Color(hex: 0xF1746C)   // sport, calories
    static let nutrition    = Color(hex: 0x4CC38A)   // alimentation, objectifs verts
    static let hydration    = Color(hex: 0x3CB2E0)   // eau, hydratation
    static let sleep        = Color(hex: 0x6C7BF1)   // sommeil, repos
    static let mind         = Color(hex: 0x9B6CF1)   // méditation, mental
    static let energy       = Color(hex: 0xE0A23C)   // énergie, amber
    static let finance      = Color(hex: 0x4CC38A)   // finance (vert = croissance)
    static let invest       = Color(hex: 0x46C9A8)   // investissement
    static let career       = Color(hex: 0xE07B3C)   // carrière, orange
    static let looks        = Color(hex: 0xE0A23C)   // beauté, skincare (amber)
    static let productivity = Color(hex: 0x3CB2E0)   // productivité, tâches
    static let learning     = Color(hex: 0xF97316)   // apprentissage, orange vif
    static let home         = Color(hex: 0x6CA0F1)   // maison
    static let social       = Color(hex: 0xF16CB0)   // social, relations
    static let admin        = Color(hex: 0x8A93A8)   // admin, neutre
    static let mobility     = Color(hex: 0x3CD0C8)   // transport, teal
    static let travel       = Color(hex: 0x6C9BF1)   // voyage
    static let cycle        = Color(hex: 0xE85D9A)   // cycle menstruel
    static let medical      = Color(hex: 0xE84C4C)   // santé médicale

    // Statuts
    static let success    = Color(hex: 0x4CC38A)   // validé, objectif atteint
    static let warning    = Color(hex: 0xE0A23C)   // attention, moyen
    static let danger     = Color(hex: 0xF1746C)   // risque élevé, danger
    static let tealDark   = Color(hex: 0x008F6C)   // potentiel fort (scores crypto)

    // MARK: - Grille d'espacement 8pt
    static let space2: CGFloat  = 2
    static let space4: CGFloat  = 4
    static let space8: CGFloat  = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16  // = pad
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space48: CGFloat = 48

    // Accent signature = le vert de l'icône de l'app. Aplat avec texte noir par-dessus.
    static let volt = Color(hex: 0x4CF810)
    static let onVolt = Color.black

    // Liseré discret + ombre douce (profondeur iOS 26, pas de brutalisme).
    static let hairline = Color.primary.opacity(0.10)
    static let line = Color.primary.opacity(0.22)      // trait de grille technique
    static let shadow = Color.black.opacity(0.10)
    static let shadowSoft = Color.black.opacity(0.06)

    // Coins GÉNÉREUX arrondis (iOS 26 / Liquid Glass), continus.
    static let radius: CGFloat = 22
    static let radiusSmall: CGFloat = 14
    static let radiusLarge: CGFloat = 30
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12
    static let sectionGap: CGFloat = 24

    /// Thème Verre actif ? (lu depuis les réglages — sert aux fonds adaptatifs).
    static var isGlassActive: Bool { UserDefaults.standard.string(forKey: "appTheme") == "glass" }

    /// Remplissage de carte adaptatif : verre dépoli en thème Verre, sinon surface opaque.
    /// À utiliser dans `.background(Theme.cardFill, in: shape)` pour que TOUTES les cartes
    /// suivent le thème (glass global).
    static var cardFill: AnyShapeStyle {
        isGlassActive ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(card)
    }

    /// Fond d'écran adaptatif : en thème Verre = wallpaper flou (les surfaces se dépolissent
    /// par-dessus). Sinon fond système. Utilisé par TOUS les écrans (accueil, réveil, chat,
    /// questionnaires, profil…) pour que le verre soit global.
    @ViewBuilder static var screenBG: some View {
        if isGlassActive {
            GlassBackdrop()
        } else {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        }
    }

    /// Ancien nom conservé (mêmes règles que screenBG).
    @ViewBuilder static var background: some View { screenBG }
}

/// Fond « verre » global : fond d'écran doux et flou par-dessus lequel toutes les
/// surfaces `.ultraThinMaterial` (cartes, badges, barre) se dépolissent — façon iOS 26.
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            // Fond d'écran doux mais COLORÉ (façon wallpaper iOS) pour que les surfaces
            // .ultraThinMaterial se dépolissent visiblement — vrai Liquid Glass.
            LinearGradient(colors: [Color(hex: 0x7C93C8), Color(hex: 0xAE9BC9), Color(hex: 0x8FC4BE)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(hex: 0x9FD0E8).opacity(0.75)).frame(width: 380, height: 380)
                .blur(radius: 100).offset(x: -140, y: -260)
            Circle().fill(Color(hex: 0xC7A6D8).opacity(0.7)).frame(width: 360, height: 360)
                .blur(radius: 110).offset(x: 160, y: 300)
            Circle().fill(Color(hex: 0xF0C9A8).opacity(0.6)).frame(width: 300, height: 300)
                .blur(radius: 95).offset(x: 150, y: -140)
            Circle().fill(Color(hex: 0x8FD6B4).opacity(0.55)).frame(width: 280, height: 280)
                .blur(radius: 90).offset(x: -150, y: 320)
        }
        .ignoresSafeArea()
    }
}

/// Style de bouton tactile : léger enfoncement + estompage au press.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    /// Ombre douce diffuse — profondeur flottante iOS 26.
    func softElevation(_ strong: Bool = false) -> some View {
        shadow(color: strong ? Theme.shadow : Theme.shadowSoft, radius: strong ? 18 : 11, y: strong ? 8 : 4)
    }
    /// Titre NIKE : gras extrême, majuscules, kerning serré.
    func nikeTitle(_ size: CGFloat = 34) -> some View {
        self.font(.system(size: size, weight: .black)).textCase(.uppercase).kerning(-0.5)
    }
    /// Label technique monospace en majuscules (façon fiches produit Nike ADV).
    func monoLabel(_ size: CGFloat = 11) -> some View {
        self.font(.system(size: size, weight: .semibold, design: .monospaced)).textCase(.uppercase).kerning(1.4)
    }
}

/// Grille technique fine (motif Nike/Swiss) posée derrière le contenu.
struct TechGrid: View {
    var spacing: CGFloat = 46
    var body: some View {
        GeometryReader { geo in
            Path { p in
                var x: CGFloat = 0
                while x <= geo.size.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: geo.size.height)); x += spacing }
                var y: CGFloat = 0
                while y <= geo.size.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: geo.size.width, y: y)); y += spacing }
            }
            .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// "RRGGBB" hex (sans #) — pour persister une couleur choisie par l'utilisateur.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int(round(max(0, min(1, r)) * 255)),
                      Int(round(max(0, min(1, g)) * 255)),
                      Int(round(max(0, min(1, b)) * 255)))
    }
}

// MARK: - Thèmes de l'app (Couleur de l'app)

enum AppTheme: String, CaseIterable, Identifiable {
    case classic   // NIKE bright — blanc cassé + noir + volt
    case dark      // NIKE dark — noir pur + blanc + volt
    case glass     // VERRE translucide façon Apple (Liquid Glass)
    case pinky     // rose, féminin, bubbly
    case gothic    // argent liquide sombre, gothique
    case cloud     // nuage blanc, doux

    var id: String { rawValue }

    /// Thèmes proposés dans le sélecteur. Rose/Argent/Cloud sont ARCHIVÉS (code gardé, retirés du choix).
    static let selectable: [AppTheme] = [.classic, .dark, .glass]
    var isSelectable: Bool { Self.selectable.contains(self) }

    var label: String {
        switch self {
        case .classic: return "Bright"
        case .dark:    return "Dark"
        case .glass:   return "Verre"
        case .pinky:   return "Rose"
        case .gothic:  return "Argent"
        case .cloud:   return "Cloud"
        }
    }
    var symbol: String {
        switch self {
        case .classic: return "sun.max.fill"
        case .dark:    return "moon.fill"
        case .glass:   return "circle.hexagongrid.fill"
        case .pinky:   return "heart.fill"
        case .gothic:  return "drop.fill"
        case .cloud:   return "cloud.fill"
        }
    }
    /// Schéma clair/sombre forcé par le thème.
    var scheme: ColorScheme {
        switch self {
        case .dark, .gothic: return .dark
        default:             return .light
        }
    }
    /// Couleur d'accent du thème. NIKE = volt.
    var accent: Color {
        switch self {
        case .classic: return Theme.volt
        case .dark:    return Theme.volt
        case .glass:   return Theme.volt
        case .pinky:   return Color(hex: 0xFF5BA0)
        case .gothic:  return Color(hex: 0xB7C2D0)
        case .cloud:   return Color(hex: 0x9BB2D6)
        }
    }
    /// Fond (mesh 3×3) de l'écran Catégories selon le thème.
    /// NIKE = aplat (blanc cassé / noir pur), la texture vient de la grille technique.
    var bubbleBG: [Color] {
        switch self {
        case .classic:
            return Array(repeating: Color(hex: 0xECECE7), count: 9)
        case .dark:
            return Array(repeating: Color(hex: 0x000000), count: 9)
        case .glass:
            // Toile floue neutre/chaude derrière le verre (façon fond d'écran iOS).
            return [ Color(hex: 0xB8BCC6), Color(hex: 0xC7C2BC), Color(hex: 0xAEB4BE),
                     Color(hex: 0xC9C4BE), Color(hex: 0xBFC3CB), Color(hex: 0xB2AEA9),
                     Color(hex: 0xA9AEB8), Color(hex: 0xC4BFB8), Color(hex: 0xB6BAC3) ]
        case .pinky:
            return [ Color(hex: 0xFFE3F1), Color(hex: 0xFFF0F7), Color(hex: 0xFFE7F4),
                     Color(hex: 0xFFEAF4), Color(hex: 0xFFF6FB), Color(hex: 0xFCE7FF),
                     Color(hex: 0xFFDCEF), Color(hex: 0xFFE6F5), Color(hex: 0xF8E3FF) ]
        case .gothic:
            return [ Color(hex: 0x070708), Color(hex: 0x050506), Color(hex: 0x0A0A0C),
                     Color(hex: 0x060607), Color(hex: 0x0C0C0F), Color(hex: 0x060608),
                     Color(hex: 0x040405), Color(hex: 0x080809), Color(hex: 0x0A0A0D) ]
        case .cloud:
            return [ Color(hex: 0xF2F5FA), Color(hex: 0xFAFCFF), Color(hex: 0xEFF3F9),
                     Color(hex: 0xF6F9FE), Color(hex: 0xFFFFFF), Color(hex: 0xF1F5FB),
                     Color(hex: 0xEDF1F8), Color(hex: 0xF4F7FC), Color(hex: 0xF0F4FA) ]
        }
    }
    /// Nike = thèmes bright/dark (noir & blanc + volt).
    var isNike: Bool { self == .classic || self == .dark }
    var isGlass: Bool { self == .glass }
    /// Thèmes « modernes » (Nike + Verre) → grille de catégories façon Nike (pas les bulles).
    var isModern: Bool { isNike || isGlass }
}

<<<<<<< HEAD
// MARK: - Système d'ombres (3 niveaux)

private struct ShadowModifier: ViewModifier {
    let radius: CGFloat
    let y: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(opacity * 0.5), radius: radius * 0.25, y: 1)
            .shadow(color: .black.opacity(opacity), radius: radius, y: y)
    }
}

extension View {
    /// Ombre légère — cartes de contenu, tuiles
    func shadowSm() -> some View { modifier(ShadowModifier(radius: 4, y: 2, opacity: 0.06)) }
    /// Ombre moyenne — modals, sheets, bulles
    func shadowMd() -> some View { modifier(ShadowModifier(radius: 12, y: 6, opacity: 0.09)) }
    /// Ombre forte — overlays, popovers
    func shadowLg() -> some View { modifier(ShadowModifier(radius: 24, y: 12, opacity: 0.13)) }
}

// MARK: - Carte sobre (cellule groupée façon iOS)
=======
// MARK: - Carte NIKE (plate, bordure franche, coins nets)
>>>>>>> origin/pote

struct CardStyle: ViewModifier {
    @AppStorage("appTheme") private var themeRaw = "classic"
    var padding: CGFloat = Theme.pad
    var radius: CGFloat = Theme.radius
    var elevated: Bool = false
    func body(content: Content) -> some View {
        let glass = themeRaw == "glass"
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Theme.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(glass ? Color.white.opacity(0.35) : Theme.hairline, lineWidth: glass ? 1 : 0.5)
            )
            .softElevation(elevated)
    }
}

extension View {
    func card(padding: CGFloat = Theme.pad, radius: CGFloat = Theme.radius, elevated: Bool = false) -> some View {
        modifier(CardStyle(padding: padding, radius: radius, elevated: elevated))
    }
}

// MARK: - Surface (carte au contour lisible : liseré hairline + ombre douce)

private struct SurfaceStyle: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadowSm()
    }
}

extension View {
    /// Fond card + liseré + ombre légère — les bords restent visibles sur tout fond.
    func surface(radius: CGFloat = 20) -> some View { modifier(SurfaceStyle(radius: radius)) }
}

// MARK: - Apparition en cascade (stagger ~70 ms par section)

private struct StaggeredAppear: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 18)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(duration: 0.55, bounce: 0.18).delay(Double(index) * 0.07),
                value: appeared
            )
    }
}

extension View {
    /// Entrée décalée de `index` × 70 ms — déclenchée par `appeared`.
    func staggered(_ index: Int, appeared: Bool) -> some View {
        modifier(StaggeredAppear(index: index, appeared: appeared))
    }

    /// Fondu + léger scale des cartes à l'entrée/sortie du viewport de scroll.
    func scrollFade() -> some View {
        scrollTransition(axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.55)
                .scaleEffect(phase.isIdentity ? 1 : 0.965)
        }
    }
}
