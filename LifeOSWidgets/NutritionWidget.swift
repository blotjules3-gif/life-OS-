import SwiftUI
import WidgetKit

/// Calories et macros du jour face a tes objectifs (ceux de l'app ; un objectif pas
/// regle est la valeur par defaut de l'app et le widget le dit).
struct NutritionWidget: Widget {
    let kind = WidgetKinds.nutrition

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NutritionProvider()) { entry in
            NutritionWidgetView(entry: entry)
        }
        .configurationDisplayName("Nutrition")
        .description("Tes calories et macros du jour face à tes objectifs.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct NutritionEntry: TimelineEntry {
    let date: Date
    /// Deja ramene au jour de `date` (un instantane d'hier = rien enregistre aujourd'hui).
    let snapshot: NutritionSnapshot?

    var kcalProgress: Double { snapshot.map { NutritionSnapshot.ratio(Double($0.kcal), $0.goals.kcal) } ?? 0 }
    var remainingKcal: Int { snapshot.map { $0.goals.kcal - $0.kcal } ?? 0 }
}

struct NutritionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionEntry {
        NutritionEntry(date: .now, snapshot: NutritionSnapshot(day: WidgetDay.stamp(), updatedAt: .now, kcal: 1340, protein: 92, carbs: 140, fat: 45,
                                                               entries: 3, goals: .resolve(kcal: 2200, protein: 150, carbs: 250, fat: 70)))
    }

    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        let midnight = WidgetTimeline.nextMidnight()
        completion(Timeline(entries: [read(at: .now), read(at: midnight)], policy: .after(midnight)))
    }

    private func read(at date: Date) -> NutritionEntry {
        NutritionEntry(date: date, snapshot: WidgetSnapshotStore.read(NutritionSnapshot.self, key: NutritionSnapshot.key)?.current(now: date))
    }
}

struct NutritionWidgetView: View {
    let entry: NutritionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular.lifeOSAccessoryBackground()
            case .accessoryRectangular: rectangular.lifeOSAccessoryBackground()
            case .systemMedium: medium.padding(14).lifeOSWidgetBackground()
            default: small.padding(14).lifeOSWidgetBackground()
            }
        }
        .widgetURL(WidgetLink.nutrition)
    }

    private var notLoaded: some View {
        WidgetEmptyState(icon: "fork.knife", title: "Nutrition", message: "Ouvre LifeOS une fois pour afficher tes calories ici.", tint: WTint.nutrition)
    }

    private func kcalCaption(_ s: NutritionSnapshot) -> String {
        if s.entries == 0 { return "Rien noté aujourd'hui" }
        return remainingText
    }

    private var remainingText: String {
        entry.remainingKcal >= 0 ? "Reste \(entry.remainingKcal) kcal" : "\(-entry.remainingKcal) kcal au-dessus"
    }

    @ViewBuilder
    private var small: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "fork.knife", title: "CALORIES", tint: WTint.nutrition)
                ZStack {
                    WidgetRing(progress: entry.kcalProgress, tint: WTint.nutrition, lineWidth: 8)
                    VStack(spacing: 0) {
                        Text("\(s.kcal)").font(.system(size: 20, weight: .black, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6)
                        Text("/ \(s.goals.kcal)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 74)
                Text(kcalCaption(s) + (s.goals.kcalIsDefault ? " · objectif par défaut" : ""))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            notLoaded
        }
    }

    @ViewBuilder
    private var medium: some View {
        if let s = entry.snapshot {
            HStack(spacing: 14) {
                ZStack {
                    WidgetRing(progress: entry.kcalProgress, tint: WTint.nutrition, lineWidth: 9)
                    VStack(spacing: 0) {
                        Text("\(s.kcal)").font(.system(size: 20, weight: .black, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6)
                        Text("kcal").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 5) {
                    WidgetHeader(icon: "fork.knife", title: "AUJOURD'HUI", tint: WTint.nutrition, trailing: kcalCaption(s))
                    macro("Protéines", s.protein, s.goals.protein, WTint.protein)
                    macro("Glucides", s.carbs, s.goals.carbs, WTint.carbs)
                    macro("Lipides", s.fat, s.goals.fat, WTint.fat)
                    if s.goals.macrosAreDefault || s.goals.kcalIsDefault {
                        Text("Objectifs par défaut, règle-les dans LifeOS")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            notLoaded
        }
    }

    private func macro(_ name: String, _ value: Double, _ goal: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int(value.rounded())) / \(goal) g").font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            WidgetBar(progress: NutritionSnapshot.ratio(value, goal), tint: tint, height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    private var circular: some View {
        Gauge(value: entry.kcalProgress) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            Text(entry.snapshot.map { "\($0.kcal)" } ?? "0")
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("Calories : \(entry.snapshot?.kcal ?? 0) sur \(entry.snapshot?.goals.kcal ?? 0)")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(entry.snapshot.map { "\($0.kcal) / \($0.goals.kcal) kcal" } ?? "Nutrition", systemImage: "fork.knife")
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            Gauge(value: entry.kcalProgress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .widgetAccentable()
            if let s = entry.snapshot {
                Text("P \(Int(s.protein.rounded())) g · G \(Int(s.carbs.rounded())) g · L \(Int(s.fat.rounded())) g")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Ouvre LifeOS une fois").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
