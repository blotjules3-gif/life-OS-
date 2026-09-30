import AppIntents
import Foundation
import WidgetKit

/// Coche ou decoche une habitude depuis le widget, sans ouvrir LifeOS.
///
/// 1. Un ordre EXPLICITE (cocher / decocher, identifiant stable, jour metier) est
///    ecrit dans sa propre file (`HabitOps`): c'est lui la sauvegarde. L'app
///    l'applique a sa base, puis l'efface seulement apres une sauvegarde reussie.
/// 2. L'instantane affiche est mis a jour tout de suite pour le retour visuel.
@available(iOS 17.0, *)
struct SetHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Cocher une habitude"
    static let description = IntentDescription("Coche ou décoche une habitude depuis le widget, sans ouvrir LifeOS.")

    @Parameter(title: "Identifiant de l'habitude")
    var habitID: String

    @Parameter(title: "Cocher")
    var complete: Bool

    init() {}
    init(habitID: String, complete: Bool) {
        self.habitID = habitID
        self.complete = complete
    }

    func perform() async throws -> some IntentResult {
        let op = HabitOp(habitID: habitID, action: complete ? .complete : .uncomplete, source: "widget")
        try HabitOps.enqueue(op)
        // L'instantane est un lire-modifier-ecrire partage avec l'app: une ecriture
        // concurrente peut en effacer une autre. On y reapplique donc TOUS les ordres
        // du jour encore en file, pas seulement celui-ci: le prochain geste ou la
        // prochaine publication de l'app retablit ce qu'une course aurait efface.
        if var snap = HabitSnapshot.read()?.current() {
            for (_, pendingOp) in HabitOps.pending() where pendingOp.day == snap.day { snap = snap.applying(pendingOp) }
            snap.write()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "InteractiveHabitsWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitsWidget")
        return .result()
    }
}
