import Foundation
import CoreLocation
import CourseDataSwift

/// Phone: the one place that works out where the player probably hit the ball, with any club,
/// and when each hole started.
///
/// Golf is linear: the player walks from one ball to the next, and from each green to the next
/// tee. So a hole ends when the player leaves its green for the last time, and a stroke is a
/// place the player stood still and swung. Stops near the green with no swing are offered too,
/// because the watch misses most putts.
enum StrokeFinder {
    // MARK: - Stops

    /// Fixes this close to the stop's center are part of it. Watch GPS drifts about 5 m.
    static let stopRadius: Double = 5 // meters
    /// A stay shorter than this is a pause in a walk, not a stop.
    static let minStopDuration: TimeInterval = 8
    /// This many fixes in a row may land outside `stopRadius` as GPS spikes before the stop ends.
    static let maxSpikes = 2
    /// Each new fix is checked against the median of the stop's latest this-many fixes.
    static let centerWindow = 15

    // MARK: - Strokes

    /// A swing's location is the watch GPS fix nearest in time, if one is this close.
    static let swingFixWindow: TimeInterval = 5
    /// A swing this close in time to a stop's ends still belongs to it; fixes come once a second.
    static let stopSlack: TimeInterval = 2
    /// A swing this close to the hole's tee box is a tee shot.
    static let teeShotRadius: CLLocationDistance = 10
    /// A stop farther than this from the hole's centerline is off the hole (the turn, the parking lot).
    static let maxCenterlineDistance: Double = 60
    /// Tee swings closer together than this are practice then the shot. Farther apart is a re-tee.
    static let teePracticeWindow: TimeInterval = 90
    /// A new stop must be this much closer to the green than the last stroke to be a new stroke.
    static let minCloserToGreen: CLLocationDistance = 3
    /// A stop with no swing on the green or this close to its edge can be a chip or putt.
    static let chipZoneMargin: CLLocationDistance = 30
    /// At most this many suggestions are offered per hole.
    static let maxPerHole = 10

    // MARK: - Hole starts

    /// A fix or swing this close to a tee counts as reaching the hole. Only the tee box and GPS
    /// drift: a ball hit over the green can land 20 m from the next tee.
    static let teeArrivalRadius: CLLocationDistance = 10
    /// A fix on the green or this close to its edge counts as at the green. Covers GPS drift and the fringe.
    static let greenEdgeMargin: CLLocationDistance = 10

    /// The shapes of one hole the rules need. Any of them may be missing.
    struct HoleShape {
        var tees: [[Coordinate]] = []
        var green: [Coordinate]?
        var centerline: [Coordinate] = []

        init(tees: [[Coordinate]] = [], green: [Coordinate]? = nil, centerline: [Coordinate] = []) {
            self.tees = tees
            self.green = green
            self.centerline = centerline
        }

        init(hole: Hole?, course: Course) {
            tees = hole?.tees.values.compactMap { id in
                guard let feature = course.findFeature(id: id), feature.type == .tee,
                      !feature.polygon.isEmpty else { return nil }
                return feature.polygon
            } ?? []
            green = hole?.green(from: course.features).map(\.polygon).flatMap { $0.isEmpty ? nil : $0 }
            centerline = hole?.centerline ?? []
        }

        func metersToTee(_ point: Coordinate) -> CLLocationDistance? {
            tees.map { StrokeFinder.distance(from: point, to: $0) }.min()
        }

        /// Meters from the green's edge: zero on the green.
        func metersToGreen(_ point: Coordinate) -> CLLocationDistance? {
            green.map { StrokeFinder.distance(from: point, to: $0) }
        }

        func metersToCenterline(_ point: Coordinate) -> Double? {
            LocalDistance.meters(fromLat: point.latitude, lon: point.longitude,
                                 toPolyline: centerline.map { ($0.latitude, $0.longitude) })
        }
    }

    // MARK: - Suggestions

    /// The stroke suggestions for one hole of a round. Stops are found over the whole round, so
    /// moving a hole start never changes a stop or its ID. A stop is on the hole the player was
    /// playing when they walked away from it: a stop picks up a few fixes as the player slows
    /// down, so its start can fall just before the hole does.
    /// `minStop` is the shortest stop with no swing that is offered; `hidden` holds the IDs of
    /// dismissed and converted suggestions.
    static func suggestions(in round: Round, holeIndex: Int, points: [TrackPoint], swings: [StrokeSuggestion],
                            minStop: TimeInterval, hidden: Set<UUID> = []) -> [StrokeSuggestion] {
        let shape = HoleShape(hole: round.courseHole(at: holeIndex), course: round.course)
        return suggestions(on: shape, points: points, swings: swings, minStop: minStop, hidden: hidden) {
            round.holeIndex(at: $0.end) == holeIndex
        }
    }

    /// The stroke suggestions among the stops that `isOnHole` accepts by their start and end, in
    /// time order.
    ///
    /// A swing made while stopped is a stroke: practice swings happen in the same stop, so only
    /// the last swing in a stop counts, and a new stop counts only when it is closer to the green.
    /// A stop with no swing is offered only near the green.
    static func suggestions(on hole: HoleShape, points: [TrackPoint], swings: [StrokeSuggestion],
                            minStop: TimeInterval, hidden: Set<UUID> = [],
                            isOnHole: (_ stop: (start: Date, end: Date)) -> Bool = { _ in true }) -> [StrokeSuggestion] {
        struct Candidate {
            let swing: StrokeSuggestion
            let stopIndex: Int
            let isTee: Bool
        }

        let stops = stops(in: points).filter { isOnHole(($0.start, $0.end)) }
        let swings = swings.filter(\.isSwing).sorted { $0.timestamp < $1.timestamp }
        var candidates: [Candidate] = []
        var stopsWithSwings = Set<Int>()
        for swing in swings {
            // A swing while walking, or as the player arrived, is not a stroke
            guard let stopIndex = stops.firstIndex(where: { $0.contains(swing.timestamp, slack: stopSlack) }),
                  swing.timestamp >= stops[stopIndex].start else { continue }
            stopsWithSwings.insert(stopIndex)
            let stop = stops[stopIndex]
            let spot = nearestFix(to: swing.timestamp, in: points)
                .map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) } ?? stop.center

            let isTee = hole.metersToTee(spot).map { $0 <= teeShotRadius } ?? false
            if !isTee, let off = hole.metersToCenterline(stop.center), off > maxCenterlineDistance { continue }

            let candidate = Candidate(swing: swing, stopIndex: stopIndex, isTee: isTee)
            if let previous = candidates.last {
                // Earlier swings in the same stop were practice
                if previous.stopIndex == stopIndex {
                    candidates[candidates.count - 1] = candidate
                    continue
                }
                if isTee && previous.isTee {
                    // Timed from this stop's last swing, so a practice swing on the way to a
                    // re-tee doesn't join the two tee shots
                    let lastInStop = swings.last { stop.contains($0.timestamp, slack: stopSlack) }?.timestamp ?? swing.timestamp
                    if lastInStop.timeIntervalSince(previous.swing.timestamp) < teePracticeWindow {
                        candidates[candidates.count - 1] = candidate
                        continue
                    }
                }
                // On the green every putt is closer to the hole, not to the green
                if !isTee && !previous.isTee,
                   let before = hole.metersToGreen(stops[previous.stopIndex].center),
                   let now = hole.metersToGreen(stop.center), now > 0,
                   before - now < minCloserToGreen {
                    continue // a step back for another swing, not a new stroke
                }
            }
            candidates.append(candidate)
        }

        var found = candidates.map { candidate in
            let stop = stops[candidate.stopIndex]
            return StrokeSuggestion(timestamp: candidate.swing.timestamp, kind: candidate.swing.kind,
                                    coordinate: stop.coordinate, id: StrokeSuggestion.id(forStopAt: stop.start))
        }
        // Chips and putts the watch missed
        for (index, stop) in stops.enumerated() where !stopsWithSwings.contains(index) && stop.duration >= minStop {
            guard let toGreen = hole.metersToGreen(stop.center), toGreen <= chipZoneMargin else { continue }
            found.append(StrokeSuggestion(timestamp: stop.start, kind: .stop(duration: stop.duration),
                                          coordinate: stop.coordinate, id: StrokeSuggestion.id(forStopAt: stop.start)))
        }
        return Array(found.filter { !hidden.contains($0.id) }.sorted { $0.timestamp < $1.timestamp }.prefix(maxPerHole))
    }

    /// When a stroke was probably hit: the time of the fix nearest to it in `points`, which
    /// should be its hole's GPS. Nil when there are no fixes.
    static func estimatedTime(of stroke: Stroke, in points: [TrackPoint]) -> Date? {
        points.min {
            LocalDistance.meters(fromLat: $0.latitude, lon: $0.longitude, toLat: stroke.latitude, lon: stroke.longitude) <
                LocalDistance.meters(fromLat: $1.latitude, lon: $1.longitude, toLat: stroke.latitude, lon: stroke.longitude)
        }?.timestamp
    }

    /// The fix nearest in time to `date`, within `swingFixWindow`.
    static func nearestFix(to date: Date, in points: [TrackPoint]) -> TrackPoint? {
        let nearest = points.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
        guard let nearest, abs(nearest.timestamp.timeIntervalSince(date)) <= swingFixWindow else { return nil }
        return nearest
    }

    // MARK: - Hole starts

    /// The round's hole timeline, fixed from the GPS path. Each hole starts just after the
    /// player leaves the previous hole's green for the last time before reaching its tee, or on
    /// reaching its tee when that green is missing. Holes the timeline skipped, and holes played
    /// after its last entry, are filled in where the path shows them. An entry the user set is
    /// never moved. Running it again on its own result changes nothing.
    static func holeStarts(round: Round, points: [TrackPoint], swings: [StrokeSuggestion]) -> [HoleStart] {
        let entries = HoleTimeline.normalized(round.holeTimeline)
        var filled: [HoleStart] = []
        for (i, entry) in entries.enumerated() {
            filled.append(entry)
            let next = i + 1 < entries.count ? entries[i + 1] : nil
            let lastHole = next.map { $0.holeIndex - 1 } ?? round.lastHoleIndex
            guard entry.holeIndex < lastHole else { continue }
            var after = entry.startedAt
            for hole in (entry.holeIndex + 1)...lastHole {
                guard let start = start(of: hole, round: round, after: after, before: next?.startedAt ?? .distantFuture,
                                        points: points, swings: swings) else { continue }
                filled.append(HoleStart(holeIndex: hole, startedAt: start, source: .estimated))
                after = start
            }
        }

        var fixed = HoleTimeline.normalized(filled)
        for i in fixed.indices where i > 0 && fixed[i].source != .userSet {
            let upper = i + 1 < fixed.count ? fixed[i + 1].startedAt : .distantFuture
            guard let start = start(of: fixed[i].holeIndex, round: round, after: fixed[i - 1].startedAt, before: upper,
                                    points: points, swings: swings),
                  start != fixed[i].startedAt else { continue }
            fixed[i].startedAt = start
            if fixed[i].source != .estimated {
                fixed[i].source = .corrected
            }
            fixed[i].version += 1
        }
        return HoleTimeline.normalized(fixed)
    }

    /// When `hole` started, between `after` and `before`: just after the last fix at the
    /// previous hole's green before the player reached this hole's tee, or on reaching the tee
    /// when the player was never at that green. Nil when the tee was not reached.
    private static func start(of hole: Int, round: Round, after: Date, before: Date,
                              points: [TrackPoint], swings: [StrokeSuggestion]) -> Date? {
        let tee = HoleShape(hole: round.courseHole(at: hole), course: round.course)
        guard !tee.tees.isEmpty else { return nil }
        let previous = hole > 0 ? HoleShape(hole: round.courseHole(at: hole - 1), course: round.course) : HoleShape()
        let window = points.filter { $0.timestamp > after && $0.timestamp < before }

        func isAtPreviousGreen(_ point: TrackPoint) -> Bool {
            previous.metersToGreen(Coordinate(latitude: point.latitude, longitude: point.longitude)).map { $0 <= greenEdgeMargin } ?? false
        }
        func isNearTee(_ point: TrackPoint) -> Bool {
            tee.metersToTee(Coordinate(latitude: point.latitude, longitude: point.longitude)).map { $0 <= teeArrivalRadius } ?? false
        }

        // The next tee is only reached after the previous green, so a tee passed on the way
        // there does not count
        let from = window.first(where: isAtPreviousGreen)?.timestamp ?? after
        let teeSwing = swings.first { swing in
            guard swing.isSwing, swing.timestamp >= from, swing.timestamp > after, swing.timestamp < before,
                  let fix = nearestFix(to: swing.timestamp, in: window) else { return false }
            return isNearTee(fix)
        }
        guard let arrival = teeSwing?.timestamp ?? window.first(where: { $0.timestamp >= from && isNearTee($0) })?.timestamp else {
            return nil
        }

        guard let lastAtGreen = window.last(where: { $0.timestamp < arrival && isAtPreviousGreen($0) }) else { return arrival }
        let leftGreen = window.first { $0.timestamp > lastAtGreen.timestamp }?.timestamp ?? arrival
        return min(leftGreen, arrival)
    }

    // MARK: - Geometry

    /// Meters from a point to a polygon's nearest edge: zero inside it.
    static func distance(from point: Coordinate, to polygon: [Coordinate]) -> CLLocationDistance {
        guard !polygon.isEmpty else { return .infinity }
        if PolygonGeometry.contains(point, in: polygon) { return 0 }
        let ring = (polygon + [polygon[0]]).map { (latitude: $0.latitude, longitude: $0.longitude) }
        return LocalDistance.meters(fromLat: point.latitude, lon: point.longitude, toPolyline: ring)
            ?? LocalDistance.meters(fromLat: point.latitude, lon: point.longitude,
                                    toLat: polygon[0].latitude, lon: polygon[0].longitude)
    }

    // MARK: - Stops

    /// A place the player stood still.
    private struct Stop {
        let start: Date
        let end: Date
        /// The median of the stop's fixes, which a stray fix barely moves.
        let center: Coordinate

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        }

        var duration: TimeInterval { end.timeIntervalSince(start) }

        /// True when `date` falls in the stop, or within `slack` of either end.
        func contains(_ date: Date, slack: TimeInterval = 0) -> Bool {
            date >= start.addingTimeInterval(-slack) && date <= end.addingTimeInterval(slack)
        }
    }

    /// The stops in `points`, in time order. `points` must be in time order.
    private static func stops(in points: [TrackPoint]) -> [Stop] {
        var stops: [Stop] = []
        var first = 0
        while first < points.count {
            var members = [first]
            var misses = 0
            var next = first + 1
            while next < points.count {
                let center = median(members.suffix(centerWindow).map { points[$0] })
                let point = points[next]
                if LocalDistance.meters(fromLat: center.latitude, lon: center.longitude,
                                        toLat: point.latitude, lon: point.longitude) <= stopRadius {
                    members.append(next)
                    misses = 0
                } else {
                    misses += 1
                    if misses > maxSpikes { break }
                }
                next += 1
            }

            let last = members[members.count - 1]
            guard points[last].timestamp.timeIntervalSince(points[first].timestamp) >= minStopDuration else {
                first += 1
                continue
            }
            stops.append(Stop(start: points[first].timestamp, end: points[last].timestamp,
                              center: median(members.map { points[$0] })))
            first = last + 1
        }
        return stops
    }

    private static func median(_ points: [TrackPoint]) -> Coordinate {
        Coordinate(latitude: median(points.map(\.latitude)), longitude: median(points.map(\.longitude)))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
