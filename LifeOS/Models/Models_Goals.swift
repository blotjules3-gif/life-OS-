import Foundation
import SwiftData

/// Objectif utilisateur unifié — représente un but personnel de haut niveau
/// (perdre du poids, prendre du muscle, mieux dormir, économiser, etc.).
///
/// Distinct de `SavingsGoal` (spécifique finance) et de `body.targetWeightKg`
/// (ProfileField data point). `UserGoal` = le vrai objectif produit qui
/// génère un plan multi-catégories.
///
/// Loop 24 — fondation Goal-Plan-Partner architecture.
@Model final class UserGoal {
    var id: UUID = UUID()
    var title: String = ""
    /// Type d'objectif — clé qui détermine quel template plan appliquer.
    /// Voir `GoalKind` enum.
    var kindRaw: String = "custom"
    /// Valeur cible optionnelle (5 pour "perdre 5 kg", 300 pour "économiser 300€/mois").
    var targetValue: Double = 0
    /// Unité de la target (kg, €, h, séances/sem…).
    var targetUnit: String = ""
    /// Deadline optionnelle — nil = "objectif continu".
    var deadline: Date?
    /// Budget mensuel optionnel en euros (0 = pas de contrainte budget).
    var monthlyBudget: Double = 0
    /// Contraintes textuelles saisies par l'user ("pas le weekend", "sans matériel").
    var constraints: String = ""
    /// Statut — voir `GoalStatus`.
    var statusRaw: String = "active"
    /// Date de création + dernière update pour tri.
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Snapshot texte du plan appliqué (pour affichage progression).
    var appliedPlanSummary: String = ""

    init(
        id: UUID = UUID(),
        title: String = "",
        kindRaw: String = "custom",
        targetValue: Double = 0,
        targetUnit: String = "",
        deadline: Date? = nil,
        monthlyBudget: Double = 0,
        constraints: String = "",
        statusRaw: String = "active",
        appliedPlanSummary: String = ""
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kindRaw
        self.targetValue = targetValue
        self.targetUnit = targetUnit
        self.deadline = deadline
        self.monthlyBudget = monthlyBudget
        self.constraints = constraints
        self.statusRaw = statusRaw
        self.createdAt = Date()
        self.updatedAt = Date()
        self.appliedPlanSummary = appliedPlanSummary
    }

    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue; updatedAt = Date() }
    }
}

// MARK: - Enums

/// Type d'objectif — chaque type mappe vers un template de plan.
enum GoalKind: String, CaseIterable, Codable {
    case weightLoss       // perdre du poids
    case muscleGain       // prendre du muscle
    case sleepBetter      // améliorer le sommeil
    case moreProductive   // plus productif / focus
    case eatBetter        // mieux manger
    case saveMoney        // économiser
    case reduceStress     // gérer le stress
    case fitnessGeneral   // se remettre au sport
    case custom           // objectif libre

    var displayName: String {
        switch self {
        case .weightLoss:      return "Perdre du poids"
        case .muscleGain:      return "Prendre du muscle"
        case .sleepBetter:     return "Mieux dormir"
        case .moreProductive:  return "Plus productif"
        case .eatBetter:       return "Mieux manger"
        case .saveMoney:       return "Économiser"
        case .reduceStress:    return "Gérer le stress"
        case .fitnessGeneral:  return "Reprendre le sport"
        case .custom:          return "Objectif personnel"
        }
    }

    var icon: String {
        switch self {
        case .weightLoss:     return "figure.walk"
        case .muscleGain:     return "figure.strengthtraining.traditional"
        case .sleepBetter:    return "moon.stars.fill"
        case .moreProductive: return "brain.head.profile"
        case .eatBetter:      return "fork.knife"
        case .saveMoney:      return "eurosign.circle.fill"
        case .reduceStress:   return "leaf.fill"
        case .fitnessGeneral: return "figure.run"
        case .custom:         return "target"
        }
    }
}

enum GoalStatus: String, Codable {
    case active
    case paused
    case achieved
    case abandoned
}
