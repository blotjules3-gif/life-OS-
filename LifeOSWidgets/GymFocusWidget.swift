import SwiftUI
import WidgetKit

struct GymFocusWidget: Widget {
    let kind: String = WidgetKinds.gym

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GymFocusWidgetProvider()) { entry in
            GymFocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Programme sport")
        .description("La séance du jour lue dans ton programme de la semaine.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct GymFocusWidgetEntry: TimelineEntry {
    let date: Date
    /// nil = programme jamais publie par l'app.
    let week: GymWeekSnapshot?

    var today: GymWeekSnapshot.Day? { week?.plan(for: date) }
    var tomorrow: GymWeekSnapshot.Day? {
        week?.plan(for: Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date)
    }
    var weekdayName: String {
        date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR"))).uppercased()
    }
}

struct GymFocusWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> GymFocusWidgetEntry {
        let wd = Calendar.current.component(.weekday, from: .now)
        return GymFocusWidgetEntry(date: .now, week: GymWeekSnapshot(day: "", updatedAt: .now, days: [
            .init(weekday: wd, title: "Haut du corps", focus: "Développé couché · Tractions · Dips", isRest: false)
        ]))
    }

    func getSnapshot(in context: Context, completion: @escaping (GymFocusWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GymFocusWidgetEntry>) -> Void) {
        let midnight = WidgetTimeline.nextMidnight()
        // Le programme est celui de la semaine : a minuit, la seance du lendemain
        // s'affiche meme si l'app n'est pas ouverte.
        completion(Timeline(entries: [read(at: .now), read(at: midnight)], policy: .after(midnight)))
    }

    private func read(at date: Date) -> GymFocusWidgetEntry {
        GymFocusWidgetEntry(date: date, week: WidgetSnapshotStore.read(GymWeekSnapshot.self, key: GymWeekSnapshot.key))
    }
}

// MARK: - Views

struct GymFocusWidgetView: View {
    let entry: GymFocusWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumView.padding(14).lifeOSWidgetBackground()
            case .accessoryRectangular: rectangularView.lifeOSAccessoryBackground()
            default: smallView.padding(14).lifeOSWidgetBackground()
            }
        }
        .widgetURL(WidgetLink.gym)
    }

    private var title: String {
        guard let d = entry.today else { return "Rien de prévu" }
        return d.isRest ? "Jour de repos" : d.title
    }

    private var detail: String {
        if entry.week == nil { return "Ouvre LifeOS pour charger ton programme." }
        guard let d = entry.today else {
            return (entry.week?.days.isEmpty ?? true) ? "Définis ta semaine dans Fitbot." : "Pas de séance ce jour dans ton programme."
        }
        return d.isRest ? "Récupération : étirements, eau, sommeil." : d.focus
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(icon: "dumbbell.fill", title: entry.weekdayName, tint: WTint.sport)
            Spacer(minLength: 0)
            Text(entry.today?.isRest == true ? "RÉCUPÉRATION" : "SÉANCE DU JOUR")
                .font(.system(size: 10, weight: .heavy, design: .rounded)).kerning(0.6)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(2)
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "dumbbell.fill", title: "PROGRAMME SPORT", tint: WTint.sport, trailing: entry.weekdayName)
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let t = entry.tomorrow {
                    Text("Demain : \(t.isRest ? "repos" : t.title)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Image(systemName: entry.today?.isRest == true ? "moon.stars.fill" : "figure.strengthtraining.traditional")
                .font(.system(size: 30, weight: .bold))
                .wTint(WTint.sport)
                .frame(width: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "dumbbell.fill").font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sport · \(title)").font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
