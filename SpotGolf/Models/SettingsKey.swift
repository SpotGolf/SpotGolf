import Foundation

/// The phone's settings, saved in `UserDefaults`. Views read them with `@AppStorage`.
enum SettingsKey {
    /// How long the player must stand still for a stroke suggestion, in seconds.
    static let stationaryThreshold = "stationaryThreshold"
    /// Uploads the pins the player sets, for other golfers on the same course.
    static let sharePins = "sharePins"
    /// Saves `debug` log lines, on the phone and the watch.
    static let debugLogging = "debugLogging"

    static var defaults: [String: Any] {
        [stationaryThreshold: 30.0, sharePins: true, debugLogging: false]
    }

    /// Gives code outside views the same defaults `@AppStorage` uses.
    static func registerDefaults(in store: UserDefaults = .standard) {
        store.register(defaults: defaults)
    }

    /// Puts every setting back to its default, so UI tests start the same each time.
    static func reset(in store: UserDefaults = .standard) {
        for key in defaults.keys {
            store.removeObject(forKey: key)
        }
    }
}
