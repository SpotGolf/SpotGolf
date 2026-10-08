import Foundation

/// The part of a round's GPS track on one hole.
enum HoleTrack {
    /// The fixes on hole `index`: a fix belongs to the hole the timeline says was being played
    /// at its time, or to a later hole with no start yet.
    static func points(_ track: [TrackPoint], in round: Round, holeIndex index: Int) -> [TrackPoint] {
        track.filter { round.possibleHoles(at: $0.timestamp).contains(index) }
    }
}
