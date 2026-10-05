import CoreMotion

extension MotionPermission {
    var state: PermissionState {
        Self.state(CMMotionActivityManager.authorizationStatus())
    }
}
