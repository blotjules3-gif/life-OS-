import SwiftUI

/// Style de bouton interactif Apple : compression réactive avec rebond spring doux et variation d'opacité.
struct LifeOSPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var opacity: CGFloat = 0.88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .opacity(configuration.isPressed && !reduceMotion ? opacity : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.64),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == LifeOSPressStyle {
    static var applePress: LifeOSPressStyle { LifeOSPressStyle() }
    static func applePress(scale: CGFloat = 0.96, opacity: CGFloat = 0.88) -> LifeOSPressStyle {
        LifeOSPressStyle(scale: scale, opacity: opacity)
    }
}
