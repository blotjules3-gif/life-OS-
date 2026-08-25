import WidgetKit
import SwiftUI

@main
struct LifeOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AlarmActivityWidget()
        HabitsWidget()
        FoodScanWidget()
        EnergyScoreWidget()
        CoachQuickAskWidget()   // Loop 18 — raccourci coach
        if #available(iOS 16.1, *) {
            StreakActivityWidget()
        }
        if #available(iOS 17.0, *) {
            InteractiveHabitsWidget()
        }
        if #available(iOS 18.0, *) {
            FoodScanControlWidget()
        }
    }
}
