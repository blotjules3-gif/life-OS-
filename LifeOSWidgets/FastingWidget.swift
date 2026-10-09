import SwiftUI
import WidgetKit

struct FastingWidget: Widget {
    let kind: String = WidgetKinds.fasting

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastingWidgetProvider()) { entry in
            FastingWidgetView(entry: entry)
        }
        .configurationDisplayName("Jeûne intermittent")
        .description("Le temps écoulé de ton jeûne, ton objectif et ta fenêtre pour manger.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct FastingWidgetEntry: TimelineEntry {
    let date: Date
    /// nil = pas de jeune en cours.
    let start: Date?
    let targetHours: Int

    var isFasting: Bool { start != nil }
    var elapsedHours: Double { start.map { max(0, date.timeIntervalSince($0)) / 3600 } ?? 0 }
    var progress: Double { targetHours > 0 ? max(0, min(1, elapsedHours / Double(targetHours))) : 0 }
    var eatingWindow: Int { FastingMath.eatingWindow(targetHours: targetHours) }
    var end: Date? { start.map { $0.addingTimeInterval(Double(targetHours) * 3600) } }
}

struct FastingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingWidgetEntry {
        FastingWidgetEntry(date: .now, start: .now.addingTimeInterval(-10 * 3600), targetHours: 16)
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingWidgetEntry>) -> Void) {
        let first = read(at: .now)
        guard first.isFasting else {
            completion(Timeline(entries: [first], policy: .never))
            return
        }
        // Une entree par quart d'heure sur 6 h : la duree avance sans reveiller l'app.
        let entries = (0..<24).map { read(at: Date.now.addingTimeInterval(Double($0) * 900)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func read(at date: Date) -> FastingWidgetEntry {
        let defs = LifeOSGroup.defaults
        let target = defs?.integer(forKey: WidgetKeys.fastTarget) ?? 0
        let startTs = defs?.double(forKey: WidgetKeys.fastStart) ?? 0
        return FastingWidgetEntry(date: date, start: startTs > 0 ? Date(timeIntervalSince1970: startTs) : nil,
                                  targetHours: target > 0 ? target : 16)
    }
}

// MARK: - Views

struct FastingWidgetView: View {
    let entry: FastingWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circularView.lifeOSAccessoryBackground()
            case .accessoryRectangular: rectangularView.lifeOSAccessoryBackground()
            default: smallView.padding(14).lifeOSWidgetBackground()
            }
        }
        .widgetURL(WidgetLink.fasting)
    }

    private var ratio: String { FastingMath.ratioLabel(targetHours: entry.targetHours) }

    @ViewBuilder
    private var smallView: some View {
        if entry.isFasting {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "timer", title: "JEÛNE", tint: WTint.fasting, trailing: ratio)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Self.format(entry.elapsedHours))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("/ \(entry.targetHours) h")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                WidgetBar(progress: entry.progress, tint: WTint.fasting)
                Text(FastingMath.phase(elapsedHours: entry.elapsedHours, targetHours: entry.targetHours))
                    .font(.system(size: 11, weight: .bold))
                    .wTint(WTint.fasting)
                if let end = entry.end, entry.progress < 1 {
                    Text("Fin prévue \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            // Aucun jeune en cours : on le dit, au lieu d'un compteur invente.
            WidgetEmptyState(icon: "timer", title: "Pas de jeûne en cours",
                             message: "Objectif \(entry.targetHours) h, fenêtre de \(entry.eatingWindow) h pour manger. Touche pour commencer.",
                             tint: WTint.fasting)
        }
    }

    private var circularView: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "timer")
        } currentValueLabel: {
            Text(entry.isFasting ? "\(Int(entry.elapsedHours)) h" : "0 h")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel(entry.isFasting ? "Jeûne : \(Int(entry.elapsedHours)) heures sur \(entry.targetHours)" : "Pas de jeûne en cours")
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                if entry.isFasting {
                    Text("Jeûne \(Self.format(entry.elapsedHours)) / \(entry.targetHours) h")
                        .font(.system(size: 12, weight: .bold))
                    Text(FastingMath.phase(elapsedHours: entry.elapsedHours, targetHours: entry.targetHours))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("Pas de jeûne en cours").font(.system(size: 12, weight: .bold))
                    Text("Objectif \(ratio)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func format(_ h: Double) -> String {
        let total = Int(h * 60)
        return "\(total / 60)h\(String(format: "%02d", total % 60))"
    }
}
