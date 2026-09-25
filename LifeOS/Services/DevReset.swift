#if DEBUG
import Foundation
import SwiftUI
import SwiftData

/// Reset dev — remet toute la config coach à zéro pour tester le flow depuis
/// le tout premier lancement.
///
/// Uniquement disponible en DEBUG (jamais dans les builds prod TestFlight/App Store).
///
/// Ce qui est effacé par `resetCoach(context:)` :
///   1. `coachDisclaimerAccepted` (AppStorage) → réaffiche le disclaimer
///   2. `coachOnboardingCompleted` (AppStorage) → réaffiche CoachFirstLaunchSheet
///   3. `AIProviderPreference` → efface la préférence de provider actif
///   4. Toutes les clés Keychain via `AIProviderCredentials` (8 slots)
///   5. Tous les providers custom via `CustomProviderStore`
///   6. **Tous les messages de conversation** (`AIMessage` SwiftData) — permet
///      de repartir sur un chat vraiment vide, sinon les anciens messages
///      remontent à chaque ouverture (bug UX vu le 2026-09-25).
///
/// Ce qui N'est PAS effacé (volontairement — pour ne pas perdre les data de vie) :
///   - Habitudes, objectifs, sommeil, humeur, nutrition, sport
///   - Profil utilisateur, thème, préférences UI
///
/// Utilisation depuis un bouton in-app en DEBUG :
///   ```
///   Button("Reset coach (DEV)") { DevReset.resetCoach(context: ctx) }
///   ```
@MainActor
enum DevReset {

    /// Reset complet de toute la config coach + purge de l'historique de
    /// conversation. Le prochain ouverture du chat affichera le disclaimer →
    /// onboarding → gate → chat VIDE.
    ///
    /// - Parameter context: le `ModelContext` SwiftData pour supprimer les
    ///   `AIMessage`. Optionnel — si nil, seul le reset config est fait
    ///   (l'historique de conversation reste, comportement legacy).
    static func resetCoach(context: ModelContext? = nil) {
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

        // 6. Purge conversation (fix bug messages fantômes 2026-09-25)
        if let context {
            purgeConversation(context: context)
        }

        // 7. Purge divers AppStorage liés au chat pour éviter les résidus
        defaults.removeObject(forKey: AppStorageKeys.aiConversationDay)
        defaults.removeObject(forKey: AppStorageKeys.aiConversationID)
        defaults.removeObject(forKey: AppStorageKeys.aiFirstLaunchDone)
        defaults.removeObject(forKey: AppStorageKeys.aiKnownModulesRaw)

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

    /// Purge tous les `AIMessage` stockés dans SwiftData. Utilisé par
    /// `resetCoach(context:)` et exposé séparément pour un fix express
    /// "juste vider la conversation" sans toucher aux clés.
    static func purgeConversation(context: ModelContext) {
        let descriptor = FetchDescriptor<AIMessage>()
        guard let all = try? context.fetch(descriptor) else { return }
        for msg in all { context.delete(msg) }
        try? context.save()
        AppLog.coach.info("DevReset.purgeConversation() — \(all.count, privacy: .public) AIMessage supprimés")
    }
}
#endif
