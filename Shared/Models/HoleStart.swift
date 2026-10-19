import Foundation

/// The moment play moved to a hole. A round's timeline is a list of these, and the hole
/// for any timestamp is the last entry that started at or before it.
struct HoleStart: Codable, Equatable, Identifiable {
    let id: UUID
    let holeIndex: Int
    /// Nil once the hole's last stroke is removed: the hole has no start until it gets a stroke
    /// again. The entry is kept, with a higher version, so the other device's older copy can't
    /// bring the start back.
    var startedAt: Date?
    /// Only the phone changes an entry after it is made, and it adds 1 each time, so the
    /// higher version is always the newer copy.
    var version: Int

    init(id: UUID = UUID(), holeIndex: Int, startedAt: Date?, version: Int = 0) {
        self.id = id
        self.holeIndex = holeIndex
        self.startedAt = startedAt
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
    /// it, because golf is played in order and the hole only goes up. Entries with no start
    /// come last, by hole.
    static func normalized(_ entries: [HoleStart]) -> [HoleStart] {
        // The ID breaks ties so every device picks the same order
        let started = entries.filter { $0.startedAt != nil }.sorted { (a: HoleStart, b: HoleStart) -> Bool in
            let aStart = a.startedAt ?? .distantPast
            let bStart = b.startedAt ?? .distantPast
            return aStart != bStart ? aStart < bStart : a.id.uuidString < b.id.uuidString
        }
        var result: [HoleStart] = []
        for entry in started where result.last.map({ entry.holeIndex > $0.holeIndex }) ?? true {
            result.append(entry)
        }
        let cleared = entries.filter { $0.startedAt == nil }.sorted {
            $0.holeIndex != $1.holeIndex ? $0.holeIndex < $1.holeIndex : $0.id.uuidString < $1.id.uuidString
        }
        return result + cleared
    }

    /// True when hole `index` can start at `date`: after the start of every earlier hole and
    /// before the start of every later one, since holes are played in order.
    static func fits(holeIndex index: Int, at date: Date, in entries: [HoleStart]) -> Bool {
        entries.allSatisfy { entry in
            guard let start = entry.startedAt, entry.holeIndex != index else { return true }
            return entry.holeIndex < index ? start < date : start > date
        }
    }

    /// The hole being played at `date`. Before the first entry, the first entry's hole.
    static func holeIndex(at date: Date, in entries: [HoleStart]) -> Int {
        (entries.last(where: { $0.startedAt.map { $0 <= date } ?? false }) ?? entries.first)?.holeIndex ?? 0
    }

    /// The holes a moment can be on: the hole being played by the timeline, and the holes after
    /// it with no start yet, up to the next one that has. A hole gets its start from its first
    /// stroke, so until then its GPS reads as the hole before it by time alone.
    static func possibleHoles(at date: Date, in entries: [HoleStart], lastHoleIndex: Int) -> ClosedRange<Int> {
        let current = holeIndex(at: date, in: entries)
        let next = entries.first(where: { entry in
            entry.holeIndex > current && entry.startedAt.map { $0 > date } ?? false
        })?.holeIndex ?? lastHoleIndex + 1
        return current...max(current, next - 1)
    }
}
