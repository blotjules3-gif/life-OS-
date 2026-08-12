import Foundation
import SwiftData
import WidgetKit

/// Rejoue dans SwiftData les toggles d'habitudes faits depuis le widget
/// interactif. Le widget ne peut pas écrire dans SwiftData directement,
/// donc il pousse une file d'attente dans App Group defaults —
/// on la vide ici au next foreground de l'app.
///
/// À appeler dans `LifeOSApp` sur `didBecomeActiveNotification`.
@MainActor
enum WidgetToggleReconciler {

    private static let pendingKey = "widget_pending_toggles"

    static func drainAndApply(ctx: ModelContext) {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app") else { return }
        guard let pending = grp.array(forKey: pendingKey) as? [[String: Any]], !pending.isEmpty else {
            return
        }
        // On flush la liste avant de traiter — évite les doublons si l'app
        // est relancée en cours de traitement.
        grp.removeObject(forKey: pendingKey)

        let cal = Calendar.current
        for entry in pending {
            guard let name = entry["habitName"] as? String else { continue }
            let ts = entry["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
            let date = Date(timeIntervalSince1970: ts)

            // Trouve l'habitude et applique le toggle du jour correspondant.
            let descriptor = FetchDescriptor<Habit>(
                predicate: #Predicate { $0.name == name }
            )
            guard let habits = try? ctx.fetch(descriptor), let habit = habits.first else {
                continue
            }
            let day = cal.startOfDay(for: date)
            if let existing = habit.completions.first(where: {
                cal.isDate($0.date, inSameDayAs: day)
            }) {
                ctx.delete(existing)
            } else {
                habit.completions.append(HabitCompletion(date: date))
            }
        }

        do { try ctx.save() } catch { AppLog.data.error("WidgetToggleReconciler save failed: \(error.localizedDescription, privacy: .public)") }
    }
}
