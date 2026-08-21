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

    /// Setter par slot cloud (typé).
    func setPreferred(_ slot: AIProviderCredentials.Slot) {
        UserDefaults.standard.set(slot.rawValue.replacingOccurrences(of: "ai.credentials.", with: ""), forKey: storageKey)
    }

    /// Setter par providerID brut (utile pour Apple Intelligence qui n'est pas
    /// un slot Keychain).
    func setPreferredProviderID(_ providerID: String) {
        UserDefaults.standard.set(providerID, forKey: storageKey)
    }

    /// Retour à l'auto-selection du router.
    func clearPreference() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Helper de matching côté router — vrai si ce providerID est le préféré.
    func isPreferred(providerID: String) -> Bool {
        guard let pref = preferred else { return false }
        return providerID.contains(pref) || pref == providerID
    }
}
