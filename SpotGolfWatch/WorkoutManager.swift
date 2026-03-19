import HealthKit

@MainActor
class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start() {
        guard HKHealthStore.isHealthDataAvailable(),
              session == nil else { return }

        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            if let error {
                print("WorkoutManager: authorization error – \(error)")
            }
            guard success else { return }
            Task { @MainActor in
                self?.beginSession()
            }
        }
    }

    private func beginSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session?.delegate = self
            builder?.delegate = self

            session?.startActivity(with: .now)
            builder?.beginCollection(withStart: .now) { _, error in
                if let error {
                    print("WorkoutManager: begin collection error – \(error)")
                }
            }
        } catch {
            print("WorkoutManager: failed to start session – \(error)")
        }
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
