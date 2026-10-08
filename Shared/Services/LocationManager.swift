import Foundation
import Observation
import os
import CoreLocation

@MainActor
@Observable
class LocationManager: NSObject {
    var lastLocation: CLLocation? {
        didSet {
            for listener in locationListeners {
                listener(lastLocation)
            }
        }
    }
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Called with every valid fix, before accuracy filtering and smoothing.
    @ObservationIgnored var onRawLocations: (@MainActor ([CLLocation]) -> Void)?

    @ObservationIgnored private var locationListeners: [(CLLocation?) -> Void] = []

    let manager = CLLocationManager()
    @ObservationIgnored private var recentLocations: [CLLocation] = []
    private static let maxRecent = 3
    private static let maxAccuracy: CLLocationAccuracy = 20 // meters

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Adds a listener called with every new `lastLocation`. Listeners stay for the manager's life.
    func addLocationListener(_ listener: @escaping (CLLocation?) -> Void) {
        locationListeners.append(listener)
    }

    private(set) var isUpdating = false
    // Who wants updates. They stop when the last one is done.
    private var owners: Set<String> = []

    /// Safe to call again while updating; the running updates are left alone.
    func startUpdating(for owner: String = "app") {
        owners.insert(owner)
        guard !isUpdating else { return }
        isUpdating = true
        Log.location.notice("Location updates started")
        recentLocations.removeAll()
        manager.startUpdatingLocation()
    }

    /// Stops the updates once no other owner wants them.
    func stopUpdating(for owner: String = "app") {
        owners.remove(owner)
        guard owners.isEmpty, isUpdating else { return }
        isUpdating = false
        Log.location.notice("Location updates stopped")
        manager.stopUpdatingLocation()
    }
}

extension LocationManager: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let valid = locations.filter { $0.horizontalAccuracy >= 0 }
        if !valid.isEmpty {
            onRawLocations?(valid)
        }

        guard let location = locations.last else { return }

        #if targetEnvironment(simulator)
        Task { @MainActor in
            lastLocation = location
        }
        #else
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maxAccuracy else { return }

        Task { @MainActor in
            recentLocations.append(location)
            if recentLocations.count > Self.maxRecent {
                recentLocations.removeFirst(recentLocations.count - Self.maxRecent)
            }

            // Weighted average — more recent and more accurate readings count more
            var totalLat = 0.0, totalLon = 0.0, totalWeight = 0.0
            for (i, loc) in recentLocations.enumerated() {
                let recencyWeight = Double(i + 1) // newer = higher
                let accuracyWeight = 1.0 / max(loc.horizontalAccuracy, 1)
                let weight = recencyWeight * accuracyWeight
                totalLat += loc.coordinate.latitude * weight
                totalLon += loc.coordinate.longitude * weight
                totalWeight += weight
            }

            let bestAccuracy = recentLocations.map(\.horizontalAccuracy).min() ?? location.horizontalAccuracy
            let smoothed = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: totalLat / totalWeight,
                                                   longitude: totalLon / totalWeight),
                altitude: location.altitude,
                horizontalAccuracy: bestAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                timestamp: location.timestamp
            )
            lastLocation = smoothed
        }
        #endif
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.location.error("Location error: \(String(describing: error), privacy: .public)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        Log.location.notice("Location authorization: \(manager.authorizationStatus.rawValue, privacy: .public)")
        // A one-off fix is only needed when continuous updates are not already running
        if !isUpdating,
           manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}
