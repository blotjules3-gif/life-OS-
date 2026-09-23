import WidgetKit
import SwiftUI

@main
struct LifeOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Nouveaux Widgets Clés LifeOS
        TabataWidget()
        HydrationWidget()
        GymFocusWidget()
        SleepWidget()
        FastingWidget()

        // Widgets Existants
        AlarmActivityWidget()
        HabitsWidget()
        FoodScanWidget()
        EnergyScoreWidget()
        CoachQuickAskWidget()

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
