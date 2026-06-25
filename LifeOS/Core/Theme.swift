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
    static let textSecondary = Color.secondary
    static let accent = Color.accentColor

    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 11
    static let pad: CGFloat = 16

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
            return [ Color(hex: 0x15171C), Color(hex: 0x101216), Color(hex: 0x1A1C22),
                     Color(hex: 0x121419), Color(hex: 0x1E2128), Color(hex: 0x141519),
                     Color(hex: 0x0E0F12), Color(hex: 0x16181D), Color(hex: 0x191B20) ]
        case .cloud:
            return [ Color(hex: 0xF2F5FA), Color(hex: 0xFAFCFF), Color(hex: 0xEFF3F9),
                     Color(hex: 0xF6F9FE), Color(hex: 0xFFFFFF), Color(hex: 0xF1F5FB),
                     Color(hex: 0xEDF1F8), Color(hex: 0xF4F7FC), Color(hex: 0xF0F4FA) ]
        }
    }
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
