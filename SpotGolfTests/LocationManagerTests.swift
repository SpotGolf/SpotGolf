import XCTest
import CoreLocation
@testable import SpotGolf

@MainActor
private final class FixCollector {
    var received: [CLLocation] = []
}

@MainActor
final class LocationManagerTests: XCTestCase {

    private var locationManager: LocationManager!

    override func setUp() {
        super.setUp()
        locationManager = LocationManager()
    }

    override func tearDown() {
        locationManager = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testInitialLocationIsNil() {
        XCTAssertNil(locationManager.lastLocation)
    }

    func testInitialAuthorizationIsNotDetermined() {
        XCTAssertEqual(locationManager.authorizationStatus, .notDetermined)
    }

    // MARK: - didUpdateLocations

    func testDidUpdateLocationsSetsLastLocation() async {
        let location = CLLocation(latitude: 33.45, longitude: -112.07)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [location])
        await Task.yield()

        XCTAssertEqual(locationManager.lastLocation?.coordinate.latitude, 33.45)
        XCTAssertEqual(locationManager.lastLocation?.coordinate.longitude, -112.07)
    }

    func testDidUpdateLocationsUsesLastLocationInArray() async {
        let first = CLLocation(latitude: 33.0, longitude: -112.0)
        let second = CLLocation(latitude: 34.0, longitude: -113.0)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [first, second])
        await Task.yield()

        XCTAssertEqual(locationManager.lastLocation?.coordinate.latitude, 34.0)
        XCTAssertEqual(locationManager.lastLocation?.coordinate.longitude, -113.0)
    }

    func testDidUpdateLocationsWithEmptyArrayLeavesNil() async {
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [])
        await Task.yield()

        XCTAssertNil(locationManager.lastLocation)
    }

    func testDidUpdateLocationsOverwritesPreviousLocation() async {
        let first = CLLocation(latitude: 33.0, longitude: -112.0)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [first])
        await Task.yield()

        let second = CLLocation(latitude: 40.0, longitude: -74.0)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [second])
        await Task.yield()

        XCTAssertEqual(locationManager.lastLocation?.coordinate.latitude, 40.0)
        XCTAssertEqual(locationManager.lastLocation?.coordinate.longitude, -74.0)
    }

    // MARK: - Raw fixes

    func testRawLocationsReceivesEveryFixInBatch() {
        let fixes = FixCollector()
        locationManager.onRawLocations = { fixes.received += $0 }

        let first = CLLocation(latitude: 33.0, longitude: -112.0)
        let second = CLLocation(latitude: 34.0, longitude: -113.0)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [first, second])

        XCTAssertEqual(fixes.received.map(\.coordinate.latitude), [33.0, 34.0])
    }

    func testRawLocationsSkipsInvalidFixes() {
        let fixes = FixCollector()
        locationManager.onRawLocations = { fixes.received += $0 }

        let invalid = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0),
                                 altitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date())
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [invalid])

        XCTAssertTrue(fixes.received.isEmpty)
    }

    func testRawLocationsKeepsLowAccuracyFixes() {
        let fixes = FixCollector()
        locationManager.onRawLocations = { fixes.received += $0 }

        let coarse = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 33.0, longitude: -112.0),
                                altitude: 0, horizontalAccuracy: 65, verticalAccuracy: -1, timestamp: Date())
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [coarse])

        XCTAssertEqual(fixes.received.count, 1)
    }

    // MARK: - didFailWithError

    func testDidFailWithErrorDoesNotCrash() {
        let error = NSError(domain: kCLErrorDomain, code: CLError.locationUnknown.rawValue)
        locationManager.locationManager(CLLocationManager(), didFailWithError: error)

        // Should not crash — location stays nil
        XCTAssertNil(locationManager.lastLocation)
    }
}
