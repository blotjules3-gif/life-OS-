import Foundation

#if DEBUG
/// Drapeaux de lancement reserves a la verification visuelle et aux captures
/// d'ecran. Absents des builds Release.
///
/// **Pourquoi un seul endroit.** Le meme besoin portait deux noms,
/// `-noPrompts` et `-skipPermissionPrompts`, chacun lu a un endroit different.
/// Lancer avec l'un laissait passer l'alerte gardee par l'autre, et une alerte
/// systeme assombrit tout l'ecran, donc la capture est inutilisable. Un seul
/// point de verite, et ajouter un appelant ne peut plus oublier le garde.
enum DebugLaunchFlags {
    private static let args = ProcessInfo.processInfo.arguments

    static func has(_ flag: String) -> Bool { args.contains(flag) }

    /// Valeur qui suit un drapeau, par exemple `-shotTab home`.
    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Aucune alerte de permission ne doit s'afficher.
    static var suppressesPermissionPrompts: Bool {
        has("-noPrompts") || has("-skipPermissionPrompts")
            || has("-desktop") || has("-glassGallery")
    }
}
#endif
