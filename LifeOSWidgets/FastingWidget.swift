import SwiftUI
import WidgetKit

struct FastingWidget: Widget {
    let kind: String = "FastingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastingWidgetProvider()) { entry in
            FastingWidgetView(entry: entry)
        }
        .configurationDisplayName("Jeûne Intermittent")
        .description("Suis ton temps de jeûne écoulé et ta fenêtre d'alimentation.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct FastingWidgetEntry: TimelineEntry {
    let date: Date
    let elapsedHours: Double
    let targetHours: Int
    let isFasting: Bool

    var progress: Double {
        guard targetHours > 0 else { return 0 }
        return max(0.0, min(1.0, elapsedHours / Double(targetHours)))
    }

    var percentage: Int {
        Int(progress * 100)
    }
}

struct FastingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingWidgetEntry {
        FastingWidgetEntry(
            date: .now,
            elapsedHours: 14.5,
            targetHours: 16,
            isFasting: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingWidgetEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingWidgetEntry>) -> Void) {
        let entry = read()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func read() -> FastingWidgetEntry {
        let defs = WidgetAppGroup.defaults
        let target = defs?.integer(forKey: "fastTarget") ?? 16
        let startTs = defs?.double(forKey: "fastStart") ?? (Date().timeIntervalSince1970 - 14.5 * 3600)

        let elapsed = max(0.0, Date().timeIntervalSince1970 - startTs) / 3600.0

        return FastingWidgetEntry(
            date: .now,
            elapsedHours: elapsed > 0 ? elapsed : 14.0,
            targetHours: target > 0 ? target : 16,
            isFasting: true
        )
    }
}

// MARK: - Views

struct FastingWidgetView: View {
    let entry: FastingWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            default:
                smallView
            }
        }
        .widgetURL(URL(string: "lifeos://fasting"))
    }

    private var smallView: some View {
        ZStack {
            Color(widgetHex: 0x08090C)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: 0xE07B3C).opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0xE07B3C))
                    }
                    Spacer()
                    Text("\(entry.targetHours)h:8h")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(widgetHex: 0xE07B3C))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(widgetHex: 0xE07B3C).opacity(0.15), in: Capsule())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("JEÛNE EN COURS")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatElapsed(entry.elapsedHours))
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/ \(entry.targetHours)h")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(widgetHex: 0xE07B3C), Color(widgetHex: 0xFFB800)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * entry.progress))
                        }
                    }
                    .frame(height: 6)
                }

                HStack {
                    Text(entry.elapsedHours >= 12.0 ? "🔥 Cétose active" : "Digestion terminée")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(widgetHex: 0xE07B3C))
                    Spacer()
                    Text("\(entry.percentage)%")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(14)
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .bold))
                Text("\(Int(entry.elapsedHours))h")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Jeûne • \(formatElapsed(entry.elapsedHours)) / \(entry.targetHours)h")
                    .font(.system(size: 12, weight: .bold))
                Text(entry.elapsedHours >= 12.0 ? "Zone de brûlage des graisses active 🔥" : "En cours")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatElapsed(_ h: Double) -> String {
        let hours = Int(h)
        let mins = Int((h - Double(hours)) * 60)
        return "\(hours)h\(String(format: "%02d", mins))"
    }
}
