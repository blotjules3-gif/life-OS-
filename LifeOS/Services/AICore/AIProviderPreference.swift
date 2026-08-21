import Foundation

/// Store léger de la préférence utilisateur : quel provider IA choisir en
/// priorité pour le coach.
///
/// Contrat :
/// - Valeur persistée dans UserDefaults (pas une info sensible)
/// - `nil` = "auto" : le router utilise l'ordre par défaut (Apple Intelligence
///   d'abord, LocalCoach ensuite)
/// - Une valeur explicite (`"openai"`, `"anthropic"`, `"mistral"`, `"gemini"`,
///   `"apple.intelligence.on-device"`) = le router place ce provider EN TÊTE
///   de la chaîne d'essai. Si ce provider échoue (rate limit, offline, clé
///   manquante), le router tombe sur les suivants dans l'ordre par défaut.
///
/// Utilisation :
///   AIProviderPreference.shared.setPreferred(.openai)
///   let pref = AIProviderPreference.shared.preferred   // .openai
///   AIProviderPreference.shared.clearPreference()      // retour "auto"
@MainActor
final class AIProviderPreference {
    static let shared = AIProviderPreference()

    private let storageKey = "ai.provider.preference"

    private init() {}

    /// Retourne la préférence courante, ou `nil` si "auto".
    var preferred: String? {
        UserDefaults.standard.string(forKey: storageKey)
    }

    /// Setter par providerID exact (ex: "openai.gpt", "apple.intelligence.on-device").
    /// Le router matche via égalité stricte pour éviter les faux positifs si
    /// un providerID change de nom sans qu'on mette à jour la préférence.
    func setPreferredProviderID(_ providerID: String) {
        UserDefaults.standard.set(providerID, forKey: storageKey)
    }

    /// Retour à l'auto-selection du router.
    func clearPreference() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
