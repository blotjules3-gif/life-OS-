import SwiftUI
import WidgetKit

/// Widget Home Screen / Lock Screen : raccourci vers le scan repas.
///
/// Tap = ouvre l'app directement sur la caméra Nutrition via le schéma
/// `lifeos://scan-food`. Zéro donnée dynamique — pas de timeline complexe,
/// juste un bouton persistant.
struct FoodScanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.blotjules.lifeos.foodscan.widget",
            provider: FoodScanProvider()
        ) { _ in
            FoodScanWidgetView()
        }
        .configurationDisplayName("Scan repas")
        .description("Raccourci vers la caméra Nutrition — kcal + protéines en un tap.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Provider

private struct FoodScanEntry: TimelineEntry {
    let date: Date
}

private struct FoodScanProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodScanEntry {
        FoodScanEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (FoodScanEntry) -> Void) {
        completion(FoodScanEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodScanEntry>) -> Void) {
        // Contenu statique — un seul entry, jamais de refresh nécessaire.
        completion(Timeline(entries: [FoodScanEntry(date: .now)], policy: .never))
    }
}

// MARK: - View

private struct FoodScanWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private let deepLink = URL(string: "lifeos://scan-food")!

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        default:
            small
        }
    }

    private var small: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.26, green: 0.82, blue: 0.42), Color(red: 0.13, green: 0.68, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text("Scan repas")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Kcal · Protéines")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(deepLink)
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "fork.knife")
                .font(.system(size: 20, weight: .bold))
        }
        .widgetURL(deepLink)
    }

    private var accessoryRectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan repas")
                    .font(.system(size: 13, weight: .bold))
                Text("Ouvre la caméra")
                    .font(.system(size: 11))
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .widgetURL(deepLink)
    }
}
