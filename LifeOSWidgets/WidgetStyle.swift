import SwiftUI
import WidgetKit

// Briques communes des widgets LifeOS : fond du conteneur, teintes par domaine,
// respect des modes de rendu imposes par l'OS (couleur, teinte, vibrant/StandBy),
// barres, anneaux et etats vides honnetes.

/// Teintes de domaine (memes roles que l'app : travail bleu, nutrition vert, sport
/// orange, sommeil violet, eau bleu clair). Passent par `WidgetPalette` : neutre si
/// l'utilisateur a choisi la palette monochrome.
enum WTint {
    static var work: Color { WidgetPalette.tone(0.16, 0.47, 0.96) }
    static var nutrition: Color { WidgetPalette.tone(0.18, 0.70, 0.38) }
    static var sport: Color { WidgetPalette.tone(0.98, 0.52, 0.12) }
    static var sleep: Color { WidgetPalette.tone(0.56, 0.40, 0.94) }
    static var water: Color { WidgetPalette.tone(0.10, 0.62, 0.92) }
    static var fasting: Color { WidgetPalette.tone(0.90, 0.48, 0.24) }
    static var coach: Color { WidgetPalette.tone(0.30, 0.48, 0.92) }
    /// Role distinct : retard, alerte.
    static var warning: Color { WidgetPalette.tone(0.93, 0.33, 0.25) }
    static var protein: Color { WidgetPalette.tone(0.86, 0.33, 0.42) }
    static var carbs: Color { WidgetPalette.tone(0.95, 0.66, 0.16) }
    static var fat: Color { WidgetPalette.tone(0.27, 0.62, 0.90) }
}

extension View {
    /// Fond standard d'un widget d'ecran d'accueil (retire par l'OS en StandBy et en
    /// mode teinte : le contenu reste lisible car il utilise `.primary`).
    func lifeOSWidgetBackground() -> some View {
        containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    /// Fond des familles d'ecran verrouille.
    func lifeOSAccessoryBackground() -> some View {
        containerBackground(for: .widget) { Color.clear }
    }

    /// Couleur du domaine en mode couleur ; en mode teinte ou vibrant, couleur
    /// primaire marquee comme accent (l'OS applique sa teinte).
    func wTint(_ color: Color) -> some View { modifier(ModeTint(color: color)) }
}

private struct ModeTint: ViewModifier {
    let color: Color
    @Environment(\.widgetRenderingMode) private var mode
    func body(content: Content) -> some View {
        content
            .foregroundStyle(mode == .fullColor ? AnyShapeStyle(color) : AnyShapeStyle(.primary))
            .widgetAccentable()
    }
}

/// Pastille de titre : icone teintee + libelle court en capitales.
struct WidgetHeader: View {
    let icon: String
    let title: String
    let tint: Color
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .wTint(tint)
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .kerning(0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Barre de progression horizontale.
struct WidgetBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .frame(width: max(progress > 0 ? height : 0, geo.size.width * max(0, min(1, progress))))
                    .wTint(tint)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Anneau de progression.
struct WidgetRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .wTint(tint)
        }
        .accessibilityHidden(true)
    }
}

/// Etat vide : ce qui manque et comment le remplir. Jamais de chiffre invente.
struct WidgetEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            Image(systemName: icon)
                .font(.system(size: compact ? 14 : 20, weight: .bold))
                .wTint(tint)
            Text(title)
                .font(.system(size: compact ? 12 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(message)
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 2 : 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Timeline : maintenant, puis minuit (le jour change sans attendre l'app).
enum WidgetTimeline {
    static func nextMidnight(after date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400))
    }

    static func liters(_ ml: Int) -> String {
        let l = Double(ml) / 1000
        return l.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR"))) + " L"
    }

    static func hm(_ hour: Int, _ minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }
}
