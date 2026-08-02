import SwiftUI
import WidgetKit

/// Version iOS 17+ du widget habitudes — chaque ligne est un bouton qui
/// toggle l'habitude sans ouvrir l'app (via `ToggleHabitIntent`).
///
/// Coexiste avec l'ancien `HabitsWidget` (non-interactif) qui reste dispo
/// pour les iPhones < iOS 17. L'user choisit lequel poser sur son écran.
@available(iOS 17.0, *)
struct InteractiveHabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "InteractiveHabitsWidget",
            provider: HabitsProvider()
        ) { entry in
            InteractiveHabitsView(entry: entry)
        }
        .configurationDisplayName("Habitudes · interactif")
        .description("Coche tes habitudes directement depuis l'écran d'accueil.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@available(iOS 17.0, *)
private struct InteractiveHabitsView: View {
    let entry: HabitsEntry
    @Environment(\.widgetFamily) private var family

    private var visibleHabits: [WidgetHabit] {
        let max = family == .systemLarge ? 8 : 4
        return Array(entry.sortedHabits.prefix(max))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15).padding(.horizontal, 14)
            list
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Habitudes du jour")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(entry.doneCount) sur \(entry.total) faites")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 3)
                    .frame(width: 32, height: 32)
                Circle().trim(from: 0, to: entry.progress)
                    .stroke(entry.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 32, height: 32)
                Text("\(Int(entry.progress * 100))")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(visibleHabits) { habit in
                Button(intent: ToggleHabitIntent(habitName: habit.name)) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(habit.isDoneToday ? habit.color : Color.gray.opacity(0.15))
                                .frame(width: 26, height: 26)
                            Image(systemName: habit.isDoneToday ? "checkmark" : habit.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(habit.isDoneToday ? .white : .primary)
                        }
                        Text(habit.name)
                            .font(.system(size: 13, weight: habit.isDoneToday ? .regular : .semibold))
                            .foregroundStyle(habit.isDoneToday ? .secondary : .primary)
                            .strikethrough(habit.isDoneToday)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .tint(habit.color)
            }
        }
        .padding(.vertical, 4)
    }
}
