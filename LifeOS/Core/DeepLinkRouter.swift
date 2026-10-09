import SwiftUI
import SwiftData
import CoreSpotlight

// MARK: - Liens profonds
//
// Une seule porte d'entree pour tout ce qui ouvre un ecran depuis l'exterieur :
// liens `lifeos://` (widgets, raccourcis), notifications, App Intents, Spotlight,
// recherche globale. Le routeur garde une FILE : un lien qui arrive avant que
// l'interface soit montee (lancement a froid, base encore en construction,
// onboarding pas fini) n'est plus perdu, il est livre une seule fois des que
// MainTabView est la.

/// Ce qu'un lien demande d'ouvrir. Valeur pure : se teste sans interface.
enum DeepLink: Equatable {
    // Ecrans presentes par LifeOSApp lui-meme (au-dessus de toute l'app).
    case briefing
    case scanFood
    case tabata
    // Ecrans presentes par MainTabView.
    case today
    case spaces
    case space(AppCategory)
    /// Outil d'une categorie, designe par son nom ecrit dans le code (`defaultTitle`).
    case tool(AppCategory, String)
    case coach(prefill: String?)
    case capture(text: String)
    case search(query: String)
    case task(uid: String)
    case stocks(symbol: String?, list: String?)
    case photoWidget(id: UUID?)
    /// Un element trouve par la recherche globale (pas d'URL publique).
    case record(SearchRecordRef)

    /// Presente par LifeOSApp (fenetre entiere) plutot que par MainTabView.
    var isAppLevel: Bool {
        switch self {
        case .briefing, .scanFood, .tabata: return true
        default: return false
        }
    }

    // MARK: Raccourcis vers un outil precis

    /// Hotes `lifeos://<hote>` qui ouvrent directement un outil.
    /// Le nom est le `defaultTitle` de CategoryHub (stable, contrairement au titre affiche).
    static let toolShortcuts: [String: (AppCategory, String)] = [
        "water":     (.nutrition, "WaterMind"),
        "gym":       (.fitness, "Fitbot"),
        "sleep":     (.sleep, "Réveil"),
        "fasting":   (.nutrition, "Zerø"),
        "tasks":     (.productivity, "Todoo"),
        "agenda":    (.productivity, "Structurd"),
        "habits":    (.productivity, "Habitly"),
        "nutrition": (.nutrition, "Yumzio"),
    ]

    /// Outil ouvert par `stocks` (le portefeuille, actions et crypto).
    static let stocksTool: (AppCategory, String) = (.invest, "Finario")
    /// Outil ouvert par `task` quand la tache n'existe plus.
    static let tasksTool: (AppCategory, String) = (.productivity, "Todoo")

    // MARK: Lecture d'une URL

    /// `nil` = lien qui n'est pas pour nous ou qu'on ne sait pas ouvrir.
    /// Une valeur abimee retombe sur l'ecran le plus proche plutot que sur rien
    /// (outil inconnu -> son espace, identifiant illisible -> la liste).
    init?(url: URL) {
        guard url.scheme?.lowercased() == "lifeos" else { return nil }
        // `lifeos://water` (hote) et `lifeos:water` / `lifeos:///water` (chemin) sont acceptes.
        var host = (url.host ?? "").lowercased()
        if host.isEmpty {
            host = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        if let shortcut = Self.toolShortcuts[host] {
            self = .tool(shortcut.0, shortcut.1)
            return
        }
        switch host {
        case "briefing":   self = .briefing
        case "scan-food":  self = .scanFood
        case "tabata":     self = .tabata
        case "today", "home": self = .today
        case "spaces":     self = .spaces
        case "coach":      self = .coach(prefill: param("prefill"))
        case "capture":    self = .capture(text: param("text") ?? "")
        case "search":     self = .search(query: param("q") ?? "")
        case "task":
            if let uid = param("uid") { self = .task(uid: uid) }
            else { self = .tool(Self.tasksTool.0, Self.tasksTool.1) }
        case "stocks":
            self = .stocks(symbol: param("symbol")?.uppercased(), list: param("list"))
        case "photo-widget":
            self = .photoWidget(id: param("id").flatMap(UUID.init(uuidString:)))
        case "space":
            guard let cat = param("cat").flatMap(AppCategory.init(rawValue:)) else { return nil }
            self = .space(cat)
        case "tool":
            guard let cat = param("cat").flatMap(AppCategory.init(rawValue:)) else { return nil }
            if let name = param("name"), let found = Self.toolName(matching: name, in: cat) {
                self = .tool(cat, found)
            } else {
                self = .space(cat)
            }
        default:
            return nil
        }
    }

    /// Nom exact (`defaultTitle`) de l'outil d'une categorie. Tolere la casse, les
    /// accents et l'ancien nom descriptif (`alias`).
    static func toolName(matching name: String, in cat: AppCategory) -> String? {
        let n = SearchIndex.normalize(name)
        guard !n.isEmpty else { return nil }
        let tools = cat.tools
        if let t = tools.first(where: { $0.defaultTitle == name }) { return t.defaultTitle }
        return tools.first(where: { SearchIndex.normalize($0.defaultTitle) == n || SearchIndex.normalize($0.alias) == n })?
            .defaultTitle
    }

    /// L'outil designe par un lien `.tool`, s'il existe encore.
    static func resolveTool(_ cat: AppCategory, _ name: String) -> CategoryTool? {
        cat.tools.first { $0.defaultTitle == name }
    }

    // MARK: Spotlight

    static func spotlightID(_ cat: AppCategory, _ name: String) -> String { "tool:\(cat.rawValue):\(name)" }

    init?(spotlightID id: String) {
        let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "tool", let cat = AppCategory(rawValue: parts[1]),
              let name = Self.toolName(matching: parts[2], in: cat) else { return nil }
        self = .tool(cat, name)
    }
}

/// Reference vers un enregistrement trouve par la recherche globale.
struct SearchRecordRef: Hashable {
    let kind: SearchKind
    let id: PersistentIdentifier
}

/// Ce que le portefeuille doit mettre en avant (lien `stocks?symbol=&list=`).
struct StockFocus: Equatable {
    let symbol: String?
    let list: String?
}

// MARK: - Routeur

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    /// Ecran demande a LifeOSApp (briefing, scan repas, Tabata). LifeOSApp le lit puis
    /// appelle `clearAppLevel()`. Publie : un abonne tardif recoit la valeur en attente.
    @Published private(set) var appLevel: DeepLink?
    /// Avance a chaque lien mis en file. MainTabView s'y abonne et vide la file.
    @Published private(set) var revision = 0
    /// Derniere demande du portefeuille. Le module bourse peut la lire puis la vider.
    @Published var stockFocus: StockFocus?

    private(set) var queue: [DeepLink] = []
    /// Plafond de la file : un consommateur absent ne doit pas faire grossir la memoire.
    static let maxQueue = 20

    init() {}

    /// Lien `lifeos://`. Rend `false` si le lien n'est pas compris (rien n'est mis en file).
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else {
            AppLog.general.info("lien ignore: \(url.absoluteString, privacy: .public)")
            return false
        }
        send(link)
        return true
    }

    func send(_ link: DeepLink) {
        if link.isAppLevel {
            appLevel = link
            return
        }
        // Le meme lien deux fois de suite (double appui, widget + notification) = un seul.
        if queue.last == link { return }
        queue.append(link)
        if queue.count > Self.maxQueue { queue.removeFirst(queue.count - Self.maxQueue) }
        revision &+= 1
    }

    /// Rend la file et la vide : chaque lien n'est livre qu'une fois.
    func drain() -> [DeepLink] {
        let out = queue
        queue.removeAll()
        return out
    }

    func clearAppLevel() { appLevel = nil }

    /// Point d'entree des App Intents et notifications qui ouvrent un module.
    func openModule(_ module: String, tool: String? = nil) {
        guard let cat = AppCategory(rawValue: module) else { return }
        if let tool, let name = DeepLink.toolName(matching: tool, in: cat) {
            send(.tool(cat, name))
        } else {
            send(.space(cat))
        }
    }
}

// MARK: - Visites des onglets (construction paresseuse)

/// Seuls l'onglet visible et ceux deja visites sont construits. Un onglet visite
/// reste en memoire : il garde son defilement et sa navigation.
struct TabPaneVisits: Equatable {
    private(set) var visited: Set<AppTab>

    init(visited: Set<AppTab> = []) { self.visited = visited }

    mutating func visit(_ tab: AppTab) { visited.insert(tab) }
    /// L'onglet affiche est toujours construit, meme avant d'etre note comme visite.
    func shouldBuild(_ tab: AppTab, current: AppTab) -> Bool { tab == current || visited.contains(tab) }
}

// MARK: - Index Spotlight des outils

/// Les outils apparaissent dans la recherche de l'iPhone. Reindexe seulement quand
/// la liste ou les noms changent (empreinte stockee).
enum SpotlightToolIndexer {
    private static let fingerprintKey = "spotlight.tools.fingerprint"

    static func entries() -> [(id: String, title: String, detail: String, keywords: [String])] {
        AppCategory.allCases.flatMap { cat in
            cat.tools.map { t in
                (DeepLink.spotlightID(cat, t.defaultTitle),
                 t.title,
                 [t.subtitle, cat.title].filter { !$0.isEmpty }.joined(separator: " · "),
                 [t.defaultTitle, t.alias, cat.title].filter { !$0.isEmpty })
            }
        }
    }

    static func indexIfNeeded() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let all = entries()
        // Chaine complete (hashValue change a chaque lancement).
        let fingerprint = all.map { "\($0.id)|\($0.title)|\($0.detail)" }.joined(separator: "\n")
        if UserDefaults.standard.string(forKey: fingerprintKey) == fingerprint { return }
        let items = all.map { e -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            attrs.title = e.title
            attrs.contentDescription = e.detail
            attrs.keywords = e.keywords
            return CSSearchableItem(uniqueIdentifier: e.id, domainIdentifier: "lifeos.tools", attributeSet: attrs)
        }
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["lifeos.tools"])
            try await CSSearchableIndex.default().indexSearchableItems(items)
            UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
        } catch {
            AppLog.general.error("index Spotlight: \(error.localizedDescription, privacy: .public)")
        }
    }
}
