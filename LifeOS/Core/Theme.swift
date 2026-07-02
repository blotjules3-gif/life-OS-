import SwiftUI
import UIKit

/// Design system de LifeOS — sobre, natif, adaptatif (clair/sombre), façon app système Apple.
enum Theme {
    // Couleurs système adaptatives (pas de dégradé, pas de couleurs en dur)
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let bg2 = Color(uiColor: .tertiarySystemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let stroke = Color(uiColor: .separator).opacity(0.6)
    static let textPrimary = Color.primary
    // UIColor.secondaryLabel meets ≥3:1 on system backgrounds in both light and dark
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary  = Color(uiColor: .tertiaryLabel)
    static let accent = Color.accentColor

    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 11
    static let pad: CGFloat = 16
    static let padWide: CGFloat = 28   // onboarding / large content areas

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

    /// Fond neutre système (utilisé par les écrans de détail).
    static var background: some View {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
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
}

// MARK: - Thèmes de l'app (Couleur de l'app)

enum AppTheme: String, CaseIterable, Identifiable {
    case classic   // clair actuel
    case dark      // sombre (version sombre de l'actuel)
    case pinky     // rose, féminin, bubbly
    case gothic    // argent liquide sombre, gothique
    case cloud     // nuage blanc, doux

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Clair"
        case .dark:    return "Sombre"
        case .pinky:   return "Rose"
        case .gothic:  return "Argent"
        case .cloud:   return "Cloud"
        }
    }
    var symbol: String {
        switch self {
        case .classic: return "sun.max.fill"
        case .dark:    return "moon.fill"
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
    /// Couleur d'accent du thème.
    var accent: Color {
        switch self {
        case .classic: return Color(hex: 0x618EF1)
        case .dark:    return Color(hex: 0x6C9BF1)
        case .pinky:   return Color(hex: 0xFF5BA0)
        case .gothic:  return Color(hex: 0xB7C2D0)
        case .cloud:   return Color(hex: 0x9BB2D6)
        }
    }
    /// Fond (mesh 3×3) de l'écran Catégories selon le thème.
    var bubbleBG: [Color] {
        switch self {
        case .classic:
            return [ Color(hex: 0xD4E8FC), Color(hex: 0xEAF4FF), Color(hex: 0xF5EEF8),
                     Color(hex: 0xE0F2FF), Color(hex: 0xF7FBFF), Color(hex: 0xE6F2FF),
                     Color(hex: 0xD7ECFF), Color(hex: 0xDEEFFF), Color(hex: 0xE3EFFF) ]
        case .dark:
            return [ Color(hex: 0x10121F), Color(hex: 0x0D0F1C), Color(hex: 0x161122),
                     Color(hex: 0x0E1120), Color(hex: 0x121426), Color(hex: 0x100E1F),
                     Color(hex: 0x0C0E1C), Color(hex: 0x0F1122), Color(hex: 0x11101E) ]
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
}

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

struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.pad
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Theme.pad) -> some View {
        modifier(CardStyle(padding: padding))
    }
}
