import CoreLocation
import CourseDataSwift

/// The shapes of one hole: its tees, green and centerline. Any of them may be missing.
struct HoleShape {
    /// On the green or this close to its edge is where putts and chips are made: the phone
    /// suggests contacts and stops there, and the watch listens for contacts there.
    static let chipZoneMargin: CLLocationDistance = 30

    var tees: [[Coordinate]] = []
    var green: [Coordinate]?
    var centerline: [Coordinate] = []

    init(tees: [[Coordinate]] = [], green: [Coordinate]? = nil, centerline: [Coordinate] = []) {
        self.tees = tees
        self.green = green
        self.centerline = centerline
    }

    init(hole: Hole?, course: Course) {
        tees = hole?.tees.values.compactMap { id in
            guard let feature = course.findFeature(id: id), feature.type == .tee,
                  !feature.polygon.isEmpty else { return nil }
            return feature.polygon
        } ?? []
        green = hole?.green(from: course.features).map(\.polygon).flatMap { $0.isEmpty ? nil : $0 }
        centerline = hole?.centerline ?? []
    }

    func metersToTee(_ point: Coordinate) -> CLLocationDistance? {
        tees.map { Self.distance(from: point, to: $0) }.min()
    }

    /// Meters from the green's edge: zero on the green.
    func metersToGreen(_ point: Coordinate) -> CLLocationDistance? {
        green.map { Self.distance(from: point, to: $0) }
    }

    func metersToCenterline(_ point: Coordinate) -> Double? {
        LocalDistance.meters(fromLat: point.latitude, lon: point.longitude,
                             toPolyline: centerline.map { ($0.latitude, $0.longitude) })
    }

    /// Meters from a point to a polygon's nearest edge: zero inside it.
    static func distance(from point: Coordinate, to polygon: [Coordinate]) -> CLLocationDistance {
        guard !polygon.isEmpty else { return .infinity }
        if PolygonGeometry.contains(point, in: polygon) { return 0 }
        let ring = (polygon + [polygon[0]]).map { (latitude: $0.latitude, longitude: $0.longitude) }
        return LocalDistance.meters(fromLat: point.latitude, lon: point.longitude, toPolyline: ring)
            ?? LocalDistance.meters(fromLat: point.latitude, lon: point.longitude,
                                    toLat: polygon[0].latitude, lon: polygon[0].longitude)
    }
}
