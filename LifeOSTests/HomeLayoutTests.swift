import XCTest
@testable import LifeOS

/// Ordre des blocs de l'accueil, reordonnables comme sur iOS.
final class HomeLayoutTests: XCTestCase {

    /// Accueil range a l'ancienne (tous les blocs affiches, ordre d'avant le lot 8,
    /// puis les 4 blocs du lot 8). Sert aux tests de deplacement.
    private static let arrangedRaw = (HomeLayout.legacyOrder + HomeWidget.lot8Kinds)
        .map(\.rawValue).joined(separator: ",") + "|"

    private func arranged() -> HomeLayout { HomeLayout.parse(Self.arrangedRaw) }

    /// Premier lancement: les 4 blocs du lot 8, les raccourcis et le coach.
    /// Les anciens blocs attendent dans la galerie, masques.
    func testEmptyGivesDefaultLayout() {
        let l = HomeLayout.parse("")
        XCTAssertEqual(l.visible, [.now, .capture, .today, .watch, .shortcuts, .coach])
        XCTAssertEqual(Set(l.visible + l.hidden), Set(HomeLayout.defaultOrder))
        XCTAssertTrue(Set(l.visible).isDisjoint(with: l.hidden))
    }

    /// Domaine Productivite: la liste des taches reste sur l'accueil.
    func testProductivityDomainKeepsTasksVisible() {
        let l = HomeLayout.parse("", domains: [.productivity])
        XCTAssertTrue(l.visible.contains(.tasks))
        XCTAssertFalse(l.hidden.contains(.tasks))
    }

    /// Reprise d'un accueil d'avant le lot 8: l'ordre reste, les nouveaux blocs
    /// arrivent a la fin.
    func testMigrateKeepsOldOrder() {
        let l = HomeLayout.migrate(legacyRaw: "goals,score|coach")
        XCTAssertEqual(Array(l.visible.prefix(2)), [.goals, .score])
        XCTAssertEqual(l.hidden, [.coach])
        // Les blocs absents du texte stocke (lot 8 d'abord) arrivent apres l'ordre de l'utilisateur.
        XCTAssertEqual(Array(l.visible.dropFirst(2).prefix(4)), HomeWidget.lot8Kinds)
        XCTAssertEqual(Set(l.visible + l.hidden), Set(HomeWidget.allCases))
    }

    func testRoundTrip() {
        var l = arranged()
        l.move(.goals, to: .score)
        l.hide(.coach)
        XCTAssertEqual(HomeLayout.parse(l.raw), l)
    }

    /// Glisser vers le haut: le bloc prend la place de la cible.
    func testMoveUp() {
        var l = arranged()
        l.move(.tasks, to: .shortcuts)
        XCTAssertEqual(Array(l.visible.prefix(3)), [.score, .tasks, .shortcuts])
    }

    /// Glisser vers le bas: il passe apres la cible.
    func testMoveDown() {
        var l = arranged()
        l.move(.score, to: .coach)
        XCTAssertEqual(Array(l.visible.prefix(3)), [.shortcuts, .coach, .score])
    }

    func testMoveOntoItselfChangesNothing() {
        var l = arranged()
        l.move(.habits, to: .habits)
        XCTAssertEqual(l, arranged())
    }

    /// Un bloc masque ne peut pas etre deplace ni servir de cible.
    func testMoveIgnoresHiddenWidgets() {
        var l = arranged()
        l.hide(.coach)
        l.move(.coach, to: .score)
        l.move(.score, to: .coach)
        XCTAssertFalse(l.visible.contains(.coach))
        XCTAssertEqual(l.visible.first, .score)
    }

    func testHideThenShowGoesToTheEnd() {
        var l = arranged()
        l.hide(.score)
        XCTAssertEqual(l.hidden, [.score])
        l.show(.score)
        XCTAssertEqual(l.visible.last, .score)
        XCTAssertTrue(l.hidden.isEmpty)
    }

    /// Le cas qui ferait disparaitre une nouveaute: un bloc absent du texte
    /// enregistre (ajoute par une mise a jour) doit apparaitre, pas rester cache.
    func testNewWidgetAfterUpdateAppearsAtTheEnd() {
        let l = HomeLayout.parse("goals,score|coach")
        XCTAssertEqual(Array(l.visible.prefix(2)), [.goals, .score])
        XCTAssertEqual(l.hidden, [.coach])
        XCTAssertEqual(Set(l.visible + l.hidden), Set(HomeWidget.allCases))
    }

    func testUnknownAndDuplicateIdsAreDropped() {
        let l = HomeLayout.parse("score,ancien,score,tasks|tasks,inconnu")
        XCTAssertEqual(l.visible.filter { $0 == .score }.count, 1)
        XCTAssertEqual(l.visible.filter { $0 == .tasks }.count, 1)
        XCTAssertFalse(l.hidden.contains(.tasks), "un bloc ne peut pas etre a la fois affiche et masque")
    }

    /// Tout masquer est permis: l'accueil garde son bouton pour tout remettre.
    func testEverythingHidden() {
        let all = HomeWidget.allCases.map(\.rawValue).joined(separator: ",")
        let l = HomeLayout.parse("|" + all)
        XCTAssertTrue(l.visible.isEmpty)
        XCTAssertEqual(l.hidden.count, HomeWidget.allCases.count)
    }

    func testShiftForVoiceOver() {
        var l = arranged()
        l.shift(.shortcuts, by: -1)
        XCTAssertEqual(l.visible.first, .shortcuts)
        l.shift(.shortcuts, by: -1)
        XCTAssertEqual(l.visible.first, .shortcuts, "deja en haut, rien ne bouge")
        let before = l.visible.firstIndex(of: .goals)!
        l.shift(.goals, by: 1)
        XCTAssertEqual(l.visible.firstIndex(of: .goals), before + 1)
    }
}
