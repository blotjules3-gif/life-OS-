import SwiftUI
import WidgetKit

struct TabataWidget: Widget {
    let kind: String = "TabataWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TabataWidgetProvider()) { entry in
            TabataWidgetView(entry: entry)
        }
        .configurationDisplayName("HIIT & Tabata")
        .description("Lance ta séance par intervalles et visualise ton programme du jour.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct TabataWidgetEntry: TimelineEntry {
    let date: Date
    let sessionName: String
    let workSeconds: Int
    let restSeconds: Int
    let setsCount: Int
    let exercisesCount: Int
}

struct TabataWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TabataWidgetEntry {
        TabataWidgetEntry(
            date: .now,
            sessionName: "Cardio HIIT",
            workSeconds: 30,
            restSeconds: 15,
            setsCount: 4,
            exercisesCount: 6
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TabataWidgetEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TabataWidgetEntry>) -> Void) {
        let entry = read()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func read() -> TabataWidgetEntry {
        let defs = WidgetAppGroup.defaults
        let session = defs?.string(forKey: "tabata_last_preset") ?? "Cardio HIIT"
        let work = defs?.integer(forKey: "tabata_work") ?? 30
        let rest = defs?.integer(forKey: "tabata_rest") ?? 15
        let sets = defs?.integer(forKey: "tabata_sets") ?? 4

        return TabataWidgetEntry(
            date: .now,
            sessionName: session,
            workSeconds: work > 0 ? work : 30,
            restSeconds: rest > 0 ? rest : 15,
            setsCount: sets > 0 ? sets : 4,
            exercisesCount: 6
        )
    }
}

// MARK: - Views

struct TabataWidgetView: View {
    let entry: TabataWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            default:
                smallView
            }
        }
        .widgetURL(URL(string: "lifeos://tabata"))
    }

    private var smallView: some View {
        ZStack {
            Color(widgetHex: 0x08090C)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: 0x00F076).opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0x00F076))
                    }
                    Spacer()
                    Text("\(entry.setsCount) SÉRIES")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(widgetHex: 0x00F076))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(widgetHex: 0x00F076).opacity(0.15), in: Capsule())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("HIIT / TABATA")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .kerning(0.5)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(entry.sessionName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("\(entry.workSeconds)s effort")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(widgetHex: 0x00F076))
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("\(entry.restSeconds)s repos")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(widgetHex: 0xFF5252))
                }

                HStack {
                    Text("Démarrer")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(widgetHex: 0x00F076), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(14)
        }
    }

    private var mediumView: some View {
        ZStack {
            Color(widgetHex: 0x08090C)

            HStack(spacing: 16) {
                // Colonne gauche : infos séance
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0x00F076))
                        Text("HIIT & TABATA")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .kerning(0.8)
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("6 EXERCICES")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(widgetHex: 0x00F076))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(widgetHex: 0x00F076).opacity(0.15), in: Capsule())
                    }

                    Text(entry.sessionName)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        chip(label: "EFFORT", val: "\(entry.workSeconds)s", colorHex: 0x00F076)
                        chip(label: "REPOS", val: "\(entry.restSeconds)s", colorHex: 0xFF5252)
                        chip(label: "SÉRIES", val: "\(entry.setsCount)", colorHex: 0xFFB800)
                    }

                    Spacer()
                }

                // Colonne droite : bouton lancer
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: 0x00F076).opacity(0.2))
                            .frame(width: 58, height: 58)
                        Image(systemName: "play.fill")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(Color(widgetHex: 0x00F076))
                            .offset(x: 2)
                    }
                    Text("LANCER")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 80)
            }
            .padding(16)
        }
    }

    private func chip(label: String, val: String, colorHex: UInt) -> some View {
        VStack(spacing: 2) {
            Text(val)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Color(widgetHex: colorHex))
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("HIIT")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                Text("\(entry.setsCount)s")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("HIIT • \(entry.sessionName)")
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("\(entry.workSeconds)s effort / \(entry.restSeconds)s repos • \(entry.setsCount) séries")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
