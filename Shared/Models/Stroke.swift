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
    /// `Club.id` of the club it was hit with. Nil for strokes from before clubs were recorded,
    /// and when the bag had nothing to offer. See plans/2026-10-11-club-selection.md.
    var clubID: String?

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, type: StrokeType = .regular, club: Club? = nil) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.type = type
        self.clubID = club?.id
    }

    var club: Club? {
        clubID.flatMap { Club.named($0) }
    }

    /// What the stroke adds to the score: one, plus a penalty stroke when it went into a penalty
    /// area or out of bounds.
    var score: Int {
        type == .regular ? 1 : 2
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
