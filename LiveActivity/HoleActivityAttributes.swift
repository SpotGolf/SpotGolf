import ActivityKit
import Foundation

/// The Live Activity for a round: the current hole, the yards to its green, and the score.
/// Built into both the phone app, which starts and updates it, and the widget extension, which shows it.
struct HoleActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var holeNumber: Int
        /// Nil when the course has no data for the hole.
        var par: Int?
        /// Nil without a location or a green.
        var yardsToGreen: Int?
        /// The watch's "Previous": yards to the hole's last stroke, or between its last two.
        var previousYards: Int
        var holeStrokes: Int
        var totalStrokes: Int
        /// Over (+) or under (-) par on the finished holes, or nil when none are finished.
        var toPar: Int?
    }

    let roundID: UUID
    let courseName: String
}
