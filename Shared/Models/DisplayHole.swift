import Foundation

/// The hole the phone shows: its distances, strokes and map. During a round the watch's GPS
/// moves it to the next hole as its fixes arrive, and the user can pick any hole. It says nothing
/// about when holes were played (that is the hole timeline) or about the hole the watch shows
/// (`Round.playingHoleIndex`).
struct DisplayHole: Codable, Equatable {
    /// How long the hole stays after the user picks a hole or edits a spot, before the watch's
    /// GPS can move it on. The hold is kept beside the display hole, in `Round.displayHoleHeldUntil`.
    static let holdTime: TimeInterval = 30

    var holeIndex: Int
    /// When it was last set.
    var changedAt: Date
}
