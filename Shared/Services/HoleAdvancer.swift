import CoreLocation
import CourseData

struct HoleAdvancer {
    private(set) var isPaused = false

    static let teeProximityMeters: Double = 30.0

    mutating func pause() { isPaused = true }
    mutating func resume() { isPaused = false }

    static func detectHole(location: CLLocation, courseSelection: CourseSelection) -> Int? {
        let course = courseSelection.course
        let orderedHoles = courseSelection.orderedHoles
        var closestIndex: Int?
        var closestDistance = Double.greatestFiniteMagnitude

        for (index, hole) in orderedHoles.enumerated() {
            for (_, featureID) in hole.tees {
                guard let feature = course.findFeature(id: featureID) else { continue }
                let distance = location.distance(from: feature.center.clLocation)
                if distance < teeProximityMeters && distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
        }
        return closestIndex
    }

    static func nearestHole(location: CLLocation, courseSelection: CourseSelection) -> Int? {
        let course = courseSelection.course
        let orderedHoles = courseSelection.orderedHoles
        guard !orderedHoles.isEmpty else { return nil }
        var closestIndex = 0
        var closestDistance = Double.greatestFiniteMagnitude

        for (index, hole) in orderedHoles.enumerated() {
            for (_, featureID) in hole.tees {
                guard let feature = course.findFeature(id: featureID) else { continue }
                let d = location.distance(from: feature.center.clLocation)
                if d < closestDistance { closestDistance = d; closestIndex = index }
            }
            if let green = hole.green(from: course.features) {
                let d = location.distance(from: green.center.clLocation)
                if d < closestDistance { closestDistance = d; closestIndex = index }
            }
            for feature in course.features(for: hole) {
                let d = location.distance(from: feature.center.clLocation)
                if d < closestDistance { closestDistance = d; closestIndex = index }
            }
        }
        return closestIndex
    }
}
