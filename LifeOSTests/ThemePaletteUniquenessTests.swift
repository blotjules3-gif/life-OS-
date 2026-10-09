import XCTest
import SwiftUI
import UIKit
@testable import LifeOS

/// Garde-fou des couleurs de domaine (lot 8).
///
/// Lit les VRAIES couleurs de l'app : `AppCategory.tint` (via `tintUIColor`, la couleur
/// dynamique que `tint` affiche) et les tokens de statut de `Theme`, resolues dans un
/// `UITraitCollection` clair puis sombre. Plus de liste de hex recopiee a la main :
/// l'ancienne version comparait des valeurs perimees depuis des mois.
///
/// Distances en CIEDE2000 (ecart percu ; ~2 = a peine visible, ~10 = clairement
/// different) :
/// - deux catégories : au moins 7,5 ;
/// - une catégorie et un statut (succes, avertissement, erreur) : au moins 10, pour
///   qu'un domaine ne se lise jamais comme une alerte.
final class ThemePaletteUniquenessTests: XCTestCase {

    private let minCategoryGap = 7.5
    private let minStatusGap = 10.0

    private var categories: [(name: String, color: UIColor)] {
        AppCategory.allCases.map { ($0.rawValue, $0.tintUIColor) }
    }

    private var statuses: [(name: String, color: UIColor)] {
        [("success", UIColor(Theme.success)), ("warning", UIColor(Theme.warning)), ("danger", UIColor(Theme.danger))]
    }

    func test_categories_noTwoShareATone_inLightAndDark() {
        var errors: [String] = []
        for dark in [false, true] {
            let cats = categories
            for i in cats.indices {
                for j in cats.indices where j > i {
                    let d = ColorMath.deltaE2000(ColorMath.resolved(cats[i].color, dark: dark),
                                                 ColorMath.resolved(cats[j].color, dark: dark))
                    if d < minCategoryGap {
                        errors.append("\(dark ? "sombre" : "clair") \(cats[i].name)/\(cats[j].name) = \(String(format: "%.1f", d))")
                    }
                }
            }
        }
        XCTAssertTrue(errors.isEmpty, "Catégories trop proches (CIEDE2000 < \(minCategoryGap)) :\n  - " + errors.joined(separator: "\n  - "))
    }

    func test_categories_neverLookLikeAStatus() {
        var errors: [String] = []
        for dark in [false, true] {
            for cat in categories {
                for status in statuses {
                    let d = ColorMath.deltaE2000(ColorMath.resolved(cat.color, dark: dark),
                                                 ColorMath.resolved(status.color, dark: dark))
                    if d < minStatusGap {
                        errors.append("\(dark ? "sombre" : "clair") \(cat.name)/\(status.name) = \(String(format: "%.1f", d))")
                    }
                }
            }
        }
        XCTAssertTrue(errors.isEmpty, "Catégorie confondue avec un statut :\n  - " + errors.joined(separator: "\n  - "))
    }

    /// Avertissement et erreur ont deux roles : ambre et rouge, bien separes ; et la
    /// sante medicale n'est plus le rouge d'erreur.
    func test_statuses_haveDistinctRoles() {
        for dark in [false, true] {
            let s = statuses.map { ColorMath.resolved($0.color, dark: dark) }
            XCTAssertGreaterThanOrEqual(ColorMath.deltaE2000(s[1], s[2]), 20, "avertissement / erreur")
            XCTAssertGreaterThanOrEqual(ColorMath.deltaE2000(s[0], s[1]), 20, "succès / avertissement")
            XCTAssertGreaterThanOrEqual(ColorMath.deltaE2000(s[0], s[2]), 20, "succès / erreur")
            let warningHue = ColorMath.hue(s[1]), dangerHue = ColorMath.hue(s[2])
            XCTAssertTrue((30...50).contains(warningHue), "avertissement ambre, teinte \(warningHue)")
            XCTAssertTrue(dangerHue < 12 || dangerHue > 350, "erreur rouge, teinte \(dangerHue)")
            let medical = ColorMath.resolved(AppCategory.medical.tintUIColor, dark: dark)
            XCTAssertNotEqual(ColorMath.hue(medical), dangerHue, accuracy: 3, "santé médicale ≠ erreur")
        }
    }

    /// Teintes imposees par le cahier des charges : travail bleu, nutrition vert,
    /// sport orange, sommeil violet, finances turquoise, apprentissage indigo.
    func test_briefDomainHues() {
        let expected: [(AppCategory, ClosedRange<Double>, String)] = [
            (.career, 200...235, "bleu"), (.nutrition, 85...150, "vert"), (.fitness, 15...40, "orange"),
            (.sleep, 260...295, "violet"), (.finance, 170...195, "turquoise"), (.learning, 236...258, "indigo")
        ]
        for dark in [false, true] {
            for (cat, range, word) in expected {
                let h = ColorMath.hue(ColorMath.resolved(cat.tintUIColor, dark: dark))
                XCTAssertTrue(range.contains(h), "\(cat.rawValue) doit être \(word) (\(dark ? "sombre" : "clair")), teinte \(Int(h))")
            }
        }
    }

    /// `Theme.<domaine>` et `AppCategory.tint` sont la meme couleur (une seule table).
    func test_themeTokensAndCategoryTintsAreTheSameSource() {
        let pairs: [(Color, AppCategory)] = [
            (Theme.career, .career), (Theme.nutrition, .nutrition), (Theme.fitness, .fitness),
            (Theme.sleep, .sleep), (Theme.finance, .finance), (Theme.learning, .learning),
            (Theme.medical, .medical), (Theme.mind, .mind), (Theme.productivity, .productivity)
        ]
        for dark in [false, true] {
            for (token, cat) in pairs {
                let a = ColorMath.resolved(UIColor(token), dark: dark), b = ColorMath.resolved(cat.tintUIColor, dark: dark)
                XCTAssertEqual(a.r, b.r, accuracy: 0.002, cat.rawValue)
                XCTAssertEqual(a.g, b.g, accuracy: 0.002, cat.rawValue)
                XCTAssertEqual(a.b, b.b, accuracy: 0.002, cat.rawValue)
            }
        }
        // L'energie appartient au sport (elle etait ambre = avertissement).
        let energy = ColorMath.resolved(UIColor(Theme.energy), dark: false)
        let fitness = ColorMath.resolved(UIColor(Theme.fitness), dark: false)
        XCTAssertEqual(energy.r, fitness.r, accuracy: 0.002)
    }

    /// Les tokens secondaires (eau, coach) ne se lisent pas non plus comme un statut.
    func test_secondaryTokensStayAwayFromStatuses() {
        for dark in [false, true] {
            for token in [UIColor(Theme.hydration), UIColor(Theme.coach)] {
                for status in statuses {
                    XCTAssertGreaterThanOrEqual(
                        ColorMath.deltaE2000(ColorMath.resolved(token, dark: dark), ColorMath.resolved(status.color, dark: dark)),
                        minStatusGap, status.name)
                }
            }
        }
    }

    /// Palette neutre : chaque teinte devient un gris de meme luminance, en clair et en
    /// sombre. Le sens reste porte par l'icone et le titre.
    func test_neutralPaletteTurnsEveryTintGrey() {
        for dark in [false, true] {
            for cat in categories {
                let col = ColorMath.resolved(cat.color, dark: dark)
                let grey = ColorMath.resolved(cat.color, dark: dark, neutral: true)
                XCTAssertLessThan(ColorMath.chroma(grey), 0.01, cat.name)
                XCTAssertEqual(ColorMath.luminance(grey), ColorMath.luminance(col), accuracy: 0.004, cat.name)
            }
        }
    }

    func test_lightAndDarkVariantsDiffer() {
        for cat in categories {
            let l = ColorMath.resolved(cat.color, dark: false), d = ColorMath.resolved(cat.color, dark: true)
            XCTAssertGreaterThan(ColorMath.luminance(d), ColorMath.luminance(l), "\(cat.name) : plus vive en sombre")
        }
    }
}
