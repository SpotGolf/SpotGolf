import CoreMotion

/// Reads and asks for Motion & Fitness permission. The iPhone app and the watch app share it;
/// the watch's swing detection needs it. Each app reads `state` its own way.
@MainActor
final class MotionPermission {
    // Kept alive while its query shows the prompt
    private var activityManager: CMMotionActivityManager?

    /// Restricted means Fitness Tracking is off for every app, which only Settings can change.
    nonisolated static func state(_ status: CMAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: .notAsked
        case .authorized: .granted
        default: .denied
        }
    }

    /// Motion & Fitness has no request call: the first activity query shows the prompt.
    /// Returns once the user answers.
    func request() async {
        let manager = CMMotionActivityManager()
        activityManager = manager
        await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: Date(timeIntervalSinceNow: -60), to: Date(), to: .main) { _, _ in
                continuation.resume()
            }
        }
        activityManager = nil
    }
}
