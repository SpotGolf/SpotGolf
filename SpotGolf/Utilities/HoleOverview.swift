import CoreLocation
import CourseDataSwift

/// The numbers shown for a hole: its par, the yards to its green, and the round's score.
/// Used by the phone's map header and its Live Activity.
enum HoleOverview {
    /// Yards from `location` to the center of the hole's green, or nil without a green or location.
    static func yardsToGreenCenter(_ round: Round, holeIndex: Int, from location: CLLocation?) -> Int? {
        guard let courseHole = round.courseHole(at: holeIndex),
              let green = courseHole.green(from: round.course.features),
              let location else { return nil }
        return Int(DistanceCalculator.yards(from: location, to: green.center.clLocation))
    }

    /// The watch's "Previous": yards from `location` to the hole's last stroke, so it shows how
    /// far the last shot went while walking to the ball. Without a location, the yards between the
    /// last two strokes, and 0 with fewer.
    static func previousYards(strokes: [Stroke], from location: CLLocation?) -> Int {
        if let location, let last = strokes.last {
            return Int(DistanceCalculator.yards(from: location, to: last.location))
        }
        guard strokes.count >= 2 else { return 0 }
        return Int(DistanceCalculator.yards(from: strokes[strokes.count - 2], to: strokes[strokes.count - 1]))
    }

    /// Strokes over (+) or under (-) par on the finished holes, or nil when none are finished
    /// or one has no par. The display hole of an active round is not finished.
    static func toPar(_ round: Round) -> Int? {
        // Every played hole of a past round is finished
        let finished = round.holes.indices.filter {
            (!round.isActive || $0 != round.displayHoleIndex) && !round.holes[$0].strokes.isEmpty
        }
        let pars = finished.compactMap { round.courseHole(at: $0)?.par }
        guard pars.count == finished.count, !finished.isEmpty else { return nil }
        return finished.reduce(0) { $0 + round.holes[$1].strokeCount } - pars.reduce(0, +)
    }

    /// "E", "+2", or "-1".
    static func toParText(_ diff: Int) -> String {
        diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)"
    }
}
