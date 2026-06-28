import SwiftUI

struct LifeOSPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(duration: 0.15, bounce: 0.2), value: configuration.isPressed)
    }
}
