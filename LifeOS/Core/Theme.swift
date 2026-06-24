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
