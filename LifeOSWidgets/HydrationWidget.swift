import SwiftUI
import WidgetKit

struct HydrationWidget: Widget {
    let kind: String = "HydrationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HydrationWidgetProvider()) { entry in
            HydrationWidgetView(entry: entry)
        }
        .configurationDisplayName("Hydratation")
        .description("Suis ton apport en eau quotidien et atteins ton objectif d'hydratation.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Entry & Provider

struct HydrationWidgetEntry: TimelineEntry {
    let date: Date
    let currentMl: Int
    let goalMl: Int

    var progress: Double {
        guard goalMl > 0 else { return 0 }
        return max(0.0, min(1.0, Double(currentMl) / Double(goalMl)))
    }

    var percentage: Int {
        Int(progress * 100)
    }
}

struct HydrationWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HydrationWidgetEntry {
        HydrationWidgetEntry(date: .now, currentMl: 1750, goalMl: 2500)
    }

    func getSnapshot(in context: Context, completion: @escaping (HydrationWidgetEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationWidgetEntry>) -> Void) {
        let entry = read()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func read() -> HydrationWidgetEntry {
        let defs = WidgetAppGroup.defaults
        let current = defs?.integer(forKey: "water_today_ml") ?? 1800
        let goal = defs?.integer(forKey: "water_goal_ml") ?? 2500

        return HydrationWidgetEntry(
            date: .now,
            currentMl: current > 0 ? current : 1800,
            goalMl: goal > 0 ? goal : 2500
        )
    }
}

// MARK: - Views

struct HydrationWidgetView: View {
    let entry: HydrationWidgetEntry
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
            default:
                smallView
            }
        }
        .widgetURL(URL(string: "lifeos://water"))
    }

    private var smallView: some View {
        ZStack {
            Color(widgetHex: 0x08090C)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color(widgetHex: 0x00D2FF).opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "drop.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0x00D2FF))
                    }
                    Spacer()
                    Text("\(entry.percentage)%")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Color(widgetHex: 0x00D2FF))
                }

                Spacer()

                // Cercle ou barre de progression
                VStack(alignment: .leading, spacing: 4) {
                    Text("HYDRATATION")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatLiters(entry.currentMl))
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/ \(formatLiters(entry.goalMl))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    // Jauge horizontale
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(widgetHex: 0x00D2FF), Color(widgetHex: 0x0A84FF)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * entry.progress))
                        }
                    }
                    .frame(height: 6)
                }

                HStack {
                    Text("+250 ml")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(widgetHex: 0x00D2FF), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(14)
        }
    }

    private var mediumView: some View {
        ZStack {
            Color(widgetHex: 0x08090C)

            HStack(spacing: 18) {
                // Anneau de progression circulaire
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 10)
                        .frame(width: 82, height: 82)

                    Circle()
                        .trim(from: 0, to: entry.progress)
                        .stroke(
                            LinearGradient(
                                colors: [Color(widgetHex: 0x00D2FF), Color(widgetHex: 0x0A84FF)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 82, height: 82)

                    VStack(spacing: 0) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(widgetHex: 0x00D2FF))
                        Text("\(entry.percentage)%")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                // Colonne infos
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("OBJECTIF DU JOUR")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .kerning(0.8)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text("EAU PURIFIÉE")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(widgetHex: 0x00D2FF))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(widgetHex: 0x00D2FF).opacity(0.15), in: Capsule())
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(entry.currentMl)")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("ml / \(entry.goalMl) ml")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(entry.progress >= 1.0 ? "🎉 Objectif quotidien atteint !" : "Encore \(entry.goalMl - entry.currentMl) ml pour être au top")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(entry.progress >= 1.0 ? Color(widgetHex: 0x00F076) : .white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(18)
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("\(entry.percentage)%")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
        }
    }

    private func formatLiters(_ ml: Int) -> String {
        let l = Double(ml) / 1000.0
        return String(format: "%.1fL", l)
    }
}
