import SwiftUI
import WidgetKit

/// Widget Home Screen : raccourcis vers le chat coach avec questions
/// pré-remplies. Small = bouton unique, Medium = 3 questions rapides.
///
/// Tap = ouvre l'app sur le chat via `lifeos://coach?prefill=<question>`.
/// Le VM `AIAssistantView` détecte le prefill (via `NotificationCenter
/// .lifeOSOpenAIChat` déclenché par `AppDelegate`) et pré-remplit l'input.
struct CoachQuickAskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.blotjules.lifeos.coach.quickask",
            provider: CoachAskProvider()
        ) { _ in
            CoachAskWidgetView()
        }
        .configurationDisplayName("Coach — accès rapide")
        .description("Ouvre ton coach avec une question pré-remplie en un tap.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Provider

private struct CoachAskEntry: TimelineEntry {
    let date: Date
}

private struct CoachAskProvider: TimelineProvider {
    func placeholder(in context: Context) -> CoachAskEntry {
        CoachAskEntry(date: .now)
    }
    func getSnapshot(in context: Context, completion: @escaping (CoachAskEntry) -> Void) {
        completion(CoachAskEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CoachAskEntry>) -> Void) {
        completion(Timeline(entries: [CoachAskEntry(date: .now)], policy: .never))
    }
}

// MARK: - Deep links

private enum QuickAsk {
    case openBlank
    case morningBilan
    case energyCheck
    case dayRecap

    var prefill: String? {
        switch self {
        case .openBlank:     return nil
        case .morningBilan:  return "Fais le bilan de ma nuit et donne-moi une priorité pour aujourd'hui."
        case .energyCheck:   return "Comment est mon énergie en ce moment ? Ce que je devrais faire là."
        case .dayRecap:      return "Récap de ma journée : habitudes, énergie, progrès."
        }
    }

    var url: URL {
        var comps = URLComponents()
        comps.scheme = "lifeos"
        comps.host = "coach"
        if let p = prefill {
            comps.queryItems = [URLQueryItem(name: "prefill", value: p)]
        }
        return comps.url ?? URL(string: "lifeos://coach")!
    }

    var label: String {
        switch self {
        case .openBlank:    return "Poser une question"
        case .morningBilan: return "Bilan du matin"
        case .energyCheck:  return "Mon énergie"
        case .dayRecap:     return "Récap du jour"
        }
    }

    var icon: String {
        switch self {
        case .openBlank:    return "sparkles.rectangle.stack"
        case .morningBilan: return "sunrise.fill"
        case .energyCheck:  return "bolt.fill"
        case .dayRecap:     return "list.bullet.rectangle"
        }
    }
}

// MARK: - View

private struct CoachAskWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:  accessoryCircular
        case .accessoryRectangular: accessoryRectangular
        case .systemMedium:       mediumThreeQuestions
        default:                  smallSingleTap
        }
    }

    // Small : bouton unique
    private var smallSingleTap: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.55, blue: 0.95), Color(red: 0.20, green: 0.35, blue: 0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text("Ton coach")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Pose une question")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(QuickAsk.openBlank.url)
    }

    // Medium : 3 boutons de questions rapides
    private var mediumThreeQuestions: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.55, blue: 0.95), Color(red: 0.20, green: 0.35, blue: 0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                    Text("Ton coach")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(.white)

                quickRow(.morningBilan)
                quickRow(.energyCheck)
                quickRow(.dayRecap)
            }
            .padding(12)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func quickRow(_ ask: QuickAsk) -> some View {
        Link(destination: ask.url) {
            HStack(spacing: 8) {
                Image(systemName: ask.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(ask.label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .bold))
        }
        .widgetURL(QuickAsk.openBlank.url)
    }

    private var accessoryRectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Coach")
                    .font(.system(size: 13, weight: .bold))
                Text("Poser une question")
                    .font(.system(size: 11))
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .widgetURL(QuickAsk.openBlank.url)
    }
}
