import CoreLocation
import SensorSources
import XCTest
@testable import SpotGolfWatch

@MainActor
final class PreRoundChecksTests: XCTestCase {
    private final class FakeWorkout: PreRoundChecks.Workout {
        var isRunning = false
        var runsOnStart = true
        private(set) var starts = 0

        func start() {
            starts += 1
            if runsOnStart { isRunning = true }
        }
    }

    private final class FakeLocation: PreRoundChecks.Location {
        private(set) var owners: Set<String> = []

        func startUpdating(for owner: String) { owners.insert(owner) }
        func stopUpdating(for owner: String) { owners.remove(owner) }
    }

    private final class MissingPermissionSource: PermissionSource {
        let missing: [AppPermission]
        init(missing: [AppPermission]) { self.missing = missing }
        func state(of permission: AppPermission) -> PermissionState { missing.contains(permission) ? .denied : .granted }
        func request(_ permission: AppPermission) async {}
    }

    private var hub: MockSensorHub!
    private var sensors: SensorInputs!
    private var workout: FakeWorkout!
    private var location: FakeLocation!
    private let roundID = UUID()
    private let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 39.47, longitude: -104.74), altitude: 1880,
                                 horizontalAccuracy: 8, verticalAccuracy: 4, timestamp: Date())

    override func setUp() async throws {
        try await super.setUp()
        hub = MockSensorHub(inbox: nil)
        sensors = SensorInputs(sources: .mocks(hub: hub))
        workout = FakeWorkout()
        location = FakeLocation()
    }

    private func checks(missing: [AppPermission] = [], limits: PreRoundChecks.Limits? = nil) -> PreRoundChecks {
        var defaults = PreRoundChecks.Limits()
        defaults.workout = 0.3
        defaults.sensors = 3
        defaults.location = 4
        defaults.poll = 0.05
        return PreRoundChecks(sensors: sensors, permissions: PermissionChecker(source: MissingPermissionSource(missing: missing)),
                              workout: workout, location: location, limits: limits ?? defaults)
    }

    /// Runs the checks, sending a GPS fix once location updates start unless `sendsFix` is false.
    private func run(_ checks: PreRoundChecks, sendsFix: Bool = true) -> PreRoundCheckState {
        let finished = expectation(description: "checks finished")
        checks.onFinished = { _ in finished.fulfill() }
        checks.run(roundID: roundID)
        XCTAssertEqual(checks.state(for: roundID), .running)
        if sendsFix {
            Task { @MainActor in
                while !self.location.owners.contains(PreRoundChecks.locationOwner) {
                    try? await Task.sleep(for: .milliseconds(20))
                }
                checks.received([self.fix])
            }
        }
        wait(for: [finished], timeout: 10)
        return checks.state(for: roundID)
    }

    func testPassesWhenEverythingWorks() {
        let checks = checks()

        XCTAssertEqual(run(checks), .passed)
        XCTAssertEqual(workout.starts, 1)
        for input in SensorInputs.Input.allCases {
            XCTAssertTrue(sensors.isSendingRealData(input), "\(input) stays on until the round has started")
        }
        XCTAssertTrue(location.owners.contains(PreRoundChecks.locationOwner))

        checks.releaseSensors()

        XCTAssertFalse(sensors.isSendingRealData(.microphone))
        XCTAssertFalse(location.owners.contains(PreRoundChecks.locationOwner))
    }

    func testMissingPermissionsFailBeforeAnythingStarts() {
        let checks = checks(missing: [.microphone])

        XCTAssertEqual(run(checks, sendsFix: false), .failed(.missingPermissions([.microphone])))
        XCTAssertEqual(workout.starts, 0)
        XCTAssertTrue(location.owners.isEmpty)
    }

    func testWorkoutThatNeverRunsFails() {
        workout.runsOnStart = false
        let checks = checks()

        XCTAssertEqual(run(checks, sendsFix: false), .failed(.checksFailed([.workoutNotRunning])))
        XCTAssertEqual(workout.starts, 1)
        XCTAssertTrue(location.owners.isEmpty)
    }

    func testRunningWorkoutIsNotStartedAgain() {
        workout.isRunning = true

        XCTAssertEqual(run(checks()), .passed)
        XCTAssertEqual(workout.starts, 0)
    }

    func testEachBrokenSensorIsReported() {
        hub.setMode(.fail, for: .microphone)
        hub.setMode(.silent, for: .deviceMotion)
        hub.setMode(.zeros, for: .accelerometer)
        let checks = checks()

        XCTAssertEqual(run(checks), .failed(.checksFailed([
            .sensor("accelerometer", .notReal),
            .sensor("deviceMotion", .noData),
            .sensor("microphone", .notStarted)
        ])))
        // A failed run lets go of everything it started
        XCTAssertFalse(sensors.hasSentData(.accelerometer))
        XCTAssertTrue(location.owners.isEmpty)
    }

    func testNoFixFails() {
        var limits = PreRoundChecks.Limits()
        limits.sensors = 3
        limits.location = 1.5
        limits.poll = 0.05
        let checks = checks(limits: limits)

        XCTAssertEqual(run(checks, sendsFix: false), .failed(.checksFailed([.noLocation])))
        XCTAssertTrue(location.owners.isEmpty)
    }

    func testAPassIsGoodOnlyForAWhile() {
        var limits = PreRoundChecks.Limits()
        limits.sensors = 3
        limits.poll = 0.05
        limits.passedFor = 0.2
        let checks = checks(limits: limits)
        XCTAssertEqual(run(checks), .passed)

        let waited = expectation(description: "past the pass")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            waited.fulfill()
        }
        wait(for: [waited], timeout: 2)

        XCTAssertEqual(checks.state(for: roundID), .notRun)
        XCTAssertEqual(checks.state(for: UUID()), .notRun)
    }

    func testResultIsRecordedForTheStream() {
        let checks = checks()
        var events: [StreamEvent.Code] = []
        checks.onEvent = { events.append($0.code) }

        _ = run(checks)

        XCTAssertEqual(events, [.preRoundChecksPassed])
    }
}
