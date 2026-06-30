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

// MARK: - Data model

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
    var progress: Double { total > 0 ? Double(doneCount) / Double(total) : 0 }
    var allDone: Bool { total > 0 && doneCount == total }
}

struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: .now, data: WidgetHabitsData(
            habits: [
                WidgetHabit(name: "Méditation", icon: "brain.head.profile", colorHex: 0x4CC38A, isDoneToday: true),
                WidgetHabit(name: "Sport", icon: "dumbbell.fill", colorHex: 0x618EF1, isDoneToday: true),
                WidgetHabit(name: "Lecture", icon: "book.fill", colorHex: 0xE0A23C, isDoneToday: false),
                WidgetHabit(name: "Eau", icon: "drop.fill", colorHex: 0x3CD0C8, isDoneToday: false),
            ],
            appGroupWorking: true,
            lastSync: .now
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : HabitsEntry(date: .now, data: WidgetHabitsData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let entry = HabitsEntry(date: .now, data: WidgetHabitsData.load())
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

// MARK: - Shared ring component

private struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let tint: Color
    let trackColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Widget views

struct HabitsWidgetView: View {
    let entry: HabitsEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private let teal = Color(hex: 0x4CC38A)

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                lockCircularView
            case .accessoryRectangular:
                lockRectangularView
            default:
                if !entry.data.appGroupWorking {
                    setupNeededView
                } else if entry.habits.isEmpty {
                    noHabitsView
                } else if family == .systemSmall {
                    smallView
                } else {
                    mediumView
                }
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryCircular || family == .accessoryRectangular {
                Color.clear
            } else {
                Color(uiColor: .systemBackground)
            }
        }
    }

    // MARK: Small — grand anneau centré

    private var smallView: some View {
        VStack(spacing: 0) {
            // En-tête
            HStack {
                Text("LIFEOS")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(teal)
                    .kerning(1.8)
                Spacer()
                if entry.allDone {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.bottom, 6)

            // Anneau principal
            ZStack {
                ProgressRing(
                    progress: entry.progress,
                    lineWidth: 9,
                    tint: entry.allDone ? teal : teal,
                    trackColor: Color.secondary.opacity(0.12)
                )

                VStack(spacing: -1) {
                    Text("\(entry.doneCount)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(entry.allDone ? teal : .primary)
                        .contentTransition(.numericText())
                    Text("/ \(entry.total)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)

            Spacer().frame(height: 8)

            // Dots d'habitudes
            HStack(spacing: 5) {
                ForEach(entry.habits.prefix(6)) { h in
                    if h.isDoneToday {
                        Circle()
                            .fill(h.color)
                            .frame(width: 9, height: 9)
                    } else {
                        Circle()
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 9, height: 9)
                    }
                }
                if entry.total > 6 {
                    Text("+\(entry.total - 6)")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer().frame(height: 5)

            // Message
            Text(entry.allDone ? "Journée parfaite !" : entry.doneCount == 0 ? "C'est parti !" : "\(entry.total - entry.doneCount) restante\(entry.total - entry.doneCount > 1 ? "s" : "")")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(entry.allDone ? teal : .secondary)
        }
        .padding(12)
    }

    // MARK: Medium — anneau à gauche, liste à droite

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Colonne gauche : anneau
            VStack(spacing: 8) {
                ZStack {
                    ProgressRing(
                        progress: entry.progress,
                        lineWidth: 10,
                        tint: entry.allDone ? teal : teal,
                        trackColor: Color.secondary.opacity(0.12)
                    )

                    // Icônes des habitudes faites en superposition subtile
                    VStack(spacing: -2) {
                        Text("\(entry.doneCount)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(entry.allDone ? teal : .primary)
                            .contentTransition(.numericText())
                        Text("/ \(entry.total)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 88, height: 88)

                Text(entry.allDone ? "Parfait !" : "habitudes")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(entry.allDone ? teal : .secondary)
                    .kerning(0.3)
            }

            // Séparateur
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 4)

            // Colonne droite : liste
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.habits.prefix(5)) { h in
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(h.isDoneToday ? h.color.opacity(0.18) : Color.secondary.opacity(0.07))
                                .frame(width: 26, height: 26)
                            Image(systemName: h.isDoneToday ? "checkmark" : h.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(h.isDoneToday ? h.color : Color.secondary.opacity(0.5))
                        }

                        Text(h.name)
                            .font(.system(size: 12, weight: h.isDoneToday ? .semibold : .regular))
                            .foregroundStyle(h.isDoneToday ? .primary : Color.secondary.opacity(0.65))
                            .lineLimit(1)

                        Spacer()

                        if h.isDoneToday {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(h.color.opacity(0.8))
                        }
                    }
                }

                if entry.total > 5 {
                    Text("+ \(entry.total - 5) autres")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    // MARK: Lock screen – cercle

    private var lockCircularView: some View {
        ZStack {
            ProgressRing(
                progress: entry.progress,
                lineWidth: 4,
                tint: .white,
                trackColor: Color.white.opacity(0.25)
            )
            VStack(spacing: 0) {
                Text("\(entry.doneCount)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("/\(entry.total)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: Lock screen – rectangle

    private var lockRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: entry.allDone ? "checkmark.seal.fill" : "square.grid.3x3.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(entry.allDone ? "Toutes faites !" : "Habitudes  \(entry.doneCount)/\(entry.total)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            ProgressView(value: entry.progress)
                .tint(.white)
            HStack(spacing: 5) {
                ForEach(entry.habits.prefix(6)) { h in
                    Image(systemName: h.isDoneToday ? h.icon : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(h.isDoneToday ? .white : Color.white.opacity(0.35))
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: États vides

    private var setupNeededView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            Text("Ouvre LifeOS\nune fois pour activer")
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noHabitsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(teal)
            Text("Pas encore\nd'habitudes")
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget config

struct HabitsWidget: Widget {
    let kind = "HabitsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitsProvider()) { entry in
            HabitsWidgetView(entry: entry)
        }
        .configurationDisplayName("Habitudes")
        .description("Progression de tes habitudes du jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
