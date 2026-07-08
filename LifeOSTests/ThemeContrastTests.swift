import XCTest
import SwiftUI
@testable import LifeOS

/// Vérifie que pour CHAQUE thème sélectionnable, la couleur `onAccent`
/// posée sur l'accent atteint un contraste minimum lisible (WCAG AA ≥ 4.5:1
/// pour du texte normal, 3:1 pour du texte large).
///
/// Ces tests protègent contre la régression du bug identifié en juillet 2026 :
/// texte utilisateur du chat en `.white` sur fond `accent` → invisible en thème
/// Sombre (blanc sur blanc) et illisible en thème Vert (blanc sur vert clair).
///
/// Formules : luminance relative WCAG (Rec. 709) + ratio (L1 + 0.05) / (L2 + 0.05).
final class ThemeContrastTests: XCTestCase {

    // MARK: - Fixtures — chaque thème sélectionnable + son couple accent/onAccent en RGB

    /// (thème, hex accent, hex onAccent, description). Reflète la matrice AppTheme.accent + onAccent.
    private let cases: [(theme: AppTheme, accentHex: UInt32, onAccentHex: UInt32, label: String)] = [
        (.classic, 0x000000, 0xFFFFFF, "Clair (noir / blanc)"),
        (.dark,    0xFFFFFF, 0x000000, "Sombre (blanc / noir)"),
        (.volt,    0x4CF810, 0x000000, "Vert (volt / noir)"),
        (.pinky,   0xE85D9A, 0xFFFFFF, "Rose (rose / blanc)"),
    ]

    // MARK: - Tests

    func test_onAccent_meets_WCAG_AA_normalText_forEveryTheme() {
        for c in cases {
            let ratio = Self.contrastRatio(hexA: c.accentHex, hexB: c.onAccentHex)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "Le thème \(c.label) a un contraste texte user < 4.5:1 (mesuré \(String(format: "%.2f", ratio)):1) — WCAG AA échoue"
            )
        }
    }

    func test_selectableThemes_matchesFixtures() {
        // Alerte si un nouveau thème est ajouté à `selectable` sans que le test soit mis à jour.
        let selectableRaws = Set(AppTheme.selectable.map { $0.rawValue })
        let fixtureRaws = Set(cases.map { $0.theme.rawValue })
        XCTAssertEqual(
            selectableRaws, fixtureRaws,
            "Un thème sélectionnable n'a pas de fixture de contraste. Ajoute-le dans ThemeContrastTests.cases."
        )
    }

    // MARK: - WCAG helpers

    /// Luminance relative WCAG (Rec. 709).
    private static func relativeLuminance(hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex        & 0xFF) / 255.0
        func lin(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Ratio de contraste WCAG entre 2 couleurs (hex RGB 24 bits).
    private static func contrastRatio(hexA: UInt32, hexB: UInt32) -> Double {
        let la = relativeLuminance(hex: hexA)
        let lb = relativeLuminance(hex: hexB)
        let (l1, l2) = la >= lb ? (la, lb) : (lb, la)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}
