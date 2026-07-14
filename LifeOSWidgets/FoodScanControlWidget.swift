import AppIntents
import SwiftUI
import WidgetKit

/// Bouton « Scan repas » disponible dans le Centre de Contrôle iOS 18+.
///
/// Long-press sur le Centre de Contrôle → « + » → chercher LifeOS. Le tap
/// ouvre l'app en fullScreenCover sur la caméra du module Nutrition
/// (`PhotoCalorieView` avec `autoOpenCamera: true`).
///
/// Passe par le schéma URL `lifeos://scan-food` — pas besoin de partager
/// un AppIntent entre le target widget et le target app.
@available(iOS 18.0, *)
struct FoodScanControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.blotjules.lifeos.foodscan") {
            ControlWidgetButton(
                action: OpenURLIntent(URL(string: "lifeos://scan-food")!)
            ) {
                Label("Scan repas", systemImage: "fork.knife")
            }
        }
        .displayName("Scan repas")
        .description("Photographie une assiette pour logger calories + protéines.")
    }
}
