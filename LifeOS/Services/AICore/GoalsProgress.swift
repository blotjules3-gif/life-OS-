import Foundation

/// Calcule les objectifs actifs de l'user + leur % de progression, pour
/// injection dans le contexte coach.
///
/// Pourquoi : sans cette info, le coach ne peut pas dire "il te reste X
/// pour ton objectif poids" ni "tu es à mi-parcours de ton objectif fitness".
/// Un vrai coach suit activement les progrès.
///
/// Sources actuelles (basé sur ProfileField existants) :
///   - Objectif poids : `body.targetWeightKg` vs `body.currentWeightKg`
///   - Fréquence sport : `fitness.gymFrequency` (cible/semaine)
///   - Km course/semaine : `fitness.weeklyRunKm`
///   - Objectif kcal : `nutrition.kcalGoal`
///   - Objectif protéines : `nutrition.proteinGoal`
///
/// Skip silencieux si la donnée n'est pas renseignée — pas de bruit.
@MainActor
enum GoalsProgress {

    struct Goal {
        let label: String
        let currentValue: Double?
        let targetValue: Double
        let unit: String
        /// Progression 0.0-1.0 si mesurable, `nil` sinon (objectif de fréquence).
        let progressRatio: Double?
    }

    static func activeGoals() -> [Goal] {
        var goals: [Goal] = []

        // Objectif poids (le plus courant)
        if let target = readDouble("body.targetWeightKg") {
            let current = readDouble("body.currentWeightKg")
            let ratio: Double? = {
                guard let c = current else { return nil }
                // Si l'user veut perdre : progression = (start - current) / (start - target)
                // On n'a pas le start, on prend la valeur absolue de l'écart relatif.
                let delta = abs(target - c)
                // Simplification : si écart < 0.5 kg, on considère atteint.
                if delta < 0.5 { return 1.0 }
                // Ratio inverse : plus l'écart est grand, moins on est proche.
                return max(0, 1 - delta / max(abs(target), 1))
            }()
            goals.append(Goal(
                label: "Objectif poids",
                currentValue: current,
                targetValue: target,
                unit: "kg",
                progressRatio: ratio
            ))
        }

        // Fréquence salle (cible/semaine)
        if let target = readDouble("fitness.gymFrequency") {
            goals.append(Goal(
                label: "Fréquence sport",
                currentValue: nil,   // non tracké côté ProfileField
                targetValue: target,
                unit: "séances/sem",
                progressRatio: nil
            ))
        }

        // Km course/semaine
        if let target = readDouble("fitness.weeklyRunKm") {
            goals.append(Goal(
                label: "Course",
                currentValue: nil,
                targetValue: target,
                unit: "km/sem",
                progressRatio: nil
            ))
        }

        // Objectif kcal
        if let target = readDouble("nutrition.kcalGoal") {
            goals.append(Goal(
                label: "Calories",
                currentValue: nil,
                targetValue: target,
                unit: "kcal/j",
                progressRatio: nil
            ))
        }

        // Objectif protéines
        if let target = readDouble("nutrition.proteinGoal") {
            goals.append(Goal(
                label: "Protéines",
                currentValue: nil,
                targetValue: target,
                unit: "g/j",
                progressRatio: nil
            ))
        }

        return goals
    }

    /// Rend un bloc texte prêt à injecter dans le prompt système.
    /// Vide si aucun objectif renseigné.
    static func promptBlock() -> String {
        let goals = activeGoals()
        guard !goals.isEmpty else { return "" }
        var lines = ["Objectifs actifs :"]
        for g in goals {
            if let ratio = g.progressRatio, let current = g.currentValue {
                let pct = Int((ratio * 100).rounded())
                lines.append("- \(g.label) : \(fmt(current)) / \(fmt(g.targetValue)) \(g.unit) (\(pct) %)")
            } else if let current = g.currentValue {
                lines.append("- \(g.label) : \(fmt(current)) / \(fmt(g.targetValue)) \(g.unit)")
            } else {
                lines.append("- \(g.label) : cible \(fmt(g.targetValue)) \(g.unit)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func readDouble(_ fieldID: String) -> Double? {
        guard let f = ProfileStore.shared.field(fieldID) else { return nil }
        return Double(f.valueString)
    }

    private static func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }
}
