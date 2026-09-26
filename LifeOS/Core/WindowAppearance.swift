import SwiftUI
import UIKit

/// Accorde l'apparence de la FENETRE avec le theme choisi dans l'app.
///
/// LE DEFAUT
///
/// `.preferredColorScheme` ne s'applique qu'au contenu SwiftUI. Sur Mac Catalyst, la
/// barre d'outils et le titre de fenetre sont dessines par le systeme et suivent
/// l'apparence de la FENETRE. L'app injecte par ailleurs `.tint(appTheme.accent)`, et
/// l'accent du theme sombre est BLANC.
///
/// Resultat avec theme sombre dans l'app et Mac en apparence claire : des glyphes blancs
/// sur une barre d'outils pale, donc quasiment invisibles, et un titre de fenetre peu
/// lisible. Ce n'est pas un probleme de couleur d'icone, c'est un desaccord d'apparence
/// entre le contenu et l'habillage natif.
///
/// On force donc la fenetre a adopter la meme apparence que le theme. Le theme
/// "Systeme" laisse la fenetre suivre le reglage de l'ordinateur, ce qui est le
/// comportement attendu.
enum WindowAppearance {
    static func apply(_ scheme: ColorScheme?) {
        let style: UIUserInterfaceStyle
        switch scheme {
        case .dark:  style = .dark
        case .light: style = .light
        case nil:    style = .unspecified   // theme Systeme : on suit l'ordinateur
        @unknown default: style = .unspecified
        }
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                for window in scene.windows { window.overrideUserInterfaceStyle = style }
            }
        }
    }
}

extension View {
    /// A poser a la racine : garde l'habillage natif et le contenu d'accord.
    func syncWindowAppearance(_ scheme: ColorScheme?) -> some View {
        onAppear { WindowAppearance.apply(scheme) }
            .onChange(of: scheme) { _, new in WindowAppearance.apply(new) }
    }
}
