import SwiftUI
import WidgetKit

struct GymFocusWidget: Widget {
    let kind: String = "GymFocusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GymFocusWidgetProvider()) { entry in
            GymFocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Programme Sport")
        .description("Visualise ta séance de musculation ou ton focus du jour.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct GymFocusWidgetEntry: TimelineEntry {
    let date: Date
    let weekdayName: String
    let sessionTitle: String
    let focus: String
    let isRestDay: Bool
}

struct GymFocusWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> GymFocusWidgetEntry {
        GymFocusWidgetEntry(
            date: .now,
            weekdayName: "LUNDI",
            sessionTitle: "Pectoraux & Triceps",
            focus: "Développé couché · Dips · Écartés",
            isRestDay: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GymFocusWidgetEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GymFocusWidgetEntry>) -> Void) {
        let entry = read()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 3, to: .now) ?? .now.addingTimeInterval(10800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func read() -> GymFocusWidgetEntry {
        let defs = WidgetAppGroup.defaults
        let title = defs?.string(forKey: "gym_today_title") ?? "Pectoraux & Triceps"
        let focus = defs?.string(forKey: "gym_today_focus") ?? "Développé couché · Dips · Écartés"
        let isRest = defs?.bool(forKey: "gym_today_is_rest") ?? false

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: Date()).uppercased()

        return GymFocusWidgetEntry(
            date: .now,
            weekdayName: dayName,
            sessionTitle: title,
            focus: focus,
            isRestDay: isRest
        )
    }
}

// MARK: - Views

struct GymFocusWidgetView: View {
    let entry: GymFocusWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .accessoryRectangular:
                rectangularView
            default:
                smallView
            }
        }
        .widgetURL(URL(string: "lifeos://gym"))
    }

    private var smallView: some View {
        ZStack {
            Color(widgetHex: 0x08090C)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: 0xFFB800).opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0xFFB800))
                    }
                    Spacer()
                    Text(entry.weekdayName)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(widgetHex: 0xFFB800))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(widgetHex: 0xFFB800).opacity(0.15), in: Capsule())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.isRestDay ? "RÉCUPÉRATION" : "SÉANCE DU JOUR")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(entry.isRestDay ? "Jour de repos" : entry.sessionTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                if !entry.isRestDay {
                    Text(entry.focus)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                HStack {
                    Text(entry.isRestDay ? "Récupérer" : "S'entraîner")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                    Spacer()
                    Image(systemName: entry.isRestDay ? "bed.double.fill" : "arrow.right")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(widgetHex: 0xFFB800), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(14)
        }
    }

    private var mediumView: some View {
        ZStack {
            Color(widgetHex: 0x08090C)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0xFFB800))
                        Text("PROGRAMME MUSCU")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .kerning(0.8)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(entry.weekdayName)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(widgetHex: 0xFFB800))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(widgetHex: 0xFFB800).opacity(0.15), in: Capsule())
                    }

                    Text(entry.isRestDay ? "Jour de repos & Récupération" : entry.sessionTitle)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text(entry.isRestDay ? "Profite pour t'étirer, t'hydrater et bien dormir." : entry.focus)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)

                    Spacer()
                }

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: 0xFFB800).opacity(0.18))
                            .frame(width: 54, height: 54)
                        Image(systemName: entry.isRestDay ? "moon.stars.fill" : "figure.strengthtraining.traditional")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0xFFB800))
                    }
                    Text(entry.isRestDay ? "REPOS" : "GO !")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 70)
            }
            .padding(16)
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 10) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sport • \(entry.sessionTitle)")
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text(entry.focus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
