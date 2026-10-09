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
            kind: WidgetKinds.foodScan,
            provider: FoodScanProvider()
        ) { _ in
            FoodScanWidgetView()
        }
        .configurationDisplayName("Scan repas")
        .description("Raccourci vers la caméra Nutrition : calories et protéines en un appui.")
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

    private let deepLink = WidgetLink.scanFood
    @Environment(\.widgetRenderingMode) private var mode

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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fork.knife").font(.system(size: 22, weight: .bold))
                Spacer()
                Image(systemName: "camera.fill").font(.system(size: 14, weight: .semibold)).opacity(0.85)
            }
            Spacer()
            Text("Scan repas").font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Kcal · Protéines").font(.system(size: 11, weight: .medium)).opacity(0.85)
        }
        .foregroundStyle(mode == .fullColor ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .padding(14)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [WidgetPalette.tone(0.26, 0.82, 0.42), WidgetPalette.tone(0.13, 0.68, 0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(deepLink)
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "fork.knife")
                .font(.system(size: 20, weight: .bold))
        }
        .lifeOSAccessoryBackground()
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
        .lifeOSAccessoryBackground()
        .widgetURL(deepLink)
    }
}
