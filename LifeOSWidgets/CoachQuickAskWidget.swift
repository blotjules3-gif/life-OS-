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
            kind: WidgetKinds.coach,
            provider: CoachAskProvider()
        ) { _ in
            CoachAskWidgetView()
        }
        .configurationDisplayName("Coach, accès rapide")
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

    var url: URL { WidgetLink.coach(prefill: prefill) }

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
    @Environment(\.widgetRenderingMode) private var mode

    private var coachBackground: LinearGradient {
        LinearGradient(colors: [WidgetPalette.tone(0.35, 0.55, 0.95), WidgetPalette.tone(0.20, 0.35, 0.85)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var ink: AnyShapeStyle { mode == .fullColor ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary) }

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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles").font(.system(size: 22, weight: .bold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).opacity(0.85)
            }
            Spacer()
            Text("Ton coach").font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Pose une question").font(.system(size: 11, weight: .medium)).opacity(0.85)
        }
        .foregroundStyle(ink)
        .padding(14)
        .containerBackground(for: .widget) { coachBackground }
        .widgetURL(QuickAsk.openBlank.url)
    }

    // Medium : 3 boutons de questions rapides
    private var mediumThreeQuestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles").font(.system(size: 16, weight: .bold))
                Text("Ton coach").font(.system(size: 13, weight: .bold))
                Spacer()
            }
            quickRow(.morningBilan)
            quickRow(.energyCheck)
            quickRow(.dayRecap)
        }
        .foregroundStyle(ink)
        .padding(12)
        .containerBackground(for: .widget) { coachBackground }
        .widgetURL(QuickAsk.openBlank.url)
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
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .bold))
        }
        .lifeOSAccessoryBackground()
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
        .lifeOSAccessoryBackground()
        .widgetURL(QuickAsk.openBlank.url)
    }
}
