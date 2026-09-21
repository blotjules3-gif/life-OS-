import XCTest

/// Garde-fou sur les destinations du menu des categories.
///
/// `CategoryHub.swift` est la SEULE navigation vivante de l'app: 82 outils y
/// pointent chacun sur une vue. Les anciens ecrans `*HubView` sont des menus
/// intermediaires qui ne sont plus atteints par personne.
///
/// Le defaut trouve: l'outil "Médicaments" pointait sur `MedicalHubView`.
/// Toucher "Médicaments" ouvrait donc un second menu contenant Médicaments,
/// Rendez-vous, Carnet de santé et Vaccinations, c'est a dire lui-meme plus
/// les trois outils deja listes juste en dessous. La vraie liste des
/// traitements etait a un cran de plus que tout le reste de l'app, et le
/// sous-titre "Traitements en cours et rappels" annoncait autre chose que ce
/// qui s'ouvrait.
///
/// Le test lit le source parce que les destinations sont des fermetures: on ne
/// peut pas les interroger sans afficher chaque ecran.
final class CategoryHubDestinationTests: XCTestCase {

    private func hubSource() throws -> String {
        let url = repoRoot()
            .appendingPathComponent("LifeOS/Core/CategoryHub.swift")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("CategoryHub.swift introuvable à \(url.path)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Les destinations declarees, sous la forme `) { MaVue() }`.
    private func destinations(_ src: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\)\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\}"#)
        let range = NSRange(src.startIndex..<src.endIndex, in: src)
        return re.matches(in: src, range: range).compactMap {
            Range($0.range(at: 1), in: src).map { r in String(src[r]) }
        }
    }

    /// Aucun outil ne doit ouvrir un menu: un outil ouvre un ecran qui fait
    /// quelque chose.
    func testNoToolOpensAnIntermediateHub() throws {
        let src = try hubSource()
        let hubs = destinations(src).filter { $0.hasSuffix("HubView") }
        XCTAssertTrue(hubs.isEmpty,
                      "Ces outils ouvrent un menu au lieu d'un écran : \(Set(hubs).sorted()). "
                      + "Le menu des catégories EST déjà le menu.")
    }

    /// Deux outils qui ouvrent le meme ecran sont deux entrees pour une seule
    /// chose: l'une des deux est forcement mal nommee.
    func testNoDuplicateDestination() throws {
        let src = try hubSource()
        let all = destinations(src)
        let dupes = Dictionary(grouping: all, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys.sorted()
        XCTAssertTrue(dupes.isEmpty, "Destinations en double : \(dupes)")
    }

    /// Le fichier doit continuer a declarer un nombre d'outils credible.
    /// Si ce compte s'effondre, c'est qu'une liste entiere a disparu.
    func testCatalogueIsNotEmpty() throws {
        let src = try hubSource()
        XCTAssertGreaterThan(destinations(src).count, 60,
                             "Le catalogue d'outils a fondu, une catégorie a dû sauter.")
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LifeOSTests/
            .deletingLastPathComponent()   // racine
    }
}
