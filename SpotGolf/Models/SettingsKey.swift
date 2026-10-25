import Foundation

/// The phone's settings, saved in `UserDefaults`. Views read them with `@AppStorage`.
enum SettingsKey {
    /// How long the player must stand still for a stroke suggestion, in seconds.
    static let stationaryThreshold = "stationaryThreshold"
    /// Uploads the pins the player sets, for other golfers on the same course.
    static let sharePins = "sharePins"
    /// Saves `debug` log lines, on the phone and the watch.
    static let debugLogging = "debugLogging"
    /// The watch's Putt Lab records raw sensor data on the greens during a round.
    static let puttLabInRounds = "puttLabInRounds"
    /// Meters from the green's edge that count as on the green: where putts and chips are
    /// suggested and the watch listens for contacts.
    static let greenZone = "greenZone"
    /// How the round map draws the ground, a `MapStyleChoice` raw value.
    static let mapStyle = "mapStyle"
    /// Set once `GolfBagStore` has put the standard bag in the store.
    static let bagSeeded = GolfBagStore.seededKey
    /// Saves rounds and the synced settings to iCloud. Stays on this phone.
    static let iCloudSync = "iCloudSync"
    /// When the synced settings last changed on this phone, or the change they were downloaded
    /// with. Not set until they first change or download.
    static let settingsChangedAt = "settingsChangedAt"

    static var defaults: [String: Any] {
        [stationaryThreshold: 30.0, greenZone: HoleShape.chipZoneMargin, sharePins: true, debugLogging: false,
         puttLabInRounds: true, mapStyle: MapStyleChoice.standard.rawValue, bagSeeded: false, iCloudSync: true]
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
        store.removeObject(forKey: settingsChangedAt)
    }
}
