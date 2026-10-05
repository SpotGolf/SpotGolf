import Foundation
import CoreLocation

/// A place the player may have hit the ball from. The watch records each swing as one with no
/// location; `StrokeFinder` places swings and stops near the green on the course.
struct StrokeSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        /// The watch felt a swing, with its highest force in g.
        case swing(peakG: Float)
        /// The player stood still near the green with no swing: a chip or putt the watch missed.
        case stop(duration: TimeInterval)
    }

    /// The swing, or the start of the stop.
    let timestamp: Date
    let kind: Kind
    /// Nil until `StrokeFinder` places it.
    var latitude: Double?
    var longitude: Double?
    /// From a time that does not change as the round goes on: the first swing at the spot for a
    /// full swing, the start of the stop for a putt, chip or stop (see `id(at:)`). A swing that has
    /// not been placed yet uses its own time.
    var id: UUID

    init(timestamp: Date, kind: Kind, coordinate: CLLocationCoordinate2D? = nil, id: UUID? = nil) {
        self.timestamp = timestamp
        self.kind = kind
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.id = id ?? Self.id(at: timestamp)
    }

    /// A swing the watch detected, not yet placed.
    static func swing(at timestamp: Date, peakG: Float) -> StrokeSuggestion {
        StrokeSuggestion(timestamp: timestamp, kind: .swing(peakG: peakG))
    }

    /// The swing's highest force in g, or nil for a stop.
    var peakG: Float? {
        if case .swing(let peakG) = kind { return peakG }
        return nil
    }

    var isSwing: Bool { peakG != nil }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The same UUID every time for the same millisecond, so a stop or swing found again gives
    /// the same ID and a dismissed suggestion stays dismissed.
    static func id(at date: Date) -> UUID {
        // A fixed base, with the milliseconds in the last 8 bytes
        var bytes: uuid_t = (0x53, 0x47, 0x53, 0x54, 0x52, 0x4B, 0x40, 0x00, 0x80, 0, 0, 0, 0, 0, 0, 0)
        let milliseconds = UInt64(max((date.timeIntervalSince1970 * 1000).rounded(), 0))
        withUnsafeMutableBytes(of: &bytes) { buffer in
            for i in 0..<8 {
                buffer[8 + i] ^= UInt8((milliseconds >> (8 * UInt64(i))) & 0xFF)
            }
        }
        return UUID(uuid: bytes)
    }
}
