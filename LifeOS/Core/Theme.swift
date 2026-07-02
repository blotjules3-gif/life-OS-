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
    static let textSecondary = Color.secondary
    static let accent = Color.accentColor

    /// Accent signature = le VERT de l'icône de l'app (#4CF810). À utiliser en aplat, TEXTE NOIR par-dessus.
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

    /// Fond neutre système (écrans de détail).
    static var background: some View {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
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

// MARK: - Carte NIKE (plate, bordure franche, coins nets)

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
