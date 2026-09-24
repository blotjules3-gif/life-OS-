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
    // Surfaces adaptatives OLED Black & Liquid Glass :
    // En dark mode : Noir Pur (#000000) et verre translucide avec contour lumineux
    static let bg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.black : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
    })
    static let bg2 = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 0.70) : UIColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1.0)
    })
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.09, alpha: 0.60) : UIColor.white
    })
    static let stroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 1.0, alpha: 0.20) : UIColor(white: 0.0, alpha: 0.10)
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

    // Liseré discret + ombre douce (profondeur iOS 26, pas de brutalisme).
    static let hairline = Color.primary.opacity(0.10)
    static let line = Color.primary.opacity(0.22)      // trait de grille technique
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

    /// Remplissage de carte adaptatif : verre dépoli en thème Verre, sinon surface opaque.
    /// À utiliser dans `.background(Theme.cardFill, in: shape)` pour que TOUTES les cartes
    /// suivent le thème (glass global).
    static var cardFill: AnyShapeStyle {
        isGlassActive ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(card)
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
                // Base noir pur absolu OLED en dark, ou blanc cassé en clair
                if colorScheme == .dark {
                    Color.black
                } else {
                    Color(red: 0.96, green: 0.96, blue: 0.97)
                }

                if colorScheme == .dark {
                    // Orbes monochromes lunaires / argentés subtils — aucun pixel de couleur
                    Circle()
                        .fill(Color.white.opacity(0.045))
                        .frame(width: max(w * 0.65, 380), height: max(w * 0.65, 380))
                        .blur(radius: 140)
                        .offset(
                            x: cos(phase) * (w * 0.22),
                            y: sin(phase * 0.8) * (h * 0.16) - (h * 0.12)
                        )

                    Circle()
                        .fill(Color(white: 0.90).opacity(0.035))
                        .frame(width: max(w * 0.58, 340), height: max(w * 0.58, 340))
                        .blur(radius: 150)
                        .offset(
                            x: sin(phase * 0.7) * (w * 0.25),
                            y: cos(phase * 0.9) * (h * 0.18) + (h * 0.08)
                        )

                    Circle()
                        .fill(Color(white: 0.80).opacity(0.038))
                        .frame(width: max(w * 0.50, 300), height: max(w * 0.50, 300))
                        .blur(radius: 130)
                        .offset(
                            x: -cos(phase * 0.6) * (w * 0.20),
                            y: -sin(phase * 0.7) * (h * 0.14)
                        )
                } else {
                    // Mode clair : lueurs blanches subtiles
                    Circle()
                        .fill(Color.white.opacity(0.60))
                        .frame(width: max(w * 0.60, 340), height: max(w * 0.60, 340))
                        .blur(radius: 110)
                        .offset(x: cos(phase) * (w * 0.20), y: sin(phase * 0.8) * (h * 0.15))

                    Circle()
                        .fill(Color(white: 0.88).opacity(0.40))
                        .frame(width: max(w * 0.55, 300), height: max(w * 0.55, 300))
                        .blur(radius: 115)
                        .offset(x: sin(phase * 0.7) * (w * 0.22), y: cos(phase * 0.9) * (h * 0.16))
                }
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                    phase = .pi * 2
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Système Liquid Glass iOS 27 (Surfaces translucides et bordures transparentes lumineuses)

enum LiquidGlass {
    /// Bordure transparente spéculaire iOS 27 qui accroche la lumière (adaptative clair / sombre)
    static func borderGradient(opacity: Double = 1.0, tint: Color? = nil) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.primary.opacity(0.38 * opacity), location: 0.0),
                .init(color: Color.primary.opacity(0.10 * opacity), location: 0.40),
                .init(color: (tint ?? Color.primary).opacity(0.24 * opacity), location: 0.85),
                .init(color: Color.primary.opacity(0.18 * opacity), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18
    var tint: Color? = nil
    var strokeWidth: CGFloat = 1.0

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if colorScheme == .dark {
                        // En dark mode : noir translucide OLED façon Apple VisionOS / iOS 27
                        Color(hex: 0x121214).opacity(0.60)
                        if let tint {
                            tint.opacity(0.08)
                        }
                    } else {
                        Color.white.opacity(0.85)
                        if let tint {
                            tint.opacity(0.05)
                        }
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LiquidGlass.borderGradient(opacity: colorScheme == .dark ? 1.0 : 0.65, tint: tint),
                        lineWidth: strokeWidth
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.06), radius: 14, x: 0, y: 7)
    }
}

struct LiquidGlassPillModifier: ViewModifier {
    var tint: Color? = nil
    var strokeWidth: CGFloat = 1.0

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                Capsule()
                    .fill(colorScheme == .dark ? Color(white: 0.16, opacity: 0.55) : Color(white: 0.92, opacity: 0.85))
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .overlay(
                Capsule()
                    .strokeBorder(
                        LiquidGlass.borderGradient(opacity: colorScheme == .dark ? 1.0 : 0.65, tint: tint),
                        lineWidth: strokeWidth
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Système Apple Aperçu (Preview iOS) : Boutons capsules translucides, îlots flottants & coins ultra-arrondis

struct ApplePreviewPillModifier: ViewModifier {
    var height: CGFloat = 52
    var strokeWidth: CGFloat = 0.8
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .frame(height: height)
            .background {
                Capsule()
                    .fill(colorScheme == .dark
                          ? Color(white: 0.12, opacity: 0.65)
                          : Color.white.opacity(0.85))
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.15), location: 0.0),
                                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), location: 0.5),
                                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strokeWidth
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.04), radius: 8, x: 0, y: 3)
    }
}

struct ApplePreviewIslandModifier: ViewModifier {
    var strokeWidth: CGFloat = 0.6
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(colorScheme == .dark
                          ? Color(white: 0.10, opacity: 0.70)
                          : Color.white.opacity(0.85))
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .overlay(
                Capsule()
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.12),
                        lineWidth: strokeWidth
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 12, x: 0, y: 4)
    }
}

struct ApplePreviewCircleModifier: ViewModifier {
    var size: CGFloat = 40
    var strokeWidth: CGFloat = 0.6
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(colorScheme == .dark
                          ? Color(white: 0.12, opacity: 0.70)
                          : Color.white.opacity(0.85))
                    .background(.ultraThinMaterial, in: Circle())
            }
            .overlay(
                Circle()
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.25 : 0.12),
                        lineWidth: strokeWidth
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.05), radius: 8, x: 0, y: 3)
    }
}

struct ApplePreviewCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 28
    var strokeWidth: CGFloat = 0.8
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color(white: 0.09, opacity: 0.65)
                          : Color.white.opacity(0.88))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.12), location: 0.0),
                                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04), location: 0.5),
                                .init(color: Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strokeWidth
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05), radius: 14, x: 0, y: 6)
    }
}

/// Règle Apple "Jamais de verre sur du verre" (No glass on glass) :
/// Les éléments imbriqués à l'intérieur d'une carte verre utilisent des opacités subtiles et des arêtes concentriques,
/// évitant le flou empilé énergivore et grisâtre.
struct ApplePreviewInnerCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var strokeWidth: CGFloat = 0.6
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color.white.opacity(0.04)
                          : Color.black.opacity(0.03))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08),
                        lineWidth: strokeWidth
                    )
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

            // Squircle en verre liquide translucide monochrome
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.primary.opacity(colorScheme == .dark ? 0.45 : 0.35), location: 0.0),
                                    .init(color: Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.15), location: 0.5),
                                    .init(color: Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.08), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

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

extension View {
    /// Carte Liquid Glass avec bordure transparente lumineuse iOS 27
    func liquidGlassCard(cornerRadius: CGFloat = 18, tint: Color? = nil, strokeWidth: CGFloat = 1.0) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, strokeWidth: strokeWidth))
    }

    /// Bordure Liquid Glass transparente 1px
    func liquidGlassBorder(cornerRadius: CGFloat = 18, tint: Color? = nil, strokeWidth: CGFloat = 1.0) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LiquidGlass.borderGradient(tint: tint), lineWidth: strokeWidth)
        )
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

// MARK: - Carte sobre (cellule groupée façon iOS)

struct CardStyle: ViewModifier {
    @AppStorage(AppStorageKeys.appTheme) private var themeRaw = "classic"
    var padding: CGFloat = Theme.pad
    var radius: CGFloat = Theme.radius
    var elevated: Bool = false
    func body(content: Content) -> some View {
        let glass = themeRaw == "glass"
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Theme.card))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(glass ? Color.white.opacity(0.35) : Theme.hairline, lineWidth: glass ? 1 : 0.5)
            )
            .softElevation(elevated)
    }
}

extension View {
    func card(padding: CGFloat = Theme.pad, radius: CGFloat = Theme.radius, elevated: Bool = false) -> some View {
        modifier(CardStyle(padding: padding, radius: radius, elevated: elevated))
    }
}

// MARK: - Surface (carte au contour lisible : liseré hairline + ombre douce)

private struct SurfaceStyle: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .shadowSm()
    }
}

extension View {
    /// Fond card + liseré + ombre légère — les bords restent visibles sur tout fond.
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
