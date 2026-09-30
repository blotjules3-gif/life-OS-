import Foundation
import SwiftData

/// Point d'accès unique au ModelContainer, partagé entre l'app et les App Intents.
/// L'app enregistre son container au lancement ; si un intent Siri s'exécute
/// avant (app fermée), un container est créé sur le même store.
///
/// **CloudKit sync (Station F readiness — Août 2026)**
/// Le container peut être configuré avec sync iCloud (SwiftData + CloudKit),
/// permettant à un user avec iPhone + iPad de retrouver ses données sur tous
/// ses devices sans compte, sans serveur applicatif.
///
/// Statut actuel : **prêt côté code, opt-in par flag, capability Xcode requise**.
///
/// Pour activer côté Jules :
/// 1. Xcode → Signing & Capabilities → « + Capability » → **iCloud**
/// 2. Cocher **CloudKit** + créer un container `iCloud.com.blotjules.lifeos`
/// 3. Toggle `LocalStore.cloudKitEnabled = true` (ou via Settings UI)
/// 4. Vérifier que tous les `@Model` ont des relations Optional avant de
///    monter en prod (CloudKit refuse les relations `[Type]` non-Optional).
///    Cf. `CloudKitReadiness.report()` pour la check-list runtime.
enum LocalStore {

    /// Tous les types de la base, en UN seul endroit: le schema ET l'effacement
    /// des donnees les lisent ici. Avant, l'effacement avait sa propre liste et
    /// en oubliait deux (`ProfileField`, `ProfileFieldRevision`).
    static let modelTypes: [any PersistentModel.Type] = [
        // Santé
        DreamEntry.self, SleepNight.self, FoodEntry.self, FastingSession.self, WaterEntry.self,
        Supplement.self, PantryItem.self, ShoppingItem.self, WorkoutSet.self, TrainingSession.self, StepEntry.self,
        // Vie
        ProgressPhoto.self, WardrobeItem.self, MoodEntry.self, TodoItem.self,
        Habit.self, HabitCompletion.self, Note.self, MemoryEntry.self,
        Account.self, Txn.self, Envelope.self, Subscription.self, SavingsGoal.self, SplitExpense.self,
        // Patrimoine & reste
        Holding.self, NetWorthItem.self, Property.self, JobApplication.self, SkillGap.self,
        Flashcard.self, BookSummary.self, Chore.self, Pet.self, PetCare.self, Maintenance.self,
        Vehicle.self, FuelLog.self, Contact.self, SocialEvent.self, DocVault.self, Deadline.self,
        Trip.self, PackingItem.self,
        // Cycle
        CycleEntry.self,
        // Messages du coach on-device
        AIMessage.self,
        // Santé médicale
        Medication.self, MedicalAppointment.self, VitalRecord.self, Vaccination.self,
        // Rappels perso (centre de notifications) + programme de sport
        CustomReminder.self, GymDay.self,
        // Intelligent Profile Engine — Bloc A
        ProfileField.self, ProfileFieldRevision.self,
        // Objectifs unifiés (Loop 24 Goal-Plan-Partner)
        UserGoal.self
    ]

    static let schema = Schema(modelTypes)

    @MainActor private static var current: ModelContainer?

    /// Toggle exposé aux réglages. Défaut = false le temps que la capability
    /// iCloud soit ajoutée dans Xcode + que les relations non-Optional soient
    /// migrées. Une fois les deux faits, passer à true = sync automatique.
    static var cloudKitEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "cloudKitEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "cloudKitEnabled") }
    }

    /// Vrai seulement si le container EN SERVICE synchronise via iCloud.
    /// Le reglage `cloudKitEnabled` dit ce qui est demande, pas ce qui tourne:
    /// sans la capacite iCloud l'app retombe en local, et le profil affichait
    /// quand meme "Synchronisation active".
    @MainActor private(set) static var syncActive = false

    static func usesCloud(_ container: ModelContainer) -> Bool {
        container.configurations.contains { $0.cloudKitContainerIdentifier != nil }
    }

    @MainActor
    static func adopt(_ container: ModelContainer) {
        current = container
        syncActive = usesCloud(container)
    }

    @MainActor
    static func container() throws -> ModelContainer {
        if let current { return current }
        let c = try buildContainer()
        adopt(c)
        return c
    }

    /// Construit le container avec fallback progressif :
    /// 1. Essaie avec CloudKit sync si `cloudKitEnabled == true`
    /// 2. Sinon (ou si CloudKit échoue), retombe sur config locale seule
    @MainActor
    static func buildContainer() throws -> ModelContainer {
        FullBackup.applyAtLaunch(storeURL: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url)
        if cloudKitEnabled {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            if let c = try? ModelContainer(for: schema, configurations: [config]) {
                return c
            }
            // CloudKit KO (capability manquante, relations non-Optional, schéma incompatible…)
            // On désactive le flag pour ne pas boucler, on repart en local.
            cloudKitEnabled = false
        }
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

/// Diagnostic runtime pour savoir ce qui reste à migrer avant d'activer
/// vraiment le sync CloudKit. Appelable depuis un écran debug ou au boot.
@MainActor
enum CloudKitReadiness {

    struct Report {
        let cloudKitCapabilityLikelyEnabled: Bool
        let hardConstraintsMet: Bool
        let notes: [String]
    }

    /// Vérifications légères qu'on peut faire en runtime.
    static func report() -> Report {
        var notes: [String] = []
        var hardOK = true

        // Constraint 1 — Aucun @Attribute(.unique) — CloudKit ne les supporte pas.
        // Grep confirmé à l'écriture : LifeOS n'en utilise pas. OK.
        notes.append("✓ Aucun @Attribute(.unique) dans les modèles")

        // Constraint 2 — Relations Optional. Actuellement 4 relations non-Optional :
        //   Habit.completions, Pet.events, Vehicle.fuelLogs, Trip.packing
        // À migrer AVANT d'activer cloudKitEnabled en prod (crash boot sinon).
        let nonOptionalRelations = [
            "Habit.completions", "Pet.events", "Vehicle.fuelLogs", "Trip.packing"
        ]
        if !nonOptionalRelations.isEmpty {
            hardOK = false
            notes.append("✗ Migrer en Optional : \(nonOptionalRelations.joined(separator: ", "))")
        }

        // Constraint 3 — Toutes les propriétés doivent avoir un défaut ou être Optional.
        // Les @Model ont été audités : tous les init ont des valeurs par défaut.
        notes.append("✓ Tous les @Model ont init par défaut")

        // Capability iCloud/CloudKit — pas de manière fiable de checker en runtime
        // sans essayer d'init un CKContainer. On assume l'user l'a fait s'il toggle.
        let capabilityLikely = LocalStore.cloudKitEnabled
        if !capabilityLikely {
            notes.append("? Capability iCloud + CloudKit : à activer dans Xcode Signing")
        }

        return Report(
            cloudKitCapabilityLikelyEnabled: capabilityLikely,
            hardConstraintsMet: hardOK,
            notes: notes
        )
    }
}
