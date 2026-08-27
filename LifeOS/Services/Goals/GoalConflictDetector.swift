import Foundation
import SwiftData

/// Détecte les tensions potentielles entre plusieurs objectifs actifs pour
/// aider l'user à arbitrer avant de créer un nouveau plan.
///
/// Implémentation simple (règles déterministes) — le vrai arbitrage reste
/// à l'user, on lui donne juste la visibilité.
///
/// M1 audit fix.
@MainActor
enum GoalConflictDetector {

    struct Conflict {
        let existingGoal: UserGoal
        let newGoalKind: GoalKind
        let severity: Severity
        /// Message court user-facing.
        let message: String

        enum Severity: String {
            case info, warning, hard
        }
    }

    /// Retourne les conflits potentiels entre un objectif candidat et les
    /// objectifs actifs existants. Vide = aucun conflit.
    static func conflicts(for newKind: GoalKind, context: ModelContext) -> [Conflict] {
        let existing = (try? context.fetch(FetchDescriptor<UserGoal>(
            predicate: #Predicate { $0.statusRaw == "active" }
        ))) ?? []

        var out: [Conflict] = []
        for g in existing {
            guard let existingKind = GoalKind(rawValue: g.kindRaw) else { continue }
            if let conflict = detect(existing: g, existingKind: existingKind, newKind: newKind) {
                out.append(conflict)
            }
        }
        return out
    }

    private static func detect(existing: UserGoal, existingKind: GoalKind, newKind: GoalKind) -> Conflict? {
        // Perte de poids + prise muscle simultané = programme contradictoire
        if (existingKind == .weightLoss && newKind == .muscleGain) ||
           (existingKind == .muscleGain && newKind == .weightLoss) {
            return Conflict(
                existingGoal: existing, newGoalKind: newKind, severity: .warning,
                message: "Perte de poids et prise de muscle en même temps = résultat lent sur les deux. Recomposition corporelle = ok, mais plus long."
            )
        }
        // Économiser + prise muscle = régime protéiné coûteux
        if (existingKind == .saveMoney && newKind == .muscleGain) ||
           (existingKind == .muscleGain && newKind == .saveMoney) {
            return Conflict(
                existingGoal: existing, newGoalKind: newKind, severity: .info,
                message: "Prise de muscle demande +250-500 kcal/j (souvent en protéines) — impact budget alimentation à prévoir."
            )
        }
        // Mieux dormir + plus productif tard le soir = tension horaire
        if (existingKind == .sleepBetter && newKind == .moreProductive) ||
           (existingKind == .moreProductive && newKind == .sleepBetter) {
            return Conflict(
                existingGoal: existing, newGoalKind: newKind, severity: .info,
                message: "Focus tard le soir peut retarder le coucher. Priorise deep work le matin."
            )
        }
        // Même kind exact = redondance
        if existingKind == newKind {
            return Conflict(
                existingGoal: existing, newGoalKind: newKind, severity: .hard,
                message: "Tu as déjà un objectif \"\(existingKind.displayName)\" actif. Modifie-le plutôt que d'en créer un doublon."
            )
        }
        return nil
    }
}
