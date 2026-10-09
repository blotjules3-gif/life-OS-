import SwiftUI
import WidgetKit

/// Widget « Score énergie » — lit la valeur publiée par l'app dans
/// App Group defaults et l'affiche en 3 familles :
///
/// - `.accessoryCircular` — Lock Screen rond avec score central
/// - `.accessoryRectangular` — Lock Screen barre avec score + label
/// - `.systemSmall` — écran d'accueil, card carrée avec score + tendance
///
/// L'app publie le score via `EnergyScore.publishToAppGroup(...)` puis
/// devrait appeler `WidgetCenter.shared.reloadTimelines(ofKind: "EnergyScoreWidget")`.
struct EnergyScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetKinds.energy,
            provider: EnergyProvider()
        ) { entry in
            EnergyView(entry: entry)
        }
        .configurationDisplayName("Score énergie")
        .description("Ton score du jour, calculé sur ton téléphone : sommeil, humeur, eau et habitudes.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Provider

private struct EnergyEntry: TimelineEntry {
    let date: Date
    let score: Int?
    let label: String
    let colorHex: String
    let updatedAt: Date?
    /// Score calcule aujourd'hui. Sinon : "Pas encore calcule aujourd'hui", jamais
    /// le score d'hier affiche comme celui du jour.
    let isToday: Bool

    var link: URL { isToday ? WidgetLink.url("today") : WidgetLink.briefing }
}

private struct EnergyProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnergyEntry {
        EnergyEntry(date: .now, score: 72, label: "Bon", colorHex: "#30D158", updatedAt: .now, isToday: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (EnergyEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EnergyEntry>) -> Void) {
        let midnight = WidgetTimeline.nextMidnight()
        // L'app recharge le widget a chaque nouveau score ; a minuit, le score d'hier
        // n'est plus montre.
        completion(Timeline(entries: [read(), read(at: midnight)], policy: .after(midnight)))
    }

    private func read(at date: Date = .now) -> EnergyEntry {
        guard let grp = LifeOSGroup.defaults, grp.object(forKey: EnergyKeys.value) != nil else {
            return EnergyEntry(date: date, score: nil, label: "", colorHex: "#8A7C6E", updatedAt: nil, isToday: false)
        }
        let ts = grp.double(forKey: EnergyKeys.updatedAt)
        let updatedAt: Date? = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        // Jour ecrit par l'app ; a defaut (ancienne version), jour de la mise a jour.
        let day = grp.string(forKey: EnergyKeys.day) ?? updatedAt.map { WidgetDay.stamp($0) }
        let today = WidgetDay.isToday(day, now: date)
        return EnergyEntry(date: date, score: today ? grp.integer(forKey: EnergyKeys.value) : nil,
                           label: today ? (grp.string(forKey: EnergyKeys.label) ?? "") : "",
                           colorHex: grp.string(forKey: EnergyKeys.colorHex) ?? "#8A7C6E",
                           updatedAt: updatedAt, isToday: today)
    }
}

// MARK: - View

private struct EnergyView: View {
    let entry: EnergyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular.lifeOSAccessoryBackground()
            case .accessoryRectangular: rectangular.lifeOSAccessoryBackground()
            default: small
            }
        }
        .widgetURL(entry.link)
    }

    @Environment(\.widgetRenderingMode) private var mode

    private var color: Color { Color(hex: entry.colorHex) }

    private var scoreText: String {
        entry.score.map(String.init) ?? "?"
    }

    @ViewBuilder
    private var small: some View {
        if entry.score != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text(entry.label.uppercased())
                        .font(.system(size: 10, weight: .bold)).kerning(0.8)
                        .opacity(0.85)
                }
                Spacer()
                Text(scoreText)
                    .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                Text("sur 100 · énergie")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(mode == .fullColor ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(14)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [color.opacity(0.9), color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            WidgetEmptyState(icon: "bolt.fill", title: "Pas encore calculé aujourd'hui",
                             message: "Fais ton bilan du matin pour voir ton score.", tint: color)
                .padding(14)
                .lifeOSWidgetBackground()
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0, to: min(1, CGFloat(entry.score ?? 0) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
            VStack(spacing: 0) {
                Text(scoreText)
                    .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rectangular: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(color.opacity(0.35), lineWidth: 3).frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: min(1, CGFloat(entry.score ?? 0) / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: 36)
                Text(scoreText)
                    .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Énergie")
                    .font(.system(size: 13, weight: .semibold))
                Text(entry.score == nil ? "Pas encore calculé" : entry.label)
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Color(hex:) local (le widget target n'a pas Theme.swift)

private extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = WidgetPalette.tone(r, g, b)
    }
}
