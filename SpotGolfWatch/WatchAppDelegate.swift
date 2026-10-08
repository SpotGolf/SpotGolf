import HealthKit
import os
import WatchKit

/// Starts the watch app's services at launch, and passes system events on to them.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let services = WatchServices()

    func applicationDidFinishLaunching() {
        Log.rounds.notice("Watch app launched")
        services.start()
    }

    func applicationDidBecomeActive() {
        services.workoutManager.appBecameActive()
    }

    /// watchOS launches the app here when the phone starts a round with `startWatchApp`.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Log.workout.notice("Launched by the phone to start a workout")
        services.startWorkoutWaitingForRound()
    }

    /// watchOS relaunches the app here when it quit while a workout was running.
    func handleActiveWorkoutRecovery() {
        Log.workout.notice("Relaunched to recover a running workout")
        services.startWorkoutWaitingForRound()
    }
}
