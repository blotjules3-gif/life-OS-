import WidgetKit
import SwiftUI

@main
struct LifeOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AlarmActivityWidget()
        HabitsWidget()
        FoodScanWidget()
        EnergyScoreWidget()
        if #available(iOS 16.1, *) {
            StreakActivityWidget()
        }
        if #available(iOS 18.0, *) {
            FoodScanControlWidget()
        }
    }
}
