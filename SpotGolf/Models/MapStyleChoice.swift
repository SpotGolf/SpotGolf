import MapKit
import SwiftUI

/// How the round map draws the ground: Apple's drawn map, satellite photos, or photos with
/// the roads and names on top. The map's style button opens `MapStyleSheet` to pick one, and
/// the last choice is kept in the settings under `SettingsKey.mapStyle`.
enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }

    /// The map button's symbol, as Apple Maps' button changes with the mode: a folded map for
    /// the drawn map, a globe for the photo styles.
    var symbolName: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.americas.fill"
        case .hybrid: "globe.americas"
        }
    }

    /// The style the map is drawn with. The photo styles sit on real coordinates, so the
    /// player's dot lands where they stand; the drawn style can be off by a few yards.
    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: .flat)
        case .hybrid: .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
        }
    }

    /// The same style for a map snapshot, as the style sheet's previews are.
    var mapConfiguration: MKMapConfiguration {
        switch self {
        case .standard:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case .satellite:
            return MKImageryMapConfiguration(elevationStyle: .flat)
        case .hybrid:
            let configuration = MKHybridMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        }
    }

    /// The choice kept in the settings, or the standard map when none is kept.
    static func stored(in store: UserDefaults = .standard) -> MapStyleChoice {
        store.string(forKey: SettingsKey.mapStyle).flatMap(MapStyleChoice.init(rawValue:)) ?? .standard
    }

    /// Keeps this choice in the settings, for the next time the map opens.
    func store(in store: UserDefaults = .standard) {
        store.set(rawValue, forKey: SettingsKey.mapStyle)
    }
}
