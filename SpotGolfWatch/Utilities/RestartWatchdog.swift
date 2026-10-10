import Foundation

/// Decides when to restart something that can stop on its own, like sensor updates or a
/// workout. An error restarts it at most once per `interval`, and a check every `interval`
/// restarts it when it is not active, or, when it sends data, no data has arrived for that long.
/// A start gets a full `interval` to become active before the check restarts it. Restarts in a
/// row with no data between them are counted: at `stallRestarts` the thing is stalled, and
/// restarting it the same way again is not going to help.
struct RestartWatchdog {
    static let interval: TimeInterval = 10
    /// Restarts in a row with no data between them that mean the input is stalled.
    static let stallRestarts = 3

    private let checksData: Bool
    // A start counts as data, so a new start gets a full interval for its first data
    private var lastDataAt: Date
    private var lastStartAt: Date
    // Whether data has arrived since the last start; true at first, so the first start is not a restart
    private var dataSinceStart = true

    /// Restarts in a row with no data since the start before each.
    private(set) var restartsWithoutData = 0

    init(startedAt now: Date, checksData: Bool) {
        self.checksData = checksData
        lastDataAt = now
        lastStartAt = now
    }

    mutating func started(at now: Date) {
        restartsWithoutData = dataSinceStart ? 0 : restartsWithoutData + 1
        dataSinceStart = false
        lastDataAt = now
        lastStartAt = now
    }

    mutating func dataReceived(at now: Date) {
        lastDataAt = now
        dataSinceStart = true
    }

    /// True once `stallRestarts` restarts in a row brought no data.
    var isStalled: Bool {
        restartsWithoutData >= Self.stallRestarts
    }

    /// Once a stall has been acted on, the count starts over, so a stall that goes on fires again.
    mutating func stallReported() {
        restartsWithoutData = 0
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
