import Foundation

/// How a hole timeline entry was made.
enum HoleStartSource: String, Codable {
    case roundStart     // first entry
    case autoAdvance    // HoleAdvancer found the tee
    case playHole       // user tapped "Play this hole"
    case estimated      // filled in for a skipped hole from the GPS track
    case corrected      // moved by the phone to fit the marks
    case userSet        // set by the user; the phone never moves it
}

/// The moment play moved to a hole. A round's timeline is a list of these, and the hole
/// for any timestamp is the last entry that started at or before it.
struct HoleStart: Codable, Equatable, Identifiable {
    let id: UUID
    let holeIndex: Int
    var startedAt: Date
    var source: HoleStartSource
    /// Only the phone changes an entry after it is made, and it adds 1 each time, so the
    /// higher version is always the newer copy.
    var version: Int

    init(id: UUID = UUID(), holeIndex: Int, startedAt: Date, source: HoleStartSource, version: Int = 0) {
        self.id = id
        self.holeIndex = holeIndex
        self.startedAt = startedAt
        self.source = source
        self.version = version
    }
}

enum HoleTimeline {
    /// Joins two copies of a timeline. Both devices run the same steps on the same entries,
    /// so they end with the same timeline whatever order changes arrive in.
    static func merge(_ a: [HoleStart], _ b: [HoleStart]) -> [HoleStart] {
        var byID: [UUID: HoleStart] = [:]
        for entry in a + b {
            if let existing = byID[entry.id], existing.version >= entry.version { continue }
            byID[entry.id] = entry
        }
        return normalized(Array(byID.values))
    }

    /// Sorts by start time and drops any entry whose hole is not higher than the one before
    /// it, because golf is played in order and the hole only goes up.
    static func normalized(_ entries: [HoleStart]) -> [HoleStart] {
        // The ID breaks ties so every device picks the same order
        let sorted = entries.sorted {
            $0.startedAt != $1.startedAt ? $0.startedAt < $1.startedAt : $0.id.uuidString < $1.id.uuidString
        }
        var result: [HoleStart] = []
        for entry in sorted where result.last.map({ entry.holeIndex > $0.holeIndex }) ?? true {
            result.append(entry)
        }
        return result
    }

    /// The hole being played at `date`. Before the first entry, the first entry's hole.
    static func holeIndex(at date: Date, in entries: [HoleStart]) -> Int {
        (entries.last(where: { $0.startedAt <= date }) ?? entries.first)?.holeIndex ?? 0
    }
}
