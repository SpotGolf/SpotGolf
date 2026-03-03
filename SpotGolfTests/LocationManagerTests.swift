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

    func testDidUpdateLocationsSetsLastLocation() {
        let location = CLLocation(latitude: 33.45, longitude: -112.07)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [location])

        XCTAssertEqual(locationManager.lastLocation?.coordinate.latitude, 33.45)
        XCTAssertEqual(locationManager.lastLocation?.coordinate.longitude, -112.07)
    }

    func testDidUpdateLocationsUsesLastLocationInArray() {
        let first = CLLocation(latitude: 33.0, longitude: -112.0)
        let second = CLLocation(latitude: 34.0, longitude: -113.0)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [first, second])

        XCTAssertEqual(locationManager.lastLocation?.coordinate.latitude, 34.0)
        XCTAssertEqual(locationManager.lastLocation?.coordinate.longitude, -113.0)
    }

    func testDidUpdateLocationsWithEmptyArrayLeavesNil() {
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [])

        XCTAssertNil(locationManager.lastLocation)
    }

    func testDidUpdateLocationsOverwritesPreviousLocation() {
        let first = CLLocation(latitude: 33.0, longitude: -112.0)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [first])

        let second = CLLocation(latitude: 40.0, longitude: -74.0)
        locationManager.locationManager(CLLocationManager(), didUpdateLocations: [second])

        XCTAssertEqual(locationManager.lastLocation?.coordinate.latitude, 40.0)
        XCTAssertEqual(locationManager.lastLocation?.coordinate.longitude, -74.0)
    }
}
