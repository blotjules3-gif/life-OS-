import Foundation
import SwiftData

/// Applique un `GoalPlan` validé par l'user :
///   1. Active les modules recommandés (union avec `recommendedModules`)
///   2. Crée les habitudes (Habit + toast)
///   3. Crée les rappels (CustomReminder + schedule notifs)
///   4. Écrit les ProfileField (avec option `onlyIfMissing`)
///   5. Persiste `UserGoal` avec summary appliqué
///
/// Chaque étape est **idempotente** — appeler 2x le même plan ne double pas
/// les habitudes existantes (dédup par nom).
///
/// Loop 24.
@MainActor
enum GoalPlanExecutor {

    struct ApplyResult {
        let success: Bool
        let errorMessage: String?
        let modulesActivated: [String]
        let habitsCreated: Int
        let habitsSkippedExisting: Int
        let remindersCreated: Int
        let profileFieldsWritten: Int
        let profileFieldsSkipped: Int

        static func failed(_ message: String) -> ApplyResult {
            ApplyResult(success: false, errorMessage: message,
                       modulesActivated: [], habitsCreated: 0, habitsSkippedExisting: 0,
                       remindersCreated: 0, profileFieldsWritten: 0, profileFieldsSkipped: 0)
        }
    }

    /// Applique le plan et retourne un résumé de ce qui a réellement été fait.
    /// L'user peut voir ce résumé pour comprendre l'impact.
    ///
    /// C3 audit fix — idempotency : si un UserGoal du même kind existe déjà
    /// en `.active` avec la même targetValue, on ne re-crée PAS un doublon.
    /// M6 audit fix — retourne success=false + errorMessage si save() throw.
    static func apply(_ plan: GoalPlan, goal: UserGoal, context: ModelContext) -> ApplyResult {
        // C3 idempotency check
        let existingGoals = (try? context.fetch(FetchDescriptor<UserGoal>(
            predicate: #Predicate { $0.statusRaw == "active" }
        ))) ?? []
        if existingGoals.contains(where: {
            $0.kindRaw == goal.kindRaw && abs($0.targetValue - goal.targetValue) < 0.01
        }) {
            return .failed("Cet objectif est déjà actif — regarde tes objectifs en cours avant d'en créer un nouveau.")
        }

        // 1. Modules
        let activated = activateModules(plan.modulesToActivate)

        // 2. Habits (dédup par name existant)
        let existingHabits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let existingNames = Set(existingHabits.map { $0.name.lowercased() })
        var created = 0, skipped = 0
        for tpl in plan.habits {
            if existingNames.contains(tpl.name.lowercased()) {
                skipped += 1
                continue
            }
            let h = Habit(
                name: tpl.name, icon: tpl.icon,
                colorHex: 0x4CC38A, createdAt: .now,
                isPending: false, isArchived: false,
                moduleTag: tpl.moduleTag,
                scheduledHour: tpl.scheduledHour, scheduledMinute: tpl.scheduledMinute,
                sourceGoalID: goal.id.uuidString   // Loop 25 audit — traçabilité
            )
            context.insert(h)
            created += 1
        }

        // 3. Reminders
        var reminderCount = 0
        for tpl in plan.reminders {
            let r = CustomReminder(
                title: tpl.title, message: tpl.message,
                hour: tpl.hour, minute: tpl.minute,
                enabled: true, confirm: false,
                frequencyRaw: tpl.frequencyRaw,
                intervalHours: tpl.intervalHours,
                windowStartHour: tpl.windowStartHour,
                windowEndHour: tpl.windowEndHour,
                weekdayMask: tpl.weekdayMask,
                specificHoursJSON: (try? String(data: JSONEncoder().encode(tpl.specificHours), encoding: .utf8)) ?? "[]",
                categoryRaw: tpl.categoryRaw
            )
            r.sourceGoalID = goal.id.uuidString   // Loop 25 audit
            context.insert(r)
            SmartReminderScheduler.reschedule(r)
            reminderCount += 1
        }

        // 4. ProfileField
        var writtenFields = 0, skippedFields = 0
        for tpl in plan.profileFields {
            guard !tpl.value.isEmpty else { skippedFields += 1; continue }
            if tpl.onlyIfMissing,
               let existing = ProfileStore.shared.field(tpl.fieldID),
               !existing.valueString.isEmpty {
                skippedFields += 1
                continue
            }
            _ = ProfileStore.shared.upsert(tpl.fieldID, value: tpl.value, source: .chat, confidence: 0.85)
            writtenFields += 1
        }

        // 5. Persist UserGoal + snapshot (M6 fix — vraie gestion erreur)
        goal.appliedPlanSummary = plan.summary
        goal.updatedAt = .now
        context.insert(goal)
        do {
            try context.save()
        } catch {
            return .failed("Impossible d'enregistrer le plan : \(error.localizedDescription). Réessaie.")
        }

        return ApplyResult(
            success: true,
            errorMessage: nil,
            modulesActivated: activated,
            habitsCreated: created,
            habitsSkippedExisting: skipped,
            remindersCreated: reminderCount,
            profileFieldsWritten: writtenFields,
            profileFieldsSkipped: skippedFields
        )
    }

    // MARK: - Modules

    /// Ajoute les modules cibles à `recommendedModules` UserDefaults (union).
    /// Retourne uniquement les modules NOUVELLEMENT activés (déjà présents = skip).
    private static func activateModules(_ modules: [String]) -> [String] {
        let key = "recommendedModules"
        let existing = Set((UserDefaults.standard.string(forKey: key) ?? "")
            .split(separator: ",").map { String($0) })
        let newOnes = modules.filter { !existing.contains($0) }
        guard !newOnes.isEmpty else { return [] }
        let union = existing.union(newOnes)
        UserDefaults.standard.set(union.sorted().joined(separator: ","), forKey: key)
        return newOnes
    }
}
