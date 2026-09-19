import Foundation
import CoreLocation

@MainActor
class LocationManager: NSObject, ObservableObject {
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var recentLocations: [CLLocation] = []
    private static let maxRecent = 3
    private static let maxAccuracy: CLLocationAccuracy = 20 // meters

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func startUpdating() {
        recentLocations.removeAll()
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
}

extension LocationManager: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
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
        print("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}
