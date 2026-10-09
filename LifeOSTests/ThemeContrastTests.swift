import XCTest
import SwiftUI
import UIKit
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
        // Doit refleter EXACTEMENT `AppTheme.selectable`. Volt et Pinky ont ete
        // ARCHIVES (ils ne sont plus proposables), donc ils sortent d'ici : le test
        // `test_selectableThemes_matchesFixtures` compare les deux ensembles et
        // echouait depuis cet archivage.
        // `.system` suit le reglage de l'appareil ; en clair il resout sur
        // `accentHex` 0x000000 avec `onAccent` = systemBackground, donc blanc.
        (.system,  0x000000, 0xFFFFFF, "Systeme (suit l'appareil, clair)"),
        (.classic, 0x000000, 0xFFFFFF, "Clair (noir / blanc)"),
        (.dark,    0xFFFFFF, 0x000000, "Sombre (blanc / noir)"),
    ]

    // MARK: - Tests

    /// Seuil WCAG AA pour du texte large (≥ 18pt regular ou ≥ 14pt bold) ou pour
    /// des composants UI non-textuels. C'est le seuil minimum acceptable pour tous
    /// nos boutons pleins, badges et bulles de chat (police 15pt semi-bold).
    private let wcagAALargeText: Double = 3.0

    /// Seuil WCAG AA pour du texte normal. Idéal mais pas atteint par tous les thèmes.
    private let wcagAANormalText: Double = 4.5

    func test_onAccent_meets_WCAG_AA_largeText_forEveryTheme() {
        for c in cases {
            let ratio = Self.contrastRatio(hexA: c.accentHex, hexB: c.onAccentHex)
            XCTAssertGreaterThanOrEqual(
                ratio, wcagAALargeText,
                "Le thème \(c.label) a un contraste onAccent/accent < \(wcagAALargeText):1 (mesuré \(String(format: "%.2f", ratio)):1) — WCAG AA large text échoue. C'est le seuil MINIMUM pour boutons + badges."
            )
        }
    }

    /// Documente comme WARNING les thèmes qui ne passent PAS le seuil texte normal (4.5:1).
    /// Ne fait pas échouer la CI — mais loggue clairement en attendant un fix design.
    func test_document_themes_below_normalText_threshold() {
        var belowNormal: [String] = []
        for c in cases {
            let ratio = Self.contrastRatio(hexA: c.accentHex, hexB: c.onAccentHex)
            if ratio < wcagAANormalText {
                belowNormal.append("\(c.label) → \(String(format: "%.2f", ratio)):1")
            }
        }
        if !belowNormal.isEmpty {
            print("[ThemeContrast] Ces thèmes NE passent PAS WCAG AA texte normal (4.5:1) — à réserver aux textes bold/large :\n  - \(belowNormal.joined(separator: "\n  - "))")
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

    // MARK: - Teintes de domaine sur le verre (lot 8)

    /// Les teintes de domaine et de statut servent aux ICONES, pastilles et petits
    /// accents graphiques (et a quelques libelles courts en gras), jamais au texte
    /// courant. Seuil retenu : 3:1, celui de WCAG 1.4.11 (elements graphiques) et du
    /// texte large. Mesure sur les fonds reels du verre : blanc et #F2F2F7 en clair,
    /// noir et #2C2C2E en sombre (le verre sombre le plus clair qu'on rende).
    func test_domainTints_reachIconContrast_onGlassBackgrounds() {
        let iconLevel = 3.0
        var colors: [(String, UIColor)] = AppCategory.allCases.map { ($0.rawValue, $0.tintUIColor) }
        colors += [("success", UIColor(Theme.success)), ("warning", UIColor(Theme.warning)),
                   ("danger", UIColor(Theme.danger)), ("hydration", UIColor(Theme.hydration)),
                   ("coach", UIColor(Theme.coach))]
        let lightBackgrounds: [ColorMath.RGB] = [(1, 1, 1), ColorMath.rgb(0xF2F2F7)]
        let darkBackgrounds: [ColorMath.RGB] = [(0, 0, 0), ColorMath.rgb(0x2C2C2E)]
        var failures: [String] = []
        for (name, color) in colors {
            for neutral in [false, true] {
                let light = ColorMath.resolved(color, dark: false, neutral: neutral)
                let dark = ColorMath.resolved(color, dark: true, neutral: neutral)
                for bg in lightBackgrounds where ColorMath.contrast(light, bg) < iconLevel {
                    failures.append("\(name) clair\(neutral ? " neutre" : "") \(String(format: "%.2f", ColorMath.contrast(light, bg))):1")
                }
                for bg in darkBackgrounds where ColorMath.contrast(dark, bg) < iconLevel {
                    failures.append("\(name) sombre\(neutral ? " neutre" : "") \(String(format: "%.2f", ColorMath.contrast(dark, bg))):1")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "Teintes sous \(iconLevel):1 sur le verre :\n  - " + failures.joined(separator: "\n  - "))
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
