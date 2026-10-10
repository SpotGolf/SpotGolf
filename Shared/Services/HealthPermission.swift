import HealthKit
import os

/// Reads and asks for HealthKit permission. The iPhone app and the watch app share it.
/// Only saving workouts is required: HealthKit never says whether reading was allowed.
@MainActor
final class HealthPermission {
    private let store = HKHealthStore()

    /// Saving workouts, which the phone needs to launch the watch app and the watch needs
    /// for the workout that keeps it running.
    private static let share: Set<HKSampleType> = [HKObjectType.workoutType()]
    /// What `WorkoutManager`'s workout reads.
    private static let read: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
    ]

    var state: PermissionState {
        guard HKHealthStore.isHealthDataAvailable() else { return .denied }
        return Self.state(store.authorizationStatus(for: HKObjectType.workoutType()))
    }

    nonisolated static func state(_ status: HKAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: .notAsked
        case .sharingAuthorized: .granted
        default: .denied
        }
    }

    /// Shows the Health sheet and returns once the user closes it.
    func request() async {
        do {
            try await store.requestAuthorization(toShare: Self.share, read: Self.read)
        } catch {
            Log.permissions.error("HealthKit authorization error: \(String(describing: error))")
        }
    }
}
