import SwiftUI
import WidgetKit

enum WidgetAppGroup {
    static let suiteName = "group.com.chifandco.lifeos"
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
}

extension Color {
    init(widgetHex hex: UInt) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }
}
