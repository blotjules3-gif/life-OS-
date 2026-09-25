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
    // En light mode : Exact Apple Preview (#EEEEEF fond, #F5F5F7 cartes, #E8E8ED boutons intérieurs, #D4D4D5 ombre 1px)
    static let bg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.black : UIColor(red: 0.933, green: 0.933, blue: 0.937, alpha: 1.0) // #EEEEEF
    })
    static let bg2 = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.08) : UIColor(red: 0.910, green: 0.910, blue: 0.929, alpha: 1.0) // #E8E8ED
    })
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.05) : UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1.0) // #F5F5F7
    })
    static let stroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.35) : UIColor(red: 0.831, green: 0.831, blue: 0.835, alpha: 1.0) // #D4D4D5
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

    // Catégories de modules
    static let fitness      = Color(hex: 0xF1746C)   // sport, calories
    static let nutrition    = Color(hex: 0x4CC38A)   // alimentation, objectifs verts
    static let hydration    = Color(hex: 0x3CB2E0)   // eau, hydratation
    static let sleep        = Color(hex: 0x6C7BF1)   // sommeil, repos
    static let mind         = Color(hex: 0x9B6CF1)   // méditation, mental
    static let energy       = Color(hex: 0xE0A23C)   // énergie, amber
    static let finance      = Color(hex: 0x46C9A8)   // finance (teal-vert, distinct de nutrition)
    static let invest       = Color(hex: 0x2FB89A)   // investissement (teal foncé)
    static let career       = Color(hex: 0xE07B3C)   // carrière, orange
    static let looks        = Color(hex: 0xE0A23C)   // beauté, skincare (amber)
    static let productivity = Color(hex: 0x3CB2E0)   // productivité, tâches
    static let learning     = Color(hex: 0xF97316)   // apprentissage, orange vif
    static let home         = Color(hex: 0x6CA0F1)   // maison
    static let social       = Color(hex: 0xF16CB0)   // social, relations
    static let admin        = Color(hex: 0x8A93A8)   // admin, neutre
    static let mobility     = Color(hex: 0x3CD0C8)   // transport, teal
    static let travel       = Color(hex: 0x6C9BF1)   // voyage
    static let cycle        = Color(hex: 0xE85D9A)   // cycle menstruel
    static let medical      = Color(hex: 0xE84C4C)   // santé médicale

    // Statuts
    static let success    = Color(hex: 0x4CC38A)   // validé, objectif atteint
    static let warning    = Color(hex: 0xE0A23C)   // attention, moyen
    static let danger     = Color(hex: 0xF1746C)   // risque élevé, danger
    static let tealDark   = Color(hex: 0x008F6C)   // potentiel fort (scores crypto)

    // Palette système fréquemment utilisée hors tokens sémantiques
    static let systemOrange = Color(hex: 0xFF9F0A) // orange iOS system (badges alerte)
    static let systemPink   = Color(hex: 0xF16CB0) // rose bulle (social)
    static let systemRed    = Color(hex: 0xE84C4C) // rouge médical

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
    static let shadow = Color.black.opacity(0.10)
    static let shadowSoft = Color.black.opacity(0.06)

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

    /// Remplissage de carte adaptatif Liquid Glass : verre dépoli ultra-fin cristallin.
    /// À utiliser dans `.background(Theme.cardFill, in: shape)` pour que TOUTES les cartes
    /// suivent le design Liquid Glass iOS 27.
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
                // Base noir pur absolu OLED en dark, ou Apple Preview #EEEEEF en clair
                if colorScheme == .dark {
                    Color.black
                } else {
                    Color(hex: 0xEEEEEF)
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

        var isGlass: Bool { self == .raised || self == .floating }
    }
}

/// Le seul rendu de surface de l'app.
///
/// Il utilise le VRAI verre du systeme (`glassEffect`, iOS 26+), pas une imitation.
/// L'ancienne version peignait un degrade blanc opaque plus un filet plus deux ombres :
/// ca donnait du plastique blanc epais, ca cachait completement ce qu'il y avait dessous,
/// et ca ne ressemblait pas aux captures de reference.
///
/// Trois choses a ne pas defaire :
/// 1. **Aucun fond opaque sous le verre.** Le verre a besoin de voir l'arriere plan. Un
///    `.background(Color.white)` sur un ancetre suffit a tout annuler.
/// 2. **Aucun filet ni ombre ajoutes par dessus.** `glassEffect` dessine deja son arete
///    optique et son ombre. En rajouter donne le bord gris epais qu'on veut eviter.
/// 3. **Le texte reste opaque.** On ne baisse jamais l'opacite de la vue entiere pour
///    simuler un materiau : ca rend le contenu illisible.
///
/// Choix `.regular` plutot que `.clear` : verifie a l'ecran, cote a cote, sur fond neutre
/// ET sur du contenu colore. `.clear` laisse trop passer et le texte devient dur a lire
/// sur du contenu charge. `.regular` laisse voir l'arriere plan tout en gardant le
/// premier plan net, ce qui correspond aux captures.
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
                .overlay(shape.stroke(LiquidGlass.hairline(colorScheme), lineWidth: 0.5))
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        }
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private var glassStyle: Glass {
        // Teinte semantique gardee, mais a l'etat de SOUPCON.
        //
        // A 0,18 la carte "Sport & fitness" virait franchement au rose : la teinte du
        // module etait auparavant enterree sous un degrade blanc opaque, le verre la
        // laisse passer telle quelle. Un bloc de couleur contredit l'environnement neutre
        // des references. La couleur du module reste portee par son icone et son bouton
        // d'action, la ou elle veut dire quelque chose.
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
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var shadowOpacity: Double {
        guard level.isGlass else { return 0 }
        return colorScheme == .dark ? 0.28 : 0.05
    }
    private var shadowRadius: CGFloat { level.isGlass ? (level == .floating ? 12 : 8) : 0 }
    private var shadowY: CGFloat { level.isGlass ? (level == .floating ? 4 : 2) : 0 }
}

/// Voile pour ce qui est POSE DANS une surface en verre. Jamais de verre ici : deux verres
/// empiles se brouillent et alourdissent, c'est exactement ce qu'Apple interdit.
struct NestedVeil<S: Shape>: ViewModifier {
    let shape: S
    var strong: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(fill, in: shape)
            .overlay(shape.stroke(LiquidGlass.hairline(colorScheme).opacity(0.7), lineWidth: 0.5))
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
            modifier(NestedVeil(shape: shape, strong: level == .inset))
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

struct ApplePreviewPillModifier: ViewModifier {
    var height: CGFloat = 52
    var strokeWidth: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .frame(height: height)
            .raisedSurface(Capsule(), .raised)
    }
}

/// Petite pilule (statut, puce, bouton discret). Meme matiere que les gros boutons :
/// blanche, un filet, une ombre douce. Elle etait grise et plate, ce qui la faisait
/// disparaitre a cote des vrais boutons.
struct ApplePreviewIslandModifier: ViewModifier {
    var strokeWidth: CGFloat = 0.8

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .raisedSurface(Capsule(), .raised)
    }
}

struct ApplePreviewCircleModifier: ViewModifier {
    var size: CGFloat = 40
    var strokeWidth: CGFloat = 0.8

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .raisedSurface(Circle(), .raised)
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
/// Elle est de la MEME matiere que les boutons : blanche, un filet, une ombre douce.
/// Ce n'est pas du "verre sur du verre" : la regle d'Apple interdit d'empiler deux
/// MATERIAUX translucides, pas de poser une surface opaque sur une autre. Ce qui separe
/// les deux ici, c'est l'ombre plus courte, pas une teinte grise.
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

/// Icône de catégorie en verre liquide monochrome : remplace les blocs de couleur par un squircle translucide épuré
struct CategoryGlassIcon: View {
    let category: AppCategory
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var iconSize: CGFloat = 18

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Lueur monochrome subtile
            Circle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
                .frame(width: size * 0.75, height: size * 0.75)
                .blur(radius: 6)

            // Squircle en VERRE natif. L'arete est dessinee par le systeme, pas a la
            // main : le biseau maison donnait un contour gris epais.
            Color.clear
                .frame(width: size, height: size)
                .raisedSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), .raised)

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
    var scale: CGFloat = 0.97
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
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

    /// Ombre douce diffuse — profondeur flottante iOS 26.
    func softElevation(_ strong: Bool = false) -> some View {
        shadow(color: strong ? Theme.shadow : Theme.shadowSoft, radius: strong ? 18 : 11, y: strong ? 8 : 4)
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
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
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
            return Array(repeating: Color(hex: 0xECECE7), count: 9)
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
    func shadowSm() -> some View { modifier(ShadowModifier(radius: 4, y: 2, opacity: 0.06)) }
    /// Ombre moyenne — modals, sheets, bulles
    func shadowMd() -> some View { modifier(ShadowModifier(radius: 12, y: 6, opacity: 0.09)) }
    /// Ombre forte — overlays, popovers
    func shadowLg() -> some View { modifier(ShadowModifier(radius: 24, y: 12, opacity: 0.13)) }
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
            .softElevation(elevated)
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
