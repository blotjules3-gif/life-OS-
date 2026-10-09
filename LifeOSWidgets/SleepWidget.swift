import SwiftUI
import WidgetKit

struct SleepWidget: Widget {
    let kind: String = WidgetKinds.sleep

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepWidgetProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("Sommeil et réveil")
        .description("Ton heure de réveil, ton coucher conseillé et ta dernière nuit.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct SleepWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SleepSnapshot?

    /// Reveil regle dans LifeOS (sinon : etat vide, jamais 07:00 invente).
    var wake: (hour: Int, minute: Int)? {
        guard let s = snapshot, let h = s.wakeHour else { return nil }
        return (h, s.wakeMinute ?? 0)
    }
    var alarm: String? { wake.map { WidgetTimeline.hm($0.hour, $0.minute) } }
    var bedtime: String? {
        guard let w = wake, let s = snapshot else { return nil }
        let b = SleepSnapshot.bedtime(wakeHour: w.hour, wakeMinute: w.minute, targetHours: s.targetHours)
        return WidgetTimeline.hm(b.hour, b.minute)
    }
    var lastNight: Double? { snapshot?.lastNight(now: date) }
    var targetText: String {
        guard let s = snapshot else { return "" }
        let v = s.targetHours.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))
        return "\(v) h"
    }
}

struct SleepWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepWidgetEntry {
        SleepWidgetEntry(date: .now, snapshot: SleepSnapshot(day: WidgetDay.stamp(), updatedAt: .now, wakeHour: 7, wakeMinute: 0,
                                                             wakeEnabled: true, targetHours: 8, targetIsDefault: false,
                                                             lastSleepHours: 7.5, lastSleepDay: WidgetDay.stamp()))
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepWidgetEntry>) -> Void) {
        let midnight = WidgetTimeline.nextMidnight()
        // A minuit la "derniere nuit" d'hier n'est plus montree comme celle du jour.
        completion(Timeline(entries: [read(at: .now), read(at: midnight)], policy: .after(midnight)))
    }

    private func read(at date: Date) -> SleepWidgetEntry {
        SleepWidgetEntry(date: date, snapshot: WidgetSnapshotStore.read(SleepSnapshot.self, key: SleepSnapshot.key))
    }
}

// MARK: - Views

struct SleepWidgetView: View {
    let entry: SleepWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumView.padding(14).lifeOSWidgetBackground()
            case .accessoryRectangular: rectangularView.lifeOSAccessoryBackground()
            default: smallView.padding(14).lifeOSWidgetBackground()
            }
        }
        .widgetURL(WidgetLink.sleep)
    }

    private var lastNightText: String {
        guard let h = entry.lastNight else { return "Nuit pas encore notée" }
        return "Dernière nuit : " + h.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR"))) + " h"
    }

    private var alarmState: String? {
        guard let s = entry.snapshot, entry.wake != nil else { return nil }
        return s.wakeEnabled ? "RÉVEIL" : "RÉVEIL COUPÉ"
    }

    private var empty: some View {
        WidgetEmptyState(icon: "alarm", title: "Pas de réveil", message: "Règle ton réveil dans LifeOS.", tint: WTint.sleep)
    }

    @ViewBuilder
    private var smallView: some View {
        if let alarm = entry.alarm, let bed = entry.bedtime {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "alarm.fill", title: alarmState ?? "RÉVEIL", tint: WTint.sleep)
                Spacer(minLength: 0)
                Text(alarm)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text("Coucher conseillé \(bed)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(lastNightText)
                    .font(.system(size: 10, weight: .bold))
                    .wTint(WTint.sleep)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            empty
        }
    }

    @ViewBuilder
    private var mediumView: some View {
        if let alarm = entry.alarm, let bed = entry.bedtime {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(icon: "moon.fill", title: "SOMMEIL ET RÉVEIL", tint: WTint.sleep,
                                 trailing: "Objectif \(entry.targetText)" + ((entry.snapshot?.targetIsDefault ?? false) ? " par défaut" : ""))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(alarm).font(.system(size: 32, weight: .black, design: .rounded)).monospacedDigit()
                        Text((entry.snapshot?.wakeEnabled ?? false) ? "prochain réveil" : "réveil coupé")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    }
                    Text("Pour dormir \(entry.targetText), couche-toi vers \(bed).")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 4) {
                    Image(systemName: "bed.double.fill").font(.system(size: 24, weight: .bold)).wTint(WTint.sleep)
                    if let h = entry.lastNight {
                        Text(h.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR"))) + " h")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                        Text("CETTE NUIT").font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(.secondary)
                    } else {
                        Text("Nuit pas\nnotée").font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72)
            }
        } else {
            empty
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "alarm.fill").font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                if let alarm = entry.alarm, let bed = entry.bedtime {
                    Text("Réveil \(alarm)").font(.system(size: 12, weight: .bold))
                    Text("Coucher conseillé \(bed)").font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("Pas de réveil").font(.system(size: 12, weight: .bold))
                    Text("Règle-le dans LifeOS").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
