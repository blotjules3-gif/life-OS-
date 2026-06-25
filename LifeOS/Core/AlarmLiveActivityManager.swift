import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
final class AlarmLiveActivityManager {
    static let shared = AlarmLiveActivityManager()

    private var activity: Activity<AlarmAttributes>?

    private init() {}

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return } // prevent duplicates

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
        Task { await act.end(content, dismissalPolicy: .after(.now.addingTimeInterval(5))) }
    }

    private func currentTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: .now)
    }
}
