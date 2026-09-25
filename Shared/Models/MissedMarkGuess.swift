import Foundation
import CoreLocation

/// A place the player probably hit the ball without marking it, made on the phone from a
/// swing the watch detected. It has no hole of its own: the hole comes from the round's
/// timeline at `timestamp`, so a corrected timeline moves it to the right hole.
struct MissedMarkGuess: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let roundID: UUID

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, timestamp: Date = Date(), roundID: UUID) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
        self.roundID = roundID
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The same ID every time for the same swing, so a swing that is checked again never
    /// makes a second guess, and a dismissed guess stays dismissed.
    static func id(forSwingAt timestamp: Date, roundID: UUID) -> UUID {
        var bytes = roundID.uuid
        let milliseconds = UInt64(max((timestamp.timeIntervalSince1970 * 1000).rounded(), 0))
        withUnsafeMutableBytes(of: &bytes) { buffer in
            for i in 0..<8 {
                buffer[8 + i] ^= UInt8((milliseconds >> (8 * UInt64(i))) & 0xFF)
            }
        }
        return UUID(uuid: bytes)
    }
}
