import Foundation
import CoreLocation

/// Where a stroke came from.
enum StrokeOrigin: Codable, Equatable {
    /// Placed by hand. Its time is the GPS fix nearest the spot, worked out again when it is moved.
    case manual
    /// Taken from a suggestion. It keeps the suggestion's time when it is moved, and the
    /// suggestion is hidden while the stroke exists.
    case suggestion(id: UUID)
}

/// A place the player hit the ball from, saved in the round. A stroke's order in its hole is its
/// stroke number; its time sets when the hole started (see `Round.restartHole`).
struct Stroke: Identifiable, Codable, Equatable {
    /// The most penalty strokes one stroke can cost.
    static let maxPenaltyStrokes = 4

    let id: UUID
    let latitude: Double
    let longitude: Double
    /// The penalty strokes the shot cost, 0 to `maxPenaltyStrokes`: one for a ball in a penalty
    /// area, out of bounds or lost. See plans/2026-10-11-penalty-strokes.md.
    var penaltyStrokes: Int
    /// How the player rated the shot. A new stroke is a good shot until they say otherwise.
    var quality: ShotQuality
    /// `Club.id` of the club it was hit with. Nil for strokes from before clubs were recorded,
    /// and when the bag had nothing to offer. See plans/2026-10-11-club-selection.md.
    var clubID: String?
    let origin: StrokeOrigin
    /// When it was hit. Nil for a manual stroke placed where there was no GPS.
    var hitAt: Date?

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, penaltyStrokes: Int = 0, quality: ShotQuality = .good,
         club: Club? = nil, origin: StrokeOrigin = .manual, hitAt: Date? = nil) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.penaltyStrokes = Self.clamped(penaltyStrokes: penaltyStrokes)
        self.quality = quality
        self.clubID = club?.id
        self.origin = origin
        self.hitAt = hitAt
    }

    /// `count` kept between 0 and `maxPenaltyStrokes`.
    static func clamped(penaltyStrokes count: Int) -> Int {
        min(max(count, 0), maxPenaltyStrokes)
    }

    var club: Club? {
        clubID.flatMap { Club.named($0) }
    }

    /// What the stroke adds to the score: itself plus its penalty strokes.
    var score: Int {
        1 + penaltyStrokes
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, penaltyStrokes, quality, clubID, origin, hitAt
        /// Strokes saved before penalty strokes were counted: regular, penalty or outOfBounds.
        case type
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        clubID = try values.decodeIfPresent(String.self, forKey: .clubID)
        origin = try values.decode(StrokeOrigin.self, forKey: .origin)
        hitAt = try values.decodeIfPresent(Date.self, forKey: .hitAt)
        quality = try values.decodeIfPresent(ShotQuality.self, forKey: .quality) ?? .unrated
        if let count = try values.decodeIfPresent(Int.self, forKey: .penaltyStrokes) {
            penaltyStrokes = Self.clamped(penaltyStrokes: count)
        } else {
            let type = try values.decodeIfPresent(String.self, forKey: .type)
            penaltyStrokes = type == nil || type == "regular" ? 0 : 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(latitude, forKey: .latitude)
        try values.encode(longitude, forKey: .longitude)
        try values.encode(penaltyStrokes, forKey: .penaltyStrokes)
        try values.encode(quality, forKey: .quality)
        try values.encodeIfPresent(clubID, forKey: .clubID)
        try values.encode(origin, forKey: .origin)
        try values.encodeIfPresent(hitAt, forKey: .hitAt)
    }
}
