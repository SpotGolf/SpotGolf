import Combine
import CoreLocation
import HealthKit
import os
import WatchKit

/// Owns the services that record a round, so recording resumes as soon as the app
/// launches, even when watchOS launches it in the background (a round started on the phone,
/// or a relaunch after a crash) and no view appears.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let roundStore = RoundStore()
    let locationManager = LocationManager()
    let syncService = SyncService()
    let workoutManager = WorkoutManager()
    let streamStore = StreamStore()
    private let swingDetector = SwingDetector()
    private(set) lazy var watchSync = WatchSync(sync: syncService, rounds: roundStore, streams: streamStore)

    let holeAdvance = WatchHoleAdvance()

    private var activeRoundObserver: AnyCancellable?
    private var swingObserver: AnyCancellable?

    func applicationDidFinishLaunching() {
        Log.rounds.notice("Watch app launched")
        // UI tests pass --keep-rounds when relaunching mid-round to test recovery
        if CommandLine.arguments.contains("--ui-testing"),
           !CommandLine.arguments.contains("--keep-rounds") {
            roundStore.rounds = []
        }
        // Rounds start on the phone, so UI tests pass --start-round to begin one on the watch alone
        if CommandLine.arguments.contains("--ui-testing"),
           CommandLine.arguments.contains("--start-round") {
            roundStore.startRound(courseSelection: .uiTestCourse)
        }

        let sync = watchSync
        locationManager.onRawLocations = { [weak self] locations in
            sync.record(locations)
            self?.advanceHole(locations.last)
        }
        swingDetector.onSwing = { sync.record($0) }
        sync.sender.minBatchInterval = 5
        sync.sender.startRetryTimer()
        sync.sender.pump()
        locationManager.requestPermission()

        activeRoundObserver = roundStore.$rounds
            .map { $0.first(where: \.isActive)?.id }
            .removeDuplicates()
            .sink { [weak self] activeID in
                self?.activeRoundChanged(activeID != nil)
            }

        // Batched accelerometer data only arrives while the workout runs, which is some time
        // after it is asked to start
        swingObserver = roundStore.$rounds
            .map { $0.contains(where: \.isActive) }
            .combineLatest(workoutManager.$isRunning)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] detect in
                Log.swings.notice("Swing detection wanted: \(detect, privacy: .public)")
                if detect {
                    self?.swingDetector.start()
                } else {
                    self?.swingDetector.stop()
                }
            }
    }

    /// Runs here rather than in a view, so it works while watchOS runs the app in the
    /// background and no view is on screen.
    private func advanceHole(_ location: CLLocation?) {
        guard let location, let round = roundStore.activeRound, !holeAdvance.isPaused,
              let detected = HoleAdvancer.detectHole(location: location, courseSelection: round.courseSelection,
                                                     currentHoleIndex: round.currentHoleIndex) else { return }
        roundStore.startHole(detected, source: .autoAdvance)
    }

    /// watchOS launches the app here when the phone starts a round with `startWatchApp`.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Log.workout.notice("Launched by the phone to start a workout")
        startWorkoutWaitingForRound()
    }

    /// watchOS relaunches the app here when it quit while a workout was running.
    func handleActiveWorkoutRecovery() {
        Log.workout.notice("Relaunched to recover a running workout")
        startWorkoutWaitingForRound()
    }

    /// The workout keeps the app running for the round; if no round is active soon, it is not needed.
    private func startWorkoutWaitingForRound() {
        workoutManager.start()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(PhoneSync.defaultStartTimeout * 4))
            guard let self, self.roundStore.activeRound == nil else { return }
            Log.workout.notice("No round arrived after the workout launch; stopping the workout")
            self.workoutManager.stop()
        }
    }

    /// Records while a round is active, and stops everything once it is not.
    private func activeRoundChanged(_ isActive: Bool) {
        Log.rounds.notice("Active round: \(isActive, privacy: .public)")
        if isActive {
            locationManager.startUpdating()
            workoutManager.start()
        } else {
            locationManager.stopUpdating()
            workoutManager.stop()
        }
    }
}

/// Whether the round moves to the next hole when the player reaches its tee. Paused while
/// the user looks at another hole on the watch.
@MainActor
final class WatchHoleAdvance: ObservableObject {
    private(set) var isPaused = false

    func pause() { isPaused = true }
    func resume() { isPaused = false }
}
