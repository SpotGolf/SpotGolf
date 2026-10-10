import Foundation

/// The times of taps on the app's own buttons. A tap is a loud 2 to 3.6 g knock on the watch,
/// so the swing and contact detectors ignore readings around one. Kept on the uptime clock the
/// sensor readings use, so no clock conversion sits between a tap and its readings. Written on
/// the main actor, read on the sensor threads.
final class TapGuard: @unchecked Sendable {
    /// Readings this close to a tap, either side, are ignored.
    static let window: TimeInterval = 1

    private let lock = NSLock()
    private var taps: [Double] = []

    func tapped(atUptime uptime: Double = Uptime.now) {
        lock.lock()
        taps.append(uptime)
        taps.removeAll { uptime - $0 > 10 }
        lock.unlock()
    }

    /// Whether a reading at this uptime falls within `window` of a tap.
    func covers(uptime: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return taps.contains { abs(uptime - $0) <= Self.window }
    }
}
