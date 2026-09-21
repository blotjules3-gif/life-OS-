import XCTest
@testable import LifeOS

/// Ordre des elements de l'accueil, stocke en texte "a,b,c".
final class HomeOrderTests: XCTestCase {
    private let valid: Set<String> = ["tabata", "calories", "scan", "todo"]

    /// L'ordre stocke est l'ordre affiche: c'est tout le but du reordonnancement.
    func testKeepsStoredOrder() {
        XCTAssertEqual(HomeOrder.parse("todo,tabata,scan", valid: valid), ["todo", "tabata", "scan"])
    }

    /// Un outil retire d'une mise a jour restait invisible et impossible a enlever.
    func testDropsUnknownIds() {
        XCTAssertEqual(HomeOrder.parse("tabata,ancien,todo", valid: valid), ["tabata", "todo"])
    }

    /// Un doublon donnait deux vues au meme identifiant.
    func testDropsDuplicatesKeepingFirst() {
        XCTAssertEqual(HomeOrder.parse("scan,todo,scan", valid: valid), ["scan", "todo"])
    }

    func testEmptyAndStraySeparators() {
        XCTAssertEqual(HomeOrder.parse("", valid: valid), [])
        XCTAssertEqual(HomeOrder.parse(",tabata,,todo,", valid: valid), ["tabata", "todo"])
    }
}
