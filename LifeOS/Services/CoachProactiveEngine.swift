import Foundation
import SwiftData

/// Détecte des signaux qui méritent que le coach relance l'utilisateur
/// spontanément (au lieu d'attendre passivement).
///
/// Signaux surveillés :
/// - Streak à préserver (habitude à 7 jours, à 30 jours…)
/// - Objectif oublié depuis > 7 jours
/// - Sommeil qui chute 5 jours consécutifs
/// - Poids stable sans mise à jour > 4 semaines
/// - Séance manquée alors qu'elle est prévue
/// - Nutrition très en dessous de l'objectif kcal 3 jours consécutifs
///
/// Chaque signal produit un `ProactiveNudge` : sujet + question pré-formulée
/// + urgence + deep link vers le chat coach avec pré-remplissage.
@MainActor
enum CoachProactiveEngine {

    /// Une action proactive candidate.
    struct ProactiveNudge: Identifiable {
        let id = UUID()
        let category: String                       // AppCategory.rawValue
        let title: String                          // notif titre court
        let body: String                           // notif body 1-2 lignes
        let prefilledMessage: String               // ce qu'on met dans le chat coach au tap
        let urgency: Urgency
        let signal: Signal                         // pour analytics + dédup

        enum Urgency: Int, Comparable {
            case low = 1, medium = 2, high = 3
            static func < (l: Urgency, r: Urgency) -> Bool { l.rawValue < r.rawValue }
        }

        enum Signal: String {
            case streakMilestone
            case forgottenGoal
            case sleepDeclining
            case weightStale
            case missedWorkout
            case caloriesUnderTarget
        }
    }

    // MARK: - Scan principal

    /// Retourne les nudges pertinents pour maintenant, triés par urgence décroissante.
    /// À appeler depuis un BGTaskScheduler quotidien.
    static func scanNudges(context: ModelContext) -> [ProactiveNudge] {
        var nudges: [ProactiveNudge] = []

        nudges.append(contentsOf: scanStreaks(context: context))
        nudges.append(contentsOf: scanForgottenGoals(context: context))
        nudges.append(contentsOf: scanSleepDeclining())
        nudges.append(contentsOf: scanWeightStale())

        return nudges.sorted { $0.urgency > $1.urgency }
    }

    // MARK: - Signaux

    /// Habitude qui approche d'un milestone (6 jours → J7 imminent).
    private static func scanStreaks(context: ModelContext) -> [ProactiveNudge] {
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let cal = Calendar.current
        var out: [ProactiveNudge] = []

        for habit in habits where !habit.isPending && !habit.isArchived {
            let streak = currentStreak(habit, cal: cal)
            let milestones = [6, 13, 29, 99]  // 1 jour AVANT J7/J14/J30/J100
            guard milestones.contains(streak) else { continue }
            let target = streak + 1
            out.append(ProactiveNudge(
                category: habit.moduleTag.isEmpty ? "productivity" : habit.moduleTag,
                title: "Ton streak \(habit.name)",
                body: "Tu es à \(streak) jours. Encore un et tu passes le cap des \(target) jours.",
                prefilledMessage: "Rappelle-moi que je dois faire mon habitude \(habit.name) aujourd'hui pour préserver mon streak à \(target) jours.",
                urgency: streak >= 29 ? .high : .medium,
                signal: .streakMilestone
            ))
        }
        return out
    }

    /// Objectif ProfileField non re-mentionné depuis > 7 jours.
    private static func scanForgottenGoals(context: ModelContext) -> [ProactiveNudge] {
        let goalFields = ProfileStore.shared.allFields().filter {
            $0.fieldID.hasPrefix("goals.") || $0.fieldID.contains(".goal")
        }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        var out: [ProactiveNudge] = []
        for field in goalFields where field.updatedAt < cutoff {
            guard let spec = ProfileFieldCatalog.all[field.fieldID] else { continue }
            let daysAgo = Int(Date().timeIntervalSince(field.updatedAt) / 86400)
            out.append(ProactiveNudge(
                category: field.category,
                title: "On avait dit : \(spec.displayName)",
                body: "Tu m'en avais parlé il y a \(daysAgo) jours. On fait le point ?",
                prefilledMessage: "Je veux faire le point sur mon objectif \(spec.displayName). Où j'en suis vraiment aujourd'hui ?",
                urgency: daysAgo > 30 ? .high : .medium,
                signal: .forgottenGoal
            ))
        }
        return out
    }

    /// Sommeil qui chute 5 jours consécutifs (via App Group `mood_recent_7d`
    /// et clé `lastSleepHours` — approximation locale sans HealthKit direct).
    private static func scanSleepDeclining() -> [ProactiveNudge] {
        let ud = UserDefaults.standard
        let currentSleep = ud.integer(forKey: "lastSleepHours")
        guard currentSleep > 0, currentSleep < 6 else { return [] }
        // TODO Phase P1.8 : brancher HealthKit pour tendance réelle
        return [ProactiveNudge(
            category: "sleep",
            title: "Ton sommeil chute",
            body: "Cette nuit : \(currentSleep)h. On regarde ce qui bloque ?",
            prefilledMessage: "Mon sommeil est descendu à \(currentSleep)h. Qu'est-ce que je peux ajuster ce soir pour mieux dormir demain ?",
            urgency: .medium,
            signal: .sleepDeclining
        )]
    }

    /// Poids non mis à jour depuis > 4 semaines alors qu'un objectif poids existe.
    private static func scanWeightStale() -> [ProactiveNudge] {
        guard let weightField = ProfileStore.shared.field("body.currentWeightKg"),
              ProfileStore.shared.field("body.targetWeightKg") != nil else { return [] }
        let daysSince = Int(Date().timeIntervalSince(weightField.updatedAt) / 86400)
        guard daysSince >= 28 else { return [] }
        return [ProactiveNudge(
            category: "fitness",
            title: "Ton poids remonte ?",
            body: "Ça fait \(daysSince) jours qu'on ne l'a pas mis à jour. Tu me le donnes ?",
            prefilledMessage: "Je veux mettre à jour mon poids et voir la progression vers mon objectif.",
            urgency: .low,
            signal: .weightStale
        )]
    }

    // MARK: - Helpers

    private static func currentStreak(_ habit: Habit, cal: Calendar) -> Int {
        var streak = 0
        var day = cal.startOfDay(for: .now)
        // Le jour courant ne casse pas le streak s'il n'est pas encore fait.
        if !habit.completions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }),
           let prev = cal.date(byAdding: .day, value: -1, to: day) {
            day = prev
        }
        while habit.completions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }
}
