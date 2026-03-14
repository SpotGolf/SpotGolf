import Foundation
import CoreLocation

enum BallMarkType: String, Codable {
    case regular
    case penalty
    case outOfBounds
}

struct BallMark: Identifiable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    var type: BallMarkType

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, timestamp: Date = Date(), type: BallMarkType = .regular) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
        self.type = type
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

extension BallMark: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, timestamp, type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        type = try container.decodeIfPresent(BallMarkType.self, forKey: .type) ?? .regular
    }
}
