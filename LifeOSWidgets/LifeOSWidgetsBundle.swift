import WidgetKit
import SwiftUI

@main
struct LifeOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AlarmActivityWidget()
        HabitsWidget()
        FoodScanWidget()
        if #available(iOS 18.0, *) {
            FoodScanControlWidget()
        }
    }
}
