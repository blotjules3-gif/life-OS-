import AppIntents
import Foundation
import WidgetKit

/// Intent appelé depuis le widget interactif quand l'user tape sur une habitude.
///
/// Le widget vit dans son propre processus — il n'a pas accès direct au
/// SwiftData de l'app. Deux choses se passent :
///
/// 1. Toggle immédiat de `done` dans le JSON `widget_habits` (App Group defaults)
///    → le widget affiche le nouvel état à la prochaine timeline (visuel instantané)
/// 2. Push du nom d'habitude dans `widget_pending_toggles`
///    → l'app rejoue ces toggles dans SwiftData au prochain foreground
///
/// Ce pattern évite d'ouvrir l'app à chaque tap tout en gardant SwiftData
/// comme source de vérité canonique.
@available(iOS 17.0, *)
struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Valider une habitude"
    static let description = IntentDescription(
        "Coche ou décoche une habitude depuis le widget, sans ouvrir LifeOS."
    )

    @Parameter(title: "Nom de l'habitude")
    var habitName: String

    init() {}
    init(habitName: String) {
        self.habitName = habitName
    }

    func perform() async throws -> some IntentResult {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app") else {
            return .result()
        }

        // 1. Flip le flag `done` dans le snapshot widget
        if let data = grp.data(forKey: "widget_habits"),
           var arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for i in arr.indices {
                if arr[i]["name"] as? String == habitName {
                    let current = arr[i]["done"] as? Bool ?? false
                    arr[i]["done"] = !current
                }
            }
            if let newData = try? JSONSerialization.data(withJSONObject: arr) {
                grp.set(newData, forKey: "widget_habits")
            }
        }

        // 2. Enregistrer le toggle pending pour que l'app le rejoue sur SwiftData
        var pending = (grp.array(forKey: "widget_pending_toggles") as? [[String: Any]]) ?? []
        pending.append([
            "habitName": habitName,
            "timestamp": Date().timeIntervalSince1970
        ])
        grp.set(pending, forKey: "widget_pending_toggles")

        // 3. Force le refresh visuel des widgets
        WidgetCenter.shared.reloadTimelines(ofKind: "InteractiveHabitsWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitsWidget")

        return .result()
    }
}
