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
            for (_, teeCoord) in hole.tees ?? [:] {
                let distance = location.distance(from: teeCoord.clLocation)
                if distance < teeProximityMeters && distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
        }
        return closestIndex
    }

    /// Finds the nearest hole using tees, green, and features as reference points.
    /// Always returns a result (no proximity threshold).
    static func nearestHole(location: CLLocation, courseSelection: CourseSelection) -> Int? {
        let orderedHoles = courseSelection.orderedHoles
        guard !orderedHoles.isEmpty else { return nil }
        var closestIndex = 0
        var closestDistance = Double.greatestFiniteMagnitude

        for (index, hole) in orderedHoles.enumerated() {
            for (_, teeCoord) in hole.tees ?? [:] {
                let d = location.distance(from: teeCoord.clLocation)
                if d < closestDistance { closestDistance = d; closestIndex = index }
            }
            if let green = hole.green {
                for coord in [green.front, green.middle, green.back] {
                    let d = location.distance(from: coord.clLocation)
                    if d < closestDistance { closestDistance = d; closestIndex = index }
                }
            }
            for feature in hole.features ?? [] {
                let d = location.distance(from: feature.middle)
                if d < closestDistance { closestDistance = d; closestIndex = index }
            }
        }
        return closestIndex
    }
}
