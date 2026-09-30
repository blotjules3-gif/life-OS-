import SwiftUI
import CoreText
import UIKit

// MARK: - Système Typographique Chifbay : Satoshi (Titres & Gras) + Inter (Corps & Textes)

enum AppFont {
    /// Enregistrement automatique des polices Satoshi et Inter au chargement
    private static let _registerFontsOnce: Void = {
        let fontFiles = [
            "Satoshi-Black",
            "Satoshi-Bold",
            "Satoshi-Medium",
            "Satoshi-Regular",
            "Satoshi-Italic",
            "Satoshi-BoldItalic",
            "Inter-Regular",
            "Inter-Medium",
            "Inter-SemiBold",
            "Inter-Bold"
        ]
        let extensions = ["otf", "ttf"]
        for base in fontFiles {
            for ext in extensions {
                if let url = Bundle.main.url(forResource: base, withExtension: ext) {
                    var error: Unmanaged<CFError>?
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                }
            }
        }
        if let resURL = Bundle.main.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(at: resURL, includingPropertiesForKeys: nil) {
            for url in items where (url.pathExtension == "otf" || url.pathExtension == "ttf") {
                if url.lastPathComponent.contains("Satoshi") || url.lastPathComponent.contains("Inter") {
                    var error: Unmanaged<CFError>?
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                }
            }
        }
    }()

    /// Police 1 : Satoshi pour tous les grands titres, boutons majeurs & navigation (comme Chifbay)
    static func heading(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        _ = _registerFontsOnce
        let fontName: String
        switch weight {
        case .black, .heavy:
            fontName = "Satoshi-Black"
        case .bold, .semibold:
            fontName = "Satoshi-Bold"
        case .medium:
            fontName = "Satoshi-Medium"
        default:
            fontName = "Satoshi-Bold"
        }

        if UIFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        }
        return Font.system(size: size, weight: weight == .regular ? .bold : weight)
    }

    /// Police 2 : Inter pour tout le corps de texte, descriptions, labels & sous-titres (comme Chifbay)
    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        _ = _registerFontsOnce
        let fontName: String
        switch weight {
        case .black, .heavy, .bold:
            fontName = "Inter-Bold"
        case .semibold:
            fontName = "Inter-SemiBold"
        case .medium:
            fontName = "Inter-Medium"
        default:
            fontName = "Inter-Regular"
        }

        if UIFont(name: fontName, size: size) != nil {
            return Font.custom(fontName, size: size)
        }
        return Font.system(size: size, weight: weight)
    }

    /// Sélection intelligente : Satoshi pour les grands formats et poids gras, Inter pour le corps
    static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if weight == .black || weight == .heavy || (weight == .bold && size >= 16) || size >= 20 {
            return heading(size: size, weight: weight)
        } else {
            return body(size: size, weight: weight)
        }
    }

    /// Monospace (SF Mono) réservé aux chronos, timers et données techniques strictes
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    func fontHeading(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        self.font(AppFont.heading(size: size, weight: weight))
    }

    func fontBody(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(AppFont.body(size: size, weight: weight))
    }

    func fontSans(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(AppFont.sans(size: size, weight: weight))
    }

    func fontMono(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(AppFont.mono(size: size, weight: weight))
    }

    /// Tag / Badge technique en Inter majuscule avec léger espacement
    func fontMonoTag(_ size: CGFloat = 11, weight: Font.Weight = .semibold) -> some View {
        self.font(AppFont.body(size: size, weight: weight)).textCase(.uppercase).kerning(0.8)
    }

    /// Stat / Chiffre clé
    func fontMonoStat(_ size: CGFloat = 16, weight: Font.Weight = .bold) -> some View {
        self.font(AppFont.sans(size: size, weight: weight))
    }
}

/// Design system de LifeOS — aligné sur le système de design Chifbay :
/// Titres audacieux en Satoshi (Bold / Black) et typographie de lecture fluide en Inter.
enum Theme {
    // Surfaces adaptatives OLED Black & Apple Preview Liquid Glass :
    // En dark mode : Noir Pur (#000000) et verre cristallin translucide avec arête de glace spéculaire
    // En light mode : Blanc Pur (#FFFFFF fond, #F5F5F7 cartes, #E8E8ED boutons intérieurs, #D4D4D5 ombre 1px)
    static let bg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.black : UIColor.white // #FFFFFF
    })
    static let bg2 = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.08) : UIColor(red: 0.910, green: 0.910, blue: 0.929, alpha: 1.0) // #E8E8ED
    })
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.05) : UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1.0) // #F5F5F7
    })
    static let stroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.20) : UIColor(white: 0.0, alpha: 0.06)
    })
    static let textPrimary = Color.primary
    // UIColor.secondaryLabel meets ≥3:1 on system backgrounds in both light and dark
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary  = Color(uiColor: .tertiaryLabel)
    static let accent = Color.accentColor

    static let padWide: CGFloat = 28   // onboarding / large content areas

    // MARK: - Typographie Chifbay (Satoshi Titres + Inter Corps)
    static let fontDisplay   = AppFont.heading(size: 40, weight: .black)  // Satoshi Black
    static let fontHero      = AppFont.heading(size: 32, weight: .black)  // Satoshi Black
    static let fontTitle     = AppFont.heading(size: 26, weight: .bold)   // Satoshi Bold
    static let fontTitle2    = AppFont.heading(size: 20, weight: .bold)   // Satoshi Bold
    static let fontTitle3    = AppFont.heading(size: 17, weight: .bold)   // Satoshi Bold
    static let fontHeadline  = AppFont.heading(size: 15, weight: .bold)   // Satoshi Bold

    // Corps de texte, sous-titres et métadonnées en Inter
    static let fontBody      = AppFont.body(size: 15, weight: .regular)   // Inter Regular
    static let fontCallout   = AppFont.body(size: 14, weight: .medium)    // Inter Medium
    static let fontSub       = AppFont.body(size: 13, weight: .medium)    // Inter Medium
    static let fontFootnote  = AppFont.body(size: 12, weight: .regular)   // Inter Regular
    static let fontCaption   = AppFont.body(size: 11, weight: .medium)    // Inter Medium
    static let fontCaption2  = AppFont.body(size: 10, weight: .medium)    // Inter Medium

    // MARK: - Palette sémantique (remplace les Color(hex:) éparpillés)

    // Catégories de modules (saturées comme la grille des catégories)
    static var fitness: Color { tone(1.00, 0.18, 0.20) }   // sport (rouge vif saturé)
    static var nutrition: Color { tone(0.28, 0.80, 0.36) }   // alimentation (vert vif saturé)
    static var hydration: Color { tone(0.13, 0.52, 1.00) }   // eau, hydratation (bleu vif saturé)
    static var sleep: Color { tone(0.42, 0.40, 0.95) }   // sommeil, repos (indigo vif)
    static var mind: Color { tone(0.66, 0.32, 0.96) }   // méditation, mental (violet vif saturé)
    static var energy: Color { tone(1.00, 0.72, 0.24) }   // énergie, ambre (vif saturé)
    static var finance: Color { tone(0.13, 0.52, 1.00) }   // finance (bleu vif saturé)
    static var invest: Color { tone(0.16, 0.80, 0.62) }   // investissement, bourse (émeraude/menthe vif)
    static var career: Color { tone(1.00, 0.72, 0.24) }   // carrière, travail (ambre vif saturé)
    static var looks: Color { tone(1.00, 0.54, 0.10) }   // beauté, bien-être (orange vif)
    static var productivity: Color { tone(0.14, 0.78, 0.80) }   // productivité, tâches (cyan vif saturé)
    static var learning: Color { tone(1.00, 0.80, 0.18) }   // apprentissage, éducation (or/jaune vif)
    static var home: Color { tone(0.24, 0.56, 0.96) }   // maison (bleu vif)
    static var social: Color { tone(1.00, 0.20, 0.55) }   // social (rose vif saturé)
    static var admin: Color { tone(0.22, 0.58, 0.98) }   // documents (bleu vif)
    static var mobility: Color { tone(0.16, 0.74, 0.78) }   // transport (cyan vif)
    static var travel: Color { tone(0.20, 0.50, 1.00) }   // voyage (bleu cobalt vif)
    static var cycle: Color { tone(0.96, 0.24, 0.58) }   // cycle menstruel (rose vif)
    static var medical: Color { tone(1.00, 0.18, 0.20) }   // santé médicale (rouge vif)

    // Statuts
    static var success: Color { tone(0.28, 0.80, 0.36) }   // validé, objectif atteint (vert vif)
    static var warning: Color { tone(1.00, 0.72, 0.24) }   // attention, moyen (ambre vif)
    static var danger: Color { tone(1.00, 0.18, 0.20) }   // risque élevé, danger (rouge vif)
    static var tealDark: Color { Color(hex: 0x008F6C) }   // potentiel fort (scores crypto)

    // Palette système fréquemment utilisée hors tokens sémantiques
    static var systemOrange: Color { tone(1.00, 0.72, 0.24) } // ambre vif
    static var systemPink: Color { tone(1.00, 0.20, 0.55) } // rose bulle (social)
    static var systemRed: Color { tone(1.00, 0.18, 0.20) } // rouge vif

    /// Convertit les anciennes teintes pastel ternes en teintes riches et saturées identiques aux catégories
    static func saturateLegacyHex(_ hex: UInt) -> UInt {
        switch hex {
        case 0xF1746C: return 0xFF2E33 // sport/rouge vif
        case 0x4CC38A: return 0x47CC5C // vert alimentation
        case 0x3CB2E0: return 0x24C7CC // cyan tâches
        case 0x9B6CF1: return 0xA852F5 // violet mental
        case 0x6C7BF1, 0x618EF1, 0x7C93C8, 0x5B8DEF: return 0x2185FF // bleu
        case 0x46C9A8, 0x5DCFA8, 0x3CD0C8: return 0x29CC9E // menthe / émeraude
        case 0xE0A23C, 0xF1A33C, 0xF2A65A: return 0xFFB83D // ambre
        case 0xE07B3C: return 0xFF8A1A // orange
        case 0xF16CB0, 0xEC6FB0, 0xE05A7A: return 0xFF338C // rose
        case 0xC98FE8: return 0xA852F5 // violet
        case 0x4CD07A: return 0x47CC5C // vert
        case 0xE84C4C: return 0xFF2E33 // rouge
        case 0xE85D9A: return 0xF53D94 // magenta
        default: return hex
        }
    }

    // MARK: - Palette : couleurs ou neutre

    /// Vrai quand l'utilisateur a choisi l'apparence neutre (Réglages > Apparence).
    static var neutralPalette: Bool {
        UserDefaults.standard.string(forKey: AppStorageKeys.appPalette) == AppPalette.neutral.rawValue
    }

    /// Couleur d'interface qui suit la palette : la couleur telle quelle, ou le gris de
    /// MEME luminance relative. Le contraste WCAG ne depend que de la luminance, donc
    /// chaque rapport de contraste reste identique entre les deux palettes.
    ///
    /// Couleur DYNAMIQUE, comme le mode sombre : elle se resout selon le trait
    /// `NeutralPaletteTrait`, pose a la racine par `.environment(\.neutralPalette, …)`.
    /// Changer de palette redessine donc sans reconstruire les vues : la navigation et
    /// les saisies en cours restent en place.
    static func tone(_ r: Double, _ g: Double, _ b: Double, alpha: Double = 1) -> Color {
        Color(uiColor: paletteUIColor(r, g, b, alpha: alpha))
    }

    static func paletteUIColor(_ r: Double, _ g: Double, _ b: Double, alpha: Double = 1) -> UIColor {
        let color = UIColor(red: r, green: g, blue: b, alpha: alpha)
        let v = neutralLevel(r, g, b)
        let grey = UIColor(red: v, green: v, blue: v, alpha: alpha)
        return UIColor { $0.lifeOSNeutralPalette ? grey : color }
    }

    /// Gris sRGB (0...1) qui a la meme luminance relative que (r, g, b).
    static func neutralLevel(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        let v = l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
        return max(0, min(1, v))
    }

    // MARK: - Grille d'espacement 8pt
    static let space2: CGFloat  = 2
    static let space4: CGFloat  = 4
    static let space8: CGFloat  = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16  // = pad
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space48: CGFloat = 48

    // Aliases sémantiques — préférer ces noms dans les nouvelles vues.
    // Correspondance : XS=4 · S=8 · M=12 · L=16 · XL=24 · XXL=32.
    static let spacingXS: CGFloat = 4
    static let spacingS:  CGFloat = 8
    static let spacingM:  CGFloat = 12
    static let spacingL:  CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32

    // Vert signature de l'icône de l'app — utilisé UNIQUEMENT par le thème Vert.
    // Dans les vues : toujours Color.accentColor + Theme.onAccent, jamais volt en dur.
    static let volt = Color(hex: 0x4CF810)

    // Liseré spéculaire discret + ombre douce (Liquid Glass iOS 27 / Apple Preview).
    static let hairline = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.25) : UIColor(red: 0.902, green: 0.902, blue: 0.910, alpha: 1.0) // #E6E6E8
    })
    static let line = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.15) : UIColor(red: 0.831, green: 0.831, blue: 0.835, alpha: 1.0) // #D4D4D5
    })
    static let shadow = Color.black.opacity(0.04)
    static let shadowSoft = Color.black.opacity(0.02)

    // Coins GÉNÉREUX arrondis (iOS 26 / Liquid Glass), continus.
    static let radius: CGFloat = 22
    static let radiusSmall: CGFloat = 14
    static let radiusLarge: CGFloat = 30
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12
    static let sectionGap: CGFloat = 24

    // MARK: - Tokens Animation (spring physique iOS 26 — remplace les valeurs éparpillées)
    //
    // Règle : préfère TOUJOURS l'un de ces 4 tokens plutôt qu'un `.spring(response: X)` inline.
    // - animMicro   : pressions boutons, toggle instantané           (< 200 ms perçu)
    // - animQuick   : chip toggles, apparitions courtes              (~300 ms perçu)
    // - animDefault : navigation, transitions écran/section standard (~500 ms perçu)
    // - animSlow    : hero entries, staggered orchestrations         (~700 ms perçu)
    static let animMicro   = Animation.spring(response: 0.20, dampingFraction: 0.70)
    static let animQuick   = Animation.spring(response: 0.28, dampingFraction: 0.75)
    static let animDefault = Animation.spring(response: 0.35, dampingFraction: 0.80)
    static let animSlow    = Animation.spring(response: 0.45, dampingFraction: 0.90)

    /// Thème Verre actif ? (lu depuis les réglages — sert aux fonds adaptatifs).
    static var isGlassActive: Bool { UserDefaults.standard.string(forKey: "appTheme") == "glass" }

    /// Thème courant (lu depuis les réglages — même pattern que isGlassActive).
    static var currentTheme: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "classic") ?? .classic
    }

    // MARK: - Matrice foreground — quand utiliser quoi
    //
    // Choisir la bonne couleur de contenu texte/icône selon le fond sur lequel il est posé.
    //
    // ┌────────────────────────────────────────────┬─────────────────────────────┐
    // │ Fond                                       │ Foreground à utiliser       │
    // ├────────────────────────────────────────────┼─────────────────────────────┤
    // │ `Color.accentColor` / `accent`             │ `Theme.onAccent`  (adapte)  │
    // │ `Theme.card` / `Theme.bg` / cardFill       │ `.primary` / `.secondary`   │
    // │ Palette sémantique fixe (fitness/sleep/…)  │ `.white`  (couleurs = OK)   │
    // │ `Color(hex: 0x…)` fixe (gradient, badge)   │ `.white` si contraste OK    │
    // │ `.regularMaterial` / `.ultraThinMaterial`  │ `.primary` / `.secondary`   │
    // └────────────────────────────────────────────┴─────────────────────────────┘
    //
    // Piège à éviter : `.foregroundStyle(.white)` sur `.background(Color.accentColor, …)`
    // → INVISIBLE en thème Sombre (blanc sur blanc) et illisible en thème Vert (blanc sur
    // vert clair 0x4CF810). Toujours utiliser `Theme.onAccent` sur ce fond.
    //
    // Vérification anti-régression : voir `LifeOSTests/ThemeContrastTests.swift`.

    /// Couleur du texte/icône posé sur l'accent du thème (bouton plein, badge sélectionné,
    /// bulle de message user…). Retourne blanc ou noir selon le thème actif pour garantir
    /// un contraste WCAG AA (≥ 4.5:1).
    static var onAccent: Color { currentTheme.onAccent }

    /// Legacy shape fill. Containers and controls use raisedSurface/glassControl.
    @available(*, deprecated, message: "Use raisedSurface or glassControl for shared glass rendering")
    static var cardFill: AnyShapeStyle {
        // TRANSLUCIDE, pas blanc opaque. C'etait un degrade blanc plein : n'importe quelle
        // carte posee dessus cachait entierement son arriere plan, donc le verre au dessus
        // n'avait plus rien a laisser voir. Un materiau fin laisse l'environnement teinter
        // la surface, c'est tout le sujet.
        AnyShapeStyle(.ultraThinMaterial)
    }

    /// Fond d'écran adaptatif : aura fluide tamisée se déplaçant lentement sur noir OLED,
    /// ou wallpaper flou en thème Verre.
    @ViewBuilder static var screenBG: some View {
        if isGlassActive {
            GlassBackdrop()
        } else {
            AmbientAuraBackdrop()
        }
    }

    /// Ancien nom conservé (mêmes règles que screenBG).
    @ViewBuilder static var background: some View { screenBG }
}

/// Aura ambiante fluide monochrome très tamisée se déplaçant très lentement à travers l'écran
struct AmbientAuraBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Base noir pur absolu OLED en dark, ou blanc pur #FFFFFF en clair
                if colorScheme == .dark {
                    Color.black
                } else {
                    Color.white
                }

                if colorScheme == .dark {
                    // Lumière très très sombre, tamisée, presque noire qui se balade très lentement
                    Circle()
                        .fill(Color(red: 0.11, green: 0.13, blue: 0.18).opacity(0.40))
                        .frame(width: max(w * 0.70, 420), height: max(w * 0.70, 420))
                        .blur(radius: 140)
                        .offset(
                            x: cos(phase) * (w * 0.25),
                            y: sin(phase * 0.8) * (h * 0.18) - (h * 0.10)
                        )

                    Circle()
                        .fill(Color(red: 0.09, green: 0.10, blue: 0.15).opacity(0.35))
                        .frame(width: max(w * 0.62, 360), height: max(w * 0.62, 360))
                        .blur(radius: 150)
                        .offset(
                            x: sin(phase * 0.7) * (w * 0.28),
                            y: cos(phase * 0.9) * (h * 0.20) + (h * 0.10)
                        )

                    Circle()
                        .fill(Color(white: 0.65).opacity(0.028))
                        .frame(width: max(w * 0.50, 300), height: max(w * 0.50, 300))
                        .blur(radius: 120)
                        .offset(
                            x: -cos(phase * 0.6) * (w * 0.20),
                            y: -sin(phase * 0.7) * (h * 0.14)
                        )
                } else {
                    // RIEN en clair, et c'est delibere.
                    //
                    // Il y avait ici des halos `Color.white.opacity(0.65)` flous. Mesure au
                    // pixel sur une capture : ils remontaient le fond de #EEEEEF (238) a
                    // 246-254, donc quasiment blanc. Une surface blanche posee sur un fond
                    // blanc ne se voit plus, quelle que soit la qualite de son ombre.
                    //
                    // Tout le mecanisme Apple tient sur ce contraste : sol GRIS #EEEEEF,
                    // surfaces BLANCHES posees dessus. Supprimer le sol gris, c'est
                    // supprimer l'effet. Les halos restent en SOMBRE, ou ils donnent au
                    // verre quelque chose a refracter.
                    EmptyView()
                }
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
                    phase = .pi * 2
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Système Liquid Glass iOS 27 (Surfaces Cristallines Translucides & Arêtes d'Eau / Glace Spéculaires)

enum LiquidGlass {

    // MARK: - Tokens relevés sur les vraies captures Apple (Aperçu, Safari, Messages)
    //
    // La règle qui fait tout le look, et c'est la seule :
    //   une surface qui FLOTTE est blanche, plate, avec UN filet clair et DEUX ombres douces.
    //   une surface ENCASTRÉE est #E8E8ED plate, sans filet, sans ombre, sans biseau.
    //
    // Ce qui ne marche pas, mesuré côte à côte en simulateur : empiler un matériau
    // translucide + trois dégradés + une ombre grise opaque de 1px. Sur un fond plat il
    // n'y a rien à réfracter, donc le matériau rend un gris terne, les dégradés dessinent
    // un biseau en relief, et l'ombre opaque devient un trait. Résultat : un bouton en
    // relief des années 2010, pas du verre iOS 26.

    /// Surface qui flotte : blanc pur qui descend d'un cheveu vers le bas.
    /// Repli translucide uniquement (iOS < 26, ou "Reduire la transparence").
    /// Sur iOS 26+ c'est `glassEffect` qui peint la surface, pas ceci.
    static func raisedFill(_ scheme: ColorScheme, tint: Color? = nil) -> LinearGradient {
        let top    = scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.55)
        let bottom = scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.38)
        if let tint {
            return LinearGradient(colors: [top, tint.opacity(0.10)], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// Le filet : UN seul, plat, très clair. Jamais un dégradé diagonal.
    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color(hex: 0xE6E6EC)
    }

    /// Surface encastrée (onglet actif, bouton secondaire, champ) : #E8E8ED plat.
    static func insetFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color(hex: 0xE8E8ED)
    }

    /// Role de surface. Il decide du MATERIAU, pas seulement d'une ombre.
    ///
    /// Regle qui structure tout : on n'empile jamais deux verres. Une carte est en verre,
    /// donc ce qui est POSE DEDANS prend un simple voile translucide, pas un second verre.
    enum Elevation {
        case inset      // pastille d'onglet actif : voile, aucune ombre
        case nested     // boite DANS une carte : voile leger, pas de verre (pas d'empilement)
        case raised     // bouton, pilule, cercle, ilot d'outils : VERRE natif
        case floating   // carte, barre d'onglets, feuille : VERRE natif

        /// `.nested` est passe au VERRE lui aussi.
        ///
        /// Il rendait un simple voile blanc plat : les lignes de modules et les tuiles
        /// du bureau n'avaient donc ni arete optique ni matiere, alors que les pilules
        /// juste au dessus en avaient. C'etait visible d'un coup d'oeil sur la meme page.
        /// Theo veut la meme matiere sur les boites imbriquees, pas seulement sur les
        /// boutons. `.inset` reste plat : c'est la pastille d'onglet actif, qu'Apple
        /// dessine bien en aplat.
        var isGlass: Bool { self != .inset }
    }
}

/// A restrained inner reflection separates the curved edge from the clear centre.
/// Shared by cards and controls; it never changes foreground opacity or hit testing.
// `GlassEdge` a ete SUPPRIME le 27 septembre 2026, et voici la mesure qui le condamne.
//
// Il dessinait un degrade blanc du haut gauche vers le bas droite pour imiter le
// liseré d'Apple. Or Apple en dessine deja un, et on l'a lu dans son app Apercu qui
// tourne dans le simulateur (`GlassProbe`) : chaque surface de verre porte un
// `CASDFKeyFillHighlightEffect` avec une lumiere principale a -45 degres et une
// lumiere de remplissage a +135 degres, blanches, force 0,5 chacune, ouverture
// 90 degres, courbure 0,7. Autrement dit exactement ce que ce modificateur imitait.
//
// Consequence mesuree sur "Nouvelle tache" contre le "Nouveau document" d'Apple,
// meme fond : Apple rend un liseré de 2 pixels a 255, nous en rendions 3. Le
// pixel en trop, c'etait ce trait. Le retirer nous met au meme profil qu'Apple.
//
// Il survit sous le nom `DrawnEdge`, et UNIQUEMENT pour `NestedVeil`, le repli des
// systemes sans verre natif : la, il n'y a aucun liseré a doubler, il faut le peindre.
private struct DrawnEdge<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.overlay {
            shape.stroke(
                LinearGradient(colors: [
                    .white.opacity(scheme == .dark ? 0.24 : 0.85),
                    .white.opacity(0.04),
                    .white.opacity(scheme == .dark ? 0.10 : 0.65)
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.65
            )
            .padding(0.75)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct RaisedSurface<S: Shape>: ViewModifier {
    let shape: S
    var level: LiquidGlass.Elevation = .raised
    var tint: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if level.isGlass, !reduceTransparency, #available(iOS 26.0, macCatalyst 26.0, *) {
            content.glassEffect(glassStyle, in: shape)
        } else {
            content
                .background(fallbackFill, in: shape)
                .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        }
    }

    private var strokeColor: Color {
        if level == .nested || level == .inset {
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.primary.opacity(0.05)
        }
        return LiquidGlass.hairline(colorScheme)
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private var glassStyle: Glass {
        if let tint { return .regular.tint(tint.opacity(0.05)) }
        return .regular
    }

    /// Repli pour iOS 17 a 25, et pour "Reduire la transparence".
    /// Volontairement sobre : un voile, pas un bloc blanc.
    private var fallbackFill: AnyShapeStyle {
        if reduceTransparency {
            // L'utilisateur a demande de l'opaque : on le lui donne, franchement.
            return AnyShapeStyle(colorScheme == .dark ? Color(white: 0.16) : Color.white)
        }
        if level == .nested || level == .inset {
            // Boîtes et tuiles imbriquées dans une carte : teinte neutre douce (#F6F6F8 en light)
            // pour contraster élégamment avec la carte sans projeter d'ombres parasites.
            return AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.06) : Color(red: 0.965, green: 0.965, blue: 0.972))
        }
        if colorScheme == .light {
            // Sur fond blanc #FFFFFF, les cartes sont blanc pur net et lumineux,
            // évitant le gris terne du matériau ultraThin et la transparence sur l'ombre.
            return AnyShapeStyle(Color.white)
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var shadowOpacity: Double {
        // ZÉRO ombre pour les boîtes imbriquées et encastrées (.nested, .inset)
        // Les sous-éléments ne doivent JAMAIS empiler d'ombres à l'intérieur d'une carte !
        guard level != .nested && level != .inset else { return 0 }
        if colorScheme == .dark {
            return level == .floating ? 0.16 : 0.08
        } else {
            // En light mode : ombre d'ambiance ultra-aérienne et douce style App Preview d'Apple
            return level == .floating ? 0.012 : 0.005
        }
    }
    private var shadowRadius: CGFloat {
        guard level != .nested && level != .inset else { return 0 }
        return level == .floating ? 6 : 2
    }
    private var shadowY: CGFloat {
        guard level != .nested && level != .inset else { return 0 }
        return level == .floating ? 1.5 : 0.5
    }
}

/// Bouton en verre, avec un vrai retour au toucher.
///
/// Pourquoi ca ne peut pas rester un `Text` + `glassEffect` : mesure au banc d'essai
/// (`GlassGallery`, variantes 1 a 3), le style natif rend une arete plus douce que notre
/// helper sur fond plat, et surtout il apporte l'etat presse, desactive et le focus.
/// `.interactive()` fait reagir le MATERIAU lui meme a l'appui, ce qu'une animation
/// d'echelle ne sait pas imiter.
///
/// N'appliquer QUE sur des controles. Une carte d'information ne doit pas devenir
/// interactive juste pour animer sa matiere.
struct GlassControl: ViewModifier {
    var shape: AnyShape = AnyShape(Capsule())
    /// Faux pour un bouton qui DOIT toujours repondre du premier coup (fermer un
    /// bandeau): la matiere interactive gere son propre toucher, et un doigt reel qui
    /// bouge un peu peut s'y perdre.
    var interactive = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        Group {
            if !reduceTransparency, #available(iOS 26.0, macCatalyst 26.0, *) {
                // `.interactive()` porte l'etat presse. On ne l'active pas quand
                // l'utilisateur a demande moins d'animation.
                content
                    .glassEffect(reduceMotion || !interactive ? .regular : .regular.interactive(), in: shape)
                    .overlay { interiorSheen }
            } else {
                content.modifier(RaisedSurface(shape: shape, level: .raised))
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    /// Degrade interieur MESURE, pas decoratif.
    ///
    /// Releve au pixel sur la reference Apple ("Nouveau document") contre notre bouton,
    /// meme fond neutre, memes largeurs normalisees :
    ///   interieur haut -> bas : reference 245 -> 248 (+3), nous 245 -> 246 (+1)
    ///   approche du liseré    : reference 252, 253, 255 (doux), nous 247, 248, 255 (sec)
    ///   liseré                : 210 des deux cotes, deja identique
    ///
    /// Le verre natif rend donc un interieur plus PLAT que la reference sur un fond sans
    /// contenu derriere. Ce voile ajoute les ~3 niveaux manquants vers le bas et adoucit
    /// l'arrivee sur le liseré. Il ne redessine PAS de bord : l'arete optique reste celle
    /// du systeme, sinon on obtiendrait le double contour qu'on cherche a eviter.
    @ViewBuilder private var interiorSheen: some View {
        if colorScheme == .light {
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.0),  location: 0.0),
                        .init(color: .white.opacity(0.05), location: 0.62),
                        .init(color: .white.opacity(0.16), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Surface d'un controle interactif (bouton, pilule cliquable, cercle d'action).
    func glassControl<S: Shape>(_ shape: S = Capsule(), interactive: Bool = true) -> some View {
        modifier(GlassControl(shape: AnyShape(shape), interactive: interactive))
    }
}

/// Nested containers share the edge treatment with a lighter fill to limit optical stacking.
struct NestedVeil<S: Shape>: ViewModifier {
    let shape: S
    var strong: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(fill, in: shape)
            .overlay(shape.stroke(LiquidGlass.hairline(colorScheme).opacity(0.35), lineWidth: 0.5))
            .modifier(DrawnEdge(shape: shape))
    }

    private var fill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(reduceTransparency ? 0.14 : (strong ? 0.10 : 0.06))
        }
        return Color.white.opacity(reduceTransparency ? 1.0 : (strong ? 0.55 : 0.38))
    }
}

extension View {
    @ViewBuilder
    func raisedSurface<S: Shape>(_ shape: S,
                                 _ level: LiquidGlass.Elevation = .raised,
                                 tint: Color? = nil) -> some View {
        if level.isGlass {
            modifier(RaisedSurface(shape: shape, level: level, tint: tint))
        } else {
            modifier(NestedVeil(shape: shape, strong: true))
        }
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil
    var strokeWidth: CGFloat = 1.0

    func body(content: Content) -> some View {
        content.raisedSurface(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            .floating, tint: tint
        )
    }
}

struct LiquidGlassPillModifier: ViewModifier {
    var tint: Color? = nil
    var strokeWidth: CGFloat = 1.0

    func body(content: Content) -> some View {
        content.raisedSurface(Capsule(), .raised, tint: tint)
    }
}

/// Pilule INTERACTIVE. Tous ses usages actuels sont des boutons (accueil, frise des
/// habitudes, tableau bureau), donc elle passe par `GlassControl` : le materiau reagit
/// lui meme a l'appui et l'etat desactive est gere. Avant, `GlassControl` existait mais
/// n'etait appele nulle part, et ces boutons n'avaient aucun retour au toucher au dela
/// d'une animation d'echelle.
struct ApplePreviewPillModifier: ViewModifier {
    var height: CGFloat = 52
    var strokeWidth: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .frame(height: height)
            .glassControl(Capsule())
    }
}

/// Petite pilule (statut, puce, bouton discret). Sobre, nette, sans ombre superflue.
struct ApplePreviewIslandModifier: ViewModifier {
    var strokeWidth: CGFloat = 0.8

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .raisedSurface(Capsule(), .nested)
    }
}

/// Controle circulaire interactif (bouton rond de barre d'outils).
struct ApplePreviewCircleModifier: ViewModifier {
    var size: CGFloat = 40
    var strokeWidth: CGFloat = 0.8

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .glassControl(Circle())
    }
}

struct ApplePreviewCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    var strokeWidth: CGFloat = 1.0

    func body(content: Content) -> some View {
        content.raisedSurface(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            .floating
        )
    }
}

/// Boite posee DANS une carte (tuile de mesure, ligne de module).
///
/// Fond neutre épuré (#F6F6F8), bordure ultra-fine, et ZÉRO ombre pour éviter
/// l'effet de boue visuelle ou d'empilement lourd.
struct ApplePreviewInnerCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var strokeWidth: CGFloat = 0.8

    func body(content: Content) -> some View {
        content.raisedSurface(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            .nested
        )
    }
}

/// Icône de catégorie en verre liquide monochrome : squircle lumineux épuré
struct CategoryGlassIcon: View {
    let category: AppCategory
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var iconSize: CGFloat = 18

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.8)
                )
                .frame(width: size, height: size)

            // Symbole monochrome net et contrasté
            Image(systemName: category.icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(Color.primary)
        }
    }
}

/// Fond « verre » global : fond d'écran doux et flou par-dessus lequel toutes les
/// surfaces `.ultraThinMaterial` (cartes, badges, barre) se dépolissent — façon iOS 26.
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            // Fond d'écran doux mais COLORÉ (façon wallpaper iOS) pour que les surfaces
            // .ultraThinMaterial se dépolissent visiblement — vrai Liquid Glass.
            LinearGradient(colors: [Color(hex: 0x7C93C8), Color(hex: 0xAE9BC9), Color(hex: 0x8FC4BE)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(hex: 0x9FD0E8).opacity(0.75)).frame(width: 380, height: 380)
                .blur(radius: 100).offset(x: -140, y: -260)
            Circle().fill(Color(hex: 0xC7A6D8).opacity(0.7)).frame(width: 360, height: 360)
                .blur(radius: 110).offset(x: 160, y: 300)
            Circle().fill(Color(hex: 0xF0C9A8).opacity(0.6)).frame(width: 300, height: 300)
                .blur(radius: 95).offset(x: 150, y: -140)
            Circle().fill(Color(hex: 0x8FD6B4).opacity(0.55)).frame(width: 280, height: 280)
                .blur(radius: 90).offset(x: -150, y: 320)
        }
        .ignoresSafeArea()
    }
}

/// Style de bouton tactile : léger enfoncement + estompage au press.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var opacity: CGFloat = 0.88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && !reduceMotion ? opacity : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.64),
                value: configuration.isPressed
            )
    }
}

struct LiquidGlassBorderModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var tint: Color? = nil
    var strokeWidth: CGFloat = 1.0

    @Environment(\.colorScheme) private var colorScheme

    /// UN filet fin, rien d'autre.
    ///
    /// Avant : deux contours en degrade diagonal ("arete de glace" + "caustique interne").
    /// Ca dessinait un biseau en relief et un trait gris epais, l'oppose du rendu vise.
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LiquidGlass.hairline(colorScheme), lineWidth: min(strokeWidth, 0.5))
        )
    }
}

extension View {
    /// Carte Liquid Glass avec bordure transparente lumineuse iOS 27
    func liquidGlassCard(cornerRadius: CGFloat = 18, tint: Color? = nil, strokeWidth: CGFloat = 1.0) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, strokeWidth: strokeWidth))
    }

    /// Bordure Liquid Glass spéculaire façon biseau de glace
    func liquidGlassBorder(cornerRadius: CGFloat = 18, tint: Color? = nil, strokeWidth: CGFloat = 1.0) -> some View {
        self.modifier(LiquidGlassBorderModifier(cornerRadius: cornerRadius, tint: tint, strokeWidth: strokeWidth))
    }

    /// Capsule / Pillule Liquid Glass avec bordure transparente
    func liquidGlassPill(tint: Color? = nil, strokeWidth: CGFloat = 1.0) -> some View {
        self.modifier(LiquidGlassPillModifier(tint: tint, strokeWidth: strokeWidth))
    }

    /// Bouton Capsule translucide style Apple Aperçu (Preview iOS)
    func applePreviewPill(height: CGFloat = 52, strokeWidth: CGFloat = 0.8) -> some View {
        self.modifier(ApplePreviewPillModifier(height: height, strokeWidth: strokeWidth))
    }

    /// Îlot / Barre d'outils flottante capsule style Apple Aperçu
    func applePreviewIsland(strokeWidth: CGFloat = 0.6) -> some View {
        self.modifier(ApplePreviewIslandModifier(strokeWidth: strokeWidth))
    }

    /// Bouton circulaire flottant style Apple Aperçu (ex: retour, options)
    func applePreviewCircle(size: CGFloat = 40, strokeWidth: CGFloat = 0.6) -> some View {
        self.modifier(ApplePreviewCircleModifier(size: size, strokeWidth: strokeWidth))
    }

    /// Carte / Conteneur ultra-arrondi (coins continus généreux 28-34pt) style Apple Aperçu
    func applePreviewCard(cornerRadius: CGFloat = 28, strokeWidth: CGFloat = 0.8) -> some View {
        self.modifier(ApplePreviewCardModifier(cornerRadius: cornerRadius, strokeWidth: strokeWidth))
    }

    /// Carte interne imbriquée (conforme à la règle "Jamais de verre sur du verre", sans second flou)
    func applePreviewInnerCard(cornerRadius: CGFloat = 16, strokeWidth: CGFloat = 0.6) -> some View {
        self.modifier(ApplePreviewInnerCardModifier(cornerRadius: cornerRadius, strokeWidth: strokeWidth))
    }

    /// Ombre douce diffuse — profondeur flottante style Apple Aperçu.
    func softElevation(_ strong: Bool = false) -> some View {
        shadow(color: strong ? Theme.shadow : Theme.shadowSoft, radius: strong ? 8 : 5, y: strong ? 2 : 1)
    }
    /// Titre NIKE : gras extrême, majuscules, kerning serré.
    func nikeTitle(_ size: CGFloat = 34) -> some View {
        self.font(.system(size: size, weight: .black)).textCase(.uppercase).kerning(-0.5)
    }
    /// Label technique monospace en majuscules (façon fiches produit Nike ADV).
    func monoLabel(_ size: CGFloat = 11) -> some View {
        self.font(.system(size: size, weight: .semibold, design: .monospaced)).textCase(.uppercase).kerning(1.4)
    }
}

/// Grille technique fine (motif Nike/Swiss) posée derrière le contenu.
struct TechGrid: View {
    var spacing: CGFloat = 46
    var body: some View {
        GeometryReader { geo in
            Path { p in
                var x: CGFloat = 0
                while x <= geo.size.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: geo.size.height)); x += spacing }
                var y: CGFloat = 0
                while y <= geo.size.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: geo.size.width, y: y)); y += spacing }
            }
            .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        let saturated = Theme.saturateLegacyHex(hex)
        self.init(uiColor: Theme.paletteUIColor(Double((saturated >> 16) & 0xFF) / 255,
                                                Double((saturated >> 8) & 0xFF) / 255,
                                                Double(saturated & 0xFF) / 255, alpha: alpha))
    }

    /// "RRGGBB" hex (sans #) — pour persister une couleur choisie par l'utilisateur.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int(round(max(0, min(1, r)) * 255)),
                      Int(round(max(0, min(1, g)) * 255)),
                      Int(round(max(0, min(1, b)) * 255)))
    }
}

// MARK: - Trait de palette (propage comme le mode sombre)

/// Trait UIKit "palette neutre", relie a l'environnement SwiftUI. `affectsColorAppearance`
/// demande a iOS de re-resoudre les couleurs dynamiques quand il change.
struct NeutralPaletteTrait: UITraitDefinition {
    static let defaultValue = false
    static let affectsColorAppearance = true
    static let name = "LifeOSNeutralPalette"
}

extension UITraitCollection {
    var lifeOSNeutralPalette: Bool { self[NeutralPaletteTrait.self] }
}

extension UIMutableTraits {
    var lifeOSNeutralPalette: Bool {
        get { self[NeutralPaletteTrait.self] }
        set { self[NeutralPaletteTrait.self] = newValue }
    }
}

private struct NeutralPaletteKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = false
    static func read(from traitCollection: UITraitCollection) -> Bool { traitCollection.lifeOSNeutralPalette }
    static func write(to mutableTraits: inout UIMutableTraits, value: Bool) { mutableTraits.lifeOSNeutralPalette = value }
}

extension EnvironmentValues {
    var neutralPalette: Bool {
        get { self[NeutralPaletteKey.self] }
        set { self[NeutralPaletteKey.self] = newValue }
    }
}

// MARK: - Palette (second axe de l'apparence)

/// Couleurs ou neutre, independant du clair/sombre : 2 x 2 = quatre apparences.
/// Le neutre retire les accents d'interface (rouge, bleu, vert, jaune...), jamais les
/// photos ni les documents de l'utilisateur, qui ne passent pas par ces couleurs.
enum AppPalette: String, CaseIterable, Identifiable {
    case color, neutral
    var id: String { rawValue }
    var label: String { self == .color ? "Couleurs" : "Neutre" }
    var symbol: String { self == .color ? "paintpalette.fill" : "circle.grid.2x2" }
}

// MARK: - Thèmes de l'app (Couleur de l'app)

enum AppTheme: String, CaseIterable, Identifiable {
    case system    // Automatique selon le réglage de l'appareil (iOS)
    case classic   // Clair — blanc cassé + accent noir
    case dark      // Sombre — noir pur + accent blanc
    case volt      // Vert — ARCHIVÉ
    case glass     // VERRE translucide façon Apple (Liquid Glass) — ARCHIVÉ
    case pinky     // Rose — ARCHIVÉ
    case gothic    // argent liquide sombre, gothique — ARCHIVÉ
    case cloud     // nuage blanc, doux — ARCHIVÉ

    var id: String { rawValue }

    /// Thèmes proposés dans le sélecteur : Système (défaut), Clair et Sombre.
    static let selectable: [AppTheme] = [.system, .classic, .dark]
    var isSelectable: Bool { Self.selectable.contains(self) }

    var label: String {
        switch self {
        case .system:  return "Système"
        case .classic: return "Clair"
        case .dark:    return "Sombre"
        case .volt:    return "Vert"
        case .glass:   return "Verre"
        case .pinky:   return "Rose"
        case .gothic:  return "Argent"
        case .cloud:   return "Cloud"
        }
    }
    var symbol: String {
        switch self {
        case .system:  return "circle.lefthalf.filled"
        case .classic: return "sun.max.fill"
        case .dark:    return "moon.fill"
        case .volt:    return "bolt.fill"
        case .glass:   return "circle.hexagongrid.fill"
        case .pinky:   return "heart.fill"
        case .gothic:  return "drop.fill"
        case .cloud:   return "cloud.fill"
        }
    }
    /// Schéma clair/sombre forcé par le thème (nil = suit le système iOS).
    var scheme: ColorScheme? {
        switch self {
        case .system:        return nil
        case .dark, .gothic: return .dark
        default:             return .light
        }
    }
    /// Couleur d'accent du thème — UNE couleur par thème, visible partout
    /// via `Color.accentColor` (injecté par `.tint()` à la racine).
    var accent: Color {
        switch self {
        case .system:  return Color.primary
        case .classic: return .black
        case .dark:    return .white
        case .volt:    return Theme.volt
        case .glass:   return Theme.volt
        case .pinky:   return Color(hex: 0xFF5BA0)
        case .gothic:  return Color(hex: 0xB7C2D0)
        case .cloud:   return Color(hex: 0x9BB2D6)
        }
    }
    /// Hex de l'accent — synchronisé vers l'app group pour les widgets
    /// (un widget ne voit pas le tint racine de l'app).
    /// Noir/blanc sont interprétés côté widget comme `.primary` (adaptatif).
    var accentHex: Int {
        switch self {
        case .system:  return 0x000000
        case .classic: return 0x000000
        case .dark:    return 0xFFFFFF
        case .volt:    return 0x4CF810
        case .glass:   return 0x4CF810
        case .pinky:   return 0xFF5BA0
        case .gothic:  return 0xB7C2D0
        case .cloud:   return 0x9BB2D6
        }
    }
    /// Couleur du contenu posé SUR l'accent (texte d'un bouton plein, etc.).
    var onAccent: Color {
        switch self {
        case .system:  return Color(uiColor: .systemBackground)
        case .classic: return .white
        case .dark:    return .black
        case .volt:    return .black
        case .glass:   return .black
        case .pinky:   return .white
        case .gothic:  return .black
        case .cloud:   return .black
        }
    }
    /// Pastille du sélecteur de thème : la couleur signature du thème.
    var previewFill: Color {
        switch self {
        case .system:  return Color(uiColor: .tertiarySystemFill)
        case .classic: return Color(hex: 0xECECE7)
        case .dark:    return Color(hex: 0x0A0A0A)
        case .volt:    return Theme.volt
        case .glass:   return Color(hex: 0xB8BCC6)
        case .pinky:   return Color(hex: 0xFFE3F1)
        case .gothic:  return Color(hex: 0x2A2E36)
        case .cloud:   return Color(hex: 0xEAF0F9)
        }
    }
    var previewIcon: Color {
        switch self {
        case .system:  return .primary
        case .classic: return .black
        case .dark:    return .white
        case .volt:    return .black
        case .glass:   return .white
        case .pinky:   return Color(hex: 0xFF5BA0)
        case .gothic:  return Color(hex: 0xB7C2D0)
        case .cloud:   return Color(hex: 0x9BB2D6)
        }
    }

    /// Fond (mesh 3×3) de l'écran Catégories selon le thème.
    /// NIKE = aplat (blanc cassé / noir pur), la texture vient de la grille technique.
    var bubbleBG: [Color] {
        switch self {
        case .system:
            return Array(repeating: Color(uiColor: .systemGroupedBackground), count: 9)
        case .classic, .volt:
            return Array(repeating: Color.white, count: 9)
        case .dark:
            return Array(repeating: Color(hex: 0x000000), count: 9)
        case .glass:
            // Toile floue neutre/chaude derrière le verre (façon fond d'écran iOS).
            return [ Color(hex: 0xB8BCC6), Color(hex: 0xC7C2BC), Color(hex: 0xAEB4BE),
                     Color(hex: 0xC9C4BE), Color(hex: 0xBFC3CB), Color(hex: 0xB2AEA9),
                     Color(hex: 0xA9AEB8), Color(hex: 0xC4BFB8), Color(hex: 0xB6BAC3) ]
        case .pinky:
            return [ Color(hex: 0xFFE3F1), Color(hex: 0xFFF0F7), Color(hex: 0xFFE7F4),
                     Color(hex: 0xFFEAF4), Color(hex: 0xFFF6FB), Color(hex: 0xFCE7FF),
                     Color(hex: 0xFFDCEF), Color(hex: 0xFFE6F5), Color(hex: 0xF8E3FF) ]
        case .gothic:
            return [ Color(hex: 0x070708), Color(hex: 0x050506), Color(hex: 0x0A0A0C),
                     Color(hex: 0x060607), Color(hex: 0x0C0C0F), Color(hex: 0x060608),
                     Color(hex: 0x040405), Color(hex: 0x080809), Color(hex: 0x0A0A0D) ]
        case .cloud:
            return [ Color(hex: 0xF2F5FA), Color(hex: 0xFAFCFF), Color(hex: 0xEFF3F9),
                     Color(hex: 0xF6F9FE), Color(hex: 0xFFFFFF), Color(hex: 0xF1F5FB),
                     Color(hex: 0xEDF1F8), Color(hex: 0xF4F7FC), Color(hex: 0xF0F4FA) ]
        }
    }
    /// Nike = thèmes à grille technique (système/clair/sombre/vert).
    var isNike: Bool { self == .system || self == .classic || self == .dark || self == .volt }
    var isGlass: Bool { self == .glass }
    /// Thèmes « modernes » (Nike + Verre) → grille de catégories façon Nike (pas les bulles).
    var isModern: Bool { isNike || isGlass }
}

// MARK: - Système d'ombres (3 niveaux)

private struct ShadowModifier: ViewModifier {
    let radius: CGFloat
    let y: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(opacity * 0.5), radius: radius * 0.25, y: 1)
            .shadow(color: .black.opacity(opacity), radius: radius, y: y)
    }
}

extension View {
    /// Ombre légère — cartes de contenu, tuiles
    func shadowSm() -> some View { modifier(ShadowModifier(radius: 4, y: 1, opacity: 0.025)) }
    /// Ombre moyenne — modals, sheets, bulles
    func shadowMd() -> some View { modifier(ShadowModifier(radius: 8, y: 2, opacity: 0.04)) }
    /// Ombre forte — overlays, popovers
    func shadowLg() -> some View { modifier(ShadowModifier(radius: 14, y: 4, opacity: 0.06)) }
}

// MARK: - Carte Liquid Glass (cellule adaptative iOS 27)

struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.pad
    var radius: CGFloat = Theme.radius
    var elevated: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .liquidGlassCard(cornerRadius: radius)
    }
}

extension View {
    func card(padding: CGFloat = Theme.pad, radius: CGFloat = Theme.radius, elevated: Bool = false) -> some View {
        modifier(CardStyle(padding: padding, radius: radius, elevated: elevated))
    }
}

// MARK: - Surface (carte au contour lisible : verre liquide avec arête de glace)

private struct SurfaceStyle: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .liquidGlassCard(cornerRadius: radius)
    }
}

extension View {
    /// Fond card + arête de glace liquide — les bords restent nets et cristallins sur tout fond.
    func surface(radius: CGFloat = 20) -> some View { modifier(SurfaceStyle(radius: radius)) }
}

// MARK: - Apparition en cascade (stagger ~70 ms par section)

private struct StaggeredAppear: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 18)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(duration: 0.55, bounce: 0.18).delay(Double(index) * 0.07),
                value: appeared
            )
    }
}

extension View {
    /// Entrée décalée de `index` × 70 ms — déclenchée par `appeared`.
    func staggered(_ index: Int, appeared: Bool) -> some View {
        modifier(StaggeredAppear(index: index, appeared: appeared))
    }

    /// Fondu + léger scale des cartes à l'entrée/sortie du viewport de scroll.
    func scrollFade() -> some View {
        scrollTransition(axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.55)
                .scaleEffect(phase.isIdentity ? 1 : 0.965)
        }
    }
}

/// Common replacement for module-local bordered and opaque prominent buttons.
struct LifeOSGlassButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .fontWeight(prominent ? .semibold : .medium)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassControl(Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.64),
                value: configuration.isPressed
            )
    }
}
