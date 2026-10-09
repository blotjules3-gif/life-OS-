import XCTest
import SwiftUI
import UIKit
@testable import LifeOS

// MARK: - Outils de mesure partages (ThemePaletteUniquenessTests, ThemeContrastTests)

/// Mesures de couleur en sRGB : luminance et contraste WCAG, Lab D65, ecart CIEDE2000,
/// teinte HSV. Fonctions pures, testees ici contre une valeur de reference publiee.
enum ColorMath {
    typealias RGB = (r: Double, g: Double, b: Double)

    static func rgb(_ hex: UInt32) -> RGB {
        let c = DomainPalette.components(hex); return (c.0, c.1, c.2)
    }

    static func rgb(_ color: UIColor) -> RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) { return (Double(r), Double(g), Double(b)) }
        var w: CGFloat = 0
        color.getWhite(&w, alpha: &a)
        return (Double(w), Double(w), Double(w))
    }

    static func resolved(_ color: UIColor, dark: Bool, neutral: Bool = false) -> RGB {
        let traits = UITraitCollection { $0.userInterfaceStyle = dark ? .dark : .light; $0.lifeOSNeutralPalette = neutral }
        return rgb(color.resolvedColor(with: traits))
    }

    private static func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

    static func luminance(_ c: RGB) -> Double { 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Couleur `fg` posee avec une opacite sur `bg` (melange en sRGB, comme le rendu).
    static func composite(_ fg: RGB, alpha: Double, over bg: RGB) -> RGB {
        (fg.r * alpha + bg.r * (1 - alpha), fg.g * alpha + bg.g * (1 - alpha), fg.b * alpha + bg.b * (1 - alpha))
    }

    static func lab(_ c: RGB) -> (L: Double, a: Double, b: Double) {
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3) : 7.787 * t + 16.0 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    static func deltaE2000(_ c1: RGB, _ c2: RGB) -> Double {
        deltaE2000(lab: lab(c1), lab(c2))
    }

    /// CIEDE2000 (Sharma, Wu, Dalal 2005).
    static func deltaE2000(lab l1: (L: Double, a: Double, b: Double), _ l2: (L: Double, a: Double, b: Double)) -> Double {
        let rad = Double.pi / 180, deg = 180 / Double.pi
        let c1 = hypot(l1.a, l1.b), c2 = hypot(l2.a, l2.b), cb = (c1 + c2) / 2
        let g = 0.5 * (1 - sqrt(pow(cb, 7) / (pow(cb, 7) + pow(25, 7))))
        let a1p = (1 + g) * l1.a, a2p = (1 + g) * l2.a
        let c1p = hypot(a1p, l1.b), c2p = hypot(a2p, l2.b)
        func hue(_ b: Double, _ ap: Double) -> Double {
            if b == 0 && ap == 0 { return 0 }
            let h = atan2(b, ap) * deg; return h >= 0 ? h : h + 360
        }
        let h1p = hue(l1.b, a1p), h2p = hue(l2.b, a2p)
        let dLp = l2.L - l1.L, dCp = c2p - c1p
        var dhp: Double = 0
        if c1p * c2p != 0 {
            let dh = h2p - h1p
            dhp = abs(dh) <= 180 ? dh : (dh > 180 ? dh - 360 : dh + 360)
        }
        let dHp = 2 * sqrt(c1p * c2p) * sin(dhp / 2 * rad)
        let lbp = (l1.L + l2.L) / 2, cbp = (c1p + c2p) / 2
        var hbp = h1p + h2p
        if c1p * c2p != 0 {
            if abs(h1p - h2p) <= 180 { hbp = (h1p + h2p) / 2 }
            else if h1p + h2p < 360 { hbp = (h1p + h2p + 360) / 2 }
            else { hbp = (h1p + h2p - 360) / 2 }
        }
        let t = 1 - 0.17 * cos((hbp - 30) * rad) + 0.24 * cos(2 * hbp * rad)
            + 0.32 * cos((3 * hbp + 6) * rad) - 0.20 * cos((4 * hbp - 63) * rad)
        let dTheta = 30 * exp(-pow((hbp - 275) / 25, 2))
        let rc = 2 * sqrt(pow(cbp, 7) / (pow(cbp, 7) + pow(25, 7)))
        let sl = 1 + 0.015 * pow(lbp - 50, 2) / sqrt(20 + pow(lbp - 50, 2))
        let sc = 1 + 0.045 * cbp, sh = 1 + 0.015 * cbp * t
        let rt = -sin(2 * dTheta * rad) * rc
        return sqrt(pow(dLp / sl, 2) + pow(dCp / sc, 2) + pow(dHp / sh, 2) + rt * (dCp / sc) * (dHp / sh))
    }

    /// Teinte HSV en degres (0...360).
    static func hue(_ c: RGB) -> Double {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        guard d > 0 else { return 0 }
        var h: Double
        if mx == c.r { h = (c.g - c.b) / d } else if mx == c.g { h = (c.b - c.r) / d + 2 } else { h = (c.r - c.g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    static func chroma(_ c: RGB) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
}

// MARK: - Lot 8 : apparence

final class Lot8AppearanceTests: XCTestCase {
    private var savedTheme: Any?
    private var savedPalette: Any?

    override func setUp() {
        super.setUp()
        savedTheme = UserDefaults.standard.object(forKey: AppStorageKeys.appTheme)
        savedPalette = UserDefaults.standard.object(forKey: AppStorageKeys.appPalette)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedTheme, forKey: AppStorageKeys.appTheme)
        UserDefaults.standard.set(savedPalette, forKey: AppStorageKeys.appPalette)
        super.tearDown()
    }

    private static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    private func allAppSources() throws -> [(String, String)] {
        let base = Self.root.appendingPathComponent("LifeOS")
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in e where url.pathExtension == "swift" {
            out.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return out
    }

    // MARK: Defauts

    func testDefaultsAreFollowDeviceAndColour() {
        XCTAssertEqual(AppTheme.defaultTheme, .system)
        XCTAssertEqual(AppTheme.defaultRaw, "system")
        XCTAssertEqual(AppPalette.defaultPalette, .color)
        XCTAssertEqual(AppPalette.defaultRaw, "color")
    }

    func testMissingUnknownAndArchivedThemesResolveToFollowDevice() {
        XCTAssertEqual(AppTheme.resolved(nil), .system)
        XCTAssertEqual(AppTheme.resolved(""), .system)
        XCTAssertEqual(AppTheme.resolved("n'importe quoi"), .system)
        for archived in AppTheme.allCases where !archived.isSelectable {
            XCTAssertEqual(AppTheme.resolved(archived.rawValue), .system, "\(archived) est archivé")
        }
        XCTAssertEqual(AppTheme.resolved("classic"), .classic)
        XCTAssertEqual(AppTheme.resolved("dark"), .dark)
        XCTAssertEqual(AppPalette.resolved(nil), .color)
        XCTAssertEqual(AppPalette.resolved("bizarre"), .color)
        XCTAssertEqual(AppPalette.resolved("neutral"), .neutral)
    }

    /// Le bug d'installation neuve : `Theme.currentTheme` lisait "classic" par defaut.
    func testThemeReadersAgreeOnAFreshInstall() {
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.appTheme)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.appPalette)
        XCTAssertEqual(Theme.currentTheme, .system)
        XCTAssertFalse(Theme.neutralPalette)
        XCTAssertFalse(Theme.isGlassActive)
        UserDefaults.standard.set("glass", forKey: AppStorageKeys.appTheme)
        XCTAssertEqual(Theme.currentTheme, .system, "Verre archivé : suit l'appareil")
        XCTAssertFalse(Theme.isGlassActive)
        UserDefaults.standard.set("dark", forKey: AppStorageKeys.appTheme)
        XCTAssertEqual(Theme.currentTheme, .dark)
        UserDefaults.standard.set("neutral", forKey: AppStorageKeys.appPalette)
        XCTAssertTrue(Theme.neutralPalette)
    }

    /// Theme "Suivre l'appareil" : accent = encre du systeme, contenu pose dessus = fond
    /// du systeme. Les deux suivent l'appareil, donc jamais blanc sur blanc.
    func testFollowDeviceOnAccentIsReadableInBothSchemes() {
        for dark in [false, true] {
            let ink = ColorMath.resolved(.label, dark: dark)
            let bg = ColorMath.resolved(.systemBackground, dark: dark)
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(ink, bg), 4.5, dark ? "sombre" : "clair")
        }
    }

    // MARK: Quatre apparences, deux axes independants

    func testFourLooksAreTheFullGridOfTwoIndependentAxes() {
        let looks = AppearanceLook.allCases
        XCTAssertEqual(looks.count, 4)
        XCTAssertEqual(Set(looks).count, 4)
        XCTAssertEqual(Set(looks.map(\.scheme)).count, 2)
        XCTAssertEqual(Set(looks.map(\.palette)), Set(AppPalette.allCases))
        for look in looks {
            XCTAssertTrue(look.theme.isSelectable)
            XCTAssertEqual(look.theme.scheme, look.scheme)
        }
    }

    func testCurrentLookFollowsDeviceOnlyWhenAsked() {
        XCTAssertEqual(AppearanceLook.current(themeRaw: nil, paletteRaw: nil, deviceScheme: .dark),
                       AppearanceLook(scheme: .dark, palette: .color))
        XCTAssertEqual(AppearanceLook.current(themeRaw: "volt", paletteRaw: "neutral", deviceScheme: .light),
                       AppearanceLook(scheme: .light, palette: .neutral))
        XCTAssertEqual(AppearanceLook.current(themeRaw: "classic", paletteRaw: "color", deviceScheme: .dark),
                       AppearanceLook(scheme: .light, palette: .color), "Clair fixé : l'appareil ne compte plus")
        XCTAssertEqual(AppearanceLook.current(themeRaw: "dark", paletteRaw: "neutral", deviceScheme: .light),
                       AppearanceLook(scheme: .dark, palette: .neutral))
        XCTAssertEqual(AppTheme.system.brightnessLabel, "Suivre l'appareil")
    }

    // MARK: Garde-fous sur le code

    /// Une seule source pour les defauts : plus aucun `@AppStorage(…appTheme…) = "…"`
    /// ecrit a la main, ni de repli `?? .classic`. (MainTabView.swift est corrige par
    /// le crochet du lot 8 : ce test le surveille aussi.)
    func testNoHandWrittenAppearanceDefaults() throws {
        var offenders: [String] = []
        for (name, text) in try allAppSources() {
            for line in text.components(separatedBy: .newlines) {
                let l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("///") || l.hasPrefix("//") { continue }
                if (l.contains("AppStorageKeys.appTheme)") || l.contains("AppStorageKeys.appPalette)")),
                   l.range(of: #"=\s*""#, options: .regularExpression) != nil {
                    offenders.append("\(name): \(l)")
                }
                if l.contains("AppTheme(rawValue:") && l.contains("?? .classic") {
                    offenders.append("\(name): \(l)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Défauts d'apparence écrits à la main :\n" + offenders.joined(separator: "\n"))
    }

    /// Changer d'apparence ne doit reconstruire aucune vue (navigation, formulaires,
    /// seances gardes) : aucun `.id(...)` ne depend du theme, de la palette ou du schema.
    func testNoViewIdentityDependsOnAppearance() throws {
        let pattern = #"\.id\([^)]*(appTheme|appPalette|themeRaw|paletteRaw|colorScheme|neutralPalette|currentTheme)"#
        var offenders: [String] = []
        for (name, text) in try allAppSources() where text.range(of: pattern, options: .regularExpression) != nil {
            offenders.append(name)
        }
        XCTAssertTrue(offenders.isEmpty, "Vue reconstruite au changement d'apparence : \(offenders)")
    }

    /// Avant iOS 26, les surfaces restent translucides ; l'opaque est reserve a
    /// "Reduire la transparence".
    func testGlassFallbackIsTranslucentAndOpaqueOnlyForReduceTransparency() throws {
        let theme = try source("LifeOS/Core/Theme.swift")
        let start = try XCTUnwrap(theme.range(of: "private var fallbackFill: AnyShapeStyle {"))
        let end = try XCTUnwrap(theme.range(of: "private var shadowOpacity", range: start.upperBound..<theme.endIndex))
        let body = String(theme[start.upperBound..<end.lowerBound])
        XCTAssertTrue(body.contains(".regularMaterial"))
        XCTAssertTrue(body.contains(".thinMaterial"))
        let afterRT = try XCTUnwrap(body.range(of: "if reduceTransparency {"))
        let rtEnd = try XCTUnwrap(body.range(of: "\n        }\n", range: afterRT.upperBound..<body.endIndex))
        let outsideRT = String(body[rtEnd.upperBound...])
        XCTAssertFalse(outsideRT.contains("Color.white)"), "pas de blanc opaque hors Réduire la transparence")
    }

    func testMotionRespectsReduceMotion() throws {
        let theme = try source("LifeOS/Core/Theme.swift")
        let aura = try XCTUnwrap(theme.range(of: "struct AmbientAuraBackdrop"))
        let auraEnd = try XCTUnwrap(theme.range(of: "// MARK: - Système Liquid Glass", range: aura.upperBound..<theme.endIndex))
        let auraBody = String(theme[aura.lowerBound..<auraEnd.lowerBound])
        XCTAssertTrue(auraBody.contains("accessibilityReduceMotion"))
        XCTAssertTrue(auraBody.contains("guard !reduceMotion"))
        XCTAssertTrue(theme.contains("modifier(ScrollFadeModifier())"))
    }

    /// Un controle desactive (opacite partagee) garde un texte lisible.
    func testDisabledControlKeepsReadableText() {
        let a = GlassControl.disabledOpacity
        let onLight = ColorMath.composite((0, 0, 0), alpha: a, over: (1, 1, 1))
        XCTAssertGreaterThanOrEqual(ColorMath.contrast(onLight, (1, 1, 1)), 4.5)
        let darkGlass = ColorMath.rgb(0x1C1C1E)
        let onDark = ColorMath.composite((1, 1, 1), alpha: a, over: darkGlass)
        XCTAssertGreaterThanOrEqual(ColorMath.contrast(onDark, darkGlass), 4.5)
    }

    // MARK: Bureau

    func testDesktopUsesSharedBackgroundAndReadableColumns() throws {
        let desk = try source("LifeOS/Core/MacDesktopMainView.swift")
        XCTAssertFalse(desk.contains("Theme.bg"), "plus de panneau opaque sur le bureau")
        XCTAssertTrue(desk.contains("Theme.screenBG"))
        XCTAssertGreaterThanOrEqual(desk.components(separatedBy: ".readableWidth()").count - 1, 5,
                                    "habitudes, réveil, coach, catégories, profil")
        XCTAssertFalse(desk.contains("0x9B6CF1"), "bouton du coach : token Theme.coach")
        XCTAssertLessThanOrEqual(ReadableWidth.phoneModuleMaxWidth, 800)
        XCTAssertGreaterThanOrEqual(ReadableWidth.phoneModuleMaxWidth, 600)
    }

    func testCIEDE2000MatchesPublishedReference() {
        // Sharma et al., paire 1 : 2,0425
        let d = ColorMath.deltaE2000(lab: (50, 2.6772, -79.7751), (50, 0, -82.7485))
        XCTAssertEqual(d, 2.0425, accuracy: 0.0005)
        // paire 7 : 2,3669
        XCTAssertEqual(ColorMath.deltaE2000(lab: (50, 0, 0), (50, -1, 2)), 2.3669, accuracy: 0.0005)
    }
}
