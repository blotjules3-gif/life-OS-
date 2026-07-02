import SwiftUI

/// Composants UI partagés par tous les modules.

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .black)).textCase(.uppercase).kerning(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).monoLabel(10)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).monoLabel(11).foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pastille d'icône NIKE : carré NET monochrome haute intensité (encre + glyphe inverse).
/// `tint` conservé pour compat mais l'app reste noir & blanc (accent volt réservé aux CTA).
struct IconBadge: View {
    @AppStorage("appTheme") private var themeRaw = "classic"
    let icon: String
    var tint: Color = Theme.accent
    var size: CGFloat = 44
    var body: some View {
        let glass = themeRaw == "glass"
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(glass ? Color.white : Color(uiColor: .systemBackground))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .fill(glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.primary))
            )
            .overlay {
                if glass {
                    RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                }
            }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var icon: String? = nil
    var tint: Color = Theme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.headline)
            }
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.system(size: 15, weight: .black)).textCase(.uppercase).kerning(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.volt, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .foregroundStyle(Theme.onVolt)
            .shadow(color: Theme.volt.opacity(0.4), radius: 12, y: 5)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var message: String = ""
    var tint: Color = Theme.accent
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 76, height: 76)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.5))
            Text(title)
                .font(.system(size: 17, weight: .black)).textCase(.uppercase).kerning(-0.2)
                .foregroundStyle(Theme.textPrimary)
            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.system(size: 14, weight: .black)).textCase(.uppercase).kerning(0.5)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Theme.volt, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .foregroundStyle(Theme.onVolt)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

/// Bandeau qui signale un module nécessitant une intégration externe (IA / banque / API).
struct IntegrationNotice: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.badge.clock")
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

/// Anneau de progression réutilisable (timers, scores, objectifs).
struct ProgressRing: View {
    var progress: Double          // 0...1
    var lineWidth: CGFloat = 12
    var tint: Color = Theme.accent
    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.stroke, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}

/// Petit utilitaire de formatage de durée.
func formatHMS(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%02d:%02d", m, sec)
}

func formatHoursMinutes(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60
    return "\(h)h\(String(format: "%02d", m))"
}
