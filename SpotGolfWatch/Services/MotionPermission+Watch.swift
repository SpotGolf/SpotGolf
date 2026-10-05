import CoreMotion

extension MotionPermission {
    /// The permission the watch's batched accelerometer checks.
    var state: PermissionState {
        Self.state(CMBatchedSensorManager.authorizationStatus)
    }
}
