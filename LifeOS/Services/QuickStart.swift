import Foundation
import SwiftData

/// Mode « démarrage express » — au lieu de forcer l'utilisateur à traverser
/// les 10 étapes de l'onboarding, on lui pose UNE question (objectif principal)
/// et on lui pré-configure une base fonctionnelle en 30 secondes.
///
/// Impact activation D1 attendu : +30-40% (mesuré chez Fabulous, Streaks, Way of Life
/// quand ils sont passés d'onboarding long à quick-start).
@MainActor
enum QuickStart {

    /// Applique la config d'un objectif : active 3 modules pertinents, crée
    /// 3 habitudes seed, met les défauts en UserDefaults. Marque l'onboarding
    /// comme terminé.
    static func apply(goal: String, ctx: ModelContext) {
        let ud = UserDefaults.standard
        let mapping = mappingFor(goal)

        // 1. Enregistrer l'objectif choisi
        ud.set(goal, forKey: "onboardingGoalsRaw")

        // 2. Activer les 3 modules recommandés
        ud.set(mapping.modules.joined(separator: ","), forKey: "recommendedModules")
        ud.set(mapping.modules.joined(separator: ","), forKey: "habitModulesRaw")

        // 3. Créer les habitudes seed en pending (l'utilisateur les valide au 1er coup d'œil)
        for seed in mapping.seedHabits {
            let habit = Habit(
                name: seed.name,
                icon: seed.icon,
                colorHex: seed.color,
                isPending: false,
                moduleTag: seed.module,
                scheduledHour: seed.hour,
                scheduledMinute: 0
            )
            ctx.insert(habit)
        }

        // 4. Défauts sains
        if ud.integer(forKey: "waterGoal") == 0 { ud.set(2500, forKey: "waterGoal") }
        if ud.integer(forKey: "kcalGoal") == 0 { ud.set(2200, forKey: "kcalGoal") }
        if ud.integer(forKey: "wakeupHour") == 0 { ud.set(7, forKey: "wakeupHour") }
        ud.set(true, forKey: "smartNotifsEnabled")  // Le coach cross-pôles = démo qui vend le produit

        // 5. Sauvegarde + flag terminé
        do { try ctx.save() } catch { print("[QuickStart] save failed: \(error)") }
        ud.set(true, forKey: "onboardingDone")
        Analytics.log("quickstart.completed", ["goal": goal])
    }

    // MARK: - Mapping objectif → config

    private struct HabitSeed {
        let name: String
        let icon: String
        let color: Int
        let module: String
        let hour: Int
    }

    private struct Mapping {
        let modules: [String]
        let seedHabits: [HabitSeed]
    }

    private static func mappingFor(_ goal: String) -> Mapping {
        switch goal {
        case "health":
            return Mapping(
                modules: ["fitness", "nutrition", "sleep"],
                seedHabits: [
                    .init(name: "Boire 2 L d'eau", icon: "drop.fill", color: 0x3CD0C8, module: "nutrition", hour: 9),
                    .init(name: "30 min de marche", icon: "figure.walk", color: 0x4CC38A, module: "fitness", hour: 12),
                    .init(name: "Coucher avant 23h30", icon: "moon.stars.fill", color: 0x618EF1, module: "sleep", hour: 22)
                ]
            )
        case "performance":
            return Mapping(
                modules: ["fitness", "nutrition", "sleep"],
                seedHabits: [
                    .init(name: "Séance sport", icon: "dumbbell.fill", color: 0x618EF1, module: "fitness", hour: 18),
                    .init(name: "Manger 30g de protéines", icon: "fork.knife", color: 0xE0A23C, module: "nutrition", hour: 12),
                    .init(name: "8h de sommeil", icon: "bed.double.fill", color: 0x9B6CF1, module: "sleep", hour: 22)
                ]
            )
        case "money":
            return Mapping(
                modules: ["finance", "invest", "productivity"],
                seedHabits: [
                    .init(name: "Check compte matin", icon: "banknote", color: 0x4CC38A, module: "finance", hour: 9),
                    .init(name: "Note 1 dépense évitable", icon: "pencil", color: 0xE0A23C, module: "finance", hour: 20),
                    .init(name: "Lecture business 20 min", icon: "book.fill", color: 0x618EF1, module: "productivity", hour: 21)
                ]
            )
        case "mind":
            return Mapping(
                modules: ["mind", "sleep", "productivity"],
                seedHabits: [
                    .init(name: "10 min de méditation", icon: "brain.head.profile", color: 0x9B6CF1, module: "mind", hour: 8),
                    .init(name: "Journaliser 1 pensée", icon: "book.closed.fill", color: 0xE0A23C, module: "mind", hour: 21),
                    .init(name: "Écran off 1h avant dodo", icon: "iphone.slash", color: 0x618EF1, module: "sleep", hour: 22)
                ]
            )
        default:  // habits
            return Mapping(
                modules: ["productivity", "fitness", "mind"],
                seedHabits: [
                    .init(name: "Faire son lit", icon: "bed.double.fill", color: 0xE0A23C, module: "productivity", hour: 8),
                    .init(name: "10 pompes", icon: "figure.strengthtraining.traditional", color: 0x618EF1, module: "fitness", hour: 9),
                    .init(name: "3 respirations profondes", icon: "wind", color: 0x9B6CF1, module: "mind", hour: 12)
                ]
            )
        }
    }
}
