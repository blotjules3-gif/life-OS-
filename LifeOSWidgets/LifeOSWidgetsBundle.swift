import WidgetKit
import SwiftUI

// Le constructeur de bundles accepte un nombre limite d'elements par bloc : les
// widgets sont donc ranges en sous-groupes (10 au plus chacun).

@main
struct LifeOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PriorityWidgets().body
        RoutineWidgets().body
        SystemWidgets().body
        PersonalWidgets().body
    }
}

/// Bourse et widgets photo personnels, chacun configurable par instance.
struct PersonalWidgets: WidgetBundle {
    var body: some Widget {
        StockSingleWidget()
        StockListWidget()
        PortfolioWidget()
        PhotoWidget()
    }
}

/// Priorites du lot 8 : taches, agenda, habitudes, nutrition, hydratation.
struct PriorityWidgets: WidgetBundle {
    var body: some Widget {
        TasksWidget()
        AgendaWidget()
        NutritionWidget()
        HydrationWidget()
        HabitsWidget()
        if #available(iOS 17.0, *) {
            InteractiveHabitsWidget()
        }
    }
}

/// Seances, sommeil, jeune, energie, raccourcis.
struct RoutineWidgets: WidgetBundle {
    var body: some Widget {
        TabataWidget()
        GymFocusWidget()
        SleepWidget()
        FastingWidget()
        EnergyScoreWidget()
        FoodScanWidget()
        CoachQuickAskWidget()
    }
}

/// Live Activities et controles.
struct SystemWidgets: WidgetBundle {
    var body: some Widget {
        AlarmActivityWidget()
        if #available(iOS 16.1, *) {
            StreakActivityWidget()
        }
        if #available(iOS 18.0, *) {
            FoodScanControlWidget()
        }
    }
}
