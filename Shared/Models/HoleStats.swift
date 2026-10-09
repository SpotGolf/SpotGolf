import CoreLocation
import CourseDataSwift
import Foundation

/// A played hole's putts, fairway, and green, worked out from its strokes and the course
/// shapes. `RoundStore` saves them on the hole each time its strokes change. See
/// plans/2026-10-09-scorecard.md.
struct HoleStats: Codable, Equatable {
    /// Regular strokes on the green.
    var putts: Int
    /// The tee shot stopped on the fairway or the green. Nil on a par 3, or before the second
    /// stroke.
    var fairway: Bool?
    /// The ball reached the green in par − 2 strokes or fewer.
    var green: Bool
}

extension Round {
    /// The stats of hole `index` from its strokes, or nil when it has none.
    func workOutStats(holeIndex index: Int) -> HoleStats? {
        let strokes = hole(at: index).strokes
        guard !strokes.isEmpty else { return nil }
        let par = courseHole(at: index)?.par
        let onGreen = strokes.map { $0.type == .regular && isOnGreen($0.coordinate, holeIndex: index) }

        var fairway: Bool?
        if let par, par >= 4, strokes.count >= 2 {
            let second = strokes[1]
            fairway = second.type == .regular
                && (onGreen[1] || isOnFairway(second.coordinate, holeIndex: index))
        }

        // Stroke number n on the green took n - 1 strokes to get there. A hole holed from off the
        // green looks the same as one still being played, so it misses.
        var green = false
        if let par, let firstOnGreen = onGreen.firstIndex(of: true) {
            green = firstOnGreen <= par - 2
        }

        return HoleStats(putts: onGreen.filter { $0 }.count, fairway: fairway, green: green)
    }

    /// Saves the stats of every hole from its strokes.
    func updateStats() {
        holes = holes.indices.map { index in
            var hole = holes[index]
            hole.stats = workOutStats(holeIndex: index)
            return hole
        }
    }

    /// True when a played hole has no saved stats, as in rounds saved before stats were.
    var needsStats: Bool {
        holes.contains { !$0.strokes.isEmpty && $0.stats == nil }
    }

    /// True when `coordinate` is on one of hole `index`'s fairways.
    func isOnFairway(_ coordinate: CLLocationCoordinate2D, holeIndex index: Int) -> Bool {
        guard let courseHole = courseHole(at: index) else { return false }
        return courseHole.onFairway(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                    from: course.features)
    }
}
