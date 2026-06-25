import SwiftUI

/// Bouton de catégorie en CHROME LIQUIDE basé sur un asset PNG réaliste.
///
/// 3 couches (la matière vient de l'image, jamais redessinée) :
///   1. ombre de contact (respire un peu)
///   2. `AnimatedChromeDropletImage` : l'image chrome VIVANTE — distorsion liquide Metal
///      minuscule + micro scale non uniforme + dérive de rotation + shimmer masqué par l'alpha
///   3. `StableIconAndLabelOverlay` : icône + label blancs STABLES, dans une zone de sécurité.
struct ChromeCategoryButton: View {
    let title: String
    let sfSymbolName: String
    let assetName: String
    var size: CGFloat
    var showLabel: Bool = true
    var pressed: Bool = false
    var time: Double = 0
    var phase: Double = 0

    var body: some View {
        ZStack {
            // 1 — ombre de contact (respiration très légère)
            let breath = 1 + 0.03 * sin(time * 0.45 + phase)
            Ellipse()
                .fill(Color.black.opacity(0.5))
                .frame(width: size * 0.70 * breath, height: size * 0.14)
                .blur(radius: size * 0.06)
                .offset(y: size * 0.46)
                .blendMode(.multiply)

            // 2 — la goutte vivante
            AnimatedChromeDropletImage(assetName: assetName, size: size, time: time, phase: phase)

            // 3 — contenu stable (jamais distordu)
            StableIconAndLabelOverlay(title: title, symbol: sfSymbolName, size: size, showLabel: showLabel)
        }
        .frame(width: size, height: size)
        .scaleEffect(pressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: pressed)
    }

    /// Asset selon la taille (+ variante pour casser la répétition).
    static func asset(for diameter: CGFloat, base: CGFloat, index: Int) -> String {
        let ratio = base > 0 ? diameter / base : 1
        let bucket = ratio >= 1.10 ? "large" : (ratio <= 0.82 ? "small" : "medium")
        let variant = (index % 2) + 1
        return "chrome_drop_\(bucket)_0\(variant)"
    }
}

/// La couche IMAGE animée — toute la « vie » liquide, rien d'autre.
private struct AnimatedChromeDropletImage: View {
    let assetName: String
    let size: CGFloat
    let time: Double
    let phase: Double

    var body: some View {
        // micro respiration NON uniforme (volume préservé : x et y inverses), amplitude ~1.1%
        let sx  = 1 + 0.011 * sin(time * 0.50 + phase)
        let sy  = 1 - 0.011 * sin(time * 0.50 + phase)
        // dérive de rotation <= 0.4°
        let rot = 0.4 * sin(time * 0.31 + phase * 1.3)
        // déplacement du shimmer (lent, ~7 s, déphasé par goutte)
        let hx  = size * 0.16 * sin(time * 0.32 + phase)
        let hy  = size * 0.13 * cos(time * 0.26 + phase * 1.5)
        let shimmerOpacity = 0.14 + 0.04 * sin(time * 0.4 + phase * 0.9)

        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            // distorsion liquide Metal minuscule (< ~1.2 pt) — surface qui dérive, pas du jelly
            .distortionEffect(
                ShaderLibrary.liquidDrift(.float(time), .float(1.1), .float(phase)),
                maxSampleOffset: CGSize(width: 2, height: 2)
            )
            // shimmer : lumière qui glisse sur le métal, MASQUÉE par l'alpha de la goutte
            .overlay(
                Ellipse()
                    .fill(RadialGradient(colors: [.white.opacity(shimmerOpacity), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.24))
                    .frame(width: size * 0.46, height: size * 0.38)
                    .offset(x: -size * 0.08 + hx, y: -size * 0.18 + hy)
                    .blendMode(.screen)
                    .mask(Image(assetName).resizable().scaledToFit().frame(width: size, height: size))
                    .allowsHitTesting(false)
            )
            .scaleEffect(x: sx, y: sy)
            .rotationEffect(.degrees(rot))
    }
}

/// Icône + label blancs, STABLES, confinés dans la zone de sécurité interne de la goutte.
private struct StableIconAndLabelOverlay: View {
    let title: String
    let symbol: String
    let size: CGFloat
    let showLabel: Bool

    private var longLabel: Bool { title.count >= 9 }

    var body: some View {
        if !title.isEmpty || !symbol.isEmpty {
            VStack(spacing: size * 0.035) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.30, weight: .semibold))   // icône ~30% de la goutte
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                if showLabel && !title.isEmpty {
                    Text(title)
                        .font(.system(size: size * (longLabel ? 0.105 : 0.118),
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 8)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: size * 0.68)        // label plafonné à 68% de la goutte
                }
            }
            .frame(width: size * 0.72, height: size * 0.72) // zone de sécurité centrée
            .offset(y: showLabel && !title.isEmpty ? -size * 0.005 : 0)
        }
    }
}
