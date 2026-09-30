import Foundation

/// Cles du groupe d'apps partagees par l'app (qui ecrit) et les widgets (qui lisent).
/// UN seul endroit : le widget d'hydratation lisait "water_today_ml" alors que l'app
/// ecrivait "today_water_ml", et le widget de jeune lisait une cle que rien n'ecrivait.
/// Les deux affichaient donc des valeurs inventees (1800 ml, 14,5 h).
enum WidgetKeys {
    static let waterToday = "today_water_ml"      // aussi lu par le contexte du coach
    static let waterDay = "today_water_day"
    static let waterGoal = "water_goal_ml"
    static let fastStart = "fast_start_ts"        // 0 ou absent = pas de jeune en cours
    static let fastTarget = "fast_target_h"
    static let gymTitle = "gym_today_title"
    static let gymFocus = "gym_today_focus"
    static let gymRest = "gym_today_is_rest"
    static let gymDay = "gym_today_day"
    static let tabataName = "tabata_last_preset"
    static let tabataWork = "tabata_work"
    static let tabataRest = "tabata_rest"
    static let tabataSets = "tabata_sets"

    /// Jour local "yyyy-MM-dd" : une valeur "du jour" ecrite hier ne s'affiche pas aujourd'hui.
    static func dayStamp(_ date: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Eau du jour telle que le widget doit l'afficher : 0 si la valeur date d'un autre jour.
    static func waterForToday(value: Int, day: String?, now: Date = .now) -> Int {
        day == dayStamp(now) ? max(0, value) : 0
    }
}
