import ActivityKit
import Foundation

// Shared between the app target and the Widget Extension target.
// Add this file to BOTH targets in Xcode (Target Membership).

@available(iOS 16.1, *)
struct AlarmAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var phase: Phase
        var timeString: String   // "07:30"
        var message: String      // displayed in Lock Screen / Dynamic Island

        enum Phase: String, Codable, Hashable {
            case ringing         // alarm beeping, app in foreground
            case waitingUnlock   // alarm beeping, phone locked — waiting for unlock
            case speakingMessage // TTS playing after unlock
            case briefing        // daily briefing screen open
            case dismissed       // alarm ended
        }
    }

    var startTime: Date
}
