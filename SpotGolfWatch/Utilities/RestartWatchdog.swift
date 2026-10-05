import Foundation

/// Decides when to restart something that can stop on its own, like sensor updates or a
/// workout. An error restarts it at most once per `interval`, and a check every `interval`
/// restarts it when it is not active, or, when it sends data, no data has arrived for that long.
/// A start gets a full `interval` to become active before the check restarts it.
struct RestartWatchdog {
    static let interval: TimeInterval = 10

    private let checksData: Bool
    // A start counts as data, so a new start gets a full interval for its first data
    private var lastDataAt: Date
    private var lastStartAt: Date

    init(startedAt now: Date, checksData: Bool) {
        self.checksData = checksData
        lastDataAt = now
        lastStartAt = now
    }

    mutating func started(at now: Date) {
        lastDataAt = now
        lastStartAt = now
    }

    mutating func dataReceived(at now: Date) {
        lastDataAt = now
    }

    /// True when an error should restart: not within `interval` of the last start. Errors
    /// from a start that keeps failing are left to the periodic check.
    func shouldRestartAfterError(at now: Date) -> Bool {
        now.timeIntervalSince(lastStartAt) >= Self.interval
    }

    /// True when the periodic check should restart.
    func shouldRestart(at now: Date, isActive: Bool) -> Bool {
        guard now.timeIntervalSince(lastStartAt) >= Self.interval else { return false }
        return !isActive || (checksData && now.timeIntervalSince(lastDataAt) > Self.interval)
    }
}
