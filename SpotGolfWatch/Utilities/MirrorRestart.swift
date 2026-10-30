import Foundation

/// Decides when the watch starts mirroring on its running workout: once per workout, again
/// after a failed start, and again on the same workout once it has been down long enough. A
/// new workout is never started for it, since each one is saved to Fitness.
enum MirrorRestart {
    enum Trigger {
        /// The watchdog's periodic check.
        case check
        /// The phone became reachable over WatchConnectivity, so it is likely back in range.
        case phoneReachable

        /// How long mirroring is down, and since the last start, before this starts it again.
        var wait: TimeInterval {
            switch self {
            case .check: 60
            case .phoneReachable: 15
            }
        }
    }

    /// Whether to start mirroring on the running workout.
    /// - Parameters:
    ///   - isAttached: mirroring was started on this workout. False for a new workout, and
    ///     after a failed start.
    ///   - startedAt: the last start on this workout.
    ///   - disconnectedSince: when mirroring last stopped being connected, or nil if it never was.
    static func shouldStart(_ trigger: Trigger, at now: Date, isAttached: Bool, isConnected: Bool,
                            startedAt: Date?, disconnectedSince: Date?) -> Bool {
        guard isAttached else { return true }
        guard !isConnected else { return false }
        let since = max(startedAt ?? .distantPast, disconnectedSince ?? .distantPast)
        return now.timeIntervalSince(since) >= trigger.wait
    }
}
