import Foundation
import CoreLocation
import CourseDataSwift

/// Phone: repairs a round's hole timeline from the watch's GPS, its swings, and the marks.
///
/// - A jump over holes fills in each skipped hole with the first time the player came near
///   its tee (a swing there first, since that is likely the tee shot).
/// - A mark proves which hole the player was on at that moment, so hole k must start after
///   the last mark on hole k-1 and no later than the first mark on hole k. An entry outside
///   that window is moved into it.
///
/// Running it again on its own result changes nothing, so it can run after every change.
enum HoleTimelineFixer {
    /// A fix or swing this close to a tee counts as reaching the hole.
    static let teeRadius: CLLocationDistance = 20

    static func fixed(_ round: Round, points: [TrackPoint], swings: [Swing]) -> [HoleStart] {
        var entries = HoleTimeline.normalized(round.holeTimeline)
        entries = correctedFromMarks(entries, round: round, points: points, swings: swings)
        entries = filledIn(entries, round: round, points: points, swings: swings)
        return HoleTimeline.normalized(entries)
    }

    // MARK: - Marks

    /// Moves entries the marks show are wrong.
    static func correctedFromMarks(_ entries: [HoleStart], round: Round,
                                   points: [TrackPoint], swings: [Swing]) -> [HoleStart] {
        var entries = entries
        // An entry the user set by hand is never moved
        for i in entries.indices where i > 0 && entries[i].source != .userSet {
            let hole = entries[i].holeIndex
            let firstMark = round.hole(at: hole).marks.map(\.timestamp).min()
            let lastEarlierMark = hole > 0 ? round.hole(at: hole - 1).marks.map(\.timestamp).max() : nil

            let start = entries[i].startedAt
            let tooEarly = lastEarlierMark.map { start <= $0 } ?? false
            let tooLate = firstMark.map { start > $0 } ?? false
            guard tooEarly || tooLate else { continue }

            // The new time must stay between the neighboring entries
            let lower = max(lastEarlierMark ?? .distantPast, entries[i - 1].startedAt)
            let next = i + 1 < entries.count ? entries[i + 1].startedAt : .distantFuture
            let upper = min(firstMark ?? next, next)
            guard lower < upper else { continue }

            let found = firstTeeArrival(hole: hole, round: round, after: lower, before: upper,
                                        points: points, swings: swings)
            // Strictly before the next entry, so the two can't swap places
            guard let newStart = found ?? firstMark, newStart > lower, newStart <= upper, newStart < next,
                  newStart != start else { continue }
            entries[i].startedAt = newStart
            entries[i].source = .corrected
            entries[i].version += 1
        }
        return entries
    }

    // MARK: - Skipped holes

    /// Adds an estimated entry for each hole a jump skipped, where the GPS shows it.
    static func filledIn(_ entries: [HoleStart], round: Round,
                         points: [TrackPoint], swings: [Swing]) -> [HoleStart] {
        var result: [HoleStart] = []
        for (i, entry) in entries.enumerated() {
            result.append(entry)
            guard i + 1 < entries.count else { continue }
            let next = entries[i + 1]
            var after = entry.startedAt
            for hole in (entry.holeIndex + 1)..<max(next.holeIndex, entry.holeIndex + 1) {
                guard let arrival = firstTeeArrival(hole: hole, round: round, after: after, before: next.startedAt,
                                                    points: points, swings: swings) else { continue }
                result.append(HoleStart(holeIndex: hole, startedAt: arrival, source: .estimated))
                after = arrival
            }
        }
        return result
    }

    // MARK: - Tees

    /// The first swing near the hole's tee in `(after, before)`, or else the first fix near it.
    static func firstTeeArrival(hole: Int, round: Round, after: Date, before: Date,
                                points: [TrackPoint], swings: [Swing]) -> Date? {
        let tees = teePolygons(hole: hole, round: round)
        guard !tees.isEmpty else { return nil }

        func isNearTee(_ coordinate: Coordinate) -> Bool {
            tees.contains { distance(from: coordinate, to: $0) <= teeRadius }
        }

        let window = points.filter { $0.timestamp > after && $0.timestamp < before }
        for swing in swings where swing.timestamp > after && swing.timestamp < before {
            if let fix = StreamReceiver.nearestFix(to: swing.timestamp, in: window),
               isNearTee(Coordinate(latitude: fix.latitude, longitude: fix.longitude)) {
                return swing.timestamp
            }
        }
        return window.first { isNearTee(Coordinate(latitude: $0.latitude, longitude: $0.longitude)) }?.timestamp
    }

    static func teePolygons(hole: Int, round: Round) -> [[Coordinate]] {
        guard let courseHole = round.courseHole(at: hole) else { return [] }
        return courseHole.tees.values.compactMap { id in
            guard let feature = round.course.findFeature(id: id), feature.type == .tee,
                  !feature.polygon.isEmpty else { return nil }
            return feature.polygon
        }
    }

    /// Meters from a point to a polygon: zero inside it.
    static func distance(from point: Coordinate, to polygon: [Coordinate]) -> CLLocationDistance {
        if PolygonGeometry.contains(point, in: polygon) { return 0 }
        let nearest = PolygonGeometry.nearestPoint(on: polygon, to: point)
        return point.clLocation.distance(from: nearest.clLocation)
    }
}
