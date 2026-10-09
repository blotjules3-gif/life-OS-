import SwiftUI
import WidgetKit

struct TabataWidget: Widget {
    let kind: String = WidgetKinds.tabata

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TabataWidgetProvider()) { entry in
            TabataWidgetView(entry: entry)
        }
        .configurationDisplayName("HIIT et Tabata")
        .description("Ta séance d'intervalles : nom, exercices, effort et repos. Un appui pour la lancer.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct TabataWidgetEntry: TimelineEntry {
    let date: Date
    /// nil = l'app n'a encore rien publie (jamais ouverte depuis la mise a jour).
    let snapshot: TabataSnapshot?

    var title: String { snapshot?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Intervalles libres" }
}

struct TabataWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TabataWidgetEntry {
        TabataWidgetEntry(date: .now, snapshot: TabataSnapshot(day: "", updatedAt: .now, name: "Cardio HIIT", exercises: 6,
                                                               work: 30, rest: 15, rounds: 6, cycles: 4, inProgress: false, lastDone: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (TabataWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TabataWidgetEntry>) -> Void) {
        // Rien ne change avec l'heure : l'app recharge le widget quand la seance change.
        completion(Timeline(entries: [read()], policy: .never))
    }

    private func read() -> TabataWidgetEntry {
        TabataWidgetEntry(date: .now, snapshot: WidgetSnapshotStore.read(TabataSnapshot.self, key: TabataSnapshot.key))
    }
}

// MARK: - Views

struct TabataWidgetView: View {
    let entry: TabataWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: content(medium: true).padding(14).lifeOSWidgetBackground()
            case .accessoryCircular: circularView.lifeOSAccessoryBackground()
            case .accessoryRectangular: rectangularView.lifeOSAccessoryBackground()
            default: content(medium: false).padding(14).lifeOSWidgetBackground()
            }
        }
        .widgetURL(WidgetLink.tabata)
    }

    @ViewBuilder
    private func content(medium: Bool) -> some View {
        if let s = entry.snapshot {
            if medium { mediumView(s) } else { smallView(s) }
        } else {
            WidgetEmptyState(icon: "flame.fill", title: "Tabata",
                             message: "Ouvre Tabata dans LifeOS pour afficher ta séance ici.", tint: WTint.sport)
        }
    }

    private func badge(_ s: TabataSnapshot) -> String? {
        if s.inProgress { return "EN COURS" }
        return s.exercises > 0 ? "\(s.exercises) EXERCICE\(s.exercises > 1 ? "S" : "")" : nil
    }

    private func smallView(_ s: TabataSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(icon: "flame.fill", title: "TABATA", tint: WTint.sport, trailing: badge(s))
            Spacer(minLength: 0)
            Text(entry.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(2)
            Text("\(s.work) s effort · \(s.rest) s repos")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Label(s.inProgress ? "Reprendre" : "Démarrer", systemImage: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .wTint(WTint.sport)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mediumView(_ s: TabataSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(icon: "flame.fill", title: "HIIT ET TABATA", tint: WTint.sport, trailing: badge(s))
                Text(entry.title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    chip("EFFORT", "\(s.work) s")
                    chip("REPOS", "\(s.rest) s")
                    chip("TOURS", "\(s.rounds)")
                    if s.cycles > 1 { chip("SÉRIES", "\(s.cycles)") }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 4) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40, weight: .bold))
                    .wTint(WTint.sport)
                Text(s.inProgress ? "Reprendre" : "Lancer")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .frame(width: 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func chip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 13, weight: .black, design: .rounded))
            Text(label).font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.system(size: 13, weight: .bold))
                if let s = entry.snapshot {
                    Text("\(s.work)/\(s.rest)").font(.system(size: 11, weight: .heavy, design: .rounded))
                    Text("\(s.rounds) tours").font(.system(size: 8, weight: .semibold))
                } else {
                    Text("Tabata").font(.system(size: 9, weight: .heavy, design: .rounded))
                }
            }
        }
        .widgetAccentable()
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill").font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                if let s = entry.snapshot {
                    Text("\(s.work) s / \(s.rest) s · \(s.rounds) tours").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Ouvre Tabata dans LifeOS").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
