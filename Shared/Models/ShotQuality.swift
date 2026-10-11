import Foundation

/// How the player rated a shot in the Edit Spot sheet: thumbs down, meh or thumbs up. A new
/// stroke is good; only strokes saved before ratings are unrated. Kept for statistics. See plans/2026-10-11-penalty-strokes.md.
enum ShotQuality: String, Codable, CaseIterable {
    case unrated
    case bad
    case okay
    case good
}
