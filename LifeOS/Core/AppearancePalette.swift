import Foundation

/// Table unique des couleurs de domaine et de statut (lot 8).
///
/// Une paire par token : `light` (plus profonde, lisible sur le verre clair) et `dark`
/// (plus vive, lisible sur le verre sombre). `Theme.<token>` et `AppCategory.tint`
/// lisent CETTE table, et les tests aussi : il n'existe pas de deuxieme copie a tenir
/// a jour.
///
/// Comment elle a ete fixee (mesures, pas gout) :
/// - teintes imposees par le cahier des charges : travail bleu, nutrition vert, sport
///   orange, sommeil violet, finances turquoise, apprentissage indigo ;
/// - aucune catégorie a moins de 7,5 en ecart de couleur CIEDE2000 d'une autre, ni a
///   moins de 10 d'un statut (succes, avertissement, erreur), en clair comme en sombre ;
/// - chaque variante a au moins 3:1 de contraste sur son fond (seuil WCAG 1.4.11 des
///   icones et elements graphiques).
/// `ThemePaletteUniquenessTests` et `ThemeContrastTests` refont ces mesures.
enum DomainPalette {
    struct Pair: Equatable {
        let light: UInt32
        let dark: UInt32
    }

    // Domaines imposes par le cahier des charges
    static let career       = Pair(light: 0x0A60E6, dark: 0x4A93FF) // travail : bleu
    static let nutrition    = Pair(light: 0x3A8A12, dark: 0x6FD94A) // vert feuille
    static let fitness      = Pair(light: 0xD45500, dark: 0xFF8C33) // sport : orange
    static let sleep        = Pair(light: 0x8A2FD1, dark: 0xB57CFF) // violet
    static let finance      = Pair(light: 0x007E86, dark: 0x2CCDD6) // turquoise
    static let learning     = Pair(light: 0x4F3FD9, dark: 0x8C80FF) // indigo

    // Autres domaines, places dans les ecarts restants
    static let productivity = Pair(light: 0x0078B4, dark: 0x45B5F5) // azur
    static let mind         = Pair(light: 0x6B7A00, dark: 0xC4D630) // vert anis
    static let invest       = Pair(light: 0x857600, dark: 0xE8C84A) // or
    static let looks        = Pair(light: 0xA85A3C, dark: 0xE8A184) // terre cuite
    static let home         = Pair(light: 0x80602E, dark: 0xCFA766) // ocre
    static let social       = Pair(light: 0xD6246F, dark: 0xFF6FA8) // rose
    static let admin        = Pair(light: 0x6B6480, dark: 0xADA6C4) // gris lavande
    static let mobility     = Pair(light: 0x5C6B6E, dark: 0xA3B4B8) // gris bleu-vert
    static let travel       = Pair(light: 0x4A6EA0, dark: 0x8FB0DC) // bleu acier
    static let cycle        = Pair(light: 0xB5179E, dark: 0xF06AD8) // magenta
    static let medical      = Pair(light: 0xA8233F, dark: 0xFF8A9E) // framboise, distinct de l'erreur

    // Tokens secondaires (hors catégories)
    static let hydration    = Pair(light: 0x1A6FD0, dark: 0x5CB2FF) // eau
    static let coach        = Pair(light: 0x6E4BD8, dark: 0xA48CFF) // identite du coach

    // Statuts : trois roles distincts
    static let success      = Pair(light: 0x0D8A5A, dark: 0x2ED39A) // emeraude
    static let warning      = Pair(light: 0xA86A00, dark: 0xFFAA2E) // ambre
    static let danger       = Pair(light: 0xD9261C, dark: 0xFF5248) // rouge

    static let statuses: [(name: String, pair: Pair)] = [
        ("success", success), ("warning", warning), ("danger", danger)
    ]

    /// Composantes sRGB 0...1 d'un hex 0xRRGGBB.
    static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
