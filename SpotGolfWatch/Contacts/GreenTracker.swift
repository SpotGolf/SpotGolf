import CoreLocation
import CourseDataSwift

/// Which of the round's greens the player is at, for contact detection. Every hole's green
/// counts, whichever hole is shown, so picking another hole never stops putts being heard.
///
/// The player is at a green within `zoneMargin` of its edge, the nearest one when several are.
/// They stay at it until their fixes have been beyond the zone for `exitDelay`.
struct GreenTracker {
    /// Fixes beyond the zone for this long leave the green.
    static let exitDelay: TimeInterval = 10

    enum Change: Equatable {
        /// At the green of the hole at playing-order `holeIndex`.
        case entered(holeIndex: Int)
        case left
    }

    /// The hole at playing-order index `holeIndex` and its green; holes without one are left out.
    private var greens: [(holeIndex: Int, shape: HoleShape)] = []
    /// The playing-order index of the hole whose green the player is at, or nil.
    private(set) var holeIndex: Int?
    private var outsideSince: Date?

    init(courseSelection: CourseSelection? = nil) {
        guard let courseSelection else { return }
        greens = courseSelection.orderedHoles.enumerated().compactMap { index, hole in
            let shape = HoleShape(hole: hole, course: courseSelection.course)
            return shape.green == nil ? nil : (index, shape)
        }
    }

    /// Returns the change this fix makes, or nil.
    mutating func update(location: CLLocation, zoneMargin: CLLocationDistance) -> Change? {
        let point = Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        if let holeIndex, let current = greens.first(where: { $0.holeIndex == holeIndex }),
           let toGreen = current.shape.metersToGreen(point) {
            if toGreen <= zoneMargin {
                outsideSince = nil
                return nil
            }
            guard let outsideSince else {
                outsideSince = location.timestamp
                return nil
            }
            guard location.timestamp.timeIntervalSince(outsideSince) >= Self.exitDelay else { return nil }
            leave()
            return .left
        }
        let nearest = greens
            .compactMap { green in green.shape.metersToGreen(point).map { (green.holeIndex, $0) } }
            .filter { $0.1 <= zoneMargin }
            .min { $0.1 < $1.1 }
        guard let nearest else { return nil }
        holeIndex = nearest.0
        outsideSince = nil
        return .entered(holeIndex: nearest.0)
    }

    /// Forgets the green, so the next fix within a zone enters it again.
    mutating func leave() {
        holeIndex = nil
        outsideSince = nil
    }
}
