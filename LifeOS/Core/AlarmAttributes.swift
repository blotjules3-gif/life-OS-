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
            case ringing         // alarm beeping
            case speakingMessage // TTS playing
            case dismissed       // alarm ended
        }
    }

    var startTime: Date
}
