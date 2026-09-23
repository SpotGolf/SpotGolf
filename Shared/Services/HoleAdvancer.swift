import CoreLocation
import CourseDataSwift

struct HoleAdvancer {
    private(set) var isPaused = false

    mutating func pause() { isPaused = true }
    mutating func resume() { isPaused = false }

    /// Returns the next hole index if the player is standing inside one of its tee polygons.
    ///
    /// Only checks the hole immediately following `currentHoleIndex` in playing order, so a
    /// tee from another part of the course never changes the hole, even when it sits next to
    /// the player. Returns `nil` if there is no next hole or the player is not inside any of
    /// its tee polygons.
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
}
