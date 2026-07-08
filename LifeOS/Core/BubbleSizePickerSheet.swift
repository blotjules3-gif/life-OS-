import SwiftUI

/// Cible du picker — capture la catégorie touchée pour piloter le sheet + `Identifiable`
/// pour l'API `.sheet(item:)`.
struct BubbleSizePickerTarget: Identifiable {
    let id = UUID()
    let title: String
    let tint: Color
    let current: BubbleSize
}

/// Sélecteur premium des tailles de bulle (Petite / Moyenne / Grande).
///
/// **Design** :
/// - 3 cartes horizontales identifiables en un coup d'œil (proto visuel de la taille au centre)
/// - Sélection : bordure accent + softElevation renforcée + scale 1.03 + checkmark badge
/// - Micro-interactions : haptic soft à la sélection, spring quick sur le layout, auto-dismiss 250 ms
/// - Responsive : HStack en tailles standard, VStack en Dynamic Type AX3+
/// - A11y : `accessibilityElement(.combine)`, `accessibilityValue` sélectionnée/non
/// - Respect strict du design system : `Theme.radius`, `Theme.animQuick/Slow`, `nikeTitle`, `monoLabel`
struct BubbleSizePickerSheet: View {
    let categoryTitle: String
    let categoryTint: Color
    @State private var selection: BubbleSize
    private let onSelect: (BubbleSize) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = false

    init(categoryTitle: String, categoryTint: Color, selection: BubbleSize, onSelect: @escaping (BubbleSize) -> Void) {
        self.categoryTitle = categoryTitle
        self.categoryTint = categoryTint
        self._selection = State(initialValue: selection)
        self.onSelect = onSelect
    }

    private var isStacked: Bool { typeSize >= .accessibility1 }

    var body: some View {
        VStack(spacing: Theme.space24) {
            header
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -8)

            layout
                .padding(.horizontal, Theme.pad)
        }
        .padding(.vertical, Theme.space32)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Theme.screenBG)
        .presentationDetents([.height(isStacked ? 600 : 380), .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.radiusLarge)
        .presentationBackground(.regularMaterial)
        .onAppear {
            withAnimation(Theme.animSlow.delay(0.05)) { appeared = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Taille de la bulle")
                .nikeTitle(24)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Circle()
                    .fill(categoryTint)
                    .frame(width: 6, height: 6)
                Text(categoryTitle.uppercased())
                    .monoLabel(11)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.pad)
    }

    // MARK: - Layout adaptatif

    @ViewBuilder private var layout: some View {
        if isStacked {
            VStack(spacing: Theme.space12) {
                sizeCards(vertical: true)
            }
        } else {
            HStack(spacing: Theme.space12) {
                sizeCards(vertical: false)
            }
        }
    }

    @ViewBuilder private func sizeCards(vertical: Bool) -> some View {
        ForEach(Array(BubbleSize.allCases.enumerated()), id: \.element) { index, size in
            SizeCard(
                size: size,
                tint: categoryTint,
                isSelected: selection == size,
                vertical: vertical
            )
            .staggeredEntry(index: index, appeared: appeared)
            .onTapGesture {
                select(size)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(size.label)
            .accessibilityValue(selection == size ? "Sélectionnée" : "Non sélectionnée")
            .accessibilityAddTraits(selection == size ? [.isSelected, .isButton] : .isButton)
            .accessibilityHint("Applique la taille \(size.label.lowercased()) à \(categoryTitle)")
        }
    }

    // MARK: - Interaction

    private func select(_ size: BubbleSize) {
        guard size != selection else {
            // Tap sur l'option déjà sélectionnée → dismiss court
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
            return
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(Theme.animQuick) {
            selection = size
        }
        onSelect(size)
        // Auto-dismiss après un court delay pour que l'utilisateur voie l'anim de sélection.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            dismiss()
        }
    }
}

// MARK: - SizeCard

/// Une carte de taille. Le visuel central est un disque proportionnel à la taille réelle.
/// L'ensemble reste dans les tokens du design system (radius, ombres, typo).
private struct SizeCard: View {
    let size: BubbleSize
    let tint: Color
    let isSelected: Bool
    let vertical: Bool

    /// Rapport visuel des 3 tailles pour l'aperçu (échelle exagérée par rapport
    /// au widthFraction réel pour bien contraster à petite échelle).
    private var previewScale: CGFloat {
        switch size {
        case .small:  return 0.35
        case .medium: return 0.55
        case .large:  return 0.80
        }
    }

    /// Pourcentage affiché en bas (fidèle à `widthFraction` réel).
    private var percentLabel: String {
        String(format: "%.0f %%", size.widthFraction * 100)
    }

    var body: some View {
        VStack(spacing: 14) {
            previewDisc
            VStack(spacing: 4) {
                Text(size.label.uppercased())
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .kerning(-0.2)
                    .foregroundStyle(Theme.textPrimary)
                Text(percentLabel)
                    .monoLabel(10)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: vertical ? .infinity : nil, minHeight: 148)
        .frame(minWidth: vertical ? nil : 96)
        .padding(.vertical, 22)
        .padding(.horizontal, 14)
        .background(cardBackground)
        .overlay(borderStroke)
        .overlay(alignment: .topTrailing) { checkmarkBadge }
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .shadow(color: isSelected ? tint.opacity(0.24) : Theme.shadowSoft,
                radius: isSelected ? 18 : 8,
                y: isSelected ? 8 : 3)
        .animation(Theme.animQuick, value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: Preview disc — proto visuel de la taille

    private var previewDisc: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // Silhouette de fond légère pour donner l'échelle max
                Circle()
                    .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: side, height: side)
                // Disque proportionnel dans la couleur de la catégorie
                Circle()
                    .fill(discGradient)
                    .frame(width: side * previewScale, height: side * previewScale)
                    .shadow(color: tint.opacity(isSelected ? 0.35 : 0.15),
                            radius: isSelected ? 10 : 6, y: 2)
                    .overlay(
                        // Reflet subtil top-left pour l'aspect "vivant"
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.35), .clear],
                                startPoint: .topLeading, endPoint: .center))
                            .frame(width: side * previewScale, height: side * previewScale)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 68)
    }

    private var discGradient: some ShapeStyle {
        LinearGradient(
            colors: [tint, tint.opacity(0.75)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: Card background & border

    @ViewBuilder private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .fill(Theme.cardFill)
    }

    @ViewBuilder private var borderStroke: some View {
        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(isSelected ? tint : Theme.hairline,
                          lineWidth: isSelected ? 1.8 : 1)
            .animation(Theme.animQuick, value: isSelected)
    }

    @ViewBuilder private var checkmarkBadge: some View {
        if isSelected {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            }
            .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
            .offset(x: -10, y: 10)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Stagger helper local

private extension View {
    /// Entrée orchestrée : chaque carte apparaît 40 ms après la précédente.
    func staggeredEntry(index: Int, appeared: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(
                Theme.animSlow.delay(0.10 + Double(index) * 0.06),
                value: appeared
            )
    }
}
