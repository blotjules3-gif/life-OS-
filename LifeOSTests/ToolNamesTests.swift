import XCTest
@testable import LifeOS

/// Noms des outils recus du serveur qui lit la table Notion.
final class ToolNamesTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testReadsNames() {
        let n = ToolNames.parse(data(#"{"source":"notion","names":{"Langues":"Trilingo","Médicaments":"MediSûr"}}"#))
        XCTAssertEqual(n?["Langues"], "Trilingo")
        XCTAssertEqual(n?["Médicaments"], "MediSûr")
    }

    /// Une case vide dans Notion ne doit pas vider le bouton dans l'app.
    func testEmptyNameIsIgnored() {
        let n = ToolNames.parse(data(#"{"names":{"Langues":"   ","Flashcards":"Anko"}}"#))
        XCTAssertNil(n?["Langues"])
        XCTAssertEqual(n?["Flashcards"], "Anko")
    }

    /// Un nom demesure casserait la grille des outils.
    func testOverlongNameIsIgnored() {
        let long = String(repeating: "x", count: ToolNames.maxLength + 1)
        XCTAssertNil(ToolNames.parse(data(#"{"names":{"Langues":"\#(long)"}}"#)))
    }

    func testWhitespaceIsCollapsed() {
        XCTAssertEqual(ToolNames.parse(data(#"{"names":{"Langues":"  Tri   lingo "}}"#))?["Langues"], "Tri lingo")
    }

    /// Une reponse cassee ne doit rien remplacer.
    func testGarbageGivesNil() {
        XCTAssertNil(ToolNames.parse(data("<html>erreur</html>")))
        XCTAssertNil(ToolNames.parse(data(#"{"names":{}}"#)))
        XCTAssertNil(ToolNames.parse(data(#"{"autre":1}"#)))
    }

    /// Les noms stockes sont relus, et un stockage vide rend un dictionnaire vide.
    func testCurrentReadsStoredNames() {
        let d = UserDefaults(suiteName: "ToolNamesTests")!
        d.removePersistentDomain(forName: "ToolNamesTests")
        XCTAssertTrue(ToolNames.current(d).isEmpty)
        d.set(#"{"names":{"Langues":"Trilingo"}}"#, forKey: ToolNames.storageKey)
        XCTAssertEqual(ToolNames.current(d)["Langues"], "Trilingo")
    }
}
