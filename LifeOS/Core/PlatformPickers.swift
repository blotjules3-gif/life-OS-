import SwiftUI

// MARK: - Roues de selection sures sur Mac
//
// POURQUOI CE FICHIER EXISTE, ne pas le supprimer :
//
// `UIPickerView` (la roue) est INTERDIT sur Mac Catalyst quand l'app tourne en idiome Mac.
// UIKit ne degrade pas, il LEVE une exception des que la roue entre dans une fenetre :
//
//   -[UIView(UICatalystMacIdiomUnsupported_Internal) _throwForUnsupportedNonMacIdiomBehaviorWithReason:]
//   -[UIPickerView _didMoveFromWindow:toWindow:]
//
// Donc l'app ne plante pas "parfois" : elle plante a chaque ouverture de l'ecran, tout de
// suite, avant meme de dessiner. C'est ce qui faisait tomber "Ajouter une habitude" sur la
// version bureau (rapports LifeOS-2026-09-25-0131*.ips).
//
// `.wheel` et `.datePickerStyle(.wheel)` sont donc INTERDITS en direct dans ce projet.
// Utiliser `.adaptiveWheelPicker()` et `.adaptiveWheelDatePicker()`, qui gardent la roue
// sur iPhone et iPad, et prennent une commande native sur Mac.

extension View {

    /// Roue sur iOS, menu deroulant sur Mac. Remplace `.pickerStyle(.wheel)`.
    @ViewBuilder
    func adaptiveWheelPicker() -> some View {
        #if targetEnvironment(macCatalyst)
        self.pickerStyle(.menu)
        #else
        self.pickerStyle(.wheel)
        #endif
    }

    /// Roue sur iOS, champ compact sur Mac. Remplace `.datePickerStyle(.wheel)`.
    @ViewBuilder
    func adaptiveWheelDatePicker() -> some View {
        #if targetEnvironment(macCatalyst)
        self.datePickerStyle(.compact)
        #else
        self.datePickerStyle(.wheel)
        #endif
    }

    /// Hauteur fixe utile a la roue, inutile et genante pour un menu Mac.
    @ViewBuilder
    func wheelHeight(_ h: CGFloat) -> some View {
        #if targetEnvironment(macCatalyst)
        self
        #else
        self.frame(height: h)
        #endif
    }
}
