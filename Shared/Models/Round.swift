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
/// Values with parts of their own (holes, timeline, display hole, pins, course) are saved as
/// encoded data and decoded once when first read. Reading one also reads its saved data, so
/// views and observers see it change.
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
    /// Phone only: stroke suggestions the user dismissed or turned into strokes. Suggestions
    /// are not saved: `StrokeFinder` works them out again and gives the same stop the same ID.
    var hiddenSuggestionIDs: [UUID]

    private var holesData: Data
    private var holeTimelineData: Data
    private var displayHoleData: Data
    private var courseSelectionData: Data
    private var pinsData: Data

    @Transient private var holesCache: [RoundHole]?
    @Transient private var holeTimelineCache: [HoleStart]?
    @Transient private var displayHoleCache: DisplayHole?
    @Transient private var courseSelectionCache: CourseSelection?
    @Transient private var pinsCache: [PinLocation]?

    static let maxHoles = 18

    init(id: UUID = UUID(), date: Date = Date(), holes: [RoundHole] = [RoundHole()],
         status: RoundStatus = .active, courseSelection: CourseSelection) {
        self.id = id
        self.date = date
        self.status = status
        self.strokesVersion = 0
        self.streamBase = 0
        self.endConfirmed = false
        self.hiddenSuggestionIDs = []
        holesData = Self.encode(holes)
        holeTimelineData = Self.encode([HoleStart(holeIndex: 0, startedAt: date, source: .roundStart)])
        displayHoleData = Self.encode(DisplayHole(holeIndex: 0, changedAt: date))
        courseSelectionData = Self.encode(courseSelection)
        pinsData = Self.encode([PinLocation]())
    }

    var holes: [RoundHole] {
        get { Self.value(holesData, cache: &holesCache) ?? [RoundHole()] }
        set {
            holesCache = newValue
            holesData = Self.encode(newValue)
        }
    }

    var holeTimeline: [HoleStart] {
        get { Self.value(holeTimelineData, cache: &holeTimelineCache) ?? [] }
        set {
            holeTimelineCache = newValue
            holeTimelineData = Self.encode(newValue)
        }
    }

    /// The hole both devices show. Separate from the timeline: see plans/2026-10-04-display-hole.md.
    var displayHole: DisplayHole {
        get { Self.value(displayHoleData, cache: &displayHoleCache) ?? DisplayHole(holeIndex: 0, changedAt: date) }
        set {
            displayHoleCache = newValue
            displayHoleData = Self.encode(newValue)
        }
    }

    /// Written once at the start, by this build, so it always decodes.
    var courseSelection: CourseSelection {
        get { Self.value(courseSelectionData, cache: &courseSelectionCache)! }
        set {
            courseSelectionCache = newValue
            courseSelectionData = Self.encode(newValue)
        }
    }

    /// Where the pin is, at most one per hole. See plans/2026-10-06-pin-location.md.
    var pins: [PinLocation] {
        get { Self.value(pinsData, cache: &pinsCache) ?? [] }
        set {
            pinsCache = newValue
            pinsData = Self.encode(newValue)
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            Log.storage.error("Could not encode \(String(describing: T.self), privacy: .public): \(String(describing: error), privacy: .public)")
            return Data()
        }
    }

    /// The decoded value, from `cache` once it has been decoded. Nil when it can't be decoded.
    private static func value<T: Decodable>(_ data: Data, cache: inout T?) -> T? {
        if let cache { return cache }
        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            cache = value
            return value
        } catch {
            Log.storage.error("Could not decode \(String(describing: T.self), privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
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
    func setDisplayHole(_ index: Int, at date: Date) -> Bool {
        guard index != displayHoleIndex, index >= 0, index <= lastHoleIndex else { return false }
        let changedAt = date > displayHole.changedAt ? date : displayHole.changedAt.addingTimeInterval(0.001)
        displayHole = DisplayHole(holeIndex: index, changedAt: changedAt)
        return true
    }

    /// Takes the other device's display hole when it was set later. Returns true if it changed.
    @discardableResult
    func mergeDisplayHole(_ other: DisplayHole) -> Bool {
        guard displayHole.isOlder(than: other), other.holeIndex >= 0, other.holeIndex <= lastHoleIndex else { return false }
        displayHole = other
        return true
    }

    /// The pin on hole `index`, if it has been set.
    func pin(onHole index: Int) -> PinLocation? {
        pins.first { $0.holeIndex == index }
    }

    /// The green of hole `index`, or nil when the course has no green outline for it.
    func green(holeIndex index: Int) -> Feature? {
        guard let green = courseHole(at: index)?.green(from: course.features), !green.polygon.isEmpty else { return nil }
        return green
    }

    /// The center of hole `index`'s green, or nil without a green.
    func greenCenter(holeIndex index: Int) -> CLLocationCoordinate2D? {
        green(holeIndex: index).map { CLLocationCoordinate2D(latitude: $0.center.latitude, longitude: $0.center.longitude) }
    }

    /// True when `coordinate` is inside the green of hole `index`. False when the course has no green for it.
    func isOnGreen(_ coordinate: CLLocationCoordinate2D, holeIndex index: Int) -> Bool {
        guard let green = green(holeIndex: index) else { return false }
        return PolygonGeometry.contains(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                        in: green.polygon)
    }

    /// Sets the player's pin on hole `index`, replacing any earlier one. Returns false when the
    /// point is not on that hole's green.
    @discardableResult
    func setPin(_ coordinate: CLLocationCoordinate2D, onHole index: Int, at date: Date) -> Bool {
        guard isOnGreen(coordinate, holeIndex: index) else { return false }
        let pin = PinLocation(holeIndex: index, coordinate: coordinate, setAt: date, source: .set)
        if let i = pins.firstIndex(where: { $0.holeIndex == index }) {
            pins[i] = pin
        } else {
            pins.append(pin)
        }
        return true
    }

    /// Takes each pin that replaces the one on its hole, by `PinLocation.isReplaced(by:)`: from
    /// the other device, from other golfers, or the green centers. Returns true if any changed.
    @discardableResult
    func mergePins(_ others: [PinLocation]) -> Bool {
        var changed = false
        for other in others where other.holeIndex >= 0 && other.holeIndex <= lastHoleIndex {
            if let i = pins.firstIndex(where: { $0.holeIndex == other.holeIndex }) {
                guard pins[i].isReplaced(by: other) else { continue }
                pins[i] = other
            } else {
                pins.append(other)
            }
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

    /// A center pin for every hole that has a green and no pin yet. Returns true if any were added.
    @discardableResult
    func addCenterPins() -> Bool {
        mergePins((0...lastHoleIndex).compactMap { index in
            greenCenter(holeIndex: index).map { PinLocation(holeIndex: index, coordinate: $0, setAt: date, source: .center) }
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

    /// Adds a start for hole `index` when it has none. Holes are played in order, so the start
    /// must fall between the starts of the holes before and after it; otherwise nothing changes.
    @discardableResult
    func startHole(_ index: Int, at date: Date, source: HoleStartSource) -> Bool {
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
    func strokeHit(onHole index: Int, at date: Date) -> Bool {
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
    func mergeTimeline(_ entries: [HoleStart]) -> Bool {
        let merged = HoleTimeline.merge(holeTimeline, entries)
        guard merged != holeTimeline else { return false }
        holeTimeline = merged
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
