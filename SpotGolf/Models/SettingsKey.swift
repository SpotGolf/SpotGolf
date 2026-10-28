import Foundation

/// The phone's settings, saved in `UserDefaults`. Views read them with `@AppStorage`.
enum SettingsKey {
    /// How long the player must stand still for a stroke suggestion, in seconds.
    static let stationaryThreshold = "stationaryThreshold"
    /// Uploads the pins the player sets, for other golfers on the same course.
    static let sharePins = "sharePins"
    /// The watch records raw sensor data on the greens during a round. Hidden in Settings until
    /// unlocked by tapping the version.
    static let developerMode = "developerMode"
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

    /// Putt Data Sharing: the consent version the player agreed to, absent before they agree.
    static let puttSharingConsent = "puttSharingConsent"
    /// Putt Data Sharing: the random ID shared sessions carry, made at consent.
    static let puttSharingSharerID = "puttSharingSharerID"
    /// Putt Data Sharing: the equipment profile, JSON.
    static let puttSharingEquipment = "puttSharingEquipment"
    /// Putt Data Sharing: sessions upload over cellular too, not only Wi-Fi.
    static let puttSharingCellular = "puttSharingCellular"

    static var defaults: [String: Any] {
        [stationaryThreshold: 30.0, greenZone: HoleShape.chipZoneMargin, sharePins: true,
         developerMode: false, mapStyle: MapStyleChoice.standard.rawValue, bagSeeded: false, iCloudSync: true]
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
        for key in [puttSharingConsent, puttSharingSharerID, puttSharingEquipment, puttSharingCellular] {
            store.removeObject(forKey: key)
        }
    }
}
