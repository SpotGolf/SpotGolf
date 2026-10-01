import Foundation
import CoreLocation

enum StrokeType: String, Codable {
    case regular
    case penalty
    case outOfBounds
}

/// A place the player hit the ball from, saved in the round. It has no time: a stroke's order
/// in its hole is its stroke number (see `StrokeFinder.estimatedTime(of:in:)` for when it was hit).
struct Stroke: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    var type: StrokeType

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, type: StrokeType = .regular) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.type = type
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
