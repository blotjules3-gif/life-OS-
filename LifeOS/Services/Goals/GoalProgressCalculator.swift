import Foundation
import SwiftData

/// Calcule un % de progression pour un `UserGoal` selon sa nature.
///
/// Approche par heuristique — pour chaque `GoalKind`, une source de vérité
/// différente :
///   - `.weightLoss` : `body.currentWeightKg` vs `body.targetWeightKg`
///   - `.muscleGain` : idem mais delta positif
///   - `.saveMoney` : nombre de mois de tracking (approximatif)
///   - `.sleepBetter` / `.moreProductive` / autres : nombre d'habits
///     complétées cette semaine parmi celles liées au goal
///
/// Retourne nil si aucune progression n'est mesurable (données manquantes).
@MainActor
enum GoalProgressCalculator {

    struct Progress {
        /// Ratio 0.0 - 1.0.
        let ratio: Double
        /// Texte user-facing court ("74 → 72 kg", "3/5 habitudes cette semaine").
        let label: String
    }

    static func progress(for goal: UserGoal, context: ModelContext) -> Progress? {
        switch goal.kind {
        case .weightLoss:      return weightProgress(goal, direction: -1)
        case .muscleGain:      return weightProgress(goal, direction: +1)
        case .sleepBetter, .moreProductive, .eatBetter, .reduceStress, .fitnessGeneral:
            return habitCompletionProgress(goal, context: context)
        case .saveMoney:       return timeElapsedProgress(goal)
        case .custom:          return nil
        }
    }

    // MARK: - Weight (targetWeightKg vs currentWeightKg)

    private static func weightProgress(_ goal: UserGoal, direction: Int) -> Progress? {
        guard let current = ProfileStore.shared.field("body.currentWeightKg"),
              let target = ProfileStore.shared.field("body.targetWeightKg"),
              let currentKg = Double(current.valueString),
              let targetKg = Double(target.valueString) else { return nil }
        // Delta signé selon direction
        let signedDelta = (currentKg - targetKg) * Double(direction)
        // Progression : plus signedDelta est proche de 0, plus on approche.
        if abs(currentKg - targetKg) < 0.3 {
            return Progress(ratio: 1.0, label: String(format: "%.1f kg — atteint", currentKg))
        }
        // Approximation : on ne connaît pas le poids de départ, on utilise 5 kg comme base d'échelle
        let scaleKg: Double = max(abs(currentKg - targetKg), 5)
        let ratio = max(0, 1 - abs(currentKg - targetKg) / scaleKg)
        return Progress(
            ratio: ratio,
            label: String(format: "%.1f → %.1f kg", currentKg, targetKg)
        )
    }

    // MARK: - Habits liées au goal complétées cette semaine

    private static func habitCompletionProgress(_ goal: UserGoal, context: ModelContext) -> Progress? {
        let goalID = goal.id.uuidString
        guard !goalID.isEmpty else { return nil }
        let allHabits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let goalHabits = allHabits.filter { $0.sourceGoalID == goalID && !$0.isArchived }
        guard !goalHabits.isEmpty else { return nil }

        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        var doneCount = 0
        for h in goalHabits {
            if h.completions.contains(where: { $0.date >= weekStart }) {
                doneCount += 1
            }
        }
        let ratio = Double(doneCount) / Double(goalHabits.count)
        return Progress(
            ratio: ratio,
            label: "\(doneCount) / \(goalHabits.count) habitudes cette semaine"
        )
    }

    // MARK: - Temps écoulé (saveMoney — approximation)

    private static func timeElapsedProgress(_ goal: UserGoal) -> Progress? {
        guard let deadline = goal.deadline else {
            // Objectif continu, on montre juste la durée d'activation
            let days = Calendar.current.dateComponents([.day], from: goal.createdAt, to: .now).day ?? 0
            return Progress(ratio: 0, label: "Actif depuis \(days) j — mesure manuelle")
        }
        let total = deadline.timeIntervalSince(goal.createdAt)
        let elapsed = Date().timeIntervalSince(goal.createdAt)
        let ratio = min(1, max(0, elapsed / total))
        let days = Calendar.current.dateComponents([.day], from: .now, to: deadline).day ?? 0
        return Progress(ratio: ratio, label: "Reste \(days) j")
    }
}
