import CoreLocation
import CourseDataSwift

/// Moves a hole on to the next one, live, from the watch's GPS fixes. Each device runs its own:
/// the watch moves the hole it thinks the player is on (`Round.playingHoleIndex`), and the phone
/// moves the hole it shows (`Round.displayHole`). Neither hole is sent to the other device, and
/// the hole timeline is set by the strokes added on the phone, not by either.
///
/// Only the hole immediately following the current one in playing order is checked, so a tee
/// from another part of the course never changes the hole, even when it sits next to the player.
/// See plans/2026-10-01-hole-advance-on-green-exit.md for how the numbers were chosen.
struct HoleAdvancer {
    /// Which hole the advancer moves on. Standing on one of the next hole's tees moves either.
    /// They differ in the walk from the green to that tee.
    enum Target {
        /// The phone's display hole. It moves on as soon as the player leaves the green and
        /// heads for the next tee, so the next hole shows early.
        case displayHole
        /// The watch's playing hole. It moves on only once that walk has brought the player
        /// within `nearTeeDistance` of the tee: until then they may still be playing the hole.
        /// A hole the user picked is not moved on from straight away; see `waitsForApproach`.
        case playingHole
    }

    /// After leaving the green (`GreenExit`), the player must be this much closer to the next tee
    /// than `towardTeeWindow` ago.
    static let towardTeeDistance: CLLocationDistance = 5
    static let towardTeeWindow: TimeInterval = 10
    /// The display hole: leaving the green only counts when the next tee is this close to it.
    /// Farther, the walk may be to the clubhouse at the end of a nine.
    static let maxGreenToTee: CLLocationDistance = 100
    /// The playing hole: the walk from the green must bring the player this close to the next tee.
    static let nearTeeDistance: CLLocationDistance = 15

    private let target: Target
    // The hole the state below is for; a change of hole clears it
    private var holeIndex: Int?
    // The hole the last fix moved on to, until the caller's hole is seen to be it
    private var advancedTo: Int?
    /// The playing hole only. The user picked the hole, so the player is on it even when the GPS
    /// has them at the next tee, as after an approach that landed on that tee. The hole stays
    /// until they have been more than `nearTeeDistance` from that tee, or have been on the green.
    private var waitsForApproach = false
    private var greenExit = GreenExit()
    private var nextTees = HoleShape()
    private var greenToTee: CLLocationDistance?
    // Distances to the next tee, oldest first. The first is the newest at least `towardTeeWindow` old.
    private var recent: [(timestamp: Date, toTee: CLLocationDistance)] = []

    init(moving target: Target) {
        self.target = target
    }

    /// Returns the next hole index when this fix moves the hole on from `current`, or nil.
    mutating func advance(location: CLLocation, courseSelection: CourseSelection, holeIndex current: Int) -> Int? {
        let orderedHoles = courseSelection.orderedHoles
        if holeIndex != current {
            // A hole this advancer did not move on to is one the user picked
            let picked = holeIndex != nil && current != advancedTo
            reset(holeIndex: current, holes: orderedHoles, course: courseSelection.course)
            waitsForApproach = picked && target == .playingHole
        }
        let nextIndex = current + 1
        guard nextIndex < orderedHoles.count else { return nil }

        let point = Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        guard let toTee = nextTees.metersToTee(point) else { return nil }
        greenExit.update(point, at: location.timestamp)
        recent.append((location.timestamp, toTee))
        while recent.count > 1, location.timestamp.timeIntervalSince(recent[1].timestamp) >= Self.towardTeeWindow {
            recent.removeFirst()
        }

        if waitsForApproach {
            guard toTee > Self.nearTeeDistance || greenExit.hasBeenOnGreen else { return nil }
            waitsForApproach = false
        }
        guard toTee == 0 || hasWalkedToTee(toTee, at: location.timestamp) else { return nil }
        advancedTo = nextIndex
        return nextIndex
    }

    /// True when the player has left the green and is heading for the next tee, as far along as
    /// the target asks for.
    private func hasWalkedToTee(_ toTee: CLLocationDistance, at timestamp: Date) -> Bool {
        guard greenExit.hasLeft,
              let oldest = recent.first,
              timestamp.timeIntervalSince(oldest.timestamp) >= Self.towardTeeWindow,
              oldest.toTee - toTee >= Self.towardTeeDistance else { return false }
        switch target {
        case .displayHole:
            guard let greenToTee else { return false }
            return greenToTee <= Self.maxGreenToTee
        case .playingHole:
            return toTee <= Self.nearTeeDistance
        }
    }

    private mutating func reset(holeIndex: Int, holes: [Hole], course: Course) {
        self.holeIndex = holeIndex
        advancedTo = nil
        // The last hole has no next hole, and nothing moves on from it
        greenExit = GreenExit(shape: HoleShape(hole: holes.indices.contains(holeIndex) ? holes[holeIndex] : nil,
                                               course: course))
        nextTees = HoleShape(hole: holes.indices.contains(holeIndex + 1) ? holes[holeIndex + 1] : nil,
                             course: course)
        greenToTee = Self.distance(from: greenExit.shape, to: nextTees)
        recent = []
    }

    /// The gap between a hole's green and the next hole's nearest tee, or nil when either is missing.
    private static func distance(from green: HoleShape, to tees: HoleShape) -> CLLocationDistance? {
        guard let greenPolygon = green.green, !tees.tees.isEmpty else { return nil }
        let fromGreen = greenPolygon.compactMap { tees.metersToTee($0) }.min() ?? .infinity
        let fromTees = tees.tees.flatMap { $0 }.compactMap { green.metersToGreen($0) }.min() ?? .infinity
        return min(fromGreen, fromTees)
    }
}
