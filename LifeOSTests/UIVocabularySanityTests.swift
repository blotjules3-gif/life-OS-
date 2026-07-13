import XCTest

/// Convention LifeOS : dans l'UI on dit « ton coach », jamais « IA » ni « LLM ».
/// Ce test scanne les littéraux Swift de LifeOS/ et échoue si un token interdit
/// apparaît dans une chaîne. Les rares occurrences historiques sont listées
/// dans `grandfathered` — à nettoyer dans les passes d'audit sectorielles,
/// jamais à agrandir.
final class UIVocabularySanityTests: XCTestCase {

    /// Fichiers historiques contenant encore un « IA » / « LLM » dans une chaîne UI.
    /// Chemins relatifs à la racine du repo.
    private let grandfathered: Set<String> = []

    /// La regex ne matche que si le token est dans une chaîne littérale `"..."`.
    /// Les commentaires `//` n'ont pas de quotes autour du token → pas de faux positif.
    private static let forbiddenInLiteral =
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #""[^"]*\b(LLM|IA)\b[^"]*""#)

    func testForbiddenTokensAbsentFromUIStrings() throws {
        let root = repoRoot().appendingPathComponent("LifeOS")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("LifeOS/ introuvable à \(root.path)")
        }

        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let rel = relativePath(url, from: repoRoot())
            if grandfathered.contains(rel) { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for (i, raw) in lines.enumerated() {
                let line = String(raw)
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if Self.forbiddenInLiteral.firstMatch(in: line, options: [], range: range) != nil {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    offenders.append("\(rel):\(i + 1): \(trimmed)")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Chaînes UI interdites (« LLM » ou « IA ») :\n"
                + offenders.joined(separator: "\n")
                + "\n\nConvention : dans l'UI, on dit « ton coach »."
        )
    }

    // MARK: - Chemin repo

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LifeOSTests/
            .deletingLastPathComponent()   // LifeOS-associe/
    }

    private func relativePath(_ url: URL, from base: URL) -> String {
        let path = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path + "/"
        return path.hasPrefix(basePath) ? String(path.dropFirst(basePath.count)) : path
    }
}
