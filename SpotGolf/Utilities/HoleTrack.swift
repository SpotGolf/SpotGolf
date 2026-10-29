import Foundation

/// The part of a round's GPS track on one hole.
enum HoleTrack {
    /// The fixes on hole `index`: the fixes `HoleTimeline.possibleHoles` puts on it.
    static func points(_ track: [TrackPoint], in round: Round, holeIndex index: Int) -> [TrackPoint] {
        // Read once: a round has thousands of fixes
        let starts = round.holeStarts
        let lastStrokes = round.lastStrokeTimes
        let lastHoleIndex = round.lastHoleIndex
        return track.filter {
            HoleTimeline.possibleHoles(at: $0.timestamp, in: starts, lastStrokes: lastStrokes, lastHoleIndex: lastHoleIndex)
                .contains(index)
        }
    }

    /// The fixes where hole `index` could start: after the start of the closest earlier hole that
    /// has one, and before the start of the closest later hole that has one. The hole's own start
    /// is left out, so a spot placed by hand can get a time before it and move it back.
    static func startWindow(_ track: [TrackPoint], in round: Round, holeIndex index: Int) -> [TrackPoint] {
        let starts = round.holeStarts
        let after = starts.indices.filter { $0 < index }.compactMap { starts[$0] }.max()
        let before = starts.indices.filter { $0 > index }.compactMap { starts[$0] }.min()
        return track.filter { point in
            (after.map { point.timestamp > $0 } ?? true) && (before.map { point.timestamp < $0 } ?? true)
        }
    }
}
