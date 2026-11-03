import CoreLocation
import CourseDataSwift

/// Meters east (`x`) and north (`y`) of a `GroundPlane`'s origin.
struct GroundPoint: Equatable {
    var x: Double
    var y: Double

    static func + (a: GroundPoint, b: GroundPoint) -> GroundPoint { GroundPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: GroundPoint, b: GroundPoint) -> GroundPoint { GroundPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: GroundPoint, k: Double) -> GroundPoint { GroundPoint(x: a.x * k, y: a.y * k) }

    var length: Double { (x * x + y * y).squareRoot() }

    func distance(to other: GroundPoint) -> Double { (other - self).length }

    /// The direction from here to `other`, in radians counter-clockwise from east.
    func heading(to other: GroundPoint) -> Double { atan2(other.y - y, other.x - x) }

    /// `meters` from here along `heading`, in radians counter-clockwise from east.
    func moved(_ meters: Double, heading: Double) -> GroundPoint {
        GroundPoint(x: x + meters * cos(heading), y: y + meters * sin(heading))
    }
}

/// The course flattened around one point, as `LocalDistance` does: plenty accurate across a hole.
struct GroundPlane {
    let origin: Coordinate
    private let metersPerDegreeLongitude: Double

    init(origin: Coordinate) {
        self.origin = origin
        metersPerDegreeLongitude = LocalDistance.metersPerDegree * cos(origin.lat * .pi / 180)
    }

    func point(_ coordinate: Coordinate) -> GroundPoint {
        GroundPoint(x: (coordinate.lon - origin.lon) * metersPerDegreeLongitude,
                    y: (coordinate.lat - origin.lat) * LocalDistance.metersPerDegree)
    }

    func point(_ coordinate: CLLocationCoordinate2D) -> GroundPoint {
        point(Coordinate(lat: coordinate.latitude, lon: coordinate.longitude))
    }

    func coordinate(_ point: GroundPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: origin.lat + point.y / LocalDistance.metersPerDegree,
                               longitude: origin.lon + point.x / metersPerDegreeLongitude)
    }
}
