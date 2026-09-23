import SwiftUI
import WidgetKit

struct SleepWidget: Widget {
    let kind: String = "SleepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepWidgetProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("Sommeil & Réveil")
        .description("Surveille ton heure de réveil, ton heure de coucher idéale et ton repos.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct SleepWidgetEntry: TimelineEntry {
    let date: Date
    let alarmTime: String
    let targetHours: Double
    let suggestedBedtime: String
    let lastSleepHours: Double
}

struct SleepWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepWidgetEntry {
        SleepWidgetEntry(
            date: .now,
            alarmTime: "07:00",
            targetHours: 8.0,
            suggestedBedtime: "23:00",
            lastSleepHours: 7.5
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepWidgetEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepWidgetEntry>) -> Void) {
        let entry = read()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func read() -> SleepWidgetEntry {
        let defs = WidgetAppGroup.defaults
        let hour = defs?.integer(forKey: "wakeupHour") ?? 7
        let min = defs?.integer(forKey: "wakeupMinute") ?? 0
        let target = defs?.double(forKey: "sleepTargetHours") ?? 8.0
        let last = defs?.double(forKey: "lastSleepHours") ?? 7.5

        let effectiveTarget = target > 0 ? target : 8.0
        let bedHour = (hour - Int(effectiveTarget) + 24) % 24
        let bedMin = min

        let alarmStr = String(format: "%02d:%02d", hour, min)
        let bedStr = String(format: "%02d:%02d", bedHour, bedMin)

        return SleepWidgetEntry(
            date: .now,
            alarmTime: alarmStr,
            targetHours: effectiveTarget,
            suggestedBedtime: bedStr,
            lastSleepHours: last > 0 ? last : 7.5
        )
    }
}

// MARK: - Views

struct SleepWidgetView: View {
    let entry: SleepWidgetEntry
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
        .widgetURL(URL(string: "lifeos://sleep"))
    }

    private var smallView: some View {
        ZStack {
            Color(widgetHex: 0x08090C)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: 0x6C7BF1).opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0x6C7BF1))
                    }
                    Spacer()
                    Text("RÉVEIL")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(widgetHex: 0x6C7BF1))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(widgetHex: 0x6C7BF1).opacity(0.15), in: Capsule())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.alarmTime)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("Coucher conseillé : \(entry.suggestedBedtime)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }

                HStack {
                    Text("Dernière nuit : \(String(format: "%.1fh", entry.lastSleepHours))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(widgetHex: 0x6C7BF1))
                    Spacer()
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(widgetHex: 0x6C7BF1))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        Image(systemName: "moon.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0x6C7BF1))
                        Text("SOMMEIL & RÉVEIL")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .kerning(0.8)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("OBJECTIF \(String(format: "%.0fh", entry.targetHours))")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(widgetHex: 0x6C7BF1))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(widgetHex: 0x6C7BF1).opacity(0.15), in: Capsule())
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.alarmTime)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("prochain réveil")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text("Pour dormir \(String(format: "%.0fh", entry.targetHours)), couche-toi vers \(entry.suggestedBedtime).")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))

                    Spacer()
                }

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: 0x6C7BF1).opacity(0.2))
                            .frame(width: 54, height: 54)
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0x6C7BF1))
                    }
                    Text("\(String(format: "%.1fh", entry.lastSleepHours))")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("DERNIER")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(width: 65)
            }
            .padding(16)
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Réveil • \(entry.alarmTime)")
                    .font(.system(size: 12, weight: .bold))
                Text("Coucher conseillé : \(entry.suggestedBedtime) (obj. \(String(format: "%.0fh", entry.targetHours)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
