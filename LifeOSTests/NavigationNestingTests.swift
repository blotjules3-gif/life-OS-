import XCTest
@testable import LifeOS

/// Un outil pousse dans le `NavigationStack` d'une categorie ne doit pas ouvrir le
/// sien.
///
/// Mesure le 28 septembre: Floe, Klue et Floe Stats enveloppaient leur ecran dans
/// un `NavigationStack`. Sur telephone, toucher Floe renvoyait a la liste des
/// categories au lieu de l'ouvrir; au retour, SwiftUI plantait
/// (`NavigationColumnState.boundPathChange`, SIGTRAP). Sur bureau, le panneau de
/// categorie a maintenant son propre conteneur, donc le meme piege s'y appliquait.
///
/// Test sur les SOURCES: le defaut est une ligne de code qui ne doit pas exister
/// a la racine de ces ecrans.
final class NavigationNestingTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// (vue, fichier) de chaque outil de categorie qui n'est PAS plein ecran,
    /// lus dans le registre du hub.
    private func pushedTools() throws -> [(view: String, file: String)] {
        let hub = try source("LifeOS/Core/CategoryHub.swift")
        let pattern = #"\.init\("[^"]*",\s*"[^"]+"[^\n]*?\{\s*([A-Za-z0-9_]+)\([^)]*\)\s*\}"#
        let re = try NSRegularExpression(pattern: pattern)
        let ns = hub as NSString
        var out: [(String, String)] = []
        for m in re.matches(in: hub, range: NSRange(location: 0, length: ns.length)) {
            let line = ns.substring(with: m.range)
            if line.contains("fullScreen: true") { continue }
            out.append((ns.substring(with: m.range(at: 1)), ""))
        }
        return out
    }

    func testNoPushedToolWrapsItsRootInANavigationStack() throws {
        let tools = try pushedTools()
        XCTAssertGreaterThan(tools.count, 50, "le registre n'a pas ete lu: le test se croirait vert a tort")

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LifeOS")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }) ?? []
        let sources = try files.map { try String(contentsOf: $0, encoding: .utf8) }

        var offenders: [String] = []
        for (view, _) in tools {
            guard let s = sources.first(where: { $0.contains("struct \(view)") }),
                  let start = s.range(of: "struct \(view)"),
                  let body = s.range(of: "var body: some View {", range: start.upperBound..<s.endIndex)
            else { continue }
            let firstLine = s[body.upperBound...]
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if firstLine.hasPrefix("NavigationStack") { offenders.append(view) }
        }
        XCTAssertEqual(offenders, [], "Ces outils ouvrent un NavigationStack imbrique: \(offenders)")
    }
}
