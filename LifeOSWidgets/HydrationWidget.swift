import AppIntents
import SwiftUI
import WidgetKit

struct HydrationWidget: Widget {
    let kind: String = WidgetKinds.hydration

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HydrationWidgetProvider()) { entry in
            HydrationWidgetView(entry: entry)
        }
        .configurationDisplayName("Hydratation")
        .description("Ton eau du jour, ton objectif, et un appui pour ajouter un verre.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct HydrationWidgetEntry: TimelineEntry {
    let date: Date
    let currentMl: Int
    let goalMl: Int

    var progress: Double { goalMl > 0 ? max(0, min(1, Double(currentMl) / Double(goalMl))) : 0 }
    var percentage: Int { Int((progress * 100).rounded()) }
    var remaining: Int { max(0, goalMl - currentMl) }
}

struct HydrationWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HydrationWidgetEntry {
        HydrationWidgetEntry(date: .now, currentMl: 1250, goalMl: 2500)
    }

    func getSnapshot(in context: Context, completion: @escaping (HydrationWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationWidgetEntry>) -> Void) {
        let midnight = WidgetTimeline.nextMidnight()
        // A minuit le total repart a 0 meme si l'app n'est pas ouverte.
        completion(Timeline(entries: [read(at: .now), read(at: midnight)], policy: .after(midnight)))
    }

    private func read(at date: Date) -> HydrationWidgetEntry {
        let defs = LifeOSGroup.defaults
        // Valeur du jour ; une valeur d'un autre jour compte pour 0 (jamais celle d'hier).
        let current = WidgetKeys.waterForToday(value: defs?.integer(forKey: WidgetKeys.waterToday) ?? 0,
                                               day: defs?.string(forKey: WidgetKeys.waterDay), now: date)
        let goal = defs?.integer(forKey: WidgetKeys.waterGoal) ?? 0
        return HydrationWidgetEntry(date: date, currentMl: current, goalMl: goal > 0 ? goal : 2500)
    }
}

// MARK: - Views

struct HydrationWidgetView: View {
    let entry: HydrationWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumView.padding(14).lifeOSWidgetBackground()
            case .accessoryCircular: circularView.lifeOSAccessoryBackground()
            case .accessoryRectangular: rectangularView.lifeOSAccessoryBackground()
            default: smallView.padding(14).lifeOSWidgetBackground()
            }
        }
        .widgetURL(WidgetLink.water)
    }

    @ViewBuilder
    private func addButton(_ ml: Int) -> some View {
        if #available(iOS 17.0, *) {
            Button(intent: AddWaterIntent(ml: ml, baseML: entry.currentMl, renderedAt: entry.date)) {
                Label("+\(ml) ml", systemImage: "plus")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .tint(WTint.water)
            .accessibilityLabel("Ajouter \(ml) millilitres d'eau")
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(icon: "drop.fill", title: "HYDRATATION", tint: WTint.water, trailing: "\(entry.percentage) %")
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(WidgetTimeline.liters(entry.currentMl))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.7)
                Text("/ \(WidgetTimeline.liters(entry.goalMl))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            WidgetBar(progress: entry.progress, tint: WTint.water)
            addButton(250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            ZStack {
                WidgetRing(progress: entry.progress, tint: WTint.water, lineWidth: 9)
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").font(.system(size: 14, weight: .bold)).wTint(WTint.water)
                    Text("\(entry.percentage) %").font(.system(size: 14, weight: .black, design: .rounded))
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text("OBJECTIF DU JOUR")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).kerning(0.6)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.currentMl)").font(.system(size: 24, weight: .black, design: .rounded))
                    Text("ml / \(entry.goalMl) ml").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                }
                Text(entry.progress >= 1 ? "Objectif atteint" : "Encore \(entry.remaining) ml")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    addButton(250)
                    addButton(500)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var circularView: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text("\(entry.percentage)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("Eau : \(entry.currentMl) millilitres sur \(entry.goalMl)")
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Eau \(WidgetTimeline.liters(entry.currentMl)) / \(WidgetTimeline.liters(entry.goalMl))", systemImage: "drop.fill")
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            Gauge(value: entry.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .widgetAccentable()
            Text(entry.progress >= 1 ? "Objectif atteint" : "Encore \(entry.remaining) ml")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
