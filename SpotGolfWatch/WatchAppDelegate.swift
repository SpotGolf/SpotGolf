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
    private(set) lazy var contactMonitor = ContactMonitor { [weak self] in self?.workoutManager.isRunning == true }
    private(set) lazy var watchSync = WatchSync(sync: syncService, rounds: roundStore, streams: streamStore)
    private(set) lazy var captureUploader = PuttCaptureUploader(transport: syncService.transport as? WatchConnectivityTransport,
                                                                directory: PuttCaptureRecorder.directory)
    private(set) lazy var puttCapture = PuttCaptureRecorder(workouts: workoutManager, uploader: captureUploader) { [weak self] in
        self?.roundStore.activeRound != nil
    }

    private var holeAdvancer = HoleAdvancer()

    /// UI tests run on simulators, which can't grant every permission
    let permissions = PermissionChecker(source: CommandLine.arguments.contains("--ui-testing")
                                        ? GrantedPermissionSource() : SystemPermissionSource())

    // The last values acted on, so only changes are acted on. Swing detection starts off.
    private var hasLaunched = false
    private var activeRoundID: UUID?
    private var detectsSwings = false

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
        // Rounds from the phone are refused until every permission is granted
        let checker = permissions
        sync.missingPermissions = {
            checker.refresh()
            return checker.missing
        }
        locationManager.setUpdatesInBackground()
        locationManager.onRawLocations = { [weak self] locations in
            sync.record(locations)
            // Every fix, so leaving the green is seen over its whole time window
            for location in locations {
                self?.advanceHole(location)
                if let self, let round = self.roundStore.activeRound {
                    self.contactMonitor.update(location: location, round: round)
                }
            }
        }
        swingDetector.onSwing = { sync.record($0) }
        swingDetector.taps = contactMonitor.taps
        swingDetector.onBatch = { [runner = contactMonitor.runner] batch in runner.addAccelerometer(batch) }
        contactMonitor.onContact = { sync.record($0) }
        sync.sender.minBatchInterval = 5
        sync.sender.startRetryTimer()
        sync.sender.pump()
        // Captures whose files never reached the phone
        captureUploader.resumePending()

        roundStore.addListener { [weak self] event in
            if case .roundsChanged = event { self?.recordingInputsChanged() }
        }
        workoutManager.addRunningListener { [weak self] _ in self?.recordingInputsChanged() }
        // A round already active at launch, after a crash or a relaunch by watchOS
        recordingInputsChanged()
    }

    func applicationDidBecomeActive() {
        workoutManager.appBecameActive()
    }

    /// Runs here rather than in a view, so it works while watchOS runs the app in the
    /// background and no view is on screen. Only the display hole moves; the timeline is set
    /// by the strokes added on the phone.
    private func advanceHole(_ location: CLLocation) {
        guard let round = roundStore.activeRound,
              let next = holeAdvancer.advance(location: location, courseSelection: round.courseSelection,
                                              displayHoleIndex: round.displayHoleIndex) else { return }
        roundStore.setDisplayHole(next)
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
            try? await Task.sleep(for: .seconds(SyncService.startTimeout * 4))
            guard let self, self.roundStore.activeRound == nil else { return }
            Log.workout.notice("No round arrived after the workout launch; stopping the workout")
            self.workoutManager.stop()
        }
    }

    /// Starts and stops recording, and swing detection, as the active round and workout change.
    private func recordingInputsChanged() {
        let activeID = roundStore.activeRound?.id
        let isActive = activeID != nil
        let isFirst = !hasLaunched
        hasLaunched = true
        if isFirst || activeID != activeRoundID {
            activeRoundID = activeID
            activeRoundChanged(isActive)
        }
        // Batched accelerometer data only arrives while the workout runs, which is some time
        // after it is asked to start
        let detect = isActive && workoutManager.isRunning
        if detect != detectsSwings {
            detectsSwings = detect
            Log.swings.notice("Swing detection wanted: \(detect, privacy: .public)")
            if detect {
                swingDetector.start()
            } else {
                swingDetector.stop()
            }
        }
    }

    /// Records while a round is active, and stops everything once it is not.
    private func activeRoundChanged(_ isActive: Bool) {
        Log.rounds.notice("Active round: \(isActive, privacy: .public)")
        if isActive {
            // A round's swing detection and a capture can't share the sensors
            puttCapture.stop()
            locationManager.startUpdating()
            workoutManager.start()
        } else {
            contactMonitor.roundEnded()
            locationManager.stopUpdating()
            workoutManager.stop()
        }
    }
}
