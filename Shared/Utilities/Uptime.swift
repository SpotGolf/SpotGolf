import Foundation

/// The clock the sensors and the microphone stamp their data with: seconds since boot, not
/// counting sleep. One place turns it into dates, so every stream converts the same way.
enum Uptime {
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// The date `uptime` seconds after boot falls on, by the clocks as they stand now.
    static func date(at uptime: Double) -> Date {
        Date(timeIntervalSinceNow: uptime - now)
    }
}
