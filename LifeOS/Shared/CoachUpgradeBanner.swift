import SwiftUI

/// Bannière discrète affichée en haut du chat coach quand `CoachUpgradeSuggestion`
/// détecte de la frustration user (≥3 dislikes en 24h sans clé cloud).
///
/// Proposer de basculer sur un provider cloud plus intelligent (Claude/GPT/etc.)
/// sans être intrusif. L'user peut :
///   - Tap "Améliorer" → ouvre l'écran Réglages Coach IA
///   - Tap "Plus tard" → snooze 7 jours
struct CoachUpgradeBanner: View {
    let onImprove: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Un coach plus intelligent ?")
                    .font(.subheadline.weight(.semibold))
                Text("Tu peux brancher une clé Claude, GPT ou Mistral en 2 min. Les réponses seront beaucoup plus précises et empathiques.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button(action: onImprove) {
                        Text("Améliorer")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Text("Plus tard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer la suggestion")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Un coach plus intelligent ? Tu peux brancher une clé Claude, GPT ou Mistral.")
    }
}
