import Foundation

/// Reads the watch's real permissions. They are shared with the iPhone app and asked for
/// there, so the watch never asks.
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
        }
    }

    func request(_ permission: AppPermission) async {}

    func observe(_ changed: @escaping () -> Void) {
        location.observe(changed)
    }
}
