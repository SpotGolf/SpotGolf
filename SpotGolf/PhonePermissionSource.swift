import Foundation

/// Reads and asks for the phone's real permissions. The watch app shares location, motion and
/// health with the phone app, so they are asked for here, where the prompts show and Settings
/// can be opened. The microphone is the watch's own.
@MainActor
final class PhonePermissionSource: PermissionSource {
    /// The permissions the phone app requires before it opens.
    static let required = AppPermission.allCases.filter { !$0.isAskedOnWatch }

    private let location = LocationPermission()
    private let motion = MotionPermission()
    private let health = HealthPermission()

    func state(of permission: AppPermission) -> PermissionState {
        switch permission {
        case .location: location.state
        case .motion: motion.state
        case .health: health.state
        // The phone never records; the watch asks for its own microphone
        case .microphone: .granted
        }
    }

    func request(_ permission: AppPermission) async {
        switch permission {
        case .location: await location.request()
        case .motion: await motion.request()
        case .health: await health.request()
        case .microphone: break
        }
    }

    func observe(_ changed: @escaping () -> Void) {
        location.observe(changed)
    }
}
