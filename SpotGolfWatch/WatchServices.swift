import CoreLocation
import Foundation
import Observation
import os

/// Every service the watch app runs, built and wired together once at launch. Owned by the app
/// delegate, so recording resumes as soon as the app launches, even when watchOS launches it in
/// the background (a round started on the phone, or a relaunch after a crash) and no view
/// appears. Views read it from the environment.
@Observable
@MainActor
final class WatchServices {
    let roundStore: RoundStore
    let locationManager = LocationManager()
    let syncService = SyncService()
    let workoutManager = WorkoutManager()
    let streamStore = StreamStore()
    let contactMonitor: ContactMonitor
    let watchSync: WatchSync
    let captureUploader: PuttCaptureUploader
    let puttCapture: PuttCaptureRecorder
    let permissions: PermissionChecker
    /// Shows the workout's status, which UI tests read to check recovery after a relaunch.
    let showsWorkoutStatus: Bool
    @ObservationIgnored private let swingDetector = SwingDetector()
    @ObservationIgnored private var holeAdvancer = HoleAdvancer()

    // The last values acted on, so only changes are acted on. Swing detection starts off.
    @ObservationIgnored private var hasLaunched = false
    @ObservationIgnored private var activeRoundID: UUID?
    @ObservationIgnored private var detectsSwings = false

    init(options: LaunchOptions = .current) {
        let rounds = RoundStore()
        // UI tests pass --keep-rounds when relaunching mid-round to test recovery
        if options.isUITesting, !options.keepsRounds {
            rounds.rounds = []
        }
        // Rounds start on the phone, so UI tests pass --start-round to begin one on the watch alone
        if options.isUITesting, options.startsRound {
            rounds.startRound(courseSelection: .uiTestCourse)
        }
        // UI tests run on simulators, which can't grant every permission
        permissions = PermissionChecker(source: options.isUITesting
                                        ? GrantedPermissionSource() : SystemPermissionSource())
        showsWorkoutStatus = options.isUITesting
        roundStore = rounds

        let workouts = workoutManager
        contactMonitor = ContactMonitor { workouts.isRunning }
        watchSync = WatchSync(sync: syncService, rounds: rounds, streams: streamStore)
        captureUploader = PuttCaptureUploader(transport: syncService.transport as? WatchConnectivityTransport,
                                              directory: PuttCaptureRecorder.directory)
        puttCapture = PuttCaptureRecorder(workouts: workouts, uploader: captureUploader) {
            rounds.activeRound != nil
        }
    }

    /// Starts recording and syncing. Called once the app has launched.
    func start() {
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

    /// Runs here rather than in a view, so it works while watchOS runs the app in the
    /// background and no view is on screen. Only the display hole moves; the timeline is set
    /// by the strokes added on the phone.
    private func advanceHole(_ location: CLLocation) {
        guard let round = roundStore.activeRound,
              let next = holeAdvancer.advance(location: location, courseSelection: round.courseSelection,
                                              displayHoleIndex: round.displayHoleIndex) else { return }
        roundStore.setDisplayHole(next)
    }

    /// The workout keeps the app running for the round; if no round is active soon, it is not needed.
    func startWorkoutWaitingForRound() {
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
