import Foundation
import CoreLocation

struct IndexCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct CourseIndexEntry: Codable, Equatable {
    let name: String
    let coordinate: IndexCoordinate
    let holes: Int
    let path: String

    var city: String? {
        let components = path.split(separator: "/")
        guard components.count >= 4 else { return nil }
        return String(components[2])
    }

    var state: String? {
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return nil }
        return String(components[1])
    }

    var country: String? {
        let components = path.split(separator: "/")
        guard components.count >= 1 else { return nil }
        return String(components[0])
    }
}
