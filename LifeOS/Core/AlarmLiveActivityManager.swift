import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
final class AlarmLiveActivityManager {
    static let shared = AlarmLiveActivityManager()

    private var activity: Activity<AlarmAttributes>?

    private init() {}

    /// Démarre le widget Lock Screen dès que l'alarme est programmée.
    /// S'affiche toute la nuit jusqu'à ce que le réveil sonne.
    func startScheduled(alarmTimeString: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end() // ferme l'éventuelle LA précédente proprement

        let attrs = AlarmAttributes(startTime: .now)
        let state = AlarmAttributes.ContentState(
            phase: .scheduled,
            timeString: alarmTimeString,
            message: "Écoute ce que tu as de prévu et déverouille pour suivre le reste."
        )
        // Durée max 8h — couvre une nuit de sommeil
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(8 * 3600))
        activity = try? Activity.request(attributes: attrs, content: content)
    }

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else {
            // LA already running (scheduled phase) — just update to ringing
            update(phase: .ringing, message: "Réveil en cours…")
            return
        }
        let attrs = AlarmAttributes(startTime: .now)
        let state = AlarmAttributes.ContentState(
            phase: .ringing,
            timeString: currentTimeString(),
            message: "Réveil en cours…"
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(120))
        activity = try? Activity.request(attributes: attrs, content: content)
    }

    func update(phase: AlarmAttributes.ContentState.Phase, message: String = "") {
        guard let activity else { return }
        let state = AlarmAttributes.ContentState(
            phase: phase,
            timeString: currentTimeString(),
            message: message
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(60))
        Task { await activity.update(content) }
    }

    func end() {
        guard let act = activity else { return }
        activity = nil
        let state = AlarmAttributes.ContentState(
            phase: .dismissed,
            timeString: currentTimeString(),
            message: "Bonne journée !"
        )
        let content = ActivityContent(state: state, staleDate: nil)
        // Garde le widget visible 30 min — l'utilisateur peut taper pour ouvrir le briefing
        // après s'être levé et habillé
        Task { await act.end(content, dismissalPolicy: .after(.now.addingTimeInterval(30 * 60))) }
    }

    private func currentTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: .now)
    }
}
