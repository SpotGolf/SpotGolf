import CoreLocation
import Foundation
import os
import SensorSources

/// Everything the watch checks before it takes a round, so a round never starts that can't be
/// recorded: the permissions, the workout, every sensor sending real data (`SensorHealth`),
/// and a GPS fix. Steps run in that order and the first that fails ends the run. GPS starts
/// with the sensor step, since a cold start takes longest, but is judged last.
///
/// On a pass the sensors and location updates stay on until `releaseSensors`, which the watch
/// calls once the round has started and its own detectors have subscribed, so nothing stops and
/// starts again in between. A pass is good for `Limits.passedFor`; a later start checks again.
@MainActor
final class PreRoundChecks {
    /// The workout session, as the checks need it. `WorkoutManager` in the app.
    @MainActor
    protocol Workout: AnyObject {
        var isRunning: Bool { get }
        func start()
    }

    /// Location updates, as the checks need them. `LocationManager` in the app; the fixes
    /// themselves come in through `received(_:)`.
    @MainActor
    protocol Location: AnyObject {
        func startUpdating(for owner: String)
        func stopUpdating(for owner: String)
    }

    struct Limits {
        /// How long the workout may take to run.
        var workout: TimeInterval = 15
        /// How long every sensor may take to send real data, once the workout runs.
        var sensors: TimeInterval = 10
        /// How long the first GPS fix may take, from the start of the sensor step.
        var location: TimeInterval = 30
        /// How long a pass stays good for a start.
        var passedFor: TimeInterval = 120
        /// How often a wait looks again.
        var poll: TimeInterval = 0.1
    }

    /// The location updates' owner while the checks hold them.
    static let locationOwner = "preRoundChecks"

    /// Called with the round's ID when a run ends, passed or failed.
    var onFinished: ((UUID) -> Void)?

    /// Called with the result, for the round's stream.
    var onEvent: ((StreamEvent) -> Void)?

    private let sensors: SensorInputs
    private let permissions: PermissionChecker
    private let workout: any Workout
    private let location: any Location
    private let limits: Limits

    private var roundID: UUID?
    private var current = PreRoundCheckState.notRun
    private var passedAt: Date?
    private var task: Task<Void, Never>?
    private var subscriptions: [SensorInputs.Subscription] = []
    private var holdsLocation = false
    private var hasFix = false

    init(sensors: SensorInputs, permissions: PermissionChecker, workout: any Workout, location: any Location,
         limits: Limits = Limits()) {
        self.sensors = sensors
        self.permissions = permissions
        self.workout = workout
        self.location = location
        self.limits = limits
    }

    /// Where the checks are for `roundID`. A pass older than `Limits.passedFor` counts as not run.
    func state(for roundID: UUID) -> PreRoundCheckState {
        guard roundID == self.roundID else { return .notRun }
        if current == .passed, let passedAt, Date().timeIntervalSince(passedAt) > limits.passedFor {
            return .notRun
        }
        return current
    }

    /// Runs the checks for `roundID`, unless they are already running for it. A run for another
    /// round is given up.
    func run(roundID: UUID) {
        guard state(for: roundID) != .running else { return }
        task?.cancel()
        release()
        self.roundID = roundID
        current = .running
        passedAt = nil
        hasFix = false
        Log.rounds.notice("Pre-round checks started for round \(roundID)")
        task = Task { [weak self] in
            guard let self else { return }
            let result = await self.check()
            guard !Task.isCancelled, self.roundID == roundID else { return }
            self.finish(roundID, result)
        }
    }

    /// Fixes from the location updates.
    func received(_ locations: [CLLocation]) {
        guard current == .running, locations.contains(where: { $0.horizontalAccuracy >= 0 }) else { return }
        hasFix = true
    }

    /// The round has started: the sensors and location updates go back to their round's owners.
    func releaseSensors() {
        release()
    }

    // MARK: - Running

    private func finish(_ roundID: UUID, _ result: PreRoundCheckState) {
        current = result
        switch result {
        case .passed:
            passedAt = Date()
            Log.rounds.notice("Pre-round checks passed for round \(roundID)")
            onEvent?(StreamEvent(code: .preRoundChecksPassed))
            // Released by the round's start; if no start comes, once the pass is too old to use
            let holdFor = limits.passedFor
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(holdFor))
                guard let self, self.roundID == roundID, self.current == .passed else { return }
                self.release()
            }
        case .failed(let reason):
            release()
            Log.rounds.error("Pre-round checks failed for round \(roundID): \(Self.describe(reason))")
            onEvent?(StreamEvent(code: .preRoundChecksFailed, value: Float(Self.count(reason))))
        case .notRun, .running:
            break
        }
        onFinished?(roundID)
    }

    private func check() async -> PreRoundCheckState {
        permissions.refresh()
        let missing = permissions.missing
        guard missing.isEmpty else { return .failed(.missingPermissions(missing)) }

        if !workout.isRunning {
            workout.start()
        }
        guard await wait(limits.workout, until: { $0.workout.isRunning }) else {
            return .failed(.checksFailed([.workoutNotRunning]))
        }

        let locationDeadline = Date().addingTimeInterval(limits.location)
        location.startUpdating(for: Self.locationOwner)
        holdsLocation = true
        subscriptions = [
            sensors.subscribeAccelerometer { _ in },
            sensors.subscribeDeviceMotion { _ in },
            sensors.subscribeMicrophone { _ in }
        ]
        let inputs = SensorInputs.Input.allCases
        _ = await wait(limits.sensors) { checks in inputs.allSatisfy { checks.sensors.isSendingRealData($0) } }
        let failures = inputs.compactMap(sensorFailure)
        guard failures.isEmpty else { return .failed(.checksFailed(failures)) }

        guard await wait(max(0, locationDeadline.timeIntervalSinceNow), until: { $0.hasFix }) else {
            return .failed(.checksFailed([.noLocation]))
        }
        return .passed
    }

    private func sensorFailure(_ input: SensorInputs.Input) -> CheckFailure? {
        guard !sensors.isSendingRealData(input) else { return nil }
        if sensors.problems[input] != nil {
            return .sensor(input.rawValue, .notStarted)
        }
        return .sensor(input.rawValue, sensors.hasSentData(input) ? .notReal : .noData)
    }

    /// Waits until `condition` holds, for at most `limit`. Returns whether it held.
    private func wait(_ limit: TimeInterval, until condition: (PreRoundChecks) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(limit)
        while !condition(self) {
            guard Date() < deadline, !Task.isCancelled else { return condition(self) }
            try? await Task.sleep(for: .seconds(limits.poll))
        }
        return true
    }

    private func release() {
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions = []
        if holdsLocation {
            holdsLocation = false
            location.stopUpdating(for: Self.locationOwner)
        }
    }

    private static func describe(_ reason: StartRoundRefused.Reason) -> String {
        switch reason {
        case .missingPermissions(let missing): "missing \(missing.map(\.rawValue).joined(separator: ", "))"
        case .checksFailed(let failures): failures.map { "\($0)" }.joined(separator: ", ")
        case .versionMismatch(let version): "watch version \(version)"
        }
    }

    private static func count(_ reason: StartRoundRefused.Reason) -> Int {
        switch reason {
        case .missingPermissions(let missing): missing.count
        case .checksFailed(let failures): failures.count
        case .versionMismatch: 1
        }
    }
}

extension WorkoutManager: PreRoundChecks.Workout {}
extension LocationManager: PreRoundChecks.Location {}
