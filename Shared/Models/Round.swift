import Foundation
import CoreLocation
import CourseDataSwift
import os
import SwiftData

enum RoundStatus: String, Codable {
    /// Phone only: waiting for the watch to confirm it started the round.
    case starting
    case active
    /// Phone only: waiting for the watch's GPS up to its last record.
    case ending
    case ended
}

/// A round of golf, saved with SwiftData. `RoundStore` makes and changes every round, so
/// changes made on one device can be sent to the other.
///
/// Per-hole values (`holeStarts`, `pins`) are arrays by play index with one entry per hole, nil
/// for a hole without one. `holes` grows as play reaches each hole.
@Model
final class Round {
    @Attribute(.unique) var id: UUID
    var date: Date
    var status: RoundStatus
    var endedAt: Date?
    /// Phone: the end time a resumed round had, until the watch confirms the resume.
    /// Cancelling the resume puts it back.
    var resumedFromEnd: Date?
    /// Adds 1 on every stroke change on the phone. On the watch, the version last applied.
    var strokesVersion: Int
    /// Watch only: the stream index of the first record in this round's stream.
    var streamBase: Int
    /// The index of the watch's last stream record, once the watch has ended the round.
    /// Nil when the watch recorded nothing.
    var lastSeq: Int?
    /// Phone: the watch has confirmed `lastSeq`. Watch: the phone has acknowledged the end.
    var endConfirmed: Bool
    var holes: [RoundHole]
    /// When play moved to each hole, or nil for a hole with no start yet. Hole 0 starts with the
    /// round. Only the phone changes it. See `HoleTimeline`.
    var holeStarts: [Date?]
    /// The hole both devices show. Separate from the timeline: see plans/2026-10-04-display-hole.md.
    var displayHole: DisplayHole
    /// Until when the watch's GPS does not move the display hole on, after the user picked a hole
    /// or edited a spot. The distant past when not held. Its own attribute with a default, so
    /// rounds saved before it existed still open.
    var displayHoleHeldUntil: Date = Date.distantPast
    /// Stored as one encoded column: `Course` comes from CourseDataSwift and has optional values,
    /// and SwiftData crashes reading change history (which `@Query` does) for an optional value
    /// inside a struct it splits into columns. See plans/2026-10-19-swiftdata-models.md.
    @Attribute(.codable) var courseSelection: CourseSelection
    /// Where each hole's pin is, or nil for a hole without one. See plans/2026-10-06-pin-location.md.
    var pins: [PinLocation?]
    /// When the round last changed on this phone, or the change it was downloaded with from iCloud.
    /// The newer of two copies of a round wins. See plans/2026-10-22-cloudkit-sync.md.
    var changedAt: Date = Date.distantPast

    static let maxHoles = 18

    init(id: UUID = UUID(), date: Date = Date(), holes: [RoundHole] = [RoundHole()],
         status: RoundStatus = .active, courseSelection: CourseSelection) {
        let holeCount = Self.lastHoleIndex(of: courseSelection) + 1
        self.id = id
        self.date = date
        self.status = status
        self.strokesVersion = 0
        self.streamBase = 0
        self.endConfirmed = false
        self.holes = holes
        self.holeStarts = [date] + Array(repeating: nil, count: holeCount - 1)
        self.displayHole = DisplayHole(holeIndex: 0, changedAt: date)
        self.courseSelection = courseSelection
        self.pins = Array(repeating: nil, count: holeCount)
        self.changedAt = date
    }

    /// Recording and syncing.
    var isActive: Bool { status == .active }

    /// Not yet ended: starting, active, or ending.
    var isInProgress: Bool { status != .ended }

    var displayTitle: String {
        let dateStr = date.formatted(date: .long, time: .omitted)
        let course = Self.shortenCourseName(courseSelection.course.name)
        return String(localized: "\(course) on \(dateStr)", comment: "A round's title: the course and the day it was played")
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
        HoleTimeline.holeIndex(at: date, in: holeStarts)
    }

    /// The holes a moment can be on. See `HoleTimeline.possibleHoles`.
    func possibleHoles(at date: Date) -> ClosedRange<Int> {
        HoleTimeline.possibleHoles(at: date, in: holeStarts, lastStrokes: lastStrokeTimes, lastHoleIndex: lastHoleIndex)
    }

    /// When the last stroke on each hole was hit, by play index, or nil for a hole with no stroke
    /// of known time.
    var lastStrokeTimes: [Date?] {
        holes.map { $0.strokes.compactMap(\.hitAt).max() }
    }

    var course: Course {
        courseSelection.course
    }

    /// The hole both devices show.
    var displayHoleIndex: Int {
        displayHole.holeIndex
    }

    /// The display hole's number: its place in nine order, which a shotgun start does not change.
    var displayHoleNumber: Int {
        holeNumber(at: displayHoleIndex)
    }

    /// The number the player sees for the hole at playing-order `index`.
    func holeNumber(at index: Int) -> Int {
        courseSelection.holeNumber(at: index)
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
    /// `holds` is for a hole the user picked: the watch's GPS then leaves it alone for `DisplayHole.holdTime`.
    @discardableResult
    func setDisplayHole(_ index: Int, at date: Date, holds: Bool = false) -> Bool {
        guard index != displayHoleIndex, index >= 0, index <= lastHoleIndex else { return false }
        let changedAt = date > displayHole.changedAt ? date : displayHole.changedAt.addingTimeInterval(0.001)
        displayHole = DisplayHole(holeIndex: index, changedAt: changedAt)
        if holds {
            holdDisplayHole(at: date)
        }
        return true
    }

    /// Keeps the watch's GPS from moving the display hole on for `DisplayHole.holdTime` from
    /// `date`. Returns false when it is held that long already.
    @discardableResult
    func holdDisplayHole(at date: Date) -> Bool {
        let until = date.addingTimeInterval(DisplayHole.holdTime)
        guard until > displayHoleHeldUntil else { return false }
        displayHoleHeldUntil = until
        return true
    }

    /// True while the watch's GPS must not move the display hole on.
    func isDisplayHoleHeld(at date: Date) -> Bool {
        date < displayHoleHeldUntil
    }

    /// Takes the other device's display hole when it was set later, and its hold when that
    /// lasts longer. Returns true if either changed.
    @discardableResult
    func mergeDisplayHole(_ other: DisplayHole, heldUntil: Date = .distantPast) -> Bool {
        guard other.holeIndex >= 0, other.holeIndex <= lastHoleIndex else { return false }
        var changed = false
        if displayHole.isOlder(than: other) {
            displayHole = other
            changed = true
        }
        // A hold sent with an older hole still counts, so it never moves the hole back
        if heldUntil > displayHoleHeldUntil {
            displayHoleHeldUntil = heldUntil
            changed = true
        }
        return changed
    }

    /// The pin on hole `index`, if it has been set.
    func pin(onHole index: Int) -> PinLocation? {
        pins.indices.contains(index) ? pins[index] : nil
    }

    /// The green of hole `index`, or nil when the course has no green outline for it.
    func green(holeIndex index: Int) -> Feature? {
        guard let green = courseHole(at: index)?.green(from: course.features), !green.polygon.isEmpty else { return nil }
        return green
    }

    /// The center of hole `index`'s green, or nil without a green.
    func greenCenter(holeIndex index: Int) -> CLLocationCoordinate2D? {
        green(holeIndex: index).map { CLLocationCoordinate2D(latitude: $0.center.lat, longitude: $0.center.lon) }
    }

    /// True when `coordinate` is inside the green of hole `index`. False when the course has no green for it.
    func isOnGreen(_ coordinate: CLLocationCoordinate2D, holeIndex index: Int) -> Bool {
        guard let green = green(holeIndex: index) else { return false }
        return PolygonGeometry.contains(Coordinate(lat: coordinate.latitude, lon: coordinate.longitude),
                                        in: green.polygon)
    }

    /// Sets the player's pin on hole `index`, replacing any earlier one. Returns false when the
    /// point is not on that hole's green.
    @discardableResult
    func setPin(_ coordinate: CLLocationCoordinate2D, onHole index: Int, at date: Date) -> Bool {
        guard pins.indices.contains(index), isOnGreen(coordinate, holeIndex: index) else { return false }
        pins[index] = PinLocation(coordinate: coordinate, setAt: date, source: .set)
        return true
    }

    /// Takes each pin that replaces the one on its hole, by `PinLocation.isReplaced(by:)`: from
    /// the other device, from other golfers, or the green centers. `others` is by play index, like
    /// `pins`. Returns true if any changed.
    @discardableResult
    func mergePins(_ others: [PinLocation?]) -> Bool {
        var changed = false
        for index in others.indices where pins.indices.contains(index) {
            guard let other = others[index] else { continue }
            if let pin = pins[index], !pin.isReplaced(by: other) { continue }
            pins[index] = other
            changed = true
        }
        return changed
    }

    /// Where distances to the middle of hole `index`'s green go: its pin, or the green's center
    /// without one. Nil when the course has no green for the hole.
    func targetCoordinate(holeIndex index: Int) -> CLLocationCoordinate2D? {
        pin(onHole: index)?.coordinate ?? greenCenter(holeIndex: index)
    }

    /// True when hole `index` has a real pin: shared by other golfers or set by the player.
    func hasKnownPin(holeIndex index: Int) -> Bool {
        guard let source = pin(onHole: index)?.source else { return false }
        return source != .center
    }

    /// True when the player set hole `index`'s pin, on the watch or the phone.
    func hasSetPin(holeIndex index: Int) -> Bool {
        pin(onHole: index)?.source == .set
    }

    /// A center pin for every hole that has a green and no pin yet. Returns true if any were added.
    @discardableResult
    func addCenterPins() -> Bool {
        mergePins(pins.indices.map { index in
            greenCenter(holeIndex: index).map { PinLocation(coordinate: $0, setAt: date, source: .center) }
        })
    }

    /// The course data for the hole at `index`, or nil past the course's last hole.
    func courseHole(at index: Int) -> Hole? {
        let orderedHoles = courseSelection.orderedHoles
        guard index >= 0, index < orderedHoles.count else { return nil }
        return orderedHoles[index]
    }

    /// The last hole that can be played: the course's last hole, or `maxHoles` without course holes.
    var lastHoleIndex: Int {
        Self.lastHoleIndex(of: courseSelection)
    }

    private static func lastHoleIndex(of selection: CourseSelection) -> Int {
        let count = selection.orderedHoles.count
        return (count > 0 ? min(count, maxHoles) : maxHoles) - 1
    }

    /// The hole at `index`, or an empty hole when play has not reached it yet.
    func hole(at index: Int) -> RoundHole {
        index >= 0 && index < holes.count ? holes[index] : RoundHole()
    }

    /// All strokes across all holes.
    var allStrokes: [Stroke] {
        holes.flatMap { $0.strokes }
    }

    /// The suggestions turned into strokes, hidden while their strokes exist. Suggestions are not
    /// saved: `StrokeFinder` works them out again and gives the same stop the same ID.
    var takenSuggestionIDs: Set<UUID> {
        Set(allStrokes.compactMap { stroke in
            guard case .suggestion(let id) = stroke.origin else { return nil }
            return id
        })
    }

    /// The round's score: every hole's `strokeCount`, penalty strokes included.
    var strokeCount: Int {
        holes.reduce(0) { $0 + $1.strokeCount }
    }

    /// Strokes for every hole, as a snapshot for the watch.
    var strokesSnapshot: StrokesSnapshot {
        StrokesSnapshot(roundID: id, version: strokesVersion, holes: holes.map(\.strokes))
    }

    func addStroke(_ stroke: Stroke, toHoleIndex holeIndex: Int) {
        guard holeIndex >= 0, !hasStroke(id: stroke.id) else { return }
        ensureHole(holeIndex)
        holes[min(holeIndex, holes.count - 1)].strokes.append(stroke)
    }

    func hasStroke(id: UUID) -> Bool {
        holes.contains { $0.strokes.contains { $0.id == id } }
    }

    /// Makes sure `holes` reaches `index`, up to `maxHoles`.
    func ensureHole(_ index: Int) {
        while holes.count <= index && holes.count < Self.maxHoles {
            holes.append(RoundHole())
        }
    }

    /// When hole `index` started, or nil when it has no start.
    func startOfHole(_ index: Int) -> Date? {
        holeStarts.indices.contains(index) ? holeStarts[index] : nil
    }

    /// Adds a start for hole `index` when it has none. Holes are played in order, so the start
    /// must fall between the starts of the holes before and after it; otherwise nothing changes.
    @discardableResult
    func startHole(_ index: Int, at date: Date) -> Bool {
        guard index <= lastHoleIndex, startOfHole(index) == nil else { return false }
        return setStart(ofHole: index, to: date)
    }

    /// A stroke on hole `index` hit at `date` starts the hole when it has no start yet, and moves
    /// the start back when it was hit before it. Returns true if the timeline changed.
    @discardableResult
    func strokeHit(onHole index: Int, at date: Date) -> Bool {
        guard let start = startOfHole(index) else { return startHole(index, at: date) }
        guard date < start else { return false }
        return setStart(ofHole: index, to: date)
    }

    /// Sets hole `index`'s start from its strokes, after one of them was moved or removed, so the
    /// start follows them both ways: the earliest stroke's time, or no start once the hole has
    /// no strokes. `hitTime` is when each stroke was hit. Nothing changes when a stroke's time is
    /// unknown. Returns true if the timeline changed.
    @discardableResult
    func restartHole(_ index: Int, hitTime: (Stroke) -> Date?) -> Bool {
        let strokes = hole(at: index).strokes
        let times = strokes.compactMap(hitTime)
        guard times.count == strokes.count else { return false }
        return setStart(ofHole: index, to: times.min())
    }

    /// Sets or clears hole `index`'s start. Hole 0's start is the round's and never changes, and a
    /// start that would put the holes out of order is not set.
    private func setStart(ofHole index: Int, to date: Date?) -> Bool {
        guard index > 0, holeStarts.indices.contains(index), holeStarts[index] != date else { return false }
        if let date {
            guard HoleTimeline.fits(holeIndex: index, at: date, in: holeStarts) else { return false }
            ensureHole(index)
        }
        holeStarts[index] = date
        return true
    }

    func end(at date: Date) {
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
