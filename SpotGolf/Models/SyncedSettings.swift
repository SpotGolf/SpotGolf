import Foundation

/// The settings saved to iCloud: Stroke Suggestions, Clubs and Pins. The rest stay on the phone.
/// See plans/2026-10-22-cloudkit-sync.md.
struct SyncedSettings: Codable, Equatable {
    struct Club: Codable, Equatable {
        var clubID: String
        /// Nil for the putter.
        var distance: Int?
    }

    var stationaryThreshold: Double
    var greenZone: Double
    var sharePins: Bool
    /// Sorted by club ID, so the same bag always compares equal.
    var clubs: [Club]

    /// The settings as this phone has them.
    @MainActor
    init(defaults: UserDefaults, bag: GolfBagStore) {
        stationaryThreshold = defaults.double(forKey: SettingsKey.stationaryThreshold)
        greenZone = defaults.double(forKey: SettingsKey.greenZone)
        sharePins = defaults.bool(forKey: SettingsKey.sharePins)
        clubs = bag.entries.map { Club(clubID: $0.clubID, distance: $0.distance) }
    }

    init(stationaryThreshold: Double, greenZone: Double, sharePins: Bool, clubs: [Club]) {
        self.stationaryThreshold = stationaryThreshold
        self.greenZone = greenZone
        self.sharePins = sharePins
        self.clubs = clubs.sorted { $0.clubID < $1.clubID }
    }

    /// Makes this phone's settings match.
    @MainActor
    func apply(defaults: UserDefaults, bag: GolfBagStore) {
        defaults.set(stationaryThreshold, forKey: SettingsKey.stationaryThreshold)
        defaults.set(greenZone, forKey: SettingsKey.greenZone)
        defaults.set(sharePins, forKey: SettingsKey.sharePins)
        if bag.entries.map({ Club(clubID: $0.clubID, distance: $0.distance) }) != clubs {
            bag.replace(with: clubs.map { ($0.clubID, $0.distance) })
        }
    }
}
