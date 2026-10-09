import SwiftUI

// MARK: - Apparence : UNE seule source pour les valeurs par defaut
//
// Avant le lot 8, le defaut du theme etait ecrit a la main dans neuf fichiers, et pas
// toujours le meme : "system" dans LifeOSApp et le Profil, "classic" dans l'accueil,
// les catégories, le coach et `Theme.currentTheme`. Sur une installation neuve, l'app
// suivait donc l'appareil (sombre) pendant que `Theme.onAccent` croyait au theme Clair
// et peignait du BLANC sur l'accent blanc du mode sombre : bouton illisible.
//
// Regle : toute lecture du theme ou de la palette passe par `AppTheme.resolved(_:)` et
// `AppPalette.resolved(_:)`, et tout `@AppStorage` prend `AppTheme.defaultRaw` /
// `AppPalette.defaultRaw` comme valeur initiale. Un theme archive (Vert, Verre, Rose,
// Argent, Cloud) se lit comme "Suivre l'appareil", partout, sans reecrire la valeur
// stockee : rien n'est perdu si on le ressort un jour.

extension AppTheme {
    /// Defaut de l'app : la luminosite suit l'appareil.
    static let defaultTheme: AppTheme = .system
    /// Valeur brute a donner a chaque `@AppStorage(AppStorageKeys.appTheme)`.
    static let defaultRaw: String = AppTheme.system.rawValue

    /// Lit une valeur stockee. Absente, inconnue ou archivee : `defaultTheme`.
    static func resolved(_ raw: String?) -> AppTheme {
        guard let raw, let theme = AppTheme(rawValue: raw), theme.isSelectable else { return defaultTheme }
        return theme
    }

    /// Libelle du choix dans le reglage de luminosite. "Système" devient une phrase
    /// qui dit ce que fait le choix.
    var brightnessLabel: String {
        switch self {
        case .system: return "Suivre l'appareil"
        case .classic: return "Clair"
        case .dark: return "Sombre"
        default: return label
        }
    }
}

extension AppPalette {
    /// Defaut de l'app : Liquid Glass en couleurs.
    static let defaultPalette: AppPalette = .color
    /// Valeur brute a donner a chaque `@AppStorage(AppStorageKeys.appPalette)`.
    static let defaultRaw: String = AppPalette.color.rawValue

    static func resolved(_ raw: String?) -> AppPalette {
        guard let raw, let palette = AppPalette(rawValue: raw) else { return defaultPalette }
        return palette
    }
}

/// Les quatre apparences : luminosite (clair/sombre) x palette (couleurs/neutre).
/// "Suivre l'appareil" n'est pas une cinquieme apparence : c'est le choix de laisser
/// l'appareil decider du clair ou du sombre, la palette restant la sienne.
struct AppearanceLook: Hashable, Identifiable, CaseIterable {
    let scheme: ColorScheme
    let palette: AppPalette

    var id: String { "\(scheme == .dark ? "dark" : "light")-\(palette.rawValue)" }

    static let allCases: [AppearanceLook] = [
        .init(scheme: .light, palette: .color), .init(scheme: .dark, palette: .color),
        .init(scheme: .light, palette: .neutral), .init(scheme: .dark, palette: .neutral)
    ]

    var label: String {
        "\(scheme == .dark ? "Sombre" : "Clair") \(palette == .color ? "coloré" : "neutre")"
    }

    /// Theme a stocker quand on choisit cette vignette (fixe le clair ou le sombre).
    var theme: AppTheme { scheme == .dark ? .dark : .classic }

    /// Apparence reellement affichee pour un reglage donne. `deviceScheme` sert
    /// seulement quand le theme suit l'appareil.
    static func current(themeRaw: String?, paletteRaw: String?, deviceScheme: ColorScheme) -> AppearanceLook {
        let theme = AppTheme.resolved(themeRaw)
        return AppearanceLook(scheme: theme.scheme ?? deviceScheme, palette: AppPalette.resolved(paletteRaw))
    }
}
