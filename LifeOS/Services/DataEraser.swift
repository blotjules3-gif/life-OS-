import Foundation
import SwiftData

/// Suppression complète des données utilisateur — requis App Store depuis 2022
/// (guideline 5.1.1(v) : les apps qui créent un compte doivent offrir la
/// suppression). Même sans compte serveur, LifeOS stocke localement des
/// données personnelles (photos, sommeil, humeur, finances) → droit à l'oubli.
///
/// Trois niveaux :
///   • `eraseAllData()` — reset SwiftData + UserDefaults + fichiers + App Group
///   • `exportBackup()` — export JSON avant suppression (offre de sauvegarde)
///   • `eraseAndKeepOnboarding()` — même chose mais garde le flag onboarding
///     pour éviter de refaire tout le flow après reset
enum DataEraser {

    /// Efface tout : modèles SwiftData, UserDefaults, images, App Group, backups.
    /// L'app retourne en état "premier lancement" (onboarding relancé).
    @MainActor
    static func eraseAllData(container: ModelContainer) {
        eraseSwiftData(container: container)
        eraseUserDefaults(keepKeys: [])
        eraseImageStore()
        eraseAppGroup()
        eraseBackups()
        eraseAIArtifacts()
        AppLog.data.info("DataEraser: full erase completed")
    }

    /// Supprime les artefacts IA locaux (feedback coach, sessions activity logger,
    /// coach reports). Séparé pour être appelable indépendamment.
    @MainActor
    static func eraseAIArtifacts() {
        // Feedback store (JSONL)
        CoachFeedbackStore.reset()
        // Coach reports (JSONL)
        if let dir = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) {
            let reportsURL = dir.appendingPathComponent("coach_reports.jsonl")
            try? FileManager.default.removeItem(at: reportsURL)
        }
        // Activity logger (in-memory, cleared au reset)
        AIActivityLogger.shared.clear()
        // Usage tracker cloud (UserDefaults, compteurs jour + coûts)
        AIProviderUsageTracker.shared.resetAll()
        // Cost guard preference (plafond quotidien + jour de notif)
        AICostGuardPreference.shared.reset()
        // Suggestion d'upgrade coach (snooze bannière)
        CoachUpgradeSuggestion.shared.reset()
        // Mode vocal (Loop 16)
        CoachVoiceMode.shared.reset()
        // Bilan mensuel (Loop 20)
        MonthlyReviewScheduler.cancel()
        // Cache UserContextBuilder
        UserContextBuilder.shared.invalidateCache()
        AppLog.data.info("DataEraser: AI artifacts erased")
    }

    /// Idem mais préserve les clés d'onboarding + thème pour éviter de refaire
    /// le tunnel après reset. Utilisé quand l'user veut "recommencer à zéro"
    /// sans perdre son thème préféré.
    @MainActor
    static func eraseAndKeepOnboarding(container: ModelContainer) {
        eraseSwiftData(container: container)
        eraseUserDefaults(keepKeys: [
            AppStorageKeys.onboardingDone,
            AppStorageKeys.appTheme,
            AppStorageKeys.userName,
            AppStorageKeys.userGender,
            AppStorageKeys.lifeProfile,
            AppStorageKeys.recommendedModules
        ])
        eraseImageStore()
        eraseAppGroup()
        eraseBackups()
        AppLog.data.info("DataEraser: erase (kept onboarding) completed")
    }

    // MARK: - Composants privés

    @MainActor
    private static func eraseSwiftData(container: ModelContainer) {
        let ctx = container.mainContext
        do {
            try ctx.delete(model: DreamEntry.self)
            try ctx.delete(model: SleepNight.self)
            try ctx.delete(model: FoodEntry.self)
            try ctx.delete(model: FastingSession.self)
            try ctx.delete(model: WaterEntry.self)
            try ctx.delete(model: Supplement.self)
            try ctx.delete(model: PantryItem.self)
            try ctx.delete(model: ShoppingItem.self)
            try ctx.delete(model: WorkoutSet.self)
            try ctx.delete(model: StepEntry.self)
            try ctx.delete(model: ProgressPhoto.self)
            try ctx.delete(model: WardrobeItem.self)
            try ctx.delete(model: MoodEntry.self)
            try ctx.delete(model: TodoItem.self)
            try ctx.delete(model: Habit.self)
            try ctx.delete(model: HabitCompletion.self)
            try ctx.delete(model: Note.self)
            try ctx.delete(model: MemoryEntry.self)
            try ctx.delete(model: Account.self)
            try ctx.delete(model: Txn.self)
            try ctx.delete(model: Envelope.self)
            try ctx.delete(model: Subscription.self)
            try ctx.delete(model: SavingsGoal.self)
            try ctx.delete(model: UserGoal.self)
            try ctx.delete(model: SplitExpense.self)
            try ctx.delete(model: Holding.self)
            try ctx.delete(model: NetWorthItem.self)
            try ctx.delete(model: Property.self)
            try ctx.delete(model: JobApplication.self)
            try ctx.delete(model: SkillGap.self)
            try ctx.delete(model: Flashcard.self)
            try ctx.delete(model: BookSummary.self)
            try ctx.delete(model: Chore.self)
            try ctx.delete(model: Pet.self)
            try ctx.delete(model: PetCare.self)
            try ctx.delete(model: Maintenance.self)
            try ctx.delete(model: Vehicle.self)
            try ctx.delete(model: FuelLog.self)
            try ctx.delete(model: Contact.self)
            try ctx.delete(model: SocialEvent.self)
            try ctx.delete(model: DocVault.self)
            try ctx.delete(model: Deadline.self)
            try ctx.delete(model: Trip.self)
            try ctx.delete(model: PackingItem.self)
            try ctx.delete(model: CycleEntry.self)
            try ctx.delete(model: AIMessage.self)
            try ctx.delete(model: Medication.self)
            try ctx.delete(model: MedicalAppointment.self)
            try ctx.delete(model: VitalRecord.self)
            try ctx.delete(model: Vaccination.self)
            try ctx.delete(model: CustomReminder.self)
            try ctx.delete(model: GymDay.self)
            try ctx.save()
        } catch {
            AppLog.data.error("DataEraser SwiftData wipe failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func eraseUserDefaults(keepKeys: Set<String>) {
        let ud = UserDefaults.standard
        let all = ud.dictionaryRepresentation()
        for key in all.keys where !keepKeys.contains(key) {
            // Skip clés système Apple (com.apple.*, NSAllowsArbitraryLoads…) pour
            // ne pas casser le runtime iOS.
            if key.hasPrefix("com.apple.") || key.hasPrefix("NS") || key.hasPrefix("Apple") {
                continue
            }
            ud.removeObject(forKey: key)
        }
    }

    private static func eraseImageStore() {
        let fm = FileManager.default
        let dir = ImageStore.dir
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files {
            try? fm.removeItem(at: f)
        }
    }

    private static func eraseAppGroup() {
        guard let defaults = UserDefaults(suiteName: "group.lifeos.app") else { return }
        let all = defaults.dictionaryRepresentation()
        for key in all.keys {
            defaults.removeObject(forKey: key)
        }
    }

    private static func eraseBackups() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
              let contents = try? fm.contentsOfDirectory(at: docs.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        else { return }
        for url in contents where url.lastPathComponent.hasPrefix("LifeOSBackup-") {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Export JSON

    /// Export léger : dump des UserDefaults non-système + compte des entités SwiftData.
    /// Permet à l'user d'avoir un aperçu textuel de ses données avant suppression.
    /// Version 1 : JSON minimal, pas les blobs images.
    @MainActor
    static func exportBackup(container: ModelContainer) -> Data? {
        let ctx = container.mainContext
        var payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: .now),
            "version": 1
        ]

        // UserDefaults (filtrés)
        let ud = UserDefaults.standard.dictionaryRepresentation()
        var udExport: [String: Any] = [:]
        for (k, v) in ud where !k.hasPrefix("com.apple.") && !k.hasPrefix("NS") && !k.hasPrefix("Apple") {
            if v is String || v is NSNumber || v is Bool || v is Int || v is Double {
                udExport[k] = v
            }
        }
        payload["preferences"] = udExport

        // Compte des entités
        var counts: [String: Int] = [:]
        counts["habits"]    = (try? ctx.fetchCount(FetchDescriptor<Habit>())) ?? 0
        counts["moods"]     = (try? ctx.fetchCount(FetchDescriptor<MoodEntry>())) ?? 0
        counts["sleeps"]    = (try? ctx.fetchCount(FetchDescriptor<SleepNight>())) ?? 0
        counts["foods"]     = (try? ctx.fetchCount(FetchDescriptor<FoodEntry>())) ?? 0
        counts["workouts"]  = (try? ctx.fetchCount(FetchDescriptor<WorkoutSet>())) ?? 0
        counts["notes"]     = (try? ctx.fetchCount(FetchDescriptor<Note>())) ?? 0
        counts["todos"]     = (try? ctx.fetchCount(FetchDescriptor<TodoItem>())) ?? 0
        counts["photos"]    = (try? ctx.fetchCount(FetchDescriptor<ProgressPhoto>())) ?? 0
        counts["chatMessages"] = (try? ctx.fetchCount(FetchDescriptor<AIMessage>())) ?? 0
        payload["entityCounts"] = counts

        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
