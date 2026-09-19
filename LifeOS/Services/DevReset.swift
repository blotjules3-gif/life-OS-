#if DEBUG
import Foundation
import SwiftUI

/// Reset dev — remet toute la config coach à zéro pour tester le flow depuis
/// le tout premier lancement.
///
/// Uniquement disponible en DEBUG (jamais dans les builds prod TestFlight/App Store).
///
/// Ce qui est effacé :
///   1. `coachDisclaimerAccepted` (AppStorage) → réaffiche le disclaimer
///   2. `coachOnboardingCompleted` (AppStorage) → réaffiche CoachFirstLaunchSheet
///   3. `AIProviderPreference` → efface la préférence de provider actif
///   4. Toutes les clés Keychain via `AIProviderCredentials` (8 slots)
///   5. Tous les providers custom via `CustomProviderStore`
///   6. Les compteurs d'usage du tracker (repartir à 0 requêtes / 0 €)
///
/// Ce qui N'est PAS effacé (volontairement — pour ne pas perdre les data de vie) :
///   - Habitudes, objectifs, sommeil, humeur, nutrition, sport
///   - Historique des conversations (SwiftData `AIMessage`)
///   - Profil utilisateur, thème, préférences UI
///
/// Utilisation depuis un bouton in-app en DEBUG :
///   ```
///   Button("Reset coach (DEV)") { DevReset.resetCoach() }
///   ```
@MainActor
enum DevReset {

    /// Reset complet de toute la config coach. Le prochain ouverture du chat
    /// affichera le disclaimer → onboarding → gate → chat.
    static func resetCoach() {
        let defaults = UserDefaults.standard

        // 1-2. Flags AppStorage
        defaults.removeObject(forKey: AppStorageKeys.coachDisclaimerAccepted)
        defaults.removeObject(forKey: AppStorageKeys.coachOnboardingCompleted)

        // 3. Préférence provider active
        AIProviderPreference.shared.clearPreference()

        // 4. Toutes les clés Keychain (8 slots cloud)
        for slot in AIProviderCredentials.Slot.allCases {
            AIProviderCredentials.shared.deleteKey(for: slot)
        }

        // 5. Providers custom
        let customs = CustomProviderStore.shared.configs.map { $0.id }
        for id in customs {
            CustomProviderStore.shared.delete(id)
        }

        AppLog.coach.info("DevReset.resetCoach() completed — user should re-onboard on next chat open")
    }

    /// Reset UNIQUEMENT le gate de connexion (garde le disclaimer + onboarding
    /// déjà validés). Pratique pour tester juste le flow "Connecte ton coach"
    /// sans refaire le disclaimer à chaque fois.
    static func resetConnectGate() {
        AIProviderPreference.shared.clearPreference()
        for slot in AIProviderCredentials.Slot.allCases {
            AIProviderCredentials.shared.deleteKey(for: slot)
        }
        AppLog.coach.info("DevReset.resetConnectGate() — user should see CoachConnectGate on next chat open")
    }
}
#endif
