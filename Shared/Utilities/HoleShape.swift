import CoreLocation
import CourseDataSwift

/// The shapes of one hole: its tees, green and centerline. Any of them may be missing.
struct HoleShape {
    /// On the green or this close to its edge is where putts and chips are made: the phone
    /// suggests contacts and stops there, and the watch listens for contacts there. The default
    /// for the phone's Green Zone setting, which travels to the watch with each round.
    static let chipZoneMargin: CLLocationDistance = 10

    var tees: [[Coordinate]] = []
    var green: [Coordinate]?
    var centerline: [Coordinate] = []

    init(tees: [[Coordinate]] = [], green: [Coordinate]? = nil, centerline: [Coordinate] = []) {
        self.tees = tees
        self.green = green
        self.centerline = centerline
    }

    init(hole: Hole?, course: Course) {
        tees = hole?.teeBoxes(from: course.features).compactMap {
            $0.polygon.isEmpty ? nil : Array($0.polygon)
        } ?? []
        green = hole?.green(from: course.features).flatMap { $0.polygon.isEmpty ? nil : Array($0.polygon) }
        centerline = hole?.centerline(from: course.features).map { Array($0.polygon) } ?? []
    }

    func metersToTee(_ point: Coordinate) -> CLLocationDistance? {
        tees.map { Self.distance(from: point, to: $0) }.min()
    }

    /// Meters from the green's edge: zero on the green.
    func metersToGreen(_ point: Coordinate) -> CLLocationDistance? {
        green.map { Self.distance(from: point, to: $0) }
    }

    func metersToCenterline(_ point: Coordinate) -> Double? {
        LocalDistance.meters(fromLat: point.lat, lon: point.lon,
                             toPolyline: centerline.map { ($0.lat, $0.lon) })
    }

    /// Meters from a point to a polygon's nearest edge: zero inside it.
    static func distance(from point: Coordinate, to polygon: [Coordinate]) -> CLLocationDistance {
        guard !polygon.isEmpty else { return .infinity }
        if PolygonGeometry.contains(point, in: polygon) { return 0 }
        let ring = (polygon + [polygon[0]]).map { (latitude: $0.lat, longitude: $0.lon) }
        return LocalDistance.meters(fromLat: point.lat, lon: point.lon, toPolyline: ring)
            ?? LocalDistance.meters(fromLat: point.lat, lon: point.lon,
                                    toLat: polygon[0].lat, lon: polygon[0].lon)
    }
}
