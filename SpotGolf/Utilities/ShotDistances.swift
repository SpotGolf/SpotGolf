import CoreLocation
import CourseDataSwift

/// The shots that count toward how far the player hits each club, and how far each went: from
/// its spot to the next spot on the same hole. See plans/2026-11-02-caddie-club-distances.md,
/// section 3.
enum ShotDistances {
    /// Each club's counted shots, in yards, from the ended rounds. `greenZone` is the Green Zone
    /// setting, in meters from the green's edge.
    static func shots(in rounds: [Round], greenZone: CLLocationDistance) -> [Club: [Double]] {
        var shots: [Club: [Double]] = [:]
        for round in rounds {
            for shot in self.shots(in: round, greenZone: greenZone) {
                shots[shot.club, default: []].append(shot.yards)
            }
        }
        return shots
    }

    /// The counted shots of one round, none while it is in progress.
    static func shots(in round: Round, greenZone: CLLocationDistance) -> [(club: Club, yards: Double)] {
        guard round.status == .ended else { return [] }
        // Read once: the round decodes its course on each read
        let selection = round.courseSelection
        let courseHoles = selection.orderedHoles
        var shots: [(club: Club, yards: Double)] = []
        for (index, hole) in round.holes.enumerated() {
            let green = courseHoles.indices.contains(index)
                ? courseHoles[index].green(from: selection.course.features).flatMap { $0.polygon.isEmpty ? nil : Array($0.polygon) }
                : nil
            // The last stroke has no next spot, so where the ball went is not known
            for (stroke, next) in zip(hole.strokes, hole.strokes.dropFirst()) {
                guard let club = stroke.club, counts(stroke, from: green, greenZone: greenZone) else { continue }
                shots.append((club, DistanceCalculator.yards(from: stroke, to: next)))
            }
        }
        return shots
    }

    /// Putts, thumbs-down shots, shots with penalty strokes (the next spot is a drop or a
    /// re-tee) and chips from the Green Zone are left out. A hole with no green can't be checked
    /// for the Green Zone, so its shots count.
    private static func counts(_ stroke: Stroke, from green: [Coordinate]?, greenZone: CLLocationDistance) -> Bool {
        guard stroke.club?.kind != .putter, stroke.penaltyStrokes == 0, stroke.quality != .bad else { return false }
        guard let green else { return true }
        let spot = Coordinate(lat: stroke.latitude, lon: stroke.longitude)
        return HoleShape.distance(from: spot, to: green) > greenZone
    }
}
