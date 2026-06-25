import SwiftUI

/// Bouton de catégorie en CHROME LIQUIDE basé sur un asset PNG réaliste.
///
/// La matière (goutte de métal argenté, réflexions miroir) vient d'une image
/// pré-rendue haute résolution dans l'asset catalog — on ne la redessine PAS
/// avec des dégradés SwiftUI. Ce composant ne fait que :
///   1. poser une ombre de contact
///   2. afficher le PNG chrome (resizable, scaledToFit)
///   3. superposer l'icône SF Symbol + le label en blanc, par-dessus
///
/// Assets attendus (remplaçables par tes propres PNG, mêmes noms) :
///   chrome_drop_large_01 / _02, chrome_drop_medium_01 / _02, chrome_drop_small_01 / _02
struct ChromeCategoryButton: View {
    let title: String
    let sfSymbolName: String
    let assetName: String
    var size: CGFloat
    var showLabel: Bool = true
    var pressed: Bool = false

    var body: some View {
        ZStack {
            // 1 — ombre de contact douce sous la goutte
            Ellipse()
                .fill(Color.black.opacity(0.55))
                .frame(width: size * 0.72, height: size * 0.16)
                .blur(radius: size * 0.06)
                .offset(y: size * 0.45)
                .blendMode(.multiply)

            // 2 — la goutte de chrome (image, jamais redessinée en gradient)
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)

            // 4 + 5 — icône + label blancs, posés PAR-DESSUS la goutte
            if !title.isEmpty || !sfSymbolName.isEmpty {
                VStack(spacing: size * 0.045) {
                    Image(systemName: sfSymbolName)
                        .font(.system(size: size * 0.30, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 6)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    if showLabel && !title.isEmpty {
                        Text(title)
                            .font(.system(size: size * 0.115, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 8)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .offset(y: showLabel && !title.isEmpty ? -size * 0.02 : 0)
            }
        }
        .frame(width: size, height: size)
        // état pressé : très léger enfoncement (premium, pas cartoon)
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
