import Foundation

/// Store de préférence du cap coût user pour les providers cloud.
///
/// Modèle simple :
/// - `dailyCapEUR = 0` (défaut) → aucun cap, tous les providers passent
/// - `dailyCapEUR > 0` → si le cumul du jour (tous providers cloud confondus)
///   atteint ce seuil, les providers cloud sont bloqués jusqu'au prochain
///   changement de jour local. Apple Intelligence + LocalCoach restent actifs.
///
/// UserDefaults uniquement — pas une donnée sensible. Persistance survit à
/// un relaunch mais pas à un uninstall (comportement iOS standard).
@MainActor
final class AICostGuardPreference {
    static let shared = AICostGuardPreference()

    private let capKey = "ai.costguard.dailyCapEUR"
    private let notifiedDayKey = "ai.costguard.lastNotifiedDay"

    private init() {}

    /// Seuil configuré en EUR/jour. `0` = pas de cap actif.
    var dailyCapEUR: Double {
        get { UserDefaults.standard.double(forKey: capKey) }
        set { UserDefaults.standard.set(newValue, forKey: capKey) }
    }

    /// Vrai si le cap est activé (> 0).
    var isEnabled: Bool { dailyCapEUR > 0 }

    /// Retourne le jour "yyyy-MM-dd" où la notif de dépassement a été envoyée
    /// pour la dernière fois — évite de spammer l'user.
    var lastNotifiedDay: String? {
        get { UserDefaults.standard.string(forKey: notifiedDayKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifiedDayKey) }
    }

    /// Reset du cap (utilisé par DataEraser + debug).
    func reset() {
        UserDefaults.standard.removeObject(forKey: capKey)
        UserDefaults.standard.removeObject(forKey: notifiedDayKey)
    }
}
