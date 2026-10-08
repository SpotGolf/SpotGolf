import CoreLocation
import CourseDataSwift
import MapKit
import SwiftUI

/// The math behind the round map: where its camera points, how far one point of it reaches on
/// the ground, and where the target's lines stop.
enum MapGeometry {
    static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0015)
    /// How high the camera that follows the player sits, in meters.
    static let followDistance: CLLocationDistance = 600

    /// Degrees clockwise from north, from `start` to `end`.
    static func bearing(from start: Coordinate, to end: Coordinate) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The bearing from hole `index`'s first tee to its green, so the map can turn the green to
    /// the top. Nil without a tee or green.
    static func heading(of round: Round, holeIndex index: Int) -> Double? {
        guard let courseHole = round.courseHole(at: index),
              let green = courseHole.green(from: round.course.features),
              let firstTeeID = courseHole.tees.values.first,
              let teeFeature = round.course.findFeature(id: firstTeeID) else { return nil }
        return bearing(from: teeFeature.center, to: green.center)
    }

    /// The camera that follows the player: turned so the green is at the top when `heading` is known.
    static func following(_ location: CLLocation, heading: Double?) -> MapCameraPosition {
        if let heading {
            return .camera(MapCamera(centerCoordinate: location.coordinate, distance: followDistance,
                                     heading: heading, pitch: 0))
        }
        return .region(MKCoordinateRegion(center: location.coordinate, span: defaultSpan))
    }

    /// A camera showing all of hole `index`, with the green at the top. Nil without a green or
    /// any features to show.
    static func holeCamera(_ round: Round, holeIndex index: Int) -> MapCamera? {
        guard let courseHole = round.courseHole(at: index),
              let green = courseHole.green(from: round.course.features) else { return nil }
        let course = round.course

        let allCoords = course.features(for: courseHole).flatMap(\.polygon)
        guard !allCoords.isEmpty else { return nil }

        let minLat = allCoords.map(\.latitude).min()!
        let maxLat = allCoords.map(\.latitude).max()!
        let minLon = allCoords.map(\.longitude).min()!
        let maxLon = allCoords.map(\.longitude).max()!
        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2

        // Bearing from tee to green → heading so green is at top
        let teeCenter: Coordinate
        if let firstTeeID = courseHole.tees.values.first,
           let teeFeature = course.findFeature(id: firstTeeID) {
            teeCenter = teeFeature.center
        } else {
            teeCenter = Coordinate(latitude: midLat, longitude: midLon)
        }
        let heading = bearing(from: teeCenter, to: green.center)

        // Offset center towards the tee so the user's location (near tee)
        // appears above the button bar instead of hidden behind it
        let headingRad = heading * .pi / 180
        let offsetFraction = 0.08 // shift 8% of hole length towards tee
        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        let center = CLLocationCoordinate2D(
            latitude: midLat - cos(headingRad) * latSpan * offsetFraction,
            longitude: midLon - sin(headingRad) * lonSpan * offsetFraction
        )

        // Camera distance: must show all features + padding from the offset center.
        // Compute the farthest point from center, then double (center→edge is half the view).
        let padMeters = 18.3 // ~20 yards
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let farthest = allCoords.map { centerLoc.distance(from: $0.clLocation) }.max() ?? 0
        let cameraDistance = (farthest + padMeters) * 3.5

        return MapCamera(centerCoordinate: center, distance: cameraDistance, heading: heading, pitch: 0)
    }

    /// Meters of ground across one point of the map, from the width of the area it shows. The
    /// area is the box around the turned map, so the turn is taken back out. Nil before the map
    /// has a size.
    static func metersPerPoint(mapSize: CGSize, heading: CLLocationDirection,
                               metersAcross: CLLocationDistance) -> Double? {
        guard mapSize.width > 0, mapSize.height > 0 else { return nil }
        let radians = heading * .pi / 180
        let cosine = abs(cos(radians)), sine = abs(sin(radians))
        let pointsAcross = Double(mapSize.width) * cosine + Double(mapSize.height) * sine
        return metersAcross / pointsAcross
    }

    /// Where a line from `target` toward `other` starts: `gap` meters out from the target, so
    /// the line stays outside the bullseye. Nil when `other` is inside the gap.
    static func lineEnd(at target: CLLocationCoordinate2D, toward other: CLLocationCoordinate2D,
                        gap: CLLocationDistance) -> CLLocationCoordinate2D? {
        let from = CLLocation(latitude: target.latitude, longitude: target.longitude)
        let length = from.distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
        guard length > gap else { return nil }
        let fraction = gap / length
        return CLLocationCoordinate2D(latitude: target.latitude + (other.latitude - target.latitude) * fraction,
                                      longitude: target.longitude + (other.longitude - target.longitude) * fraction)
    }

    /// The flag grows with the zoom level: its normal size at the whole-hole view and below,
    /// growing evenly per zoom level up to `largestFlagScale` when zoomed in close, and no larger.
    static let normalFlagMetersPerPoint = 0.6
    static let largestFlagMetersPerPoint = 0.1
    static let largestFlagScale = 1.5

    /// How much larger than normal the flag is drawn at the map's zoom. The zoom level is the
    /// log of meters per point, as each pinch step halves or doubles it.
    static func flagScale(metersPerPoint: Double) -> CGFloat {
        let zoom = log2(normalFlagMetersPerPoint / metersPerPoint)
        let fullZoom = log2(normalFlagMetersPerPoint / largestFlagMetersPerPoint)
        let progress = min(max(zoom / fullZoom, 0), 1)
        return 1 + (largestFlagScale - 1) * progress
    }
}
