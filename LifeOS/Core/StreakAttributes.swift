import ActivityKit
import Foundation

/// Live Activity « Streak en cours » — affiche la meilleure série d'habitudes
/// active de l'utilisateur sur le Lock Screen + Dynamic Island.
///
/// Doit être compilé dans le target app ET le target widget.
/// Fichier dupliqué à l'identique dans `LifeOSWidgets/StreakAttributes.swift`.
@available(iOS 16.1, *)
struct StreakAttributes: ActivityAttributes {

    /// Le nom de l'habitude, fixé au moment du start(). Immutable.
    let habitName: String

    /// L'icône SF Symbol, fixée au start.
    let iconName: String

    struct ContentState: Codable, Hashable {
        var streakDays: Int
        var doneToday: Bool
        var milestone: Milestone?

        enum Milestone: String, Codable, Hashable {
            case week      // 7 jours
            case twoWeeks  // 14
            case month     // 30
            case hundred   // 100
        }

        var caption: String {
            switch milestone {
            case .week:      return "7 jours d'affilée — la semaine parfaite"
            case .twoWeeks:  return "14 jours — l'habitude tient"
            case .month:     return "30 jours — c'est ancré"
            case .hundred:   return "100 jours — record"
            case .none:      return doneToday ? "Validé aujourd'hui" : "Reste à cocher"
            }
        }
    }
}
