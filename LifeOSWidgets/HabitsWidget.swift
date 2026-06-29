import WidgetKit
import SwiftUI

// MARK: - Shared data model

struct WidgetHabit: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let colorHex: Int
    let isDoneToday: Bool

    var color: Color { Color(hex: UInt(colorHex)) }

    static var fromSharedDefaults: [WidgetHabit] {
        let defaults = UserDefaults(suiteName: "group.lifeos.app") ?? .standard
        guard let data = defaults.data(forKey: "widget_habits"),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return raw.compactMap { d in
            guard let name = d["name"] as? String,
                  let icon = d["icon"] as? String,
                  let colorHex = d["colorHex"] as? Int
            else { return nil }
            return WidgetHabit(name: name, icon: icon, colorHex: colorHex, isDoneToday: d["done"] as? Bool ?? false)
        }
    }
}

// MARK: - Timeline

struct HabitsEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabit]

    var doneCount: Int { habits.filter { $0.isDoneToday }.count }
    var total: Int { habits.count }
}

struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: .now, habits: [
            WidgetHabit(name: "Méditation", icon: "brain.head.profile", colorHex: 0x4CC38A, isDoneToday: true),
            WidgetHabit(name: "Sport", icon: "dumbbell.fill", colorHex: 0x618EF1, isDoneToday: false),
            WidgetHabit(name: "Lecture", icon: "book.fill", colorHex: 0xE0A23C, isDoneToday: true),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        completion(HabitsEntry(date: .now, habits: WidgetHabit.fromSharedDefaults))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let entry = HabitsEntry(date: .now, habits: WidgetHabit.fromSharedDefaults)
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

// MARK: - Views

struct HabitsWidgetView: View {
    let entry: HabitsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.habits.isEmpty {
            emptyView
        } else if family == .systemSmall {
            smallView
        } else {
            mediumView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("Aucune habitude")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Habitudes")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.doneCount)/\(entry.total)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.doneCount == entry.total && entry.total > 0 ? .green : .secondary)
            }

            Spacer()

            ForEach(entry.habits.prefix(4)) { h in
                HStack(spacing: 6) {
                    Image(systemName: h.isDoneToday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(h.isDoneToday ? h.color : Color.secondary.opacity(0.4))
                    Text(h.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(h.isDoneToday ? .primary : .secondary)
                        .lineLimit(1)
                }
            }

            if entry.total > 4 {
                Text("+\(entry.total - 4) autres")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Habitudes du jour")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.doneCount)/\(entry.total)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.doneCount == entry.total && entry.total > 0 ? .green : .primary)
            }

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(entry.habits.prefix(6)) { h in
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(h.isDoneToday ? h.color.opacity(0.15) : Color.secondary.opacity(0.08))
                                .frame(width: 26, height: 26)
                            Image(systemName: h.isDoneToday ? "checkmark" : h.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(h.isDoneToday ? h.color : .secondary)
                        }
                        Text(h.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(h.isDoneToday ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(h.isDoneToday ? h.color.opacity(0.07) : Color.secondary.opacity(0.04))
                    )
                }
            }

            if entry.total > 0 {
                ProgressView(value: Double(entry.doneCount), total: Double(entry.total))
                    .tint(entry.doneCount == entry.total ? .green : .accentColor)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}

// MARK: - Widget

struct HabitsWidget: Widget {
    let kind = "HabitsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitsProvider()) { entry in
            HabitsWidgetView(entry: entry)
        }
        .configurationDisplayName("Habitudes")
        .description("Tes habitudes du jour et ta progression.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
