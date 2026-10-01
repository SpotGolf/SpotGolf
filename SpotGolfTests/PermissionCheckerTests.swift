import XCTest
import CoreLocation
import HealthKit
import CoreMotion
@testable import SpotGolf

/// Permissions set by the test. A request grants or denies, as `answers` says.
@MainActor
final class FakePermissionSource: PermissionSource {
    var states: [AppPermission: PermissionState]
    var answers: [AppPermission: PermissionState] = [:]
    private(set) var requested: [AppPermission] = []
    private var changed: (() -> Void)?

    init(_ states: [AppPermission: PermissionState] = [:]) {
        self.states = states
    }

    func state(of permission: AppPermission) -> PermissionState {
        states[permission] ?? .granted
    }

    func request(_ permission: AppPermission) async {
        requested.append(permission)
        states[permission] = answers[permission] ?? .granted
    }

    func observe(_ changed: @escaping () -> Void) {
        self.changed = changed
    }

    /// The system says a permission changed.
    func change(_ permission: AppPermission, to state: PermissionState) {
        states[permission] = state
        changed?()
    }
}

@MainActor
final class PermissionCheckerTests: XCTestCase {

    func testAllGranted() {
        let checker = PermissionChecker(source: FakePermissionSource())

        XCTAssertTrue(checker.allGranted)
        XCTAssertEqual(checker.missing, [])
    }

    func testMissingIsInOrder() {
        let checker = PermissionChecker(source: FakePermissionSource([.health: .notAsked, .location: .denied]))

        XCTAssertFalse(checker.allGranted)
        XCTAssertEqual(checker.missing, [.location, .health])
        XCTAssertEqual(checker.states[.motion], .granted)
    }

    func testRefreshReadsTheSourceAgain() {
        let source = FakePermissionSource([.motion: .denied])
        let checker = PermissionChecker(source: source)

        source.states[.motion] = .granted
        XCTAssertEqual(checker.missing, [.motion])

        checker.refresh()
        XCTAssertTrue(checker.allGranted)
    }

    func testRequestAsksOnlyNotAskedInOrder() async {
        let source = FakePermissionSource([.health: .notAsked, .motion: .denied, .location: .notAsked])
        let checker = PermissionChecker(source: source)

        await checker.requestMissing()

        XCTAssertEqual(source.requested, [.location, .health])
        XCTAssertEqual(checker.missing, [.motion])
    }

    func testRequestDeniedStaysMissing() async {
        let source = FakePermissionSource([.motion: .notAsked])
        source.answers[.motion] = .denied
        let checker = PermissionChecker(source: source)

        await checker.requestMissing()

        XCTAssertEqual(checker.states[.motion], .denied)
        XCTAssertEqual(checker.missing, [.motion])
    }

    func testOnlyRequiredPermissionsAreCheckedAndAsked() async {
        let source = FakePermissionSource([.location: .notAsked, .motion: .denied, .health: .notAsked])
        let checker = PermissionChecker(source: source, required: [.location])

        XCTAssertEqual(checker.missing, [.location])
        XCTAssertNil(checker.states[.motion])

        await checker.requestMissing()

        XCTAssertEqual(source.requested, [.location])
        XCTAssertTrue(checker.allGranted)
    }

    func testSystemChangeIsPickedUp() {
        let source = FakePermissionSource()
        let checker = PermissionChecker(source: source, required: [.location])
        XCTAssertTrue(checker.allGranted)

        // An "Allow Once" grant runs out when the app leaves the screen
        source.change(.location, to: .notAsked)

        XCTAssertEqual(checker.missing, [.location])
    }

    func testLocationNeedsPreciseLocation() {
        XCTAssertEqual(LocationPermission.state(status: .notDetermined, accuracy: .fullAccuracy), .notAsked)
        XCTAssertEqual(LocationPermission.state(status: .authorizedWhenInUse, accuracy: .fullAccuracy), .granted)
        XCTAssertEqual(LocationPermission.state(status: .authorizedAlways, accuracy: .fullAccuracy), .granted)
        XCTAssertEqual(LocationPermission.state(status: .authorizedWhenInUse, accuracy: .reducedAccuracy), .denied)
        XCTAssertEqual(LocationPermission.state(status: .denied, accuracy: .fullAccuracy), .denied)
        XCTAssertEqual(LocationPermission.state(status: .restricted, accuracy: .fullAccuracy), .denied)
    }

    func testHealthNeedsWorkoutSharing() {
        XCTAssertEqual(HealthPermission.state(.notDetermined), .notAsked)
        XCTAssertEqual(HealthPermission.state(.sharingAuthorized), .granted)
        XCTAssertEqual(HealthPermission.state(.sharingDenied), .denied)
    }

    func testMotionNeedsAuthorization() {
        XCTAssertEqual(MotionPermission.state(.notDetermined), .notAsked)
        XCTAssertEqual(MotionPermission.state(.authorized), .granted)
        XCTAssertEqual(MotionPermission.state(.denied), .denied)
        // Fitness Tracking is off
        XCTAssertEqual(MotionPermission.state(.restricted), .denied)
    }

    func testGrantedSourceGrantsEverything() {
        XCTAssertTrue(PermissionChecker(source: GrantedPermissionSource()).allGranted)
    }
}
