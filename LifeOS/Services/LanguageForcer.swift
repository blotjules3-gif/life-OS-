import Foundation

/// Gère l'override de langue de l'app.
///
/// **Comportement** :
/// - `.auto` : iOS choisit selon les préférences système (comportement par défaut)
/// - `.fr` : force le français quelle que soit la langue de l'iPhone
/// - `.en` : force l'anglais quelle que soit la langue de l'iPhone
///
/// **Persistance** : via `AppStorageKeys.appLanguage` (défaut = "auto").
/// **Application** : override iOS via `UserDefaults.standard.set([code], forKey: "AppleLanguages")`.
/// **Effet** : nécessite un redémarrage complet de l'app pour que SwiftUI relise
///   les strings avec la nouvelle locale. L'UI le signale explicitement.
///
/// **État de la traduction** (à date de cette session) :
/// - `Localizable.xcstrings` contient 1134 clés, ~66 traduites en EN (5%)
/// - ~440 `Text("...")` FR encore hardcodés dans le code Swift
/// - Choisir EN aujourd'hui donne un mix EN partiel + FR pour tout ce qui n'est
///   pas extrait. Documenté honnêtement dans `LanguagePickerSheet`.
enum LanguageForcer {

    enum Option: String, CaseIterable, Identifiable {
        case auto, fr, en
        var id: String { rawValue }

        var label: String {
            switch self {
            case .auto: return "Automatique (langue système)"
            case .fr:   return "Français"
            case .en:   return "English"
            }
        }

        var flag: String {
            switch self {
            case .auto: return "globe"
            case .fr:   return "circle.fill"   // couleur bleue via tint
            case .en:   return "circle.fill"   // couleur rouge via tint
            }
        }
    }

    /// Applique le choix persisté à `AppleLanguages` (au boot de l'app).
    /// À appeler tôt dans `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    static func applyPersistedChoice() {
        let raw = UserDefaults.standard.string(forKey: AppStorageKeys.appLanguage) ?? "auto"
        let option = Option(rawValue: raw) ?? .auto
        switch option {
        case .auto:
            // Supprime l'override — iOS reprend son choix natif basé sur les
            // préférences système. Sans cette suppression, un changement de
            // "fr" vers "auto" laisserait fr en place.
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .fr:
            UserDefaults.standard.set(["fr"], forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }

    /// Change le choix + persiste. L'appelant DOIT prévenir l'user qu'un
    /// redémarrage est nécessaire pour appliquer visuellement.
    static func set(_ option: Option) {
        UserDefaults.standard.set(option.rawValue, forKey: AppStorageKeys.appLanguage)
        // Applique tout de suite dans les préférences iOS pour que le prochain
        // lancement démarre déjà avec la bonne locale (même si la session
        // actuelle continue avec l'ancienne).
        applyPersistedChoice()
    }

    /// Choix actuel (par défaut auto).
    static var current: Option {
        Option(rawValue: UserDefaults.standard.string(forKey: AppStorageKeys.appLanguage) ?? "auto") ?? .auto
    }
}
