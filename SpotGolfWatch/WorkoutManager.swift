import HealthKit
import os

@MainActor
class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// How the current session began, or that the last one ended and its workout was saved.
    /// UI tests read it to check recovery after a relaunch, and to wait for the workout to be
    /// saved before quitting, or the system relaunches the app to recover it.
    enum Status: String {
        case none, started, recovered, ended
    }
    @Published private(set) var status = Status.none

    /// The session is running. Batched sensor data only arrives while it is.
    @Published private(set) var isRunning = false

    // True from start() until a session is running, so repeated calls start only one
    private var isStarting = false

    // What the app last asked for. A session that finishes starting after stop(), or ends
    // after start(), is brought back in line with it.
    private var wantsWorkout = false
    private var lastRestart: Date?

    /// Starts a golf workout, or takes over the one left running if the app quit
    /// mid-round. Safe to call repeatedly; also answers the system's recovery request.
    func start() {
        wantsWorkout = true
        guard HKHealthStore.isHealthDataAvailable() else {
            Log.workout.error("HealthKit not available; no workout, so no swing detection")
            return
        }
        guard session == nil, !isStarting else { return }
        isStarting = true

        healthStore.recoverActiveWorkoutSession { [weak self] recovered, _ in
            Task { @MainActor in
                guard let self else { return }
                if let recovered {
                    Log.workout.notice("Recovered running workout, state \(recovered.state.rawValue, privacy: .public)")
                    self.attach(recovered)
                    self.status = .recovered
                    self.isStarting = false
                    self.endIfUnwanted()
                } else {
                    self.requestAuthorizationAndBegin()
                }
            }
        }
    }

    private func requestAuthorizationAndBegin() {
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] _, error in
            if let error {
                Log.workout.error("HealthKit authorization error: \(String(describing: error), privacy: .public)")
            }
            // Start session regardless of authorization — the session keeps the app
            // active even if the user denies permissions. Data just won't be saved.
            Task { @MainActor in
                self?.beginSession()
                self?.isStarting = false
                self?.endIfUnwanted()
            }
        }
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

            session.startActivity(with: .now)
            builder?.beginCollection(withStart: .now) { _, error in
                if let error {
                    Log.workout.error("Begin collection error: \(String(describing: error), privacy: .public)")
                }
            }
        } catch {
            Log.workout.error("Could not create workout session: \(String(describing: error), privacy: .public)")
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
        endIfUnwanted()
    }

    private func endIfUnwanted() {
        guard !wantsWorkout, let session, session.state != .ended, session.state != .stopped else { return }
        session.end()
    }

    /// Clears a session that ended or failed. After an end, starts again if a workout is
    /// still wanted (a round started while the last one was ending), at most once a minute.
    private func sessionFinished(_ finished: HKWorkoutSession, restart: Bool) async {
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
                Log.workout.error("Could not save workout: \(String(describing: error), privacy: .public)")
            }
        }
        status = .ended
        Log.workout.notice("Workout session finished, restart \(restart, privacy: .public), wanted \(self.wantsWorkout, privacy: .public)")
        if restart, wantsWorkout {
            if lastRestart.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
                lastRestart = Date()
                Log.workout.notice("Restarting workout")
                start()
            } else {
                Log.workout.error("Workout ended again within a minute of a restart; not restarting")
            }
        } else if wantsWorkout {
            Log.workout.error("Workout failed while a round needs it; not restarting")
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState,
                                     date: Date) {
        Log.workout.notice("Workout state \(fromState.rawValue, privacy: .public) -> \(toState.rawValue, privacy: .public)")
        Task { @MainActor in
            if workoutSession === self.session {
                self.isRunning = toState == .running
            }
            if toState == .ended {
                await self.sessionFinished(workoutSession, restart: true)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didFailWithError error: Error) {
        Log.workout.error("Workout session error: \(String(describing: error), privacy: .public)")
        // A failed session does not keep the app running, so let start() make a new one
        Task { @MainActor in
            guard workoutSession === self.session, workoutSession.state != .running else { return }
            await self.sessionFinished(workoutSession, restart: false)
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}
