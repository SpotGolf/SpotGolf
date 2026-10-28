import CoreLocation

/// Picks a session's one starting location from the fixes after Start: the first good enough,
/// or else the best seen in `maxWait`. The session never waits for it. See
/// `plans/2026-10-27-putt-data-sharing.md`, section 2.4.
struct StartingFix {
    /// A fix this accurate or better is kept at once.
    static let goodAccuracy: CLLocationAccuracy = 30
    /// Updates stop this long after Start, keeping the best fix seen.
    static let maxWait: TimeInterval = 60

    /// When Start was tapped, on the fixes' clock.
    let startDate: Date
    private(set) var best: CLLocation?
    private(set) var isDone = false

    init(startDate: Date) {
        self.startDate = startDate
    }

    /// Takes fixes as they arrive. True once a fix is kept and updates can stop.
    @discardableResult
    mutating func add(_ locations: [CLLocation]) -> Bool {
        guard !isDone else { return true }
        for location in locations where location.horizontalAccuracy >= 0 {
            if best.map({ location.horizontalAccuracy < $0.horizontalAccuracy }) ?? true {
                best = location
            }
            if location.horizontalAccuracy <= Self.goodAccuracy {
                best = location
                isDone = true
                return true
            }
        }
        return false
    }

    /// `maxWait` has passed: the best fix seen is kept, if any.
    mutating func timeUp() {
        isDone = true
    }

    /// The location for `sharing.json`, rounded, with seconds from `sessionStart`.
    func location(sessionStart: Date) -> PuttSharing.Location? {
        guard let best else { return nil }
        return PuttSharing.Location(latitude: PuttSharing.Location.rounded(best.coordinate.latitude),
                                    longitude: PuttSharing.Location.rounded(best.coordinate.longitude),
                                    horizontalAccuracy: best.horizontalAccuracy,
                                    t: best.timestamp.timeIntervalSince(sessionStart))
    }
}
