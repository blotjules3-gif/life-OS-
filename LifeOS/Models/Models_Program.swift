import Foundation
import SwiftData

// MARK: - Programme genere par Fitbot

/// Un programme applique a la semaine (objectif, frequence, matériel, split).
///
/// Il sert a deux choses : l'historique par semaine de programme (semaine N, seances
/// faites contre prevues) et l'annulation. La semaine d'AVANT est gardee en JSON
/// (`previousWeekJSON`) : annuler la remet telle quelle, meme apres une relance.
/// Les seances passees ne dependent jamais de ce modele (exercices figes dans la
/// `TrainingSession`), donc changer de programme ne touche pas l'historique.
@Model final class GymProgramPlan {
    var createdAt: Date = Date()
    /// `FitbotGoal.rawValue`.
    var goal: String = ""
    var daysPerWeek: Int = 0
    var sessionMinutes: Int = 0
    /// `FitbotEquipment` separes par des virgules.
    var equipment: String = ""
    /// `FitbotSplit.rawValue`.
    var split: String = ""
    /// Semaine remplacee (JSON de `[GymDaySnapshot]`), pour revenir en arriere.
    var previousWeekJSON: String = ""
    /// Rempli quand l'utilisateur annule ce programme : il sort de l'historique.
    var undoneAt: Date? = nil

    init(createdAt: Date = .now, goal: String = "", daysPerWeek: Int = 0, sessionMinutes: Int = 0,
         equipment: String = "", split: String = "", previousWeekJSON: String = "") {
        self.createdAt = createdAt; self.goal = goal; self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes; self.equipment = equipment; self.split = split
        self.previousWeekJSON = previousWeekJSON
    }
}

/// Copie d'un jour de programme, sans lien avec SwiftData : apercu, annulation, tests.
struct GymDaySnapshot: Codable, Equatable {
    var weekday: Int
    var title: String
    var focus: String
    var isRest: Bool
    var supersetsJSON: String = ""

    var exercises: [String] {
        focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
