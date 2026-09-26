import SwiftUI

/// Disposition qui passe a la ligne ENTRE les elements, jamais au milieu d'un mot.
///
/// Pourquoi elle existe : les puces du matin etaient dans un `HStack` fixe a quatre
/// colonnes. En francais les libelles sont plus longs qu'en anglais, donc "Calories",
/// "Activite" et "Sommeil" se coupaient en plein mot ("Calori / es"). Retrecir le texte
/// indefiniment n'est pas une solution, ca finit illisible. Ici chaque puce garde sa
/// largeur naturelle et c'est la LIGNE qui se casse.
///
/// Sert aussi aux gros reglages de taille de texte (Dynamic Type), ou une rangee fixe
/// deborde toujours.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + spacing + s.width > maxWidth {
                widest = max(widest, x); y += lineHeight + lineSpacing; x = 0; lineHeight = 0
            }
            x += (x > 0 ? spacing : 0) + s.width
            lineHeight = max(lineHeight, s.height)
        }
        widest = max(widest, x)
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + spacing + s.width > bounds.maxX {
                y += lineHeight + lineSpacing; x = bounds.minX; lineHeight = 0
            }
            if x > bounds.minX { x += spacing }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width
            lineHeight = max(lineHeight, s.height)
        }
    }
}
