import XCTest
@testable import LifeOS

/// Garde-fou : les tokens sémantiques de couleur module ne doivent PAS
/// partager la même valeur hex. Deux modules distincts avec la même couleur
/// = confusion visible (ex. l'ancien bug Finance ≡ Nutrition = vert identique).
///
/// Ajouter un token dans Theme.swift → l'ajouter aussi ici. Si deux valeurs
/// hex sont vraiment identiques par design (ex. success ≡ nutrition = vert
/// atteint), on peut les whitelister — mais toute nouvelle collision fait
/// échouer ce test.
final class ThemePaletteUniquenessTests: XCTestCase {

    /// Tokens à comparer 2 à 2. On extrait le hex via description Color (fragile
    /// sur les vrais UIColor natifs, mais fiable sur Color(hex:) qui construit
    /// depuis un litéral).
    private struct TokenHex {
        let name: String
        let hex: UInt32
    }

    /// Palette semantic à surveiller. Miroir de Theme.swift.
    /// Ne pas y mettre `success/warning/danger` qui sont volontairement
    /// équivalents à nutrition/energy/fitness.
    private let moduleTokens: [TokenHex] = [
        .init(name: "fitness",      hex: 0xF1746C),
        .init(name: "nutrition",    hex: 0x4CC38A),
        .init(name: "hydration",    hex: 0x3CB2E0),
        .init(name: "sleep",        hex: 0x6C7BF1),
        .init(name: "mind",         hex: 0x9B6CF1),
        .init(name: "energy",       hex: 0xE0A23C),
        .init(name: "finance",      hex: 0x46C9A8), // ex-0x4CC38A (collision nutrition)
        .init(name: "invest",       hex: 0x2FB89A),
        .init(name: "career",       hex: 0xE07B3C),
        .init(name: "looks",        hex: 0xE0A23C),
        .init(name: "productivity", hex: 0x3CB2E0),
        .init(name: "learning",     hex: 0xF97316),
        .init(name: "home",         hex: 0x6CA0F1),
        .init(name: "social",       hex: 0xF16CB0),
        .init(name: "admin",        hex: 0x8A93A8),
        .init(name: "mobility",     hex: 0x3CD0C8),
        .init(name: "travel",       hex: 0x6C9BF1),
        .init(name: "cycle",        hex: 0xE85D9A),
        .init(name: "medical",      hex: 0xE84C4C),
    ]

    /// Collisions volontaires — modules qui partagent la même teinte par choix
    /// design. Ces collisions n'échouent pas le test.
    private let allowedCollisions: Set<Set<String>> = [
        ["energy", "looks"],                 // ambre commun (chaleur / soin)
        ["hydration", "productivity"],       // bleu commun (frais / clarté)
    ]

    func test_moduleTokens_noAccidentalCollision() {
        var byHex: [UInt32: [String]] = [:]
        for t in moduleTokens {
            byHex[t.hex, default: []].append(t.name)
        }
        var errors: [String] = []
        for (hex, names) in byHex where names.count > 1 {
            let set = Set(names)
            guard !allowedCollisions.contains(set) else { continue }
            let hexStr = String(format: "0x%06X", hex)
            errors.append("\(hexStr) partagé par : \(names.sorted().joined(separator: ", "))")
        }
        XCTAssertTrue(
            errors.isEmpty,
            "Collision(s) de tokens couleur non whitelistée(s) :\n  - \(errors.joined(separator: "\n  - "))\n\nSoit changer la valeur hex d'un des tokens, soit ajouter la paire dans allowedCollisions avec une justification design."
        )
    }
}
