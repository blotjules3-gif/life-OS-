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
    let accentHex: Int

    // Noir/blanc (thèmes Clair/Sombre) → .primary : le widget suit le mode
    // système, pas le schéma forcé de l'app.
    var accent: Color {
        switch accentHex {
        case 0x000000, 0xFFFFFF: return .primary
        default: return Color(hex: UInt(accentHex))
        }
    }

    static func load() -> WidgetHabitsData {
        guard let defaults = UserDefaults(suiteName: "group.lifeos.app") else {
            return WidgetHabitsData(habits: [], appGroupWorking: false, lastSync: nil, accentHex: 0)
        }
        let accentHex = defaults.object(forKey: "widget_accent_hex") as? Int ?? 0
        let lastSync = defaults.object(forKey: "widget_habits_sync_date") as? Date
        guard let data = defaults.data(forKey: "widget_habits"),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return WidgetHabitsData(habits: [], appGroupWorking: true, lastSync: lastSync, accentHex: accentHex)
        }
        let habits = raw.compactMap { d -> WidgetHabit? in
            guard let name = d["name"] as? String,
                  let icon = d["icon"] as? String,
                  let colorHex = d["colorHex"] as? Int
            else { return nil }
            return WidgetHabit(name: name, icon: icon, colorHex: colorHex, isDoneToday: d["done"] as? Bool ?? false)
        }
        return WidgetHabitsData(habits: habits, appGroupWorking: true, lastSync: lastSync, accentHex: accentHex)
    }
}

// MARK: - Timeline

struct HabitsEntry: TimelineEntry {
    let date: Date
    let data: WidgetHabitsData

    var habits: [WidgetHabit] { data.habits }
    /// À faire d'abord, faites ensuite — l'utilisateur voit ce qui reste.
    var sortedHabits: [WidgetHabit] {
        habits.filter { !$0.isDoneToday } + habits.filter { $0.isDoneToday }
    }
    var doneCount: Int { habits.filter { $0.isDoneToday }.count }
    var total: Int { habits.count }
    var remaining: Int { total - doneCount }
    var progress: Double { total > 0 ? Double(doneCount) / Double(total) : 0 }
    var allDone: Bool { total > 0 && doneCount == total }
    var accent: Color { data.accent }
}

struct HabitsProvider: TimelineProvider {
    private func demoEntry() -> HabitsEntry {
        HabitsEntry(
            date: .now,
            data: WidgetHabitsData(
                habits: [
                    WidgetHabit(name: "Méditation", icon: "brain.head.profile", colorHex: 0x4CC38A, isDoneToday: true),
                    WidgetHabit(name: "Sport", icon: "dumbbell.fill", colorHex: 0x618EF1, isDoneToday: true),
                    WidgetHabit(name: "Lecture", icon: "book.fill", colorHex: 0xE0A23C, isDoneToday: false),
                    WidgetHabit(name: "Boire de l'eau", icon: "drop.fill", colorHex: 0x3CD0C8, isDoneToday: false),
                ],
                appGroupWorking: true,
                lastSync: .now,
                accentHex: 0
            ),
            challenge: WidgetChallengeData(
                title: "Boire 8 verres d'eau",
                streak: 5, durationDays: 21, daysElapsed: 8, challengeType: "water"
            )
        )
    }

    func placeholder(in context: Context) -> HabitsEntry { demoEntry() }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        completion(context.isPreview
                   ? demoEntry()
                   : HabitsEntry(date: .now, data: WidgetHabitsData.load(),
                                 challenge: WidgetChallengeData.fromSharedDefaults))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let entry = HabitsEntry(date: .now, data: WidgetHabitsData.load(),
                                challenge: WidgetChallengeData.fromSharedDefaults)
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

// MARK: - Primitives ORBIT (langage de l'onglet Profil)

/// Orbe miniature : bezel de ticks + anneau AngularGradient + compteur central.
private struct MiniOrb: View {
    let progress: Double
    let done: Int
    let total: Int
    let accent: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<36, id: \.self) { i in
                Capsule()
                    .fill(Color.primary.opacity(i % 3 == 0 ? 0.28 : 0.10))
                    .frame(width: 1.5, height: i % 3 == 0 ? 5 : 3)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(Double(i) * 10))
            }
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: size * 0.085)
                .padding(size * 0.13)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(colors: [accent.opacity(0.25), accent], center: .center),
                    style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(size * 0.13)
            VStack(spacing: -2) {
                Text("\(done)")
                    .font(.system(size: size * 0.30, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("/ \(total)")
                    .font(.system(size: size * 0.13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size + 12, height: size + 12)
    }
}

/// Jauge segmentée : un tick par habitude, rempli dans la couleur de l'habitude.
private struct TickGauge: View {
    let habits: [WidgetHabit]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(habits) { h in
                Capsule()
                    .fill(h.isDoneToday ? h.color : Color.primary.opacity(0.10))
                    .frame(height: 4)
            }
        }
    }
}

/// En-tête de facette « 01 HABITUDES » — index mono accent + titre black + barre.
private struct FacetHeader: View {
    let code: String
    let title: String
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(code)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 12, weight: .black))
                    .kerning(-0.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.primary)
            }
            Capsule().fill(accent).frame(width: 22, height: 2.5)
        }
    }
}

// MARK: - Widget views

struct HabitsWidgetView: View {
    let entry: HabitsEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { entry.accent }

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
                } else {
                    switch family {
                    case .systemSmall:  smallView
                    case .systemLarge:  largeView
                    default:            mediumView
                    }
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

    // MARK: Rangée habitude

    private func habitRow(_ h: WidgetHabit, chip: CGFloat = 22, font: CGFloat = 11) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(h.isDoneToday ? h.color.opacity(0.16) : Color.primary.opacity(0.05))
                Circle()
                    .strokeBorder(h.isDoneToday ? h.color.opacity(0.25) : Color.primary.opacity(0.08), lineWidth: 1)
                Image(systemName: h.isDoneToday ? "checkmark" : h.icon)
                    .font(.system(size: chip * 0.42, weight: .bold))
                    .foregroundStyle(h.isDoneToday ? AnyShapeStyle(h.color) : AnyShapeStyle(.secondary))
            }
            .frame(width: chip, height: chip)

            Text(h.name)
                .font(.system(size: font, weight: h.isDoneToday ? .regular : .semibold))
                .foregroundStyle(h.isDoneToday ? AnyShapeStyle(Color.secondary.opacity(0.6)) : AnyShapeStyle(.primary))
                .strikethrough(h.isDoneToday, color: .secondary.opacity(0.4))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    // MARK: Small — ce qu'il reste à faire

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("HABITUDES")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .kerning(1.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.doneCount)/\(entry.total)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(entry.allDone ? AnyShapeStyle(accent) : AnyShapeStyle(.primary))
            }

            TickGauge(habits: entry.habits)
                .padding(.top, 7)

            if entry.allDone {
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(accent)
                    Text("Journée parfaite")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.sortedHabits.prefix(3)) { h in
                        habitRow(h)
                    }
                }
                .padding(.top, 10)

                Spacer(minLength: 0)

                if entry.total > 3 {
                    Text("+ \(entry.total - 3) autre\(entry.total - 3 > 1 ? "s" : "")")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(13)
    }

    // MARK: Medium — orbe + liste

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                MiniOrb(progress: entry.progress, done: entry.doneCount,
                        total: entry.total, accent: accent, size: 82)
                Text(entry.allDone ? "PARFAIT" : "\(entry.remaining) RESTANTE\(entry.remaining > 1 ? "S" : "")")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(entry.allDone ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
            }

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.sortedHabits.prefix(4)) { h in
                    habitRow(h, chip: 24, font: 12)
                }
                if entry.total > 4 {
                    Text("+ \(entry.total - 4) autre\(entry.total - 4 > 1 ? "s" : "")")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    // MARK: Large — habitudes + défi

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .kerning(1.4)
                        .foregroundStyle(.secondary)
                    Text("MA JOURNÉE")
                        .font(.system(size: 17, weight: .black))
                        .kerning(-0.3)
                        .foregroundStyle(.primary)
                }
                Spacer()
                MiniOrb(progress: entry.progress, done: entry.doneCount,
                        total: entry.total, accent: accent, size: 52)
            }

            FacetHeader(code: "01", title: "Habitudes", accent: accent)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(entry.sortedHabits.prefix(5)) { h in
                    habitRow(h, chip: 23, font: 12)
                }
                if entry.total > 5 {
                    Text("+ \(entry.total - 5) autre\(entry.total - 5 > 1 ? "s" : "")")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 9)

            Spacer(minLength: 8)

            FacetHeader(code: "02", title: "Défi", accent: accent)

            Group {
                if let c = entry.challenge {
                    challengeRow(c)
                } else {
                    Text("Aucun défi actif — lance-en un depuis le Profil.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .padding(15)
    }

    private func challengeRow(_ c: WidgetChallengeData) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(c.color.opacity(0.14))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(c.color.opacity(0.2), lineWidth: 1)
                Image(systemName: c.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.color)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if c.durationDays > 0 {
                        Text("J\(c.daysElapsed)/\(c.durationDays)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("\(c.streak) j de suite")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(c.color)
                                .frame(width: max(4, geo.size.width * CGFloat(c.progressFraction)))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    // MARK: Lock screen – cercle

    private var lockCircularView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(entry.progress))
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
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
            if entry.allDone {
                Text("Journée parfaite")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.sortedHabits.filter { !$0.isDoneToday }.prefix(2).map(\.name).joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                .foregroundStyle(accent)
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
        .description("Tes habitudes du jour — et ton défi en cours sur le grand format.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}
