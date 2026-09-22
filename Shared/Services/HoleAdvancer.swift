import CoreLocation
import CourseDataSwift

struct HoleAdvancer {
    private(set) var isPaused = false

    mutating func pause() { isPaused = true }
    mutating func resume() { isPaused = false }

    /// Returns the next hole index if the player is standing inside one of its tee polygons.
    ///
    /// Only checks the hole immediately following `currentHoleIndex`. Returns `nil` if
    /// there is no next hole or the player is not inside any of its tee polygons.
    static func detectHole(location: CLLocation, courseSelection: CourseSelection, currentHoleIndex: Int) -> Int? {
        let orderedHoles = courseSelection.orderedHoles
        let nextIndex = currentHoleIndex + 1
        guard nextIndex < orderedHoles.count else { return nil }

        let nextHole = orderedHoles[nextIndex]
        let course = courseSelection.course
        let coord = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

        for (_, featureID) in nextHole.tees {
            guard let feature = course.findFeature(id: featureID),
                  feature.type == .tee else { continue }
            if PolygonGeometry.contains(coord, in: feature.polygon) {
                return nextIndex
            }
        }
        return nil
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
