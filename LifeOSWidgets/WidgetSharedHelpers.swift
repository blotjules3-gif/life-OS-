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
        self = WidgetPalette.tone(Double((hex >> 16) & 0xFF) / 255,
                                  Double((hex >> 8) & 0xFF) / 255,
                                  Double(hex & 0xFF) / 255)
    }
}

/// Palette des widgets : suit le choix "Couleurs / Neutre" de l'app, synchronise dans
/// le groupe d'apps sous `widget_palette`. Neutre = gris de meme luminance relative,
/// comme dans l'app, donc memes contrastes. Lu a chaque rendu (pas de cache statique).
enum WidgetPalette {
    static var neutral: Bool {
        UserDefaults(suiteName: "group.com.chifandco.lifeos")?.string(forKey: "widget_palette") == "neutral"
    }
    static func tone(_ r: Double, _ g: Double, _ b: Double) -> Color {
        guard neutral else { return Color(red: r, green: g, blue: b) }
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        let v = max(0, min(1, l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055))
        return Color(red: v, green: v, blue: v)
    }
    static var orange: Color { tone(1.00, 0.58, 0.00) }
    static var green: Color { tone(0.20, 0.78, 0.35) }
}
