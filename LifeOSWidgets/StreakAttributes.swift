import ActivityKit
import Foundation

/// Live Activity « Streak en cours » — copie identique du fichier
/// LifeOS/Core/StreakAttributes.swift. Sync groups Xcode ne partagent pas
/// entre targets — on duplique volontairement (même pattern qu'AlarmAttributes).
@available(iOS 16.1, *)
struct StreakAttributes: ActivityAttributes {

    let habitName: String
    let iconName: String

    struct ContentState: Codable, Hashable {
        var streakDays: Int
        var doneToday: Bool
        var milestone: Milestone?

        enum Milestone: String, Codable, Hashable {
            case week
            case twoWeeks
            case month
            case hundred
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
