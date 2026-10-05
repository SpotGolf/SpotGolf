import Foundation
import CoreLocation
import CourseDataSwift

/// Phone: the one place that works out where the player probably hit the ball, with any club.
///
/// Golf is linear: the player walks from one ball to the next. On the wrist a full swing is
/// unmistakable: every recorded shot measured 13 g or more, while waiting, walking and handling
/// clubs stay under 10 g. So a full swing made while standing still is a stroke, and when several
/// are made at one spot the strongest is the shot, because practice swings come before it. Softer
/// swings, and stops with no swing, are offered only on and around the green, where putts and
/// chips the watch barely feels are made. Measured on the Coal Creek round of 2026-10-02; see
/// plans/2026-10-04-full-swing-strokes.md.
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
    /// A swing of this force or more is a full swing, and a stroke wherever it is made. Shots
    /// measured 13 to 38 g; the small movements of waiting and handling clubs stay under 10 g.
    static let fullSwingPeak: Float = 10
    /// Full swings this close in time, and within `sameShotRadius`, are practice swings and the
    /// shot, which is the strongest of them. A duff hit again from the same spot within this time
    /// is lost, and the player adds it by hand.
    static let sameShotWindow: TimeInterval = 60
    static let sameShotRadius: CLLocationDistance = 15
    /// A swing this close to one of the hole's tee boxes is on the hole, even where the centerline
    /// starts past the tee.
    static let teeShotRadius: CLLocationDistance = 10
    /// A stop farther than this from the hole's centerline is off the hole (the turn, the parking lot).
    static let maxCenterlineDistance: Double = 60
    /// Softer swings, and stops with no swing, count only on the green or this close to its edge:
    /// putts, and chips the watch barely felt.
    static let chipZoneMargin: CLLocationDistance = 30
    /// At most this many suggestions are offered per hole. Full swings are always kept; putts and
    /// chips fill the rest.
    static let maxPerHole = 10

    // MARK: - Suggestions

    /// The stroke suggestions for one hole of a round. Stops are found over the whole round, so
    /// moving a hole start never changes a stop or its ID. A stop is on the hole the player was
    /// playing when they walked away from it: a stop picks up a few fixes as the player slows
    /// down, so its start can fall just before the hole does. A hole with no start yet (no stroke
    /// on it) is also offered the stops after the last hole that has one; see `HoleTimeline.possibleHoles`.
    /// `minStop` is the shortest stop with no swing that is offered; `hidden` holds the IDs of
    /// dismissed and converted suggestions.
    static func suggestions(in round: Round, holeIndex: Int, points: [TrackPoint], swings: [StrokeSuggestion],
                            minStop: TimeInterval, hidden: Set<UUID> = []) -> [StrokeSuggestion] {
        let shape = HoleShape(hole: round.courseHole(at: holeIndex), course: round.course)
        return suggestions(on: shape, points: points, swings: swings, minStop: minStop, hidden: hidden) {
            round.possibleHoles(at: $0.end).contains(holeIndex)
        }
    }

    /// The stroke suggestions among the stops that `isOnHole` accepts by their start and end, in
    /// time order.
    ///
    /// A full swing made while stopped is a stroke. Full swings at one spot within `sameShotWindow`
    /// are one stroke, the strongest of them: practice swings come before the shot. A softer swing
    /// counts only on or near the green, where the strongest swing in a stop is the putt, and a
    /// stop with no swing there may be a putt or chip the watch missed.
    static func suggestions(on hole: HoleShape, points: [TrackPoint], swings: [StrokeSuggestion],
                            minStop: TimeInterval, hidden: Set<UUID> = [],
                            isOnHole: (_ stop: (start: Date, end: Date)) -> Bool = { _ in true }) -> [StrokeSuggestion] {
        /// A swing in the stop it was made in.
        struct Placed {
            let swing: StrokeSuggestion
            let peakG: Float
            let stopIndex: Int
            /// The fix nearest the swing, or the stop's center.
            let spot: Coordinate
        }

        let stops = stops(in: points).filter { isOnHole(($0.start, $0.end)) }
        var placed: [Placed] = []
        for swing in swings.sorted(by: { $0.timestamp < $1.timestamp }) {
            // A swing while walking, or as the player arrived, is not a stroke
            guard let peakG = swing.peakG,
                  let stopIndex = stops.firstIndex(where: { $0.contains(swing.timestamp, slack: stopSlack) }),
                  swing.timestamp >= stops[stopIndex].start else { continue }
            let stop = stops[stopIndex]
            let spot = nearestFix(to: swing.timestamp, in: points)
                .map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) } ?? stop.center
            // Off the hole: the turn, the parking lot. A tee box is on the hole.
            let atTee = hole.metersToTee(spot).map { $0 <= teeShotRadius } ?? false
            if !atTee, let off = hole.metersToCenterline(stop.center), off > maxCenterlineDistance { continue }
            placed.append(Placed(swing: swing, peakG: peakG, stopIndex: stopIndex, spot: spot))
        }

        // Full swings: the strongest of those made at one spot is the shot. Its ID comes from the
        // first swing there, which does not change as more arrive.
        var fullSwings: [StrokeSuggestion] = []
        var atOneSpot: [Placed] = []
        func finishShot() {
            guard let first = atOneSpot.first, let shot = atOneSpot.max(by: { $0.peakG < $1.peakG }) else { return }
            fullSwings.append(StrokeSuggestion(
                timestamp: shot.swing.timestamp, kind: shot.swing.kind,
                coordinate: CLLocationCoordinate2D(latitude: shot.spot.latitude, longitude: shot.spot.longitude),
                id: StrokeSuggestion.id(at: first.swing.timestamp)))
            atOneSpot = []
        }
        for full in placed where full.peakG >= fullSwingPeak {
            if let last = atOneSpot.last,
               full.swing.timestamp.timeIntervalSince(last.swing.timestamp) <= sameShotWindow,
               LocalDistance.meters(fromLat: last.spot.latitude, lon: last.spot.longitude,
                                    toLat: full.spot.latitude, lon: full.spot.longitude) <= sameShotRadius {
                atOneSpot.append(full)
            } else {
                finishShot()
                atOneSpot = [full]
            }
        }
        finishShot()

        // Putts, and chips the watch barely felt: softer swings and stops with no swing near the green
        var shortGame: [StrokeSuggestion] = []
        let stopsWithFullSwings = Set(placed.filter { $0.peakG >= fullSwingPeak }.map(\.stopIndex))
        for (index, stop) in stops.enumerated() where !stopsWithFullSwings.contains(index) {
            guard let toGreen = hole.metersToGreen(stop.center), toGreen <= chipZoneMargin else { continue }
            if let putt = placed.filter({ $0.stopIndex == index }).max(by: { $0.peakG < $1.peakG }) {
                shortGame.append(StrokeSuggestion(timestamp: putt.swing.timestamp, kind: putt.swing.kind,
                                                  coordinate: stop.coordinate, id: StrokeSuggestion.id(at: stop.start)))
            } else if stop.duration >= minStop {
                shortGame.append(StrokeSuggestion(timestamp: stop.start, kind: .stop(duration: stop.duration),
                                                  coordinate: stop.coordinate, id: StrokeSuggestion.id(at: stop.start)))
            }
        }

        let shownFullSwings = fullSwings.filter { !hidden.contains($0.id) }
        let shownShortGame = shortGame.filter { !hidden.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
            .prefix(max(0, maxPerHole - shownFullSwings.count))
        return (shownFullSwings + shownShortGame).sorted { $0.timestamp < $1.timestamp }
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
