import CoreLocation

extension LocationManager {
    /// Keeps fixes coming while the wrist is down. Needs the location background mode.
    func setUpdatesInBackground() {
        manager.allowsBackgroundLocationUpdates = true
    }
}
