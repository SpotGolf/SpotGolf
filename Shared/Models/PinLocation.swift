import Foundation
import CoreLocation

/// Where a pin came from. See plans/2026-10-06-shared-pins.md.
enum PinSource: String, Codable {
    /// The center of the green, until a real pin is known.
    case center
    /// Downloaded from other golfers.
    case shared
    /// Set by the player on the watch or phone.
    case set
}

/// Where the pin is on a hole's green. See plans/2026-10-06-pin-location.md.
struct PinLocation: Codable, Equatable {
    let holeIndex: Int
    let latitude: Double
    let longitude: Double
    /// When it was set.
    let setAt: Date
    let source: PinSource

    init(holeIndex: Int, coordinate: CLLocationCoordinate2D, setAt: Date, source: PinSource = .set) {
        self.holeIndex = holeIndex
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.setAt = setAt
        self.source = source
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// True when `incoming` should replace this pin when merged. A center pin never replaces
    /// anything, a shared pin replaces anything but a set one, and a set pin replaces anything.
    /// Between two set pins, from the watch and the phone, the later one wins so both keep it.
    func isReplaced(by incoming: PinLocation) -> Bool {
        switch (source, incoming.source) {
        case (_, .center): false
        case (.center, _): true
        case (.shared, .set), (.shared, .shared): true
        case (.set, .shared): false
        case (.set, .set): setAt < incoming.setAt
        }
    }
}
