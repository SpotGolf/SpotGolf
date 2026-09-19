import Foundation
import CoreLocation

enum GuessReason: String, Codable {
    case swing
    case stationary
}

struct MissedMarkGuess: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let holeIndex: Int
    let reason: GuessReason
    let roundID: UUID

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, timestamp: Date = Date(),
         holeIndex: Int, reason: GuessReason, roundID: UUID) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
        self.holeIndex = holeIndex
        self.reason = reason
        self.roundID = roundID
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
