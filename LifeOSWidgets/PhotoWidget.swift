import WidgetKit
import SwiftUI
import AppIntents

// Widget photo: chaque instance pose sur l'ecran affiche UNE configuration creee
// dans le studio de LifeOS (Profil > Widgets photo). Plusieurs instances = plusieurs
// configurations independantes.
//
// Memoire: l'extension a environ 30 Mo. On ne garde jamais d'image dans les entrees
// de la frise (24 entrees x 3 photos depasseraient la limite): l'entree porte les
// references, la vue lit chaque photo deja reduite par ImageIO au moment du rendu.

// MARK: - Choix de la configuration

@available(iOS 17.0, *)
struct PhotoWidgetConfigEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Widget photo"
    static let defaultQuery = PhotoWidgetConfigQuery()

    let id: UUID
    let name: String
    let templateTitle: String

    init(_ s: PhotoWidgetSummary) {
        id = s.id; name = s.name; templateTitle = s.template.title
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(templateTitle)")
    }
}

@available(iOS 17.0, *)
struct PhotoWidgetConfigQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PhotoWidgetConfigEntity] {
        PhotoWidgetIndexQuery.entities(for: identifiers, in: PhotoWidgetStorage.readIndex()).map(PhotoWidgetConfigEntity.init)
    }

    func entities(matching string: String) async throws -> [PhotoWidgetConfigEntity] {
        PhotoWidgetIndexQuery.matching(string, in: PhotoWidgetStorage.readIndex()).map(PhotoWidgetConfigEntity.init)
    }

    func suggestedEntities() async throws -> [PhotoWidgetConfigEntity] {
        PhotoWidgetIndexQuery.summaries(PhotoWidgetStorage.readIndex()).map(PhotoWidgetConfigEntity.init)
    }

    /// Un widget pose sans choix montre la configuration la plus recente.
    func defaultResult() async -> PhotoWidgetConfigEntity? {
        let configs = PhotoWidgetStorage.readIndex().sorted { $0.updatedAt > $1.updatedAt }
        return PhotoWidgetIndexQuery.summaries(configs).first.map(PhotoWidgetConfigEntity.init)
    }
}

@available(iOS 17.0, *)
struct SelectPhotoWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choisir un widget photo"
    static let description = IntentDescription("Choisis lequel de tes widgets créés dans LifeOS afficher ici.")

    @Parameter(title: "Widget")
    var config: PhotoWidgetConfigEntity?

    init() {}
    init(config: PhotoWidgetConfigEntity?) { self.config = config }
}

// MARK: - Frise

struct PhotoWidgetEntry: TimelineEntry {
    let date: Date
    let state: PhotoWidgetDisplayState
}

@available(iOS 17.0, *)
struct PhotoWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhotoWidgetEntry {
        PhotoWidgetEntry(date: .now, state: .placeholder)
    }

    func snapshot(for configuration: SelectPhotoWidgetIntent, in context: Context) async -> PhotoWidgetEntry {
        let configs = PhotoWidgetStorage.readIndex()
        let state = PhotoWidgetTimeline.state(selectedID: configuration.config?.id, configs: configs)
        if context.isPreview, case .notChosen = state { return PhotoWidgetEntry(date: .now, state: .placeholder) }
        return PhotoWidgetEntry(date: .now, state: state)
    }

    func timeline(for configuration: SelectPhotoWidgetIntent, in context: Context) async -> Timeline<PhotoWidgetEntry> {
        let configs = PhotoWidgetStorage.readIndex()
        let now = Date()
        let state = PhotoWidgetTimeline.state(selectedID: configuration.config?.id, configs: configs)
        guard case .config(let config, _) = state else {
            // Rien a faire tourner: l'app recharge le widget a chaque enregistrement.
            return Timeline(entries: [PhotoWidgetEntry(date: now, state: state)], policy: .never)
        }
        let plan = PhotoWidgetTimeline.plan(for: config, now: now)
        let entries = plan.dates.map { PhotoWidgetEntry(date: $0.date, state: .config(config, photoOffset: $0.offset)) }
        return Timeline(entries: entries, policy: plan.reloadAtEnd ? .atEnd : .never)
    }
}

// MARK: - Vue

@available(iOS 17.0, *)
struct PhotoWidgetEntryView: View {
    let entry: PhotoWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var size: PhotoWidgetSize { PhotoWidgetSize(family: family) }

    /// Photos de cette entree, lues reduites MAINTENANT (jamais gardees dans la frise).
    private var images: [UIImage] {
        guard case .config(let c, let offset) = entry.state, c.template.usesPhotos || c.style.background == .blurredPhoto,
              size != .rectangular else { return [] }
        let count = c.template == .collage ? c.style.layout.slots : 1
        let refs = PhotoWidgetSchedule.photos(c.rotatingPhotos, offset: offset, count: count)
        let px = size.maxPixel(slots: count)
        return refs.compactMap { PhotoWidgetImage.load($0, maxPixel: px) }
    }

    private var config: PhotoWidgetConfig? {
        if case .config(let c, _) = entry.state { return c }
        return nil
    }

    private var url: URL {
        config?.tapURL ?? URL(string: "lifeos://photo-widget")!
    }

    var body: some View {
        let imgs = images
        PhotoWidgetContentView(state: entry.state, images: imgs, size: size, now: entry.date)
            .containerBackground(for: .widget) {
                if size == .rectangular {
                    AccessoryWidgetBackground()
                } else {
                    PhotoWidgetBackdrop(config: config, firstImage: imgs.first)
                }
            }
            .widgetURL(url)
    }
}

@available(iOS 17.0, *)
struct PhotoWidget: Widget {
    let kind = PhotoWidgetStorage.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectPhotoWidgetIntent.self, provider: PhotoWidgetProvider()) { entry in
            PhotoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Widget photo")
        .description("Tes photos, une note, un compte à rebours ou un objectif, créés dans LifeOS.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
