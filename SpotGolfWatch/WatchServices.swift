import CoreLocation
import Foundation
import Observation
import os
import SensorSources
import SwiftData

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
    /// The sensors and the microphone, shared by swing detection, contact detection and Developer Mode.
    let sensors = SensorInputs()
    let streamStore: StreamStore
    let logStore: LogStore
    /// Where rounds and streams are saved. UI tests start each run empty, unless a test
    /// relaunches mid-round with --keep-rounds and needs the round it saved.
    let container: ModelContainer
    let contactMonitor: ContactMonitor
    let watchSync: WatchSync
    let puttCapture: PuttCaptureRecorder
    /// Putt Data Sharing's drill sessions, outside rounds.
    let drills: DrillRecorder
    let permissions: PermissionChecker
    /// What must work before the watch takes a round.
    let preRoundChecks: PreRoundChecks
    /// Shows the workout's status, which UI tests read to check recovery after a relaunch.
    let showsWorkoutStatus: Bool
    @ObservationIgnored private let swingDetector: SwingDetector
    @ObservationIgnored private var holeAdvancer = HoleAdvancer()

    // The last values acted on, so only changes are acted on. Swing detection starts off.
    @ObservationIgnored private var hasLaunched = false
    @ObservationIgnored private var activeRoundID: UUID?
    /// The display hole last written to Developer Mode's events.
    @ObservationIgnored private var recordedDisplayHole: Int?
    @ObservationIgnored private var detectsSwings = false
    /// The Developer Mode setting the active round runs with, so only a change starts or stops
    /// the capture. The round shows the Developer Mode page while it is on.
    private(set) var developerModeInRound = false

    init(options: LaunchOptions = .current) {
        container = Storage.container(for: options)
        let rounds = RoundStore(context: container.mainContext)
        streamStore = StreamStore(context: container.mainContext)
        let logs = LogStore(context: container.mainContext)
        logs.roundIDForNewLines = { rounds.activeRound?.id }
        logStore = logs
        Log.isDebugEnabled = UserDefaults.standard.bool(forKey: WatchSync.debugLoggingKey)
        Log.setSink { logs.receive($0) }
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
        let inputs = sensors
        swingDetector = SwingDetector(sensors: inputs)
        contactMonitor = ContactMonitor(sensors: inputs) { workouts.isRunning }
        watchSync = WatchSync(sync: syncService, rounds: rounds, streams: streamStore, logs: logs)
        puttCapture = PuttCaptureRecorder(sensors: inputs)
        drills = DrillRecorder(sensors: inputs, workouts: workouts, sync: syncService) {
            rounds.activeRound != nil
        }
        if options.isUITesting {
            let consent = PhoneSettingsMessage(consentVersion: PuttSharing.consentVersion, sharerID: UUID(),
                                               equipment: PuttSharing.Equipment())
            let hasConsent = options.hasDrillConsent
            drills.settings = { hasConsent ? consent : nil }
        }
        preRoundChecks = PreRoundChecks(sensors: inputs, permissions: permissions, workout: workouts, location: locationManager)
    }

    /// Starts recording and syncing. Called once the app has launched.
    func start() {
        let sync = watchSync
        // The sensor sources' own lines, such as the microphone starting, go into the round's log
        SensorLog.handler = { level, message in
            switch level {
            case .notice: Log.sensors.notice("\(message)")
            case .error: Log.sensors.error("\(message)")
            }
        }
        // Rounds from the phone start only once the pre-round checks pass. Once the round has
        // started and its detectors have subscribed, the checks let go of the sensors.
        let checks = preRoundChecks
        sync.preRoundCheck = { checks.state(for: $0) }
        sync.runPreRoundChecks = { checks.run(roundID: $0) }
        checks.onFinished = { [weak self] roundID in
            guard let self else { return }
            self.watchSync.preRoundChecksFinished(roundID)
            if self.roundStore.activeRound?.id == roundID {
                checks.releaseSensors()
            }
        }
        locationManager.setUpdatesInBackground()
        let location = locationManager
        drills.startLocation = { location.startUpdating(for: "drills") }
        drills.stopLocation = { location.stopUpdating(for: "drills") }
        drills.locationDenied = { [.denied, .restricted].contains(location.authorizationStatus) }
        syncService.fileTransferFinished = { [weak self] in self?.drills.transferFinished($0, error: $1) }
        locationManager.onRawLocations = { [weak self] locations in
            self?.drills.record(locations)
            // Outside a round there is no stream to record them in
            if self?.roundStore.activeRound != nil {
                sync.record(locations)
            }
            self?.preRoundChecks.received(locations)
            self?.puttCapture.record(locations)
            // Every fix, so leaving the green is seen over its whole time window
            for location in locations {
                self?.advanceHole(location)
                if let self, let round = self.roundStore.activeRound {
                    self.contactMonitor.update(location: location, round: round)
                }
            }
        }
        swingDetector.onSwing = { [weak self] swing in
            sync.record(swing)
            self?.puttCapture.record(event: "swing", value: Double(swing.peakG ?? 0), at: swing.timestamp)
        }
        contactMonitor.onContact = { sync.record($0) }
        // Developer Mode records a segment for each of the monitor's sessions on a green
        contactMonitor.onSession = { [weak self] in self?.puttCapture.sessionChanged($0) }
        contactMonitor.onDetectorContact = { [weak self] in self?.puttCapture.detectorContact($0) }
        contactMonitor.onDetectorCandidate = { [weak self] in self?.puttCapture.detectorCandidate($0) }
        contactMonitor.recordsCandidates = { [weak self] in self?.puttCapture.recordsRound ?? false }
        let monitor = contactMonitor
        puttCapture.greenZone = { monitor.zoneMargin }
        // Developer Mode's events: taps, haptics, swings, display hole changes and the stream's events
        sensors.onGuarded = { [weak self] in self?.puttCapture.record(event: $0, value: $1) }
        // Settings changed on the phone mid-round take effect at once
        sync.onSettings = { [weak self] in self?.applyRoundSettings($0) }
        sync.onRoundDeleted = { [weak self] in self?.puttCapture.deleteCaptures(roundID: $0) }
        sync.onPhoneSettings = { [weak self] _ in self?.drills.settingsChanged() }
        // The watch's own account of its workout and sensors goes into the round's stream
        let record: (StreamEvent) -> Void = { [weak self] event in
            sync.record(event)
            self?.puttCapture.record(event)
        }
        workoutManager.onEvent = record
        preRoundChecks.onEvent = record
        sensors.onEvent = record
        swingDetector.onEvent = record
        contactMonitor.onEvent = record
        // A batched sensor that stays dead through its own restarts needs a new workout session
        sensors.onStalled = { [weak self] input in
            guard input != .microphone else { return }
            self?.workoutManager.restart(reason: "\(input.rawValue) stalled")
        }
        sync.sender.minBatchInterval = 5
        sync.sender.startRetryTimer()
        sync.sender.pump()
        // Segments left open by a kill
        puttCapture.recoverUnfinished()
        drills.recoverAtLaunch()

        roundStore.addListener { [weak self] event in
            guard case .roundsChanged = event, let self else { return }
            self.recordingInputsChanged()
            // Developer Mode's events: the display hole, however it changed
            let hole = self.roundStore.activeRound?.displayHoleNumber
            if hole != self.recordedDisplayHole {
                self.recordedDisplayHole = hole
                if let hole { self.puttCapture.record(event: "displayHole", value: Double(hole)) }
            }
        }
        workoutManager.addRunningListener { [weak self] _ in self?.recordingInputsChanged() }
        // A round already active at launch, after a crash or a relaunch by watchOS
        recordingInputsChanged()
    }

    /// The user's hard restart, for sensors that die as they did at Legacy Ridge on 2026-10-09
    /// and stay dead through the repair ladder: every input goes on a fresh manager, location
    /// updates start over, and the workout session is replaced with no rate limit, which
    /// starts the inputs again once it runs.
    func hardRestartSensors() {
        Log.sensors.error("Hard restart of the sensors, asked for by the user")
        watchSync.record(StreamEvent(code: .hardRestart))
        sensors.restartAll(reason: "hard restart")
        locationManager.restartUpdating()
        workoutManager.forceRestart(reason: "hard restart")
    }

    /// The phone's settings for the active round, sent mid-round: the zone changes at once, and
    /// Developer Mode starts or stops the capture when it changes.
    private func applyRoundSettings(_ settings: RoundSettingsMessage) {
        guard let round = roundStore.activeRound, round.id == settings.roundID else { return }
        contactMonitor.zoneMargin = settings.greenZone
        guard settings.developerMode != developerModeInRound else { return }
        developerModeInRound = settings.developerMode
        if settings.developerMode {
            puttCapture.startInRound(roundID: round.id)
        } else {
            puttCapture.stop()
        }
    }

    /// Runs here rather than in a view, so it works while watchOS runs the app in the
    /// background and no view is on screen. Only the display hole moves; the timeline is set
    /// by the strokes added on the phone. While the user holds the hole, the advancer still sees
    /// every fix, but its move is dropped.
    private func advanceHole(_ location: CLLocation) {
        guard let round = roundStore.activeRound,
              let next = holeAdvancer.advance(location: location, courseSelection: round.courseSelection,
                                              displayHoleIndex: round.displayHoleIndex),
              !round.isDisplayHoleHeld(at: location.timestamp) else { return }
        roundStore.setDisplayHole(next)
    }

    /// How long a workout launched by the phone waits for its round. The phone keeps sending
    /// the start while the user leaves it, and the workout keeps the watch reachable for it.
    static let roundWaitTime: TimeInterval = 3 * 60

    /// When the workout launched by the phone gives up waiting for a round. Each launch moves it.
    @ObservationIgnored private var roundWaitDeadline: Date?

    /// The workout keeps the app running for the round; if no round is active in time, it is not needed.
    func startWorkoutWaitingForRound() {
        workoutManager.start()
        let deadline = Date().addingTimeInterval(Self.roundWaitTime)
        roundWaitDeadline = deadline
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.roundWaitTime))
            // A later launch moved the deadline; its own wait stops the workout
            guard let self, self.roundWaitDeadline == deadline, self.roundStore.activeRound == nil else { return }
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
            Log.swings.notice("Swing detection wanted: \(detect)")
            if detect {
                swingDetector.start()
            } else {
                swingDetector.stop()
            }
        }
    }

    /// Records while a round is active, and stops everything once it is not.
    private func activeRoundChanged(_ isActive: Bool) {
        Log.rounds.notice("Active round: \(isActive)")
        if isActive, let round = roundStore.activeRound {
            contactMonitor.zoneMargin = WatchSync.greenZone
            // A round takes the workout and the sensors from a drill session, which ends and is sent
            drills.stop()
            // Old captures go first, whether or not this round records one
            puttCapture.pruneCaptures(keeping: round.id)
            developerModeInRound = WatchSync.developerMode
            if developerModeInRound {
                puttCapture.startInRound(roundID: round.id)
            } else {
                puttCapture.stop()
            }
            locationManager.startUpdating()
            workoutManager.start()
        } else {
            // The monitor's stop closes the open segment, after the contact it flushes; the capture ends after both
            contactMonitor.roundEnded()
            developerModeInRound = false
            let capturedRound = puttCapture.captureRoundID
            contactMonitor.afterPending { [weak self] in self?.puttCapture.roundEnded(roundID: capturedRound) }
            locationManager.stopUpdating()
            workoutManager.stop()
        }
    }
}
