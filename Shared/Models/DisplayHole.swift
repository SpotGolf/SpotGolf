import Foundation

/// The hole both devices show: its distances, strokes and map. The watch's GPS moves it to the
/// next hole, and the user can pick any hole on either device. It says nothing about when holes
/// were played; that is the hole timeline.
struct DisplayHole: Codable, Equatable {
    /// How long the watch's GPS leaves the hole alone after the user picks a hole or edits a spot.
    /// The hold is kept beside the display hole, in `Round.displayHoleHeldUntil`.
    static let holdTime: TimeInterval = 30

    var holeIndex: Int
    /// When it was last set. When both devices set it, the later one wins.
    var changedAt: Date

    /// True when `other` was set later, so it should replace this one. At the same time the
    /// higher hole wins, so both devices pick the same one.
    func isOlder(than other: DisplayHole) -> Bool {
        changedAt < other.changedAt || (changedAt == other.changedAt && holeIndex < other.holeIndex)
    }
}
