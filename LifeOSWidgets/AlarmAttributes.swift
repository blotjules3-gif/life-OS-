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
            case scheduled       // alarm set, shows on lock screen all night
            case ringing         // alarm beeping
            case speakingMessage // TTS playing on lock screen
            case waitingUnlock   // voice done, invite to unlock for full briefing
            case briefing        // full briefing screen open (app foreground)
            case dismissed       // alarm ended
        }
    }

    var startTime: Date
}
