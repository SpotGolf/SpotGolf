import Observation
import HealthKit
import os
import WatchKit

@MainActor
@Observable
class WorkoutManager: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// How the current session began, or that the last one ended and its workout was saved.
    /// UI tests read it to check recovery after a relaunch, and to wait for the workout to be
    /// saved before quitting, or the system relaunches the app to recover it.
    enum Status: String {
        case none, started, recovered, ended
    }
    private(set) var status = Status.none

    /// The session is running. Batched sensor data only arrives while it is.
    private(set) var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            for listener in runningListeners {
                listener(isRunning)
            }
        }
    }

    @ObservationIgnored private var runningListeners: [(Bool) -> Void] = []

    /// Called on the main actor with each event worth keeping in the round's stream.
    @ObservationIgnored var onEvent: ((StreamEvent) -> Void)?

    /// Adds a listener called each time `isRunning` changes. Listeners stay for the manager's life.
    func addRunningListener(_ listener: @escaping (Bool) -> Void) {
        runningListeners.append(listener)
    }

    /// What is going on, for the screen while a start is waited on.
    var stateText: String {
        var parts = [status.rawValue]
        if let session { parts.append("session \(session.state.rawValue)") }
        if isStarting { parts.append("starting") }
        if waitsForForeground { parts.append("refused") }
        return parts.joined(separator: ", ")
    }

    // True from start() until a session is running, so repeated calls start only one
    private var isStarting = false

    // What the app last asked for. A session that finishes starting after stop(), or ends
    // after start(), is brought back in line with it.
    private var wantsWorkout = false

    // Restarts a workout that ended, failed, or never ran while a round needs it
    private var watchdog = RestartWatchdog(startedAt: Date(), checksData: false)
    private var watchdogTimer: Timer?
    // watchOS refuses a new workout while another app's workout runs, or while this app
    // is in the background, so retries wait until the app is on screen
    private var waitsForForeground = false
    // Refusals while on screen are retried after a wait that doubles each time, since the
    // cause may be another app's workout, which no retry here can end
    private var refusedRetryDelay: TimeInterval = RestartWatchdog.interval
    private var refusedRetryAt: Date?
    private static let maxRefusedRetryDelay: TimeInterval = 5 * 60
    // A forced restart ends the session, and starts a new one once it has ended
    private var restartAfterEnd = false
    private var lastForcedRestartAt: Date?
    /// Forced restarts, for sensors that stay dead on a session that says it is running, come
    /// at most this often.
    static let forcedRestartInterval: TimeInterval = 2 * 60

    /// Starts a golf workout, or takes over the one left running if the app quit
    /// mid-round. Safe to call repeatedly; also answers the system's recovery request.
    func start() {
        wantsWorkout = true
        guard HKHealthStore.isHealthDataAvailable() else {
            Log.workout.error("HealthKit not available; no workout, so no swing detection")
            return
        }
        startWatchdog()
        dropFinishedSession()
        guard session == nil, !isStarting else { return }
        isStarting = true
        watchdog.started(at: Date())

        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            if let error {
                Log.workout.error("Could not recover a running workout; starting a new one: \(String(describing: error))")
            }
            Task { @MainActor in
                guard let self else { return }
                // A session that already ended, such as the last capture's, is no use
                if let recovered, recovered.state != .ended, recovered.state != .stopped {
                    Log.workout.notice("Recovered running workout, state \(recovered.state.rawValue)")
                    self.report(.workoutRecovered, value: Float(recovered.state.rawValue))
                    self.attach(recovered)
                    self.status = .recovered
                    self.isStarting = false
                    self.endIfUnwanted()
                } else {
                    self.begin()
                }
            }
        }
    }

    /// `PermissionChecker` has already asked for HealthKit, since rounds wait for it.
    private func begin() {
        beginSession()
        isStarting = false
        endIfUnwanted()
    }

    private func beginSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            attach(session)
            status = .started
            Log.workout.notice("Workout session started")
            report(.workoutStarted)

            session.startActivity(with: .now)
            builder?.beginCollection(withStart: .now) { _, error in
                if let error {
                    Log.workout.error("Begin collection error: \(String(describing: error))")
                }
            }
        } catch {
            Log.workout.error("Could not create workout session: \(String(describing: error))")
            report(.workoutError, value: Self.errorCode(error))
            if Self.needsForeground(error) {
                waitForForeground()
            }
        }
    }

    /// Wires up a new or recovered session. A recovered session is already running,
    /// so it is not started again.
    private func attach(_ session: HKWorkoutSession) {
        self.session = session
        builder = session.associatedWorkoutBuilder()
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                      workoutConfiguration: session.workoutConfiguration)
        session.delegate = self
        builder?.delegate = self
        isRunning = session.state == .running
    }

    func stop() {
        wantsWorkout = false
        restartAfterEnd = false
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        endIfUnwanted()
    }

    /// Ends the running session and starts a new one once it has ended, for sensors that stay
    /// dead on a session that says it is running. At most once per `forcedRestartInterval`.
    func restart(reason: String) {
        guard wantsWorkout, let session, session.state == .running || session.state == .paused else {
            Log.workout.notice("No running workout to restart for \(reason)")
            return
        }
        guard Date().timeIntervalSince(lastForcedRestartAt ?? .distantPast) >= Self.forcedRestartInterval else {
            Log.workout.notice("Workout restart for \(reason) skipped: one was forced within \(Int(Self.forcedRestartInterval)) s")
            return
        }
        lastForcedRestartAt = Date()
        restartAfterEnd = true
        Log.workout.error("Ending the workout to start a new one: \(reason)")
        report(.workoutRestart, value: 2)
        session.end()
    }

    /// watchOS allows a new workout once the app is on screen.
    func appBecameActive() {
        guard waitsForForeground else { return }
        waitsForForeground = false
        refusedRetryDelay = RestartWatchdog.interval
        guard wantsWorkout, !isRunning, !isStarting else { return }
        Log.workout.notice("App on screen; restarting the workout")
        restart()
    }

    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: RestartWatchdog.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkWorkout() }
        }
    }

    private func checkWorkout() {
        guard wantsWorkout, !isStarting else { return }
        if waitsForForeground {
            // The refusal can come while the app is on screen, when a workout that just ended
            // is still being saved; then no foreground event ever arrives to retry on
            guard WKApplication.shared().applicationState == .active,
                  Date() >= refusedRetryAt ?? .distantPast else { return }
            Log.workout.notice("App is on screen; retrying the refused workout")
            waitsForForeground = false
            refusedRetryDelay = min(refusedRetryDelay * 2, Self.maxRefusedRetryDelay)
            restart()
            return
        }
        // The flag follows the delegate's callbacks; if one was missed, the session's own state wins
        if let session {
            let running = session.state == .running
            if running != isRunning {
                Log.workout.error("Workout state \(session.state.rawValue) but running flag \(self.isRunning); correcting")
                report(.workoutRestart, value: 3)
                isRunning = running
            }
        }
        guard watchdog.shouldRestart(at: Date(), isActive: isRunning) else { return }
        Log.workout.error("Workout not running while a round needs it (state \(self.session.map { String($0.state.rawValue) } ?? "none")); restarting")
        report(.workoutRestart, value: 1)
        restart()
    }

    /// Clears a session that has ended or stopped, so `start` makes a new one. The delegate
    /// clears a session that ends while attached; this is for one that was already over.
    private func dropFinishedSession() {
        guard let session, session.state == .ended || session.state == .stopped else { return }
        Log.workout.notice("Dropping a workout already in state \(session.state.rawValue)")
        self.session = nil
        builder = nil
        isRunning = false
    }

    /// Starts a new workout, or gets a session that is not running to run.
    private func restart() {
        dropFinishedSession()
        guard let session else {
            start()
            return
        }
        watchdog.started(at: Date())
        switch session.state {
        case .notStarted, .prepared:
            Log.workout.notice("Starting the activity of a workout that never ran")
            session.startActivity(with: .now)
        case .paused:
            Log.workout.notice("Resuming a paused workout")
            session.resume()
        default:
            // Running, or ending; the delegate clears an ended session
            Log.workout.error("Cannot restart a workout in state \(session.state.rawValue); waiting for it to end")
        }
    }

    private func waitForForeground() {
        guard !waitsForForeground else { return }
        waitsForForeground = true
        refusedRetryAt = Date().addingTimeInterval(refusedRetryDelay)
        Log.workout.error("watchOS refuses a new workout for now; retrying when the app is on screen, in \(Int(self.refusedRetryDelay)) s at the soonest")
        report(.workoutRefused, value: Float(refusedRetryDelay))
    }

    /// The errors for which watchOS refuses a new workout until the app is on screen.
    private static func needsForeground(_ error: Error) -> Bool {
        guard let code = (error as? HKError)?.code else { return false }
        return code == .errorAnotherWorkoutSessionStarted || code == .errorBackgroundWorkoutSessionNotAllowed
    }

    private static func errorCode(_ error: Error) -> Float {
        Float((error as? HKError)?.code.rawValue ?? (error as NSError).code)
    }

    private func report(_ code: StreamEvent.Code, value: Float = 0) {
        onEvent?(StreamEvent(code: code, value: value))
    }

    private func endIfUnwanted() {
        guard !wantsWorkout, let session, session.state != .ended, session.state != .stopped else { return }
        session.end()
    }

    /// Clears a session that ended or failed. If a round still needs a workout, the watchdog
    /// starts a new one; it does not start here, because a failure's error can arrive after
    /// the end and say that watchOS refuses a new workout for now.
    private func sessionFinished(_ finished: HKWorkoutSession) async {
        guard finished === session else { return }
        let builder = self.builder
        session = nil
        self.builder = nil
        isRunning = false
        if let builder, finished.state == .ended {
            do {
                try await builder.endCollection(at: .now)
                try await builder.finishWorkout()
            } catch {
                Log.workout.error("Could not save workout: \(String(describing: error))")
            }
        }
        status = .ended
        Log.workout.notice("Workout session finished, wanted \(self.wantsWorkout)")
        report(.workoutEnded)
        if restartAfterEnd {
            restartAfterEnd = false
            if wantsWorkout {
                Log.workout.notice("Starting the new workout after the forced end")
                start()
            }
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState,
                                     date: Date) {
        Log.workout.notice("Workout state \(fromState.rawValue) -> \(toState.rawValue)")
        Task { @MainActor in
            self.report(.workoutState, value: Float(toState.rawValue))
            if workoutSession === self.session {
                self.isRunning = toState == .running
                if toState == .running {
                    self.refusedRetryDelay = RestartWatchdog.interval
                }
            }
            if toState == .ended {
                await self.sessionFinished(workoutSession)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didFailWithError error: Error) {
        Log.workout.error("Workout session error: \(String(describing: error))")
        // A failed session does not keep the app running, so let start() make a new one
        Task { @MainActor in
            self.report(.workoutError, value: Self.errorCode(error))
            if Self.needsForeground(error) {
                self.waitForForeground()
            }
            guard workoutSession === self.session, workoutSession.state != .running else { return }
            await self.sessionFinished(workoutSession)
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}
