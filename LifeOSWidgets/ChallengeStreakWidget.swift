import WidgetKit
import SwiftUI

// MARK: - Shared data from App Group

struct WidgetChallengeData {
    let title: String
    let streak: Int
    let durationDays: Int
    let daysElapsed: Int
    let challengeType: String

    static var fromSharedDefaults: WidgetChallengeData? {
        let defaults = UserDefaults(suiteName: "group.lifeos.app") ?? .standard
        guard let title = defaults.string(forKey: "widget_challenge_title") else { return nil }
        return WidgetChallengeData(
            title: title,
            streak: defaults.integer(forKey: "widget_challenge_streak"),
            durationDays: defaults.integer(forKey: "widget_challenge_duration"),
            daysElapsed: defaults.integer(forKey: "widget_challenge_elapsed"),
            challengeType: defaults.string(forKey: "widget_challenge_type") ?? "custom"
        )
    }

    var progressFraction: Double {
        guard durationDays > 0 else { return 0 }
        return min(1.0, Double(daysElapsed) / Double(durationDays))
    }

    var color: Color {
        switch challengeType {
        case "water":      return Color(red: 0.24, green: 0.70, blue: 0.88)
        case "sport":      return Color(red: 0.95, green: 0.45, blue: 0.42)
        case "smoking":    return Color(red: 0.61, green: 0.48, blue: 0.95)
        case "meditation": return Color(red: 0.30, green: 0.76, blue: 0.54)
        case "nutrition":  return Color(red: 0.88, green: 0.64, blue: 0.24)
        case "sleep":      return Color(red: 0.42, green: 0.48, blue: 0.95)
        default:           return Color.accentColor
        }
    }

    var icon: String {
        switch challengeType {
        case "water":      return "drop.fill"
        case "sport":      return "figure.run"
        case "smoking":    return "smoke.fill"
        case "meditation": return "brain.head.profile"
        case "nutrition":  return "leaf.fill"
        case "sleep":      return "moon.stars.fill"
        default:           return "flame.fill"
        }
    }
}

// MARK: - Timeline Entry

struct ChallengeEntry: TimelineEntry {
    let date: Date
    let data: WidgetChallengeData?
}

// MARK: - Provider

struct ChallengeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChallengeEntry {
        ChallengeEntry(date: .now, data: WidgetChallengeData(
            title: "Boire 8 verres d'eau",
            streak: 5, durationDays: 21, daysElapsed: 8, challengeType: "water"
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ChallengeEntry) -> Void) {
        completion(ChallengeEntry(date: .now, data: WidgetChallengeData.fromSharedDefaults))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChallengeEntry>) -> Void) {
        let entry = ChallengeEntry(date: .now, data: WidgetChallengeData.fromSharedDefaults)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget View

struct ChallengeStreakWidgetView: View {
    let entry: ChallengeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let data = entry.data {
            filledView(data: data)
        } else {
            emptyView
        }
    }

    private func filledView(data: WidgetChallengeData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: data.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(data.color)
                Text("Défi en cours")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(data.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("\(data.streak)")
                            .font(.system(size: 24, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    Text("jour\(data.streak != 1 ? "s" : "") de suite")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if data.durationDays > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("J\(data.daysElapsed)/\(data.durationDays)")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(data.color)
                        ProgressRingMini(progress: data.progressFraction, color: data.color)
                            .frame(width: 28, height: 28)
                    }
                }
            }

            ProgressView(value: data.progressFraction)
                .tint(data.color)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Aucun défi actif")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }
}

// MARK: - Mini progress ring for widget

private struct ProgressRingMini: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Widget Declaration

struct ChallengeStreakWidget: Widget {
    let kind = "ChallengeStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChallengeProvider()) { entry in
            ChallengeStreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Défi en cours")
        .description("Ton streak et ta progression sur le défi actif.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
