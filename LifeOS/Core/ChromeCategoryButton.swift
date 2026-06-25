import SwiftUI

/// Bouton de catégorie en CHROME LIQUIDE basé sur un asset PNG réaliste.
///
/// Structure en 3 couches (la matière vient de l'image, jamais redessinée) :
///   1. ombre de contact (respire légèrement)
///   2. `AnimatedChromeDropletLayer` : l'image chrome avec une VIE liquide subtile
///      (micro scale non uniforme + dérive de rotation + reflet spéculaire qui glisse)
///   3. `StableContentOverlay` : icône SF Symbol + label blancs, STABLES et lisibles,
///      contraints dans une zone de sécurité interne pour ne jamais toucher le bord.
struct ChromeCategoryButton: View {
    let title: String
    let sfSymbolName: String
    let assetName: String
    var size: CGFloat
    var showLabel: Bool = true
    var pressed: Bool = false
    var time: Double = 0      // horloge partagée (TimelineView)
    var phase: Double = 0     // déphasage par goutte -> mouvements désynchronisés

    var body: some View {
        ZStack {
            // 1 — ombre de contact, respiration très légère
            let breath = 1 + 0.035 * sin(time * 0.5 + phase)
            Ellipse()
                .fill(Color.black.opacity(0.5))
                .frame(width: size * 0.70 * breath, height: size * 0.15)
                .blur(radius: size * 0.06)
                .offset(y: size * 0.45)
                .blendMode(.multiply)

            // 2 — la goutte vivante (image animée)
            AnimatedChromeDropletLayer(assetName: assetName, size: size, time: time, phase: phase)

            // 3 — contenu stable (icône + label) dans la zone de sécurité
            StableContentOverlay(title: title, symbol: sfSymbolName, size: size, showLabel: showLabel)
        }
        .frame(width: size, height: size)
        .scaleEffect(pressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: pressed)
    }

    /// Choisit l'asset selon la taille (et une variante pour casser la répétition).
    static func asset(for diameter: CGFloat, base: CGFloat, index: Int) -> String {
        let ratio = base > 0 ? diameter / base : 1
        let bucket = ratio >= 1.12 ? "large" : (ratio <= 0.80 ? "small" : "medium")
        let variant = (index % 2) + 1
        return "chrome_drop_\(bucket)_0\(variant)"
    }
}

/// Couche image animée — la « vie » du métal liquide. Tout reste minuscule et lent.
private struct AnimatedChromeDropletLayer: View {
    let assetName: String
    let size: CGFloat
    let time: Double
    let phase: Double

    var body: some View {
        // micro déformation NON uniforme (préserve le volume : x et y inverses)
        let sx  = 1 + 0.014 * sin(time * 0.55 + phase)
        let sy  = 1 - 0.014 * sin(time * 0.55 + phase)
        // dérive de rotation très faible (< 0.8°)
        let rot = 0.7 * sin(time * 0.33 + phase * 1.3)
        // reflet spéculaire qui glisse lentement sur la goutte
        let hx  = size * 0.16 * sin(time * 0.21 + phase)
        let hy  = size * 0.14 * cos(time * 0.17 + phase * 1.4)

        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .overlay(
                // highlight spéculaire mobile, masqué par la forme de la goutte
                Ellipse()
                    .fill(RadialGradient(colors: [.white.opacity(0.22), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.26))
                    .frame(width: size * 0.5, height: size * 0.42)
                    .offset(x: -size * 0.10 + hx, y: -size * 0.16 + hy)
                    .blendMode(.screen)
                    .mask(Image(assetName).resizable().scaledToFit().frame(width: size, height: size))
                    .allowsHitTesting(false)
            )
            .scaleEffect(x: sx, y: sy)
            .rotationEffect(.degrees(rot))
    }
}

/// Icône + label blancs, STABLES (non animés) et confinés dans une zone de sécurité
/// interne pour ne jamais toucher le bord de la goutte.
private struct StableContentOverlay: View {
    let title: String
    let symbol: String
    let size: CGFloat
    let showLabel: Bool

    private var longLabel: Bool { title.count >= 9 }   // Alimentation, Bien-être, Transports, Éducation…

    var body: some View {
        if !title.isEmpty || !symbol.isEmpty {
            VStack(spacing: size * 0.035) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.27, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                if showLabel && !title.isEmpty {
                    Text(title)
                        .font(.system(size: size * (longLabel ? 0.098 : 0.115),
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 8)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: size * 0.70)        // largeur de sécurité
                }
            }
            // zone de sécurité interne : le contenu reste bien à l'intérieur de la goutte
            .frame(width: size * 0.74, height: size * 0.74)
            .offset(y: showLabel && !title.isEmpty ? -size * 0.01 : 0)
        }
    }
}
