import HealthKit

@MainActor
class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// How the current session began. UI tests read it to check recovery after a relaunch.
    enum Status: String {
        case none, started, recovered
    }
    @Published private(set) var status = Status.none

    // True from start() until a session is running, so repeated calls start only one
    private var isStarting = false

    /// Starts a golf workout, or takes over the one left running if the app quit
    /// mid-round. Safe to call repeatedly; also answers the system's recovery request.
    func start() {
        guard HKHealthStore.isHealthDataAvailable(),
              session == nil, !isStarting else { return }
        isStarting = true

        healthStore.recoverActiveWorkoutSession { [weak self] recovered, _ in
            Task { @MainActor in
                guard let self else { return }
                if let recovered {
                    self.attach(recovered)
                    self.status = .recovered
                    self.isStarting = false
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
                print("WorkoutManager: authorization error – \(error)")
            }
            // Start session regardless of authorization — the session keeps the app
            // active even if the user denies permissions. Data just won't be saved.
            Task { @MainActor in
                self?.beginSession()
                self?.isStarting = false
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

            session.startActivity(with: .now)
            builder?.beginCollection(withStart: .now) { _, error in
                if let error {
                    print("WorkoutManager: begin collection error – \(error)")
                }
            }
        } catch {
            print("WorkoutManager: failed to start session – \(error)")
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
    }

    func stop() {
        session?.end()
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didChangeTo toState: HKWorkoutSessionState,
                                     from fromState: HKWorkoutSessionState,
                                     date: Date) {
        if toState == .ended {
            Task { @MainActor in
                guard let builder else {
                    session = nil
                    status = .none
                    return
                }
                do {
                    try await builder.endCollection(at: .now)
                    try await builder.finishWorkout()
                } catch {
                    print("WorkoutManager: finish workout error – \(error)")
                }
                self.session = nil
                self.builder = nil
                self.status = .none
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                     didFailWithError error: Error) {
        print("WorkoutManager: session error – \(error)")
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                     didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}
