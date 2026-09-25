import SwiftUI

// MARK: - Écran de Tri Manuel des Catégories

struct CategoryOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = CategoryOrderManager.shared

    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Barre de filtres et raccourcis rapides
                presetsBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.cardFill)

                Divider()

                // Liste réordonnable
                List {
                    ForEach(Array(manager.order.enumerated()), id: \.element.id) { index, cat in
                        categoryOrderRow(cat, index: index)
                    }
                    .onMove { source, destination in
                        manager.move(from: source, to: destination)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, $editMode)
            }
            .navigationTitle("Trier les catégories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminer") {
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 540, minHeight: 620)
        #endif
    }

    // MARK: - Barre des Presets Rapides

    private var presetsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                presetChip(
                    title: "Sport & Nutrition",
                    icon: "figure.run",
                    tint: .red
                ) {
                    manager.setFitnessFirst()
                }

                presetChip(
                    title: "Optimisé Bureau (Mac)",
                    icon: "macbook",
                    tint: .blue
                ) {
                    manager.setDesktopOptimized()
                }

                presetChip(
                    title: "Inverser l'ordre",
                    icon: "arrow.up.arrow.down",
                    tint: .purple
                ) {
                    manager.reverseOrder()
                }

                presetChip(
                    title: "Réinitialiser",
                    icon: "arrow.counterclockwise",
                    tint: .secondary
                ) {
                    manager.reset()
                }
            }
        }
    }

    private func presetChip(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ligne de Catégorie avec Boutons Déplacement

    private func categoryOrderRow(_ cat: AppCategory, index: Int) -> some View {
        HStack(spacing: 12) {
            // Badge Numéroté
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 26)

            // Icône Catégorie
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cat.tint.gradient)
                    .frame(width: 36, height: 36)
                Image(systemName: cat.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Titre & Sous-titre
            VStack(alignment: .leading, spacing: 2) {
                Text(cat.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(cat.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Boutons d'action directe "Placer en haut" / "Placer en bas"
            HStack(spacing: 6) {
                // Placer en haut
                Button {
                    manager.moveToTop(cat)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(index == 0 ? Color.secondary.opacity(0.3) : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help("Placer en tête de liste")

                // Placer en bas
                Button {
                    manager.moveToBottom(cat)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(index == manager.order.count - 1 ? Color.secondary.opacity(0.3) : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(index == manager.order.count - 1)
                .help("Placer tout en bas")
            }
            .padding(.trailing, 4)
        }
        .padding(.vertical, 4)
    }
}
