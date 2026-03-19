import XCTest
import CoreLocation
@testable import SpotGolf

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

    // MARK: - didFailWithError

    func testDidFailWithErrorDoesNotCrash() {
        let error = NSError(domain: kCLErrorDomain, code: CLError.locationUnknown.rawValue)
        locationManager.locationManager(CLLocationManager(), didFailWithError: error)

        // Should not crash — location stays nil
        XCTAssertNil(locationManager.lastLocation)
    }
}
