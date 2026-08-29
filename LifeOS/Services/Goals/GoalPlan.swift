import Foundation

/// Représentation d'un plan complet généré pour un `UserGoal`.
///
/// Non-persisté (Codable pour serialisation debug/preview). Le plan est
/// généré à la volée par `GoalPlanEngine` puis appliqué par `GoalPlanExecutor`
/// qui crée les Habits, Reminders, ProfileField, active les modules.
///
/// Contrat : le plan doit être **entièrement compréhensible par l'user**
/// avant qu'il valide. C'est le contrat "l'application propose, l'user décide".
struct GoalPlan: Codable {
    let goalKind: GoalKind
    let title: String
    let summary: String
    /// Modules à activer (ex: [.fitness, .nutrition]).
    let modulesToActivate: [String]  // AppCategory rawValue
    let habits: [HabitTemplate]
    let reminders: [ReminderTemplate]
    let profileFields: [ProfileFieldTemplate]
    let recommendations: [Recommendation]

    /// Nombre total d'actions que le plan va appliquer — utilisé pour le
    /// résumé de preview ("Je vais créer 3 habitudes + 2 rappels + activer 2 modules").
    var totalActionCount: Int {
        modulesToActivate.count + habits.count + reminders.count + profileFields.count
    }
}

// MARK: - Habit template

struct HabitTemplate: Codable {
    let name: String
    let icon: String
    let moduleTag: String     // ex: "fitness", "sleep"
    let scheduledHour: Int
    let scheduledMinute: Int
    /// Description user-facing pour la preview.
    let rationale: String
}

// MARK: - Reminder template

struct ReminderTemplate: Codable {
    let title: String
    let message: String
    let categoryRaw: String
    /// Fréquence — enum aligné avec `CustomReminder.Frequency.rawValue`.
    let frequencyRaw: String
    let hour: Int
    let minute: Int
    let intervalHours: Int
    let windowStartHour: Int
    let windowEndHour: Int
    let weekdayMask: Int
    let specificHours: [Int]
}

// MARK: - ProfileField template

struct ProfileFieldTemplate: Codable {
    let fieldID: String
    let value: String
    /// Si `true`, l'executor n'écrit QUE si le champ n'est pas déjà renseigné
    /// (évite d'écraser une valeur user manuelle).
    let onlyIfMissing: Bool
}

// MARK: - Recommendation

/// Recommandation — spec §7 + §14 : chaque reco doit avoir objectif, raison,
/// coût, effort, priorité, alternatives, partenaire éventuel, kind d'action.
///
/// Distinction claire (règle produit) :
///   - `partnerID != nil` = OFFRE partenaire (peut être commerciale, marquée UI)
///   - `partnerID == nil` = RECOMMANDATION NEUTRE (choisie pour l'user)
struct Recommendation: Codable, Identifiable {
    var id: String { title }
    let title: String
    let rationale: String
    let effort: RecommendationEffort
    let estimatedCostEUR: Double?
    /// Partner ID si cette reco vient d'un partenaire (nil = neutre).
    let partnerID: String?
    /// Action possible côté user (ex: "add_habit:méditation" ou "open:https://…").
    let actionKey: String?

    // Loop 26 — spec §7 + §14 champs enrichis

    /// Priorité 1 (critique) → 5 (bonus). Utilisée pour trier l'affichage.
    var priority: Int = 3

    /// Alternatives textuelles proposées à l'user ("Programme maison sans matériel",
    /// "Salle partenaire à 15 €/mois"). Vide = pas d'alternatives.
    var alternatives: [String] = []

    /// Type d'action spec §14 — distinction Information/Recommandation/Prepare/Validate/Execute.
    var kind: RecommendationKind = .recommendation

    enum RecommendationEffort: String, Codable {
        case low, medium, high
    }

    enum RecommendationKind: String, Codable {
        case information    // L'app informe (fait scientifique, principe)
        case recommendation // L'app suggère (défaut pour la plupart)
        case preparation    // L'app prépare une action à valider
        case validation     // L'user doit confirmer (produit financier, engagement)
        case execution      // L'app exécute (nécessite API partenaire opérationnelle)

        var displayLabel: String {
            switch self {
            case .information:    return "Info"
            case .recommendation: return "Conseil"
            case .preparation:    return "À préparer"
            case .validation:     return "À valider"
            case .execution:      return "Exécutable"
            }
        }
    }
}
