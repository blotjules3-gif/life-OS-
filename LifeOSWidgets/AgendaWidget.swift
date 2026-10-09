import SwiftUI
import WidgetKit

/// Agenda du jour : taches avec heure ou creneau, seance, complements, evenements
/// LifeOS et calendrier de l'appareil (seulement si l'acces complet est accorde).
/// Chaque element dit d'ou il vient.
struct AgendaWidget: Widget {
    let kind = WidgetKinds.agenda

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry)
        }
        .configurationDisplayName("Agenda")
        .description("Ta journée dans l'ordre : tâches, séance, compléments et calendrier.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct AgendaEntry: TimelineEntry {
    let date: Date
    let snapshot: AgendaSnapshot?

    var remaining: [AgendaSnapshot.Item] { AgendaSnapshot.remaining(snapshot?.items ?? [], now: date) }
    var tomorrow: [AgendaSnapshot.Item] {
        AgendaSnapshot.items(on: Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date, from: snapshot?.items ?? [])
    }
    var next: AgendaSnapshot.Item? { AgendaSnapshot.next(snapshot?.items ?? [], now: date) }
    var stale: Bool { snapshot.map { !WidgetDay.isToday($0.day, now: date) } ?? false }
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        return AgendaEntry(date: now, snapshot: AgendaSnapshot(day: WidgetDay.stamp(now), updatedAt: now, items: [
            .init(id: "1", title: "Réunion d'équipe", detail: "Calendrier", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400), allDay: false, source: .event, link: "lifeos://agenda"),
            .init(id: "2", title: "Haut du corps", detail: "Séance de sport", start: start, end: start, allDay: true, source: .gym, link: "lifeos://gym"),
        ], calendarAccess: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : AgendaEntry(date: .now, snapshot: read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let snap = read()
        let now = Date()
        let midnight = WidgetTimeline.nextMidnight(after: now)
        // Une entree a chaque fin d'element d'aujourd'hui (il sort de la liste), puis minuit.
        let ends = (snap?.items ?? []).compactMap { i -> Date? in
            guard !i.allDay, let e = i.end ?? i.start, e > now, e < midnight else { return nil }
            return e.addingTimeInterval(1)
        }
        let dates = [now] + Array(Set(ends)).sorted().prefix(12) + [midnight]
        completion(Timeline(entries: dates.map { AgendaEntry(date: $0, snapshot: snap) }, policy: .after(midnight)))
    }

    private func read() -> AgendaSnapshot? {
        WidgetSnapshotStore.read(AgendaSnapshot.self, key: AgendaSnapshot.key)
    }
}

struct AgendaWidgetView: View {
    let entry: AgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular.lifeOSAccessoryBackground()
            case .systemLarge: list(max: 7, showTomorrow: true).padding(14).lifeOSWidgetBackground()
            default: list(max: 3, showTomorrow: false).padding(14).lifeOSWidgetBackground()
            }
        }
        .widgetURL(WidgetLink.agenda)
    }

    private static func icon(_ s: AgendaSnapshot.Source) -> String {
        switch s {
        case .task: return "checklist"
        case .event: return "calendar"
        case .gym: return "dumbbell.fill"
        case .supplement: return "pills.fill"
        case .social: return "person.2.fill"
        }
    }

    private static func sourceName(_ s: AgendaSnapshot.Source) -> String {
        switch s {
        case .task: return "Tâche"
        case .event: return "Calendrier"
        case .gym: return "Sport"
        case .supplement: return "Complément"
        case .social: return "Événement"
        }
    }

    private func timeText(_ i: AgendaSnapshot.Item) -> String {
        guard !i.allDay, let s = i.start else { return "Journée" }
        return s.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func list(max: Int, showTomorrow: Bool) -> some View {
        if entry.snapshot == nil {
            WidgetEmptyState(icon: "calendar", title: "Agenda", message: "Ouvre LifeOS une fois pour afficher ta journée ici.", tint: WTint.work)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "calendar", title: entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))).uppercased(),
                             tint: WTint.work)
                if entry.remaining.isEmpty {
                    Text("Plus rien de prévu aujourd'hui.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.remaining.prefix(max)) { row($0) }
                    if entry.remaining.count > max {
                        Text("+ \(entry.remaining.count - max) autre\(entry.remaining.count - max > 1 ? "s" : "")")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                    }
                }
                if showTomorrow, !entry.tomorrow.isEmpty {
                    Text("DEMAIN").font(.system(size: 10, weight: .heavy, design: .rounded)).kerning(0.6)
                        .foregroundStyle(.secondary).padding(.top, 6)
                    ForEach(entry.tomorrow.prefix(3)) { row($0) }
                }
                Spacer(minLength: 0)
                if !(entry.snapshot?.calendarAccess ?? false) {
                    Text("Calendrier non lu : autorise-le dans LifeOS pour voir tes rendez-vous.")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).lineLimit(2)
                } else if entry.stale {
                    Text("Ouvre LifeOS pour actualiser").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func row(_ i: AgendaSnapshot.Item) -> some View {
        Link(destination: URL(string: i.link) ?? WidgetLink.agenda) {
            HStack(spacing: 8) {
                Text(timeText(i))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .leading)
                    .foregroundStyle(.secondary)
                Image(systemName: Self.icon(i.source))
                    .font(.system(size: 11, weight: .bold))
                    .wTint(WTint.work)
                    .frame(width: 16)
                    .accessibilityLabel(Self.sourceName(i.source))
                VStack(alignment: .leading, spacing: 0) {
                    Text(i.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).privacySensitive()
                    Text(i.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 30)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Agenda", systemImage: "calendar").font(.system(size: 11, weight: .bold)).widgetAccentable()
            if let n = entry.next {
                Text(n.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).privacySensitive()
                Text("\(timeText(n)) · \(Self.sourceName(n.source))").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text(entry.snapshot == nil ? "Ouvre LifeOS une fois" : "Plus rien aujourd'hui").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
