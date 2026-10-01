import CoreLocation

/// Reads and asks for location permission. Precise location is required: without it a fix
/// can be kilometers off, which is no use for finding a ball.
@MainActor
final class LocationPermission: NSObject {
    private let manager = CLLocationManager()
    private var answer: CheckedContinuation<Void, Never>?
    private var changed: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var state: PermissionState {
        Self.state(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
    }

    /// Granted only with precise location. Denied, restricted, or approximate is denied.
    nonisolated static func state(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) -> PermissionState {
        switch status {
        case .notDetermined:
            return .notAsked
        case .authorizedWhenInUse, .authorizedAlways:
            return accuracy == .fullAccuracy ? .granted : .denied
        default:
            return .denied
        }
    }

    /// Shows the prompt and returns once the user answers.
    func request() async {
        await withCheckedContinuation { continuation in
            answer = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Calls `changed` on every change, such as an "Allow Once" grant running out when the
    /// app leaves the screen.
    func observe(_ changed: @escaping () -> Void) {
        self.changed = changed
    }
}

extension LocationPermission: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        changed?()
        // Also called when the delegate is set, before any answer
        guard manager.authorizationStatus != .notDetermined, let answer else { return }
        self.answer = nil
        answer.resume()
    }
}
