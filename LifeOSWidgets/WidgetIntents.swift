import AppIntents
import Foundation
import WidgetKit

// Actions des widgets interactifs (iOS 17). Elles n'ecrivent JAMAIS dans la base :
// elles deposent un ordre dans la file partagee (`WidgetOps`), que l'app applique
// et acquitte apres une sauvegarde reussie, puis mettent a jour l'affichage tout de
// suite (retour visuel). Meme schema que `SetHabitIntent`.

/// Ajoute de l'eau depuis le widget Hydratation.
@available(iOS 17.0, *)
struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Ajouter de l'eau depuis le widget"
    static let description = IntentDescription("Ajoute une prise d'eau sans ouvrir LifeOS.")
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Quantité (ml)")
    var ml: Int
    /// Total affiche au moment du rendu : avec `renderedAt`, il identifie l'appui.
    /// Deux appuis sur le meme rendu = une seule prise (double appui).
    @Parameter(title: "Total affiché")
    var baseML: Int
    @Parameter(title: "Rendu")
    var renderedAt: Double

    init() {}
    init(ml: Int, baseML: Int, renderedAt: Date) {
        self.ml = ml
        self.baseML = baseML
        self.renderedAt = renderedAt.timeIntervalSince1970
    }

    func perform() async throws -> some IntentResult {
        guard (1...3000).contains(ml) else { return .result() }
        let day = WidgetKeys.dayStamp()
        let id = WidgetOp.waterOpID(day: day, baseML: baseML, amount: ml, renderedAt: Date(timeIntervalSince1970: renderedAt))
        let op = WidgetOp(opID: id, kind: .water, action: .add, amount: ml, source: "widget")
        if try WidgetOps.enqueue(op) {
            WaterWidgetState.applyOptimisticAdd(ml, defaults: LifeOSGroup.defaults)
            WidgetOpsSignal.post()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.hydration)
        return .result()
    }
}

/// Coche ou decoche une tache depuis le widget Taches.
@available(iOS 17.0, *)
struct SetTaskDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Cocher une tâche depuis le widget"
    static let description = IntentDescription("Coche ou décoche une tâche sans ouvrir LifeOS.")
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Identifiant de la tâche")
    var taskID: String
    /// Etat voulu, explicite : un double appui redonne le meme ordre, jamais l'inverse.
    @Parameter(title: "Faite")
    var done: Bool

    init() {}
    init(taskID: String, done: Bool) {
        self.taskID = taskID
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        let op = WidgetOp(kind: .task, targetID: taskID, action: done ? .complete : .uncomplete, source: "widget")
        try WidgetOps.enqueue(op)
        if var snap = WidgetSnapshotStore.read(TasksSnapshot.self, key: TasksSnapshot.key) {
            // Tous les ordres encore en file, pas seulement celui-ci : une ecriture
            // concurrente de l'app ne peut pas effacer un geste.
            for (_, pending) in WidgetOps.pending() where pending.kind == .task { snap = TaskSelection.applying(pending, to: snap) }
            WidgetSnapshotStore.overwrite(snap, key: TasksSnapshot.key)
        }
        WidgetOpsSignal.post()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.tasks)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.agenda)
        return .result()
    }
}
