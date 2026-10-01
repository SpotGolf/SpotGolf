import Foundation
import CourseDataSwift

enum RoundStatus: String, Codable {
    /// Phone only: waiting for the watch to confirm it started the round.
    case starting
    case active
    /// Phone only: waiting for the watch's GPS up to its last record.
    case ending
    case ended
}

struct Round: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    var holes: [RoundHole]
    var holeTimeline: [HoleStart]
    var status: RoundStatus
    var endedAt: Date?
    /// Phone: the end time a resumed round had, until the watch confirms the resume.
    /// Cancelling the resume puts it back.
    var resumedFromEnd: Date?
    var courseSelection: CourseSelection
    /// Adds 1 on every stroke change on the phone. On the watch, the version last applied.
    var strokesVersion: Int
    /// Watch only: the stream index of the first record in this round's stream file.
    var streamBase: Int
    /// The index of the watch's last stream record, once the watch has ended the round.
    /// Nil when the watch recorded nothing.
    var lastSeq: Int?
    /// Phone: the watch has confirmed `lastSeq`. Watch: the phone has acknowledged the end.
    var endConfirmed: Bool

    static let maxHoles = 18

    init(id: UUID = UUID(), date: Date = Date(), holes: [RoundHole] = [RoundHole()],
         status: RoundStatus = .active, courseSelection: CourseSelection) {
        self.id = id
        self.date = date
        self.holes = holes
        self.holeTimeline = [HoleStart(holeIndex: 0, startedAt: date, source: .roundStart)]
        self.status = status
        self.courseSelection = courseSelection
        self.strokesVersion = 0
        self.streamBase = 0
        self.endConfirmed = false
    }

    /// Recording and syncing.
    var isActive: Bool { status == .active }

    /// Not yet ended: starting, active, or ending.
    var isInProgress: Bool { status != .ended }

    var displayTitle: String {
        let dateStr = date.formatted(date: .long, time: .omitted)
        return "\(Self.shortenCourseName(courseSelection.course.name)) on \(dateStr)"
    }

    static func shortenCourseName(_ name: String) -> String {
        var s = name

        // Strip leading "The Club at " or "The "
        if s.lowercased().hasPrefix("the club at ") {
            s = String(s.dropFirst("the club at ".count))
        } else if s.lowercased().hasPrefix("the ") {
            s = String(s.dropFirst("the ".count))
        }

        // Replace trailing suffixes (case-insensitive, longest match first)
        let replacements: [(suffix: String, replacement: String)] = [
            ("country club", "CC"),
            ("golf course", "GC"),
            ("golf resort", "GC"),
            ("golf club", "GC"),
            ("resort", "Resort"),
        ]
        let lower = s.lowercased()
        for (suffix, replacement) in replacements {
            if lower.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count)) + replacement
                break
            }
        }

        return s.trimmingCharacters(in: .whitespaces)
    }

    /// The hole being played now: the last entry in the timeline.
    var currentHoleIndex: Int {
        holeTimeline.last?.holeIndex ?? 0
    }

    /// The hole being played at `date`.
    func holeIndex(at date: Date) -> Int {
        HoleTimeline.holeIndex(at: date, in: holeTimeline)
    }

    var currentHole: RoundHole {
        hole(at: currentHoleIndex)
    }

    var currentHoleNumber: Int {
        currentHoleIndex + 1
    }

    var course: Course {
        courseSelection.course
    }

    var currentCourseHole: Hole? {
        courseHole(at: currentHoleIndex)
    }

    /// The course data for the hole at `index`, or nil past the course's last hole.
    func courseHole(at index: Int) -> Hole? {
        let orderedHoles = courseSelection.orderedHoles
        guard index >= 0, index < orderedHoles.count else { return nil }
        return orderedHoles[index]
    }

    /// The last hole that can be played: the course's last hole, or `maxHoles` without course holes.
    var lastHoleIndex: Int {
        let count = courseSelection.orderedHoles.count
        return (count > 0 ? min(count, Self.maxHoles) : Self.maxHoles) - 1
    }

    /// The hole at `index`, or an empty hole when play has not reached it yet.
    func hole(at index: Int) -> RoundHole {
        index >= 0 && index < holes.count ? holes[index] : RoundHole()
    }

    /// Strokes for the current hole.
    var strokes: [Stroke] {
        hole(at: currentHoleIndex).strokes
    }

    /// All strokes across all holes.
    var allStrokes: [Stroke] {
        holes.flatMap { $0.strokes }
    }

    /// Strokes for every hole, as a snapshot for the watch.
    var strokesSnapshot: StrokesSnapshot {
        StrokesSnapshot(roundID: id, version: strokesVersion, holes: holes.map(\.strokes))
    }

    mutating func addStroke(_ stroke: Stroke, toHoleIndex holeIndex: Int) {
        guard holeIndex >= 0, !hasStroke(id: stroke.id) else { return }
        ensureHole(holeIndex)
        holes[min(holeIndex, holes.count - 1)].strokes.append(stroke)
    }

    func hasStroke(id: UUID) -> Bool {
        holes.contains { $0.strokes.contains { $0.id == id } }
    }

    /// Makes sure `holes` reaches `index`, up to `maxHoles`.
    mutating func ensureHole(_ index: Int) {
        while holes.count <= index && holes.count < Self.maxHoles {
            holes.append(RoundHole())
        }
    }

    /// Moves play to a later hole. Returns false when the hole is not after the current one.
    /// A time before the last entry (the two devices' clocks differ slightly) is moved just after it.
    @discardableResult
    mutating func startHole(_ index: Int, at date: Date, source: HoleStartSource) -> Bool {
        guard index > currentHoleIndex, index <= lastHoleIndex else { return false }
        let last = holeTimeline.last?.startedAt ?? .distantPast
        let startedAt = date > last ? date : last.addingTimeInterval(0.001)
        holeTimeline.append(HoleStart(holeIndex: index, startedAt: startedAt, source: source))
        ensureHole(index)
        return true
    }

    /// Merges another copy of the timeline into this one. Returns true if anything changed.
    @discardableResult
    mutating func mergeTimeline(_ entries: [HoleStart]) -> Bool {
        let merged = HoleTimeline.merge(holeTimeline, entries)
        guard merged != holeTimeline else { return false }
        holeTimeline = merged
        ensureHole(currentHoleIndex)
        return true
    }

    mutating func end(at date: Date) {
        // Trim trailing empty holes
        while holes.count > 1 && holes.last!.strokes.isEmpty {
            holes.removeLast()
        }
        status = .ended
        if endedAt == nil {
            endedAt = date
        }
    }

    /// Find which hole contains a given stroke by ID.
    func holeIndex(containing strokeID: UUID) -> Int? {
        holes.firstIndex(where: { hole in
            hole.strokes.contains(where: { $0.id == strokeID })
        })
    }
}
