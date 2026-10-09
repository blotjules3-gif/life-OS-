import AppIntents
import WidgetKit

// Configuration des widgets bourse : les choix viennent de l'instantane ecrit par
// l'app (`StockWidgetSnapshot`), jamais d'une liste figee.

struct StockListEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Liste de titres"
    static var defaultQuery = StockListQuery()

    var id: String
    var name: String
    var detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(_ c: StockChoice) { id = c.id; name = c.title; detail = c.subtitle }
}

struct StockListQuery: EntityQuery {
    func entities(for identifiers: [StockListEntity.ID]) async throws -> [StockListEntity] {
        let all = StockWidgetSnapshot.read()?.listChoices ?? []
        return identifiers.compactMap { id in all.first { $0.id == id }.map(StockListEntity.init) }
    }

    func suggestedEntities() async throws -> [StockListEntity] {
        (StockWidgetSnapshot.read()?.listChoices ?? []).map(StockListEntity.init)
    }

    func defaultResult() async -> StockListEntity? {
        guard let snap = StockWidgetSnapshot.read(), let l = snap.defaultList else { return nil }
        return snap.listChoices.first { $0.id == l.id }.map(StockListEntity.init)
    }
}

struct StockSymbolEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Titre"
    static var defaultQuery = StockSymbolQuery()

    var id: String
    var detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)", subtitle: "\(detail)")
    }

    init(_ c: StockChoice) { id = c.id; detail = c.subtitle }
}

struct StockSymbolQuery: EntityQuery {
    func entities(for identifiers: [StockSymbolEntity.ID]) async throws -> [StockSymbolEntity] {
        let all = StockWidgetSnapshot.read()?.symbolChoices ?? []
        // Un titre retire des listes n'est plus propose ; s'il etait choisi, le widget le dit.
        return identifiers.compactMap { id in all.first { $0.id == id }.map(StockSymbolEntity.init) }
    }

    func suggestedEntities() async throws -> [StockSymbolEntity] {
        (StockWidgetSnapshot.read()?.symbolChoices ?? []).map(StockSymbolEntity.init)
    }

    func defaultResult() async -> StockSymbolEntity? {
        StockWidgetSnapshot.read()?.symbolChoices.first.map(StockSymbolEntity.init)
    }
}

struct StockListWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Liste de titres"
    static var description = IntentDescription("Choisis la liste de titres suivis à afficher.")

    @Parameter(title: "Liste")
    var list: StockListEntity?

    init() {}
    init(list: StockListEntity?) { self.list = list }
}

struct StockSingleWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Un titre"
    static var description = IntentDescription("Choisis le titre à afficher.")

    @Parameter(title: "Titre")
    var symbol: StockSymbolEntity?

    init() {}
    init(symbol: StockSymbolEntity?) { self.symbol = symbol }
}
