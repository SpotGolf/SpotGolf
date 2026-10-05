import CoreLocation

extension LocationManager {
    /// Keeps fixes coming with the app in the background. Needs the location background mode.
    func setUpdatesInBackground(_ enabled: Bool) {
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
    }
}
