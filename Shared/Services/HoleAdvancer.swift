import CoreLocation

struct HoleAdvancer {
    private(set) var isPaused = false

    static let teeProximityMeters: Double = 30.0

    mutating func pause() { isPaused = true }
    mutating func resume() { isPaused = false }

    /// Detects which hole (0-based index into orderedHoles) the user is near,
    /// based on proximity to tee boxes. Returns nil if not near any tee.
    static func detectHole(location: CLLocation, courseSelection: CourseSelection) -> Int? {
        let orderedHoles = courseSelection.orderedHoles
        var closestIndex: Int?
        var closestDistance = Double.greatestFiniteMagnitude

        for (index, hole) in orderedHoles.enumerated() {
            for (_, teeCoord) in hole.tees {
                let distance = location.distance(from: teeCoord.clLocation)
                if distance < teeProximityMeters && distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
        }
        return closestIndex
    }
}
