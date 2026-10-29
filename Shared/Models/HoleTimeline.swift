import Foundation

/// Reads a round's hole starts: when play moved to each hole, by play index, or nil for a hole with
/// no start. Starts with a date go up with the index, since holes are played in order, so the hole
/// for any timestamp is the last one that started at or before it.
enum HoleTimeline {
    /// True when hole `index` can start at `date`: after the start of every earlier hole and
    /// before the start of every later one, since holes are played in order.
    static func fits(holeIndex index: Int, at date: Date, in starts: [Date?]) -> Bool {
        starts.indices.allSatisfy { hole in
            guard hole != index, let start = starts[hole] else { return true }
            return hole < index ? start < date : start > date
        }
    }

    /// The hole being played at `date`. Before the first start, the first hole with a start.
    static func holeIndex(at date: Date, in starts: [Date?]) -> Int {
        starts.indices.last { starts[$0].map { $0 <= date } ?? false } ?? starts.firstIndex { $0 != nil } ?? 0
    }

    /// The holes a moment can be on: the hole being played by the timeline, and the holes after
    /// it with no start yet, up to the next one that has. A hole gets its start from its first
    /// stroke, so until then its GPS reads as the hole before it by time alone.
    ///
    /// A moment after the last stroke on its hole (`lastStrokes`, by play index, nil for a hole
    /// with none) can also be on the next hole that has a start. That start is only the earliest
    /// stroke so far: when the second shot is turned into a stroke before the tee shot, the tee
    /// shot comes before it.
    static func possibleHoles(at date: Date, in starts: [Date?], lastStrokes: [Date?], lastHoleIndex: Int) -> ClosedRange<Int> {
        let current = holeIndex(at: date, in: starts)
        let next = starts.indices.first { hole in
            hole > current && starts[hole].map { $0 > date } ?? false
        } ?? lastHoleIndex + 1
        let lastStroke = lastStrokes.indices.contains(current) ? lastStrokes[current] : nil
        let pastLastStroke = lastStroke.map { date > $0 } ?? true
        let last = pastLastStroke ? min(next, lastHoleIndex) : next - 1
        return current...max(current, last)
    }
}
