import XCTest
import SwiftData
@testable import LifeOS

/// Lot 8, navigation : liens profonds, file a froid, migration des onglets, Mes espaces,
/// recherche globale (outils et contenus), construction paresseuse des onglets.
@MainActor
final class Lot8NavTests: XCTestCase {

    private func link(_ s: String) -> DeepLink? { DeepLink(url: URL(string: s)!) }

    // MARK: - Lecture des URL

    func testExistingWidgetRoutes() {
        XCTAssertEqual(link("lifeos://briefing"), .briefing)
        XCTAssertEqual(link("lifeos://scan-food"), .scanFood)
        XCTAssertEqual(link("lifeos://tabata"), .tabata)
        XCTAssertTrue(DeepLink.briefing.isAppLevel)
        XCTAssertTrue(DeepLink.scanFood.isAppLevel)
        XCTAssertTrue(DeepLink.tabata.isAppLevel)
        XCTAssertFalse(DeepLink.coach(prefill: nil).isAppLevel)
    }

    func testToolShortcutsOpenTheRightTool() {
        XCTAssertEqual(link("lifeos://water"), .tool(.nutrition, "WaterMind"))
        XCTAssertEqual(link("lifeos://gym"), .tool(.fitness, "Fitbot"))
        XCTAssertEqual(link("lifeos://sleep"), .tool(.sleep, "Réveil"))
        XCTAssertEqual(link("lifeos://fasting"), .tool(.nutrition, "Zerø"))
        XCTAssertEqual(link("lifeos://tasks"), .tool(.productivity, "Todoo"))
        XCTAssertEqual(link("lifeos://agenda"), .tool(.productivity, "Structurd"))
        XCTAssertEqual(link("lifeos://habits"), .tool(.productivity, "Habitly"))
        XCTAssertEqual(link("lifeos://nutrition"), .tool(.nutrition, "Yumzio"))
    }

    /// Chaque raccourci et chaque outil d'un type de contenu existe vraiment dans
    /// CategoryHub : un renommage du code casserait le lien sans bruit.
    func testEveryShortcutTargetExists() {
        for (host, target) in DeepLink.toolShortcuts {
            XCTAssertNotNil(DeepLink.resolveTool(target.0, target.1), "lifeos://\(host) vise un outil absent")
        }
        XCTAssertNotNil(DeepLink.resolveTool(DeepLink.stocksTool.0, DeepLink.stocksTool.1))
        XCTAssertNotNil(DeepLink.resolveTool(DeepLink.tasksTool.0, DeepLink.tasksTool.1))
        for kind in SearchKind.allCases {
            guard let home = kind.home else { continue }
            XCTAssertNotNil(DeepLink.resolveTool(home.0, home.1), "\(kind) : outil d'origine absent")
        }
    }

    func testParameterRoutes() {
        XCTAssertEqual(link("lifeos://coach?prefill=Bonjour%20coach"), .coach(prefill: "Bonjour coach"))
        XCTAssertEqual(link("lifeos://coach"), .coach(prefill: nil))
        XCTAssertEqual(link("lifeos://coach?prefill="), .coach(prefill: nil))
        XCTAssertEqual(link("lifeos://capture?text=Acheter%20du%20pain%20demain"), .capture(text: "Acheter du pain demain"))
        XCTAssertEqual(link("lifeos://capture"), .capture(text: ""))
        XCTAssertEqual(link("lifeos://search?q=budget"), .search(query: "budget"))
        XCTAssertEqual(link("lifeos://search"), .search(query: ""))
        XCTAssertEqual(link("lifeos://task?uid=ABC-123"), .task(uid: "ABC-123"))
        XCTAssertEqual(link("lifeos://stocks?symbol=aapl&list=Favoris"), .stocks(symbol: "AAPL", list: "Favoris"))
        XCTAssertEqual(link("lifeos://stocks"), .stocks(symbol: nil, list: nil))
        let id = UUID()
        XCTAssertEqual(link("lifeos://photo-widget?id=\(id.uuidString)"), .photoWidget(id: id))
        XCTAssertEqual(link("lifeos://tool?cat=fitness&name=Hevvy"), .tool(.fitness, "Hevvy"))
        XCTAssertEqual(link("lifeos://today"), .today)
        XCTAssertEqual(link("lifeos://spaces"), .spaces)
        XCTAssertEqual(link("lifeos://space?cat=finance"), .space(.finance))
    }

    func testToolNameIsTolerant() {
        // Casse, accents, ancien nom descriptif.
        XCTAssertEqual(link("lifeos://tool?cat=fitness&name=hevvy"), .tool(.fitness, "Hevvy"))
        XCTAssertEqual(link("lifeos://tool?cat=nutrition&name=Hydratation"), .tool(.nutrition, "WaterMind"))
        XCTAssertEqual(link("lifeos://tool?cat=sleep&name=reveil"), .tool(.sleep, "Réveil"))
    }

    func testBadInputFallsBackOrIsRefused() {
        XCTAssertNil(link("https://lifeos.app/water"), "autre schema")
        XCTAssertNil(link("lifeos://inconnu"))
        XCTAssertNil(link("lifeos://tool?cat=pasunecategorie&name=Hevvy"))
        XCTAssertNil(link("lifeos://tool"))
        XCTAssertNil(link("lifeos://space?cat=xyz"))
        // Outil inconnu : on ouvre au moins son espace.
        XCTAssertEqual(link("lifeos://tool?cat=fitness&name=OutilDisparu"), .space(.fitness))
        XCTAssertEqual(link("lifeos://tool?cat=fitness"), .space(.fitness))
        // Tache sans identifiant : la liste des taches.
        XCTAssertEqual(link("lifeos://task"), .tool(.productivity, "Todoo"))
        XCTAssertEqual(link("lifeos://task?uid=%20"), .tool(.productivity, "Todoo"))
        // Identifiant de widget illisible : le studio, sans configuration.
        XCTAssertEqual(link("lifeos://photo-widget?id=pas-un-uuid"), .photoWidget(id: nil))
        // Casse du schema et de l'hote.
        XCTAssertEqual(link("LIFEOS://WATER"), .tool(.nutrition, "WaterMind"))
        XCTAssertEqual(link("lifeos:water"), .tool(.nutrition, "WaterMind"))
    }

    func testNotificationRouteAcceptsNamesAndURLs() {
        XCTAssertEqual(ToolRoute.link(for: "trilingo"), .tool(.learning, "Trilingo"))
        XCTAssertEqual(ToolRoute.link(for: "lifeos://habits"), .tool(.productivity, "Habitly"))
        XCTAssertNil(ToolRoute.link(for: "inconnu"))
    }

    func testSpotlightIdentifierRoundTrip() {
        let id = DeepLink.spotlightID(.travel, "Envol")
        XCTAssertEqual(DeepLink(spotlightID: id), .tool(.travel, "Envol"))
        XCTAssertNil(DeepLink(spotlightID: "tool:travel"))
        XCTAssertNil(DeepLink(spotlightID: "note:travel:Envol"))
        XCTAssertNil(DeepLink(spotlightID: "tool:travel:Disparu"))
    }

    // MARK: - File du routeur (lancement a froid)

    func testQueueHoldsLinksUntilMountedAndDeliversOnce() {
        let r = DeepLinkRouter()
        XCTAssertTrue(r.open(URL(string: "lifeos://water")!))
        XCTAssertTrue(r.open(URL(string: "lifeos://coach?prefill=Salut")!))
        XCTAssertEqual(r.revision, 2)
        // MainTabView se monte : il vide la file.
        XCTAssertEqual(r.drain(), [.tool(.nutrition, "WaterMind"), .coach(prefill: "Salut")])
        // Livre une seule fois.
        XCTAssertEqual(r.drain(), [])
    }

    func testUnknownLinkIsNotQueued() {
        let r = DeepLinkRouter()
        XCTAssertFalse(r.open(URL(string: "lifeos://nimporte")!))
        XCTAssertEqual(r.revision, 0)
        XCTAssertEqual(r.drain(), [])
    }

    func testAppLevelLinksBypassTheQueue() {
        let r = DeepLinkRouter()
        r.open(URL(string: "lifeos://tabata")!)
        XCTAssertEqual(r.appLevel, .tabata)
        XCTAssertEqual(r.drain(), [], "Tabata est presente par LifeOSApp, pas par les onglets")
        r.clearAppLevel()
        XCTAssertNil(r.appLevel)
    }

    func testDuplicateTapIsDeliveredOnceAndQueueIsBounded() {
        let r = DeepLinkRouter()
        r.send(.search(query: "x"))
        r.send(.search(query: "x"))
        XCTAssertEqual(r.drain().count, 1)
        for i in 0..<(DeepLinkRouter.maxQueue + 5) { r.send(.search(query: "\(i)")) }
        let out = r.drain()
        XCTAssertEqual(out.count, DeepLinkRouter.maxQueue)
        XCTAssertEqual(out.last, .search(query: "\(DeepLinkRouter.maxQueue + 4)"), "les plus recents sont gardes")
    }

    func testOpenModuleHook() {
        let r = DeepLinkRouter()
        r.openModule("fitness")
        r.openModule("learning", tool: "Trilingo")
        r.openModule("pasunmodule")
        XCTAssertEqual(r.drain(), [.space(.fitness), .tool(.learning, "Trilingo")])
    }

    // MARK: - Onglets

    func testTabMigrationFromOldStoredValues() {
        XCTAssertEqual(AppTab.migrated("home"), .home)
        XCTAssertEqual(AppTab.migrated("wakeup"), .spaces)
        XCTAssertEqual(AppTab.migrated("categories"), .spaces)
        XCTAssertEqual(AppTab.migrated("spaces"), .spaces)
        XCTAssertEqual(AppTab.migrated("profile"), .profile)
        XCTAssertEqual(AppTab.migrated(""), .home)
        XCTAssertEqual(AppTab.migrated("nimporte"), .home)
        XCTAssertEqual(AppTab.home.label, "Aujourd'hui")
        XCTAssertEqual(AppTab.spaces.label, "Mes espaces")
    }

    func testTabBarSlotsKeepPlusInTheCenterAndTheCoach() {
        XCTAssertEqual(FloatingTabBar.slots, [.tab(.home), .tab(.spaces), .capture, .coach, .tab(.profile)])
        XCTAssertEqual(FloatingTabBar.slot(atX: 10, usefulWidth: 500), .tab(.home))
        XCTAssertEqual(FloatingTabBar.slot(atX: 250, usefulWidth: 500), .capture)
        XCTAssertEqual(FloatingTabBar.slot(atX: 499, usefulWidth: 500), .tab(.profile))
        XCTAssertEqual(FloatingTabBar.slot(atX: -40, usefulWidth: 500), .tab(.home), "borne a gauche")
        XCTAssertEqual(FloatingTabBar.slot(atX: 900, usefulWidth: 500), .tab(.profile), "borne a droite")
        XCTAssertNil(FloatingTabBar.slot(atX: 10, usefulWidth: 0))
    }

    func testLazyPanesBuildOnlyVisibleAndVisited() {
        var v = TabPaneVisits()
        XCTAssertTrue(v.shouldBuild(.home, current: .home))
        XCTAssertFalse(v.shouldBuild(.spaces, current: .home))
        XCTAssertFalse(v.shouldBuild(.profile, current: .home))
        v.visit(.home)
        v.visit(.profile)
        // Retour a l'accueil : le Profil visite reste construit (defilement garde).
        XCTAssertTrue(v.shouldBuild(.profile, current: .home))
        XCTAssertFalse(v.shouldBuild(.spaces, current: .home))
        // Relance restauree sur le Profil : l'accueil n'est pas construit pour rien.
        let restored = TabPaneVisits()
        XCTAssertTrue(restored.shouldBuild(.profile, current: .profile))
        XCTAssertFalse(restored.shouldBuild(.home, current: .profile))
    }

    // MARK: - Mes espaces

    func testFavoriteDomainSeeding() {
        // Choisi a la main : gagne.
        XCTAssertEqual(SpacesPreferences.favorite(storedRaw: "finance", priorityRaw: "nutrition", secondTabRaw: "fitness", recommendedRaw: ""), .finance)
        // Sinon le premier domaine prioritaire.
        XCTAssertEqual(SpacesPreferences.favorite(storedRaw: "", priorityRaw: "nutrition,fitness", secondTabRaw: "sleep", recommendedRaw: ""), .nutrition)
        // Sinon l'ancien 2e onglet (une categorie).
        XCTAssertEqual(SpacesPreferences.favorite(storedRaw: "", priorityRaw: "", secondTabRaw: "fitness", recommendedRaw: "mind"), .fitness)
        // L'ancien Reveil n'est pas une categorie : on passe aux recommandations.
        XCTAssertEqual(SpacesPreferences.favorite(storedRaw: "", priorityRaw: "", secondTabRaw: "wakeup", recommendedRaw: "mind"), .mind)
        // Rien du tout, ou valeurs abimees : jamais vide.
        XCTAssertEqual(SpacesPreferences.favorite(storedRaw: "xx", priorityRaw: "yy", secondTabRaw: "zz", recommendedRaw: ""), .productivity)
    }

    func testPriorityOthersNeverRepeatTheFavorite() {
        let o = SpacesPreferences.others(favorite: .nutrition, priorityRaw: "nutrition,fitness,fitness,sleep", recommendedRaw: "")
        XCTAssertEqual(o, [.fitness, .sleep])
        let filled = SpacesPreferences.others(favorite: .productivity, priorityRaw: "", recommendedRaw: "")
        XCTAssertEqual(filled.count, 2)
        XCTAssertFalse(filled.contains(.productivity))
        XCTAssertEqual(SpacesPreferences.parse("sleep, finance,bad,sleep"), [.sleep, .finance])
    }

    // MARK: - Recherche : correspondance et classement

    func testNormalizeAndMatchIgnoreAccentsAndCase() {
        XCTAssertEqual(SearchIndex.normalize("  Jeûne   Intermittent "), "jeune intermittent")
        XCTAssertNotNil(SearchIndex.fieldScore(query: "jeune", field: "Jeûne intermittent"))
        XCTAssertNotNil(SearchIndex.fieldScore(query: "ÉCHÉANCES", field: "echeances"))
        XCTAssertNil(SearchIndex.fieldScore(query: "xyz", field: "Hydratation"))
        XCTAssertNil(SearchIndex.fieldScore(query: "  ", field: "Hydratation"))
    }

    func testRankingPrefersExactThenPrefixThenWordThenContains() {
        let exact = SearchIndex.fieldScore(query: "notes", field: "Notes")!
        let prefix = SearchIndex.fieldScore(query: "not", field: "Notes & second cerveau")!
        let word = SearchIndex.fieldScore(query: "second", field: "Notes & second cerveau")!
        let inside = SearchIndex.fieldScore(query: "cond", field: "Notes & second cerveau")!
        let multi = SearchIndex.fieldScore(query: "cerveau notes", field: "Notes & second cerveau")!
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, word)
        XCTAssertGreaterThan(word, inside)
        XCTAssertGreaterThan(inside, multi)
    }

    private let catalog: [ToolSearchEntry] = [
        .init(category: .nutrition, categoryTitle: "Nutrition", title: "WaterMind", defaultTitle: "WaterMind",
              alias: "Hydratation", subtitle: "Suivi + rappels", icon: "drop.fill"),
        .init(category: .nutrition, categoryTitle: "Nutrition", title: "Zerø", defaultTitle: "Zerø",
              alias: "Jeûne intermittent", subtitle: "16:8, 18:6, OMAD", icon: "timer"),
        .init(category: .productivity, categoryTitle: "Productivité", title: "Notio", defaultTitle: "Notio",
              alias: "Notes & second cerveau", subtitle: "Capture rapide + tags", icon: "note.text"),
        .init(category: .finance, categoryTitle: "Finances perso", title: "Ynabi", defaultTitle: "Ynabi",
              alias: "Budget par enveloppes", subtitle: "Catégorise et plafonne", icon: "tray"),
    ]

    func testToolSearchMatchesAliasCategoryAndRanksNamesFirst() {
        XCTAssertEqual(SearchIndex.toolHits("hydra", in: catalog).map(\.toolName), ["WaterMind"])
        XCTAssertEqual(SearchIndex.toolHits("jeune", in: catalog).map(\.toolName), ["Zerø"])
        // Le nom de l'espace trouve tous ses outils.
        XCTAssertEqual(Set(SearchIndex.toolHits("nutrition", in: catalog).compactMap(\.toolName)), ["WaterMind", "Zerø"])
        // Un titre l'emporte sur un mot du sous-titre.
        let notes = SearchIndex.toolHits("not", in: catalog)
        XCTAssertEqual(notes.first?.toolName, "Notio")
        XCTAssertTrue(SearchIndex.toolHits("", in: catalog).isEmpty)
        XCTAssertEqual(SearchIndex.toolHits("budget", in: catalog).first?.kind, .tool)
    }

    func testRealCatalogFindsToolsByOldDescriptiveName() {
        let all = SearchIndex.toolCatalog()
        XCTAssertGreaterThan(all.count, 80)
        XCTAssertEqual(SearchIndex.toolHits("tabata", in: all).first?.toolName, "TabaTime")
        XCTAssertEqual(SearchIndex.toolHits("medicaments", in: all).first?.toolName, "MediSûr")
    }

    func testGroupsPutToolsBeforeContent() {
        let tool = SearchIndex.toolHits("budget", in: catalog)
        let content = SearchHit(id: "task:1", kind: .task, title: "Faire le budget", subtitle: "", category: .productivity,
                                score: 100, toolCategory: .productivity, toolName: "Todoo", record: nil, icon: "checklist")
        let g = SearchIndex.grouped([content] + tool)
        XCTAssertEqual(g.map(\.kind), [.tool, .task])
    }

    func testFoodDedupeKeepsMostRecentOnly() {
        func food(_ id: String, _ title: String) -> SearchHit {
            SearchHit(id: id, kind: .food, title: title, subtitle: "", category: .nutrition, score: 80,
                      toolCategory: .nutrition, toolName: "Yumzio", record: nil, icon: "fork.knife")
        }
        let out = SearchIndex.dedupeByTitle([food("1", "Pomme"), food("2", "pomme"), food("3", "Poire")])
        XCTAssertEqual(out.map(\.id), ["1", "3"])
    }

    // MARK: - Recherche dans les contenus (SwiftData en memoire)

    func testContentSearchFindsEachTypeAccentInsensitive() throws {
        let container = try ModelContainer(for: LocalStore.schema,
                                           configurations: [ModelConfiguration(schema: LocalStore.schema, isStoredInMemoryOnly: true)])
        let ctx = container.mainContext
        let now = Date()
        ctx.insert(TodoItem(title: "Réserver le vélo", notes: ""))
        ctx.insert(Note(title: "Idées", body: "Un vélo électrique pour le trajet"))
        ctx.insert(Habit(name: "Vélo 20 min"))
        let archived = Habit(name: "Vélo archivé"); archived.isArchived = true
        ctx.insert(archived)
        ctx.insert(Contact(name: "Velo Club", notes: ""))
        ctx.insert(Trip(name: "Tour à vélo", destination: "Loire"))
        ctx.insert(FoodEntry(date: now, name: "Barre vélo", calories: 200))
        ctx.insert(FoodEntry(date: now.addingTimeInterval(-3600), name: "Barre vélo", calories: 200))
        ctx.insert(FoodEntry(date: now.addingTimeInterval(-200 * 86_400), name: "Vieux vélo snack", calories: 100))
        ctx.insert(Txn(date: now, amount: -12, category: "Transport", note: "Réparation vélo"))
        ctx.insert(Txn(date: now.addingTimeInterval(-400 * 86_400), amount: -5, category: "Transport", note: "Vélo ancien"))
        ctx.insert(TodoItem(title: "Sans rapport"))
        try ctx.save()

        let hits = SearchIndex.contentHits("velo", in: ctx, now: now)
        let kinds = Set(hits.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.task, .note, .habit, .contact, .trip, .food, .transaction]), "trouves : \(kinds)")
        XCTAssertFalse(hits.contains { $0.title == "Vélo archivé" }, "habitude archivee exclue")
        XCTAssertEqual(hits.filter { $0.kind == .food }.count, 1, "un seul resultat par aliment, et rien au-dela de 90 jours")
        XCTAssertEqual(hits.filter { $0.kind == .transaction }.count, 1, "rien au-dela de 365 jours")
        XCTAssertFalse(hits.contains { $0.title == "Sans rapport" })
        XCTAssertTrue(hits.allSatisfy { $0.record != nil }, "chaque contenu pointe vers son element")
        XCTAssertTrue(SearchIndex.contentHits("v", in: ctx, now: now).isEmpty, "une lettre ne lance pas de recherche")
        _ = container
    }

    func testContentSearchRespectsPerTypeLimit() throws {
        let container = try ModelContainer(for: LocalStore.schema,
                                           configurations: [ModelConfiguration(schema: LocalStore.schema, isStoredInMemoryOnly: true)])
        let ctx = container.mainContext
        for i in 0..<30 { ctx.insert(TodoItem(title: "Courses \(i)")) }
        try ctx.save()
        let hits = SearchIndex.contentHits("courses", in: ctx)
        XCTAssertEqual(hits.filter { $0.kind == .task }.count, SearchIndex.perTypeLimit)
        _ = container
    }

    // MARK: - Lot 8 : garde des branchements

    func testAppForwardsURLsAndIntentsToTheRouter() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("LifeOS/LifeOSApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("DeepLinkRouter.shared.open(url)"))
        let delegate = try String(contentsOf: root.appendingPathComponent("LifeOS/Core/AppDelegate.swift"), encoding: .utf8)
        XCTAssertTrue(delegate.contains("DeepLinkRouter.shared.send(link)"), "notifications par la file du routeur")
    }
}
