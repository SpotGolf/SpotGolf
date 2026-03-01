import CoreLocation

enum DistanceCalculator {
    /// Returns distance in yards between two ball marks
    static func yards(from a: BallMark, to b: BallMark) -> Double {
        let meters = a.location.distance(from: b.location)
        return meters * 1.09361
    }

    /// Returns a formatted distance string in yards
    static func formattedYards(from a: BallMark, to b: BallMark) -> String {
        let yds = yards(from: a, to: b)
        return "\(Int(yds)) yds"
    }
}
