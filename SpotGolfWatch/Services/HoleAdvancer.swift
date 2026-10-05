import CoreLocation
import CourseDataSwift

/// Moves the display to the next hole, live, from GPS fixes. The next hole shows when the
/// player stands on one of its tees, or sooner, once they leave the green and head for that tee.
/// Only the display changes: the hole timeline is set by the strokes added on the phone.
///
/// Only the hole immediately following the one shown in playing order is checked, so a tee
/// from another part of the course never changes the hole, even when it sits next to the player.
/// See plans/2026-10-01-hole-advance-on-green-exit.md for how the numbers were chosen.
struct HoleAdvancer {
    /// The player must be this far from the green's edge, past where a bag is usually left.
    static let greenExitDistance: CLLocationDistance = 20
    /// And this much closer to the next tee than `towardTeeWindow` ago.
    static let towardTeeDistance: CLLocationDistance = 5
    static let towardTeeWindow: TimeInterval = 10
    /// Leaving the green only counts when the next tee is this close to it. Farther, the walk
    /// may be to the clubhouse at the end of a nine.
    static let maxGreenToTee: CLLocationDistance = 100
    /// Fixes inside the green, in total, before leaving it counts. About 20 s; GPS drift and
    /// walking across a corner give fewer.
    static let minGreenFixes = 20

    // The hole the state below is for; a change of hole clears it
    private var holeIndex: Int?
    private var green = HoleShape()
    private var nextTees = HoleShape()
    private var greenToTee: CLLocationDistance?
    private var greenFixes = 0
    // Distances to the next tee, oldest first. The first is the newest at least `towardTeeWindow` old.
    private var recent: [(timestamp: Date, toTee: CLLocationDistance)] = []

    /// Returns the next hole index when this fix moves the display to it, or nil.
    mutating func advance(location: CLLocation, courseSelection: CourseSelection, displayHoleIndex: Int) -> Int? {
        let orderedHoles = courseSelection.orderedHoles
        let nextIndex = displayHoleIndex + 1
        guard nextIndex < orderedHoles.count else { return nil }
        if holeIndex != displayHoleIndex {
            reset(holeIndex: displayHoleIndex, holes: orderedHoles, course: courseSelection.course)
        }

        let point = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard let toTee = nextTees.metersToTee(point) else { return nil }
        if toTee == 0 {
            return nextIndex
        }

        let toGreen = green.metersToGreen(point)
        if toGreen == 0 {
            greenFixes += 1
        }
        recent.append((location.timestamp, toTee))
        while recent.count > 1, location.timestamp.timeIntervalSince(recent[1].timestamp) >= Self.towardTeeWindow {
            recent.removeFirst()
        }

        guard greenFixes >= Self.minGreenFixes,
              let greenToTee, greenToTee <= Self.maxGreenToTee,
              let toGreen, toGreen >= Self.greenExitDistance,
              let oldest = recent.first,
              location.timestamp.timeIntervalSince(oldest.timestamp) >= Self.towardTeeWindow,
              oldest.toTee - toTee >= Self.towardTeeDistance else { return nil }
        return nextIndex
    }

    private mutating func reset(holeIndex: Int, holes: [Hole], course: Course) {
        self.holeIndex = holeIndex
        green = HoleShape(hole: holes[holeIndex], course: course)
        nextTees = HoleShape(hole: holes[holeIndex + 1], course: course)
        greenToTee = Self.distance(from: green, to: nextTees)
        greenFixes = 0
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
