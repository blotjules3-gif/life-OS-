import AppIntents
import SwiftUI
import WidgetKit

/// Taches du jour : retards, echeances du jour, puis la semaine. Coche sans ouvrir
/// l'app (iOS 17, `SetTaskDoneIntent` + file d'ordres appliquee par l'app). Les
/// titres sont masques sur l'ecran verrouille quand l'OS cache les donnees privees.
struct TasksWidget: Widget {
    let kind = WidgetKinds.tasks

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Tâches")
        .description("Tes tâches du jour et en retard. Coche-les directement.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct TasksEntry: TimelineEntry {
    let date: Date
    /// nil = l'app n'a encore rien publie.
    let snapshot: TasksSnapshot?

    var items: [TasksSnapshot.Item] { snapshot?.items ?? [] }
    var today: [TasksSnapshot.Item] { TaskSelection.today(items, now: date) }
    var upcoming: [TasksSnapshot.Item] { TaskSelection.upcoming(items, now: date) }
    var next: TasksSnapshot.Item? { TaskSelection.next(items, now: date) }
    var openToday: Int { TaskSelection.openTodayCount(items, now: date) }
    var overdue: Int { today.filter { TaskSelection.isOverdue($0, now: date) }.count }
    /// Instantane publie un autre jour : on le signale (l'app a ete fermee longtemps).
    var stale: Bool { snapshot.map { !WidgetDay.isToday($0.day, now: date) } ?? false }
}

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        let now = Date()
        let items: [TasksSnapshot.Item] = [
            .init(id: "p1", title: "Appeler le garage", due: now.addingTimeInterval(3600), dateOnly: false, priority: 2, done: false, completedAt: nil, project: "Perso", recurring: false),
            .init(id: "p2", title: "Envoyer le devis", due: Calendar.current.startOfDay(for: now), dateOnly: true, priority: 1, done: false, completedAt: nil, project: "Travail", recurring: false),
            .init(id: "p3", title: "Courses", due: now.addingTimeInterval(-3600), dateOnly: false, priority: 0, done: true, completedAt: now, project: "Perso", recurring: false),
        ]
        return TasksEntry(date: now, snapshot: TasksSnapshot(day: WidgetDay.stamp(now), updatedAt: now, items: items, openCount: 2))
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TasksEntry(date: .now, snapshot: read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let snap = read()
        let now = Date()
        let midnight = WidgetTimeline.nextMidnight(after: now)
        // Une entree a chaque echeance avec heure d'aujourd'hui (passage "en retard"),
        // puis minuit.
        let dues = (snap?.items ?? []).compactMap { i -> Date? in
            guard !i.done, !i.dateOnly, let d = i.due, d > now, d < midnight else { return nil }
            return d.addingTimeInterval(1)
        }
        let dates = ([now] + Array(Set(dues)).sorted().prefix(10) + [midnight])
        completion(Timeline(entries: dates.map { TasksEntry(date: $0, snapshot: snap) }, policy: .after(midnight)))
    }

    private func read() -> TasksSnapshot? {
        WidgetSnapshotStore.read(TasksSnapshot.self, key: TasksSnapshot.key)
    }
}

struct TasksWidgetView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular.lifeOSAccessoryBackground()
            case .accessoryInline: inline.lifeOSAccessoryBackground()
            case .systemSmall: small.padding(14).lifeOSWidgetBackground()
            case .systemLarge: list(maxToday: 7, showUpcoming: true).padding(14).lifeOSWidgetBackground()
            default: list(maxToday: 3, showUpcoming: false).padding(14).lifeOSWidgetBackground()
            }
        }
        .widgetURL(WidgetLink.tasks)
    }

    // MARK: Small : nombre + prochaine tache

    @ViewBuilder
    private var small: some View {
        if entry.snapshot == nil {
            notLoaded
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "checklist", title: "TÂCHES", tint: WTint.work)
                Spacer(minLength: 0)
                Text("\(entry.openToday)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(entry.openToday == 0 ? "rien pour aujourd'hui" : "à faire aujourd'hui")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if entry.overdue > 0 {
                    Label("\(entry.overdue) en retard", systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .wTint(WTint.warning)
                }
                if let n = entry.next {
                    Text(n.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: Medium / Large : liste cochable

    @ViewBuilder
    private func list(maxToday: Int, showUpcoming: Bool) -> some View {
        if entry.snapshot == nil {
            notLoaded
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "checklist", title: "AUJOURD'HUI", tint: WTint.work,
                             trailing: entry.overdue > 0 ? "\(entry.openToday) à faire · \(entry.overdue) en retard" : "\(entry.openToday) à faire")
                if entry.today.isEmpty {
                    Text("Rien de prévu aujourd'hui.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Link(destination: WidgetLink.url("capture")) {
                        Label("Ajouter une tâche", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .wTint(WTint.work)
                            .frame(minHeight: 32)
                    }
                } else {
                    ForEach(entry.today.prefix(maxToday)) { row($0) }
                    if entry.today.count > maxToday {
                        Text("+ \(entry.today.count - maxToday) autre\(entry.today.count - maxToday > 1 ? "s" : "")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                if showUpcoming, !entry.upcoming.isEmpty {
                    Text("CETTE SEMAINE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).kerning(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    ForEach(entry.upcoming.prefix(4)) { row($0) }
                }
                Spacer(minLength: 0)
                if entry.stale {
                    Text("Ouvre LifeOS pour actualiser")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func dueText(_ i: TasksSnapshot.Item) -> String? {
        guard let d = i.due else { return nil }
        let cal = Calendar.current
        if TaskSelection.isOverdue(i, now: entry.date) {
            return cal.isDate(d, inSameDayAs: entry.date) ? "En retard · \(d.formatted(date: .omitted, time: .shortened))" : "En retard"
        }
        if cal.isDate(d, inSameDayAs: entry.date) { return i.dateOnly ? nil : d.formatted(date: .omitted, time: .shortened) }
        let day = d.formatted(.dateTime.weekday(.abbreviated).day().locale(Locale(identifier: "fr_FR")))
        return i.dateOnly ? day : day + " " + d.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func row(_ i: TasksSnapshot.Item) -> some View {
        HStack(spacing: 8) {
            checkbox(i)
            Link(destination: WidgetLink.task(i.id)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(i.title)
                        .font(.system(size: 13, weight: i.done ? .regular : .semibold))
                        .foregroundStyle(i.done ? .secondary : .primary)
                        .strikethrough(i.done)
                        .lineLimit(1)
                        .privacySensitive()
                    if let due = dueText(i) {
                        Text(due)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(TaskSelection.isOverdue(i, now: entry.date) ? AnyShapeStyle(WTint.warning) : AnyShapeStyle(.secondary))
                    }
                }
                Spacer(minLength: 0)
                if i.priority >= 2 && !i.done {
                    Image(systemName: "exclamationmark.2").font(.system(size: 10, weight: .bold)).wTint(WTint.warning)
                        .accessibilityLabel("Urgente")
                }
            }
        }
        .frame(minHeight: 30)
    }

    @ViewBuilder
    private func checkbox(_ i: TasksSnapshot.Item) -> some View {
        let icon = Image(systemName: i.done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .wTint(WTint.work)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        if #available(iOS 17.0, *) {
            Button(intent: SetTaskDoneIntent(taskID: i.id, done: !i.done)) { icon }
                .buttonStyle(.plain)
                .accessibilityLabel(i.done ? "Rouvrir \(i.title)" : "Cocher \(i.title)")
        } else {
            icon
        }
    }

    // MARK: Ecran verrouille

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.snapshot == nil ? "Tâches" : "\(entry.openToday) tâche\(entry.openToday > 1 ? "s" : "") aujourd'hui",
                  systemImage: "checklist")
                .font(.system(size: 12, weight: .bold))
                .widgetAccentable()
            if let n = entry.next {
                Text(n.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).privacySensitive()
                if let due = dueText(n) { Text(due).font(.system(size: 10)).foregroundStyle(.secondary) }
            } else {
                Text(entry.snapshot == nil ? "Ouvre LifeOS une fois" : "Rien à faire").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label(entry.snapshot == nil ? "Tâches" : "\(entry.openToday) tâche\(entry.openToday > 1 ? "s" : "") aujourd'hui", systemImage: "checklist")
    }

    private var notLoaded: some View {
        WidgetEmptyState(icon: "checklist", title: "Tâches",
                         message: "Ouvre LifeOS une fois pour afficher tes tâches ici.", tint: WTint.work)
    }
}
