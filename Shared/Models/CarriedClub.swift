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

    /// Nil for a row whose ID is not a club.
    var club: Club? {
        Club.named(clubID)
    }
}
