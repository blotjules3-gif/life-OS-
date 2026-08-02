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
            kind: "EnergyScoreWidget",
            provider: EnergyProvider()
        ) { entry in
            EnergyView(entry: entry)
        }
        .configurationDisplayName("Score énergie")
        .description("Ton score du jour, calculé on-device — sommeil × humeur × eau × habitudes.")
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
}

private struct EnergyProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnergyEntry {
        EnergyEntry(date: .now, score: 72, label: "Bon", colorHex: "#30D158", updatedAt: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (EnergyEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EnergyEntry>) -> Void) {
        let entry = read()
        // Refresh à chaque heure pleine — plus si l'app publie une update
        // (via WidgetCenter.reloadTimelines).
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func read() -> EnergyEntry {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app") else {
            return EnergyEntry(date: .now, score: nil, label: "—", colorHex: "#8A7C6E", updatedAt: nil)
        }
        // `object(forKey:) != nil` évite de retourner 0 quand la clé n'a jamais été set.
        let hasScore = grp.object(forKey: "energyScore.value") != nil
        let score = hasScore ? grp.integer(forKey: "energyScore.value") : nil
        let label = grp.string(forKey: "energyScore.label") ?? "—"
        let colorHex = grp.string(forKey: "energyScore.colorHex") ?? "#8A7C6E"
        let ts = grp.double(forKey: "energyScore.updatedAt")
        let updatedAt: Date? = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return EnergyEntry(date: .now, score: score, label: label, colorHex: colorHex, updatedAt: updatedAt)
    }
}

// MARK: - View

private struct EnergyView: View {
    let entry: EnergyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        default:
            small
        }
    }

    private var color: Color { Color(hex: entry.colorHex) }

    private var scoreText: String {
        entry.score.map(String.init) ?? "—"
    }

    private var small: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [color.opacity(0.9), color.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(entry.label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .kerning(0.8)
                }
                Spacer()
                Text(scoreText)
                    .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                Text("sur 100 · énergie")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .containerBackground(for: .widget) { Color.clear }
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
                Text("nrj")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
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
                Text(entry.label)
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
        self.init(red: r, green: g, blue: b)
    }
}
