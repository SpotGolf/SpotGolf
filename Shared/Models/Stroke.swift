import Foundation
import CoreLocation

/// A place the player hit the ball from, saved in the round. It has no time: a stroke's order
/// in its hole is its stroke number (see `StrokeFinder.estimatedTime(of:in:)` for when it was hit).
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

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, penaltyStrokes: Int = 0, quality: ShotQuality = .good,
         club: Club? = nil) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.penaltyStrokes = Self.clamped(penaltyStrokes: penaltyStrokes)
        self.quality = quality
        self.clubID = club?.id
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
        case id, latitude, longitude, penaltyStrokes, quality, clubID
        /// Strokes saved before penalty strokes were counted: regular, penalty or outOfBounds.
        case type
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        clubID = try values.decodeIfPresent(String.self, forKey: .clubID)
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
    }
}
