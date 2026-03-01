import Foundation
import CoreLocation

struct BallMark: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, timestamp: Date = Date()) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
