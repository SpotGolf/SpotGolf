import Foundation

/// Reads the watch's real permissions. Location, motion and health are shared with the iPhone
/// app and asked for there; the microphone is asked for here.
@MainActor
final class SystemPermissionSource: PermissionSource {
    private let location = LocationPermission()
    private let motion = MotionPermission()
    private let health = HealthPermission()

    func state(of permission: AppPermission) -> PermissionState {
        switch permission {
        case .location: location.state
        case .motion: motion.state
        case .health: health.state
        case .microphone: MicrophoneInput.permission
        }
    }

    func request(_ permission: AppPermission) async {
        guard permission == .microphone else { return }
        await MicrophoneInput.requestPermission()
    }

    func observe(_ changed: @escaping () -> Void) {
        location.observe(changed)
    }
}
