import Foundation
import SwiftData

/// A club in the player's bag, saved with SwiftData: one row per club. Later features add what
/// the player's strokes show about the club. See plans/2026-10-10-club-distances.md.
@Model
final class CarriedClub {
    /// `Club.id`.
    @Attribute(.unique) var clubID: String
    /// How far the player hits the club, in yards. Nil for the putter only.
    var distance: Int?

    /// The club at its default distance.
    init(_ club: Club) {
        clubID = club.id
        distance = club.defaultDistance
    }

    /// A club at the distance a copy of the bag gave it, such as one from iCloud.
    init(clubID: String, distance: Int?) {
        self.clubID = clubID
        self.distance = distance
    }

    /// Nil for a row whose ID is not a club.
    var club: Club? {
        Club.named(clubID)
    }
}
