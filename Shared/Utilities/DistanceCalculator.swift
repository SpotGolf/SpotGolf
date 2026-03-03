import CoreLocation

enum DistanceCalculator {
    private static let metersToYards = 1.09361

    /// Returns distance in yards between two locations
    static func yards(from a: CLLocation, to b: CLLocation) -> Double {
        a.distance(from: b) * metersToYards
    }

    /// Returns distance in yards between two ball marks
    static func yards(from a: BallMark, to b: BallMark) -> Double {
        yards(from: a.location, to: b.location)
    }

    /// Returns a formatted distance string in yards
    static func formattedYards(from a: CLLocation, to b: CLLocation) -> String {
        "\(Int(yards(from: a, to: b))) yds"
    }

    /// Returns a formatted distance string in yards between two ball marks
    static func formattedYards(from a: BallMark, to b: BallMark) -> String {
        formattedYards(from: a.location, to: b.location)
    }
}
