import SwiftUI

// MARK: - Largeur lisible (desktop, iPad paysage)

/// Les modules ont ete dessines pour un telephone. Sur un grand ecran on ne les etire
/// pas : on les centre dans une colonne de lecture, et le fond partage continue de
/// chaque cote. Sur telephone (largeur deja sous la limite) rien ne change.
struct ReadableWidth: ViewModifier {
    var maxWidth: CGFloat = ReadableWidth.phoneModuleMaxWidth

    /// Un peu plus large qu'un iPhone Pro Max en paysage etroit : les listes et cartes
    /// gardent leur respiration, les lignes de texte restent courtes.
    static let phoneModuleMaxWidth: CGFloat = 760

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Centre un ecran concu pour telephone dans une colonne lisible.
    func readableWidth(_ maxWidth: CGFloat = ReadableWidth.phoneModuleMaxWidth) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}

// MARK: - Apercu vivant des quatre apparences (Profil)

/// Quatre vignettes : clair / sombre x couleurs / neutre. Chaque vignette est rendue
/// avec les VRAIES surfaces et les VRAIES teintes de domaine, dans son propre
/// environnement (clair ou sombre, palette neutre ou non), donc elle montre ce que
/// l'app affichera, pas une image figee.
struct AppearanceLookPreviewGrid: View {
    /// Apparence affichee en ce moment.
    let current: AppearanceLook
    /// Vrai quand la luminosite suit l'appareil (la vignette courante le dit).
    let followsDevice: Bool
    let onSelect: (AppearanceLook) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(AppearanceLook.allCases) { look in
                let selected = look == current
                Button { onSelect(look) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        AppearanceLookThumbnail(look: look)
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.body.weight(.bold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.accentColor.readableInk, Color.accentColor)
                                        .padding(6)
                                        .accessibilityHidden(true)
                                }
                            }
                        HStack(spacing: 4) {
                            Text(look.label)
                                .font(AppFont.body(size: 12, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            if selected && followsDevice {
                                Text("· appareil")
                                    .font(AppFont.body(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(LifeOSPressStyle())
                .accessibilityLabel(look.label)
                .accessibilityValue(selected ? (followsDevice ? "Actuel, suit l'appareil" : "Actuel") : "")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint("Fixe cette apparence")
            }
        }
    }
}

/// Mini ecran : fond partage, une carte de verre, trois domaines (travail, nutrition,
/// sport) et deux lignes de texte.
struct AppearanceLookThumbnail: View {
    let look: AppearanceLook

    var body: some View {
        ZStack {
            (look.scheme == .dark ? Color.black : Color(white: 0.94))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    ForEach([AppCategory.career, .nutrition, .fitness], id: \.self) { cat in
                        Image(systemName: cat.icon)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(cat.tint)
                            .frame(width: 18, height: 18)
                            .raisedSurface(Circle(), .nested)
                    }
                    Spacer(minLength: 0)
                }
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.85)).frame(width: 46, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.6)).frame(width: 30, height: 4)
            }
            .padding(8)
            .raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), .floating)
            .padding(8)
        }
        .frame(height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, look.scheme)
        .environment(\.neutralPalette, look.palette == .neutral)
        .accessibilityHidden(true)
    }
}
