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
    /// The hole both devices show. Separate from the timeline: see plans/2026-10-04-display-hole.md.
    var displayHole: DisplayHole
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
        self.displayHole = DisplayHole(holeIndex: 0, changedAt: date)
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

    /// The hole being played at `date`, by the timeline.
    func holeIndex(at date: Date) -> Int {
        HoleTimeline.holeIndex(at: date, in: holeTimeline)
    }

    /// The holes a moment can be on. See `HoleTimeline.possibleHoles`.
    func possibleHoles(at date: Date) -> ClosedRange<Int> {
        HoleTimeline.possibleHoles(at: date, in: holeTimeline, lastHoleIndex: lastHoleIndex)
    }

    var course: Course {
        courseSelection.course
    }

    /// The hole both devices show.
    var displayHoleIndex: Int {
        displayHole.holeIndex
    }

    var displayHoleNumber: Int {
        displayHoleIndex + 1
    }

    var displayCourseHole: Hole? {
        courseHole(at: displayHoleIndex)
    }

    /// Strokes on the display hole.
    var displayHoleStrokes: [Stroke] {
        hole(at: displayHoleIndex).strokes
    }

    /// Shows hole `index` from `date` on. Returns false when it is shown already or is not on the
    /// course. A time before the last change (the two devices' clocks differ slightly) is moved just after it.
    @discardableResult
    mutating func setDisplayHole(_ index: Int, at date: Date) -> Bool {
        guard index != displayHoleIndex, index >= 0, index <= lastHoleIndex else { return false }
        let changedAt = date > displayHole.changedAt ? date : displayHole.changedAt.addingTimeInterval(0.001)
        displayHole = DisplayHole(holeIndex: index, changedAt: changedAt)
        return true
    }

    /// Takes the other device's display hole when it was set later. Returns true if it changed.
    @discardableResult
    mutating func mergeDisplayHole(_ other: DisplayHole) -> Bool {
        guard displayHole.isOlder(than: other), other.holeIndex >= 0, other.holeIndex <= lastHoleIndex else { return false }
        displayHole = other
        return true
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

    /// Adds a start for hole `index` when it has none. Holes are played in order, so the start
    /// must fall between the starts of the holes before and after it; otherwise nothing changes.
    @discardableResult
    mutating func startHole(_ index: Int, at date: Date, source: HoleStartSource) -> Bool {
        guard index > 0, index <= lastHoleIndex, !holeTimeline.contains(where: { $0.holeIndex == index }) else { return false }
        let merged = HoleTimeline.normalized(holeTimeline + [HoleStart(holeIndex: index, startedAt: date, source: source)])
        guard merged.count == holeTimeline.count + 1 else { return false }
        holeTimeline = merged
        ensureHole(index)
        return true
    }

    /// A stroke on hole `index` hit at `date` starts the hole when it has no start yet, and moves
    /// the start back when it was hit before it. A start the user set by hand is never moved.
    /// Returns true if the timeline changed.
    @discardableResult
    mutating func strokeHit(onHole index: Int, at date: Date) -> Bool {
        guard let i = holeTimeline.firstIndex(where: { $0.holeIndex == index }) else {
            return startHole(index, at: date, source: .stroke)
        }
        guard i > 0, date < holeTimeline[i].startedAt, holeTimeline[i].source != .userSet,
              date > holeTimeline[i - 1].startedAt else { return false }
        holeTimeline[i].startedAt = date
        holeTimeline[i].source = .stroke
        holeTimeline[i].version += 1
        return true
    }

    /// Merges another copy of the timeline into this one. Returns true if anything changed.
    @discardableResult
    mutating func mergeTimeline(_ entries: [HoleStart]) -> Bool {
        let merged = HoleTimeline.merge(holeTimeline, entries)
        guard merged != holeTimeline else { return false }
        holeTimeline = merged
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
