import CoreLocation
import CourseDataSwift

/// Asks the player to end the round once they have left the final green, and ends it when they
/// don't answer. The final hole is the last in playing order, and leaving its green is found by
/// GPS alone: strokes, swings and the display hole play no part. Times are the fixes' own, or
/// the clock's for `check(at:)`. See plans/2026-11-02-end-round-prompt.md.
struct RoundEndPrompter {
    /// How long after leaving the final green the watch asks.
    static let promptDelay: TimeInterval = 5 * 60
    /// How long after asking, with no answer, the round ends by itself.
    static let autoEndDelay: TimeInterval = 20 * 60

    enum Change: Equatable {
        /// Ask the player to end the round.
        case ask
        /// Back on the green: stop asking, and wait for them to leave again.
        case stopAsking
        /// End the round, at the last fix on the final green.
        case end(at: Date)
    }

    private var greenExit: GreenExit
    /// When the player left the final green, while they stay off it.
    private var leftAt: Date?
    /// When the watch asked, while it is asking.
    private var askedAt: Date?
    /// Keep Playing, or the round was ended: nothing more to do.
    private var isDone = false

    /// For a round on `courseSelection` whose last hole is at playing-order `lastHoleIndex`.
    init(courseSelection: CourseSelection, lastHoleIndex: Int) {
        let holes = courseSelection.orderedHoles
        let finalHole = holes.indices.contains(lastHoleIndex) ? holes[lastHoleIndex] : nil
        greenExit = GreenExit(shape: HoleShape(hole: finalHole, course: courseSelection.course))
    }

    /// The round's end time: the last fix on the final green, or nil before one.
    var endTime: Date? {
        greenExit.lastOnGreenAt
    }

    /// Takes a fix. Returns the change it makes, or nil.
    mutating func update(location: CLLocation) -> Change? {
        guard !isDone else { return nil }
        let point = Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        guard let toGreen = greenExit.update(point, at: location.timestamp) else { return nil }
        if toGreen == 0 {
            leftAt = nil
            guard askedAt != nil else { return nil }
            askedAt = nil
            return .stopAsking
        }
        if leftAt == nil, greenExit.hasLeft {
            leftAt = location.timestamp
        }
        return check(at: location.timestamp)
    }

    /// Returns the change the time `now` makes, or nil. Fixes check it too; this is for when
    /// none come in.
    mutating func check(at now: Date) -> Change? {
        guard !isDone, let leftAt else { return nil }
        guard let askedAt else {
            guard now.timeIntervalSince(leftAt) >= Self.promptDelay else { return nil }
            askedAt = now
            return .ask
        }
        guard now.timeIntervalSince(askedAt) >= Self.autoEndDelay, let endTime else { return nil }
        isDone = true
        return .end(at: endTime)
    }

    /// Keep Playing: no more asking this round.
    mutating func keepPlaying() {
        isDone = true
        askedAt = nil
    }
}
