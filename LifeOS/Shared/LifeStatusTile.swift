import SwiftUI

/// Tuile "état de vie" : brique unique du dashboard Home unifiée.
///
/// Objectif : agréger UN signal fort d'un module (sommeil, kcal, pas, humeur…) en
/// une carte compacte, sémantiquement colorée, tapable, accessible.
///
/// La Home appelle N tuiles côte à côte pour donner l'état 360° instantané.
///
/// Usage minimal :
///   LifeStatusTile(
///       icon: "moon.stars.fill",
///       value: "7h 12",
///       label: "Sommeil",
///       tint: Theme.sleep
///   )
///
/// Usage avec progression et tap :
///   LifeStatusTile(
///       icon: "flame.fill",
///       value: "1 450",
///       unit: "kcal",
///       label: "Nutrition",
///       progress: 0.66,
///       tint: Theme.nutrition,
///       onTap: { navigate(.nutrition) }
///   )
struct LifeStatusTile: View {
    let icon: String
    let value: String
    var unit: String? = nil
    let label: String
    /// Progression 0…1 (nil = pas de barre).
    var progress: Double? = nil
    /// Sous-texte optionnel (contexte : "cible 2200", "obj. 8h").
    var subtitle: String? = nil
    /// État visuel : normal (par défaut), attention (jaune), critique (rouge).
    var status: TileStatus = .normal
    /// Couleur sémantique de l'icône et de la barre.
    var tint: Color = Theme.accent
    /// Action au tap. Si nil, la tuile n'est pas interactive.
    var onTap: (() -> Void)? = nil

    enum TileStatus { case normal, warning, critical }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            content
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(onTap == nil ? "" : "Ouvre le module")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 26, height: 26)
                    .background(iconColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Spacer(minLength: 0)
                if status != .normal {
                    Circle()
                        .fill(statusDot)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let unit {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            if let progress {
                LifeStatusBar(progress: progress, tint: tint)
                    .frame(height: 4)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(reduceMotion ? nil : Theme.animMicro, value: pressed)
        .simultaneousGesture(
            onTap == nil
                ? nil
                : DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
        )
    }

    private var iconColor: Color {
        switch status {
        case .normal:   return tint
        case .warning:  return Theme.warning
        case .critical: return Theme.danger
        }
    }

    private var statusDot: Color {
        switch status {
        case .normal:   return .clear
        case .warning:  return Theme.warning
        case .critical: return Theme.danger
        }
    }

    private var a11yLabel: String {
        var parts = [label, value]
        if let unit { parts.append(unit) }
        if let subtitle { parts.append(subtitle) }
        if let progress {
            parts.append("\(Int((progress * 100).rounded())) %")
        }
        return parts.joined(separator: ", ")
    }
}

/// Barre de progression fine dédiée aux tuiles Home. Anime linéairement,
/// respecte prefers-reduced-motion.
private struct LifeStatusBar: View {
    let progress: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * clamped))
            }
        }
        .animation(reduceMotion ? nil : Theme.animQuick, value: progress)
    }
}

// MARK: - Preview

#Preview("Tiles") {
    ScrollView {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                LifeStatusTile(
                    icon: "moon.stars.fill",
                    value: "7h 12",
                    label: "Sommeil",
                    subtitle: "obj. 8h",
                    tint: Theme.sleep
                )
                LifeStatusTile(
                    icon: "flame.fill",
                    value: "1 450",
                    unit: "kcal",
                    label: "Nutrition",
                    progress: 0.66,
                    tint: Theme.nutrition
                )
            }
            HStack(spacing: 12) {
                LifeStatusTile(
                    icon: "figure.walk",
                    value: "4 820",
                    label: "Pas",
                    progress: 0.48,
                    status: .warning,
                    tint: Theme.fitness
                )
                LifeStatusTile(
                    icon: "drop.fill",
                    value: "800",
                    unit: "ml",
                    label: "Hydratation",
                    progress: 0.32,
                    status: .critical,
                    tint: Theme.hydration
                )
            }
        }
        .padding()
    }
    .background(Theme.bg)
}
