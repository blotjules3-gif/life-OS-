import WidgetKit
import SwiftUI

private extension Color {
    init(hex: UInt) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }
}

// MARK: - Shared data model

struct WidgetHabit: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let colorHex: Int
    let isDoneToday: Bool

    var color: Color { Color(hex: UInt(colorHex)) }
}

struct WidgetHabitsData {
    let habits: [WidgetHabit]
    let appGroupWorking: Bool
    let lastSync: Date?

    static func load() -> WidgetHabitsData {
        guard let defaults = UserDefaults(suiteName: "group.lifeos.app") else {
            return WidgetHabitsData(habits: [], appGroupWorking: false, lastSync: nil)
        }
        let lastSync = defaults.object(forKey: "widget_habits_sync_date") as? Date
        guard let data = defaults.data(forKey: "widget_habits"),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return WidgetHabitsData(habits: [], appGroupWorking: true, lastSync: lastSync)
        }
        let habits = raw.compactMap { d -> WidgetHabit? in
            guard let name = d["name"] as? String,
                  let icon = d["icon"] as? String,
                  let colorHex = d["colorHex"] as? Int
            else { return nil }
            return WidgetHabit(name: name, icon: icon, colorHex: colorHex, isDoneToday: d["done"] as? Bool ?? false)
        }
        return WidgetHabitsData(habits: habits, appGroupWorking: true, lastSync: lastSync)
    }
}

// MARK: - Timeline

struct HabitsEntry: TimelineEntry {
    let date: Date
    let data: WidgetHabitsData

    var habits: [WidgetHabit] { data.habits }
    var doneCount: Int { habits.filter { $0.isDoneToday }.count }
    var total: Int { habits.count }
}

struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: .now, data: WidgetHabitsData(
            habits: [
                WidgetHabit(name: "Méditation", icon: "brain.head.profile", colorHex: 0x4CC38A, isDoneToday: true),
                WidgetHabit(name: "Sport", icon: "dumbbell.fill", colorHex: 0x618EF1, isDoneToday: false),
                WidgetHabit(name: "Lecture", icon: "book.fill", colorHex: 0xE0A23C, isDoneToday: true),
            ],
            appGroupWorking: true,
            lastSync: .now
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(HabitsEntry(date: .now, data: WidgetHabitsData.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let entry = HabitsEntry(date: .now, data: WidgetHabitsData.load())
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

// MARK: - Views

struct HabitsWidgetView: View {
    let entry: HabitsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                lockCircularView
            } else if family == .accessoryRectangular {
                lockRectangularView
            } else if !entry.data.appGroupWorking {
                setupNeededView
            } else if entry.habits.isEmpty {
                noHabitsView
            } else if family == .systemSmall {
                smallView
            } else {
                mediumView
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
    }

    // Lock screen — cercle de progression
    private var lockCircularView: some View {
        ZStack {
            if entry.total > 0 {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: entry.total > 0 ? Double(entry.doneCount) / Double(entry.total) : 0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(entry.doneCount)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("/\(entry.total)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // Lock screen — barre rectangulaire
    private var lockRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: entry.doneCount == entry.total && entry.total > 0 ? "checkmark.circle.fill" : "square.grid.3x3.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Habitudes — \(entry.doneCount)/\(entry.total)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            ProgressView(value: entry.total > 0 ? Double(entry.doneCount) / Double(entry.total) : 0)
                .tint(.white)
            HStack(spacing: 6) {
                ForEach(entry.habits.prefix(5)) { h in
                    Image(systemName: h.isDoneToday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(h.isDoneToday ? .white : .secondary)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // App Group non configuré
    private var setupNeededView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            Text("Ouvre LifeOS\nune fois pour activer")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // App Group OK mais aucune habitude
    private var noHabitsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: 0x4CC38A))
            Text("Aucune habitude")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Crée tes habitudes\ndans LifeOS")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x4CC38A))
                Text("Habitudes")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.doneCount)/\(entry.total)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.doneCount == entry.total ? Color(hex: 0x4CC38A) : .secondary)
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
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x4CC38A))
                Text("Habitudes du jour")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.doneCount)/\(entry.total)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.doneCount == entry.total ? Color(hex: 0x4CC38A) : .primary)
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
                    .tint(entry.doneCount == entry.total ? Color(hex: 0x4CC38A) : .accentColor)
            }
        }
        .padding(14)
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
