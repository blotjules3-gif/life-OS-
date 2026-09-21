import XCTest
@testable import LifeOS

/// Ordre des blocs de l'accueil, reordonnables comme sur iOS.
final class HomeLayoutTests: XCTestCase {

    /// Premier lancement: l'ordre qu'avait l'accueil avant, rien de masque.
    func testEmptyGivesDefaultOrder() {
        let l = HomeLayout.parse("")
        XCTAssertEqual(l.visible, HomeLayout.defaultOrder)
        XCTAssertTrue(l.hidden.isEmpty)
    }

    func testRoundTrip() {
        var l = HomeLayout.parse("")
        l.move(.goals, to: .score)
        l.hide(.coach)
        XCTAssertEqual(HomeLayout.parse(l.raw), l)
    }

    /// Glisser vers le haut: le bloc prend la place de la cible.
    func testMoveUp() {
        var l = HomeLayout.parse("")
        l.move(.tasks, to: .shortcuts)
        XCTAssertEqual(Array(l.visible.prefix(3)), [.score, .tasks, .shortcuts])
    }

    /// Glisser vers le bas: il passe apres la cible.
    func testMoveDown() {
        var l = HomeLayout.parse("")
        l.move(.score, to: .coach)
        XCTAssertEqual(Array(l.visible.prefix(3)), [.shortcuts, .coach, .score])
    }

    func testMoveOntoItselfChangesNothing() {
        var l = HomeLayout.parse("")
        l.move(.habits, to: .habits)
        XCTAssertEqual(l.visible, HomeLayout.defaultOrder)
    }

    /// Un bloc masque ne peut pas etre deplace ni servir de cible.
    func testMoveIgnoresHiddenWidgets() {
        var l = HomeLayout.parse("")
        l.hide(.coach)
        l.move(.coach, to: .score)
        l.move(.score, to: .coach)
        XCTAssertFalse(l.visible.contains(.coach))
        XCTAssertEqual(l.visible.first, .score)
    }

    func testHideThenShowGoesToTheEnd() {
        var l = HomeLayout.parse("")
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
        var l = HomeLayout.parse("")
        l.shift(.shortcuts, by: -1)
        XCTAssertEqual(l.visible.first, .shortcuts)
        l.shift(.shortcuts, by: -1)
        XCTAssertEqual(l.visible.first, .shortcuts, "deja en haut, rien ne bouge")
        l.shift(.goals, by: 1)
        XCTAssertEqual(l.visible.last, .goals)
    }
}
