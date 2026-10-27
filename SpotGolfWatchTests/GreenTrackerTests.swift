import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolfWatch

final class GreenTrackerTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A green about 22 m square centered on `latitude`, -97.0.
    private func green(id: Int, latitude: Double) -> Feature {
        Feature(id: id, type: .green, polygon: [
            Coordinate(lat: latitude - 0.0001, lon: -97.0001),
            Coordinate(lat: latitude - 0.0001, lon: -96.9999),
            Coordinate(lat: latitude + 0.0001, lon: -96.9999),
            Coordinate(lat: latitude + 0.0001, lon: -97.0001),
            Coordinate(lat: latitude - 0.0001, lon: -97.0001),
        ])
    }

    /// Three holes with greens at 33.000, 33.010 and 33.020; the second hole has none when `missingGreen`.
    private func selection(missingGreen: Bool = false) -> CourseSelection {
        let features = [green(id: 1, latitude: 33.000), green(id: 2, latitude: 33.010), green(id: 3, latitude: 33.020)]
        let holes = [
            Hole(number: 1, par: 4, features: [1]),
            Hole(number: 2, par: 4, features: missingGreen ? [] : [2]),
            Hole(number: 3, par: 4, features: [3]),
        ]
        let course = Course(
            name: "Test Course", clubName: "Test Club",
            location: CourseLocation(address: "", city: "Test", state: "TX", country: "US",
                                     coordinate: Coordinate(lat: 0, lon: 0)),
            features: features, subCourses: [SubCourse(name: "Test", holes: holes)]
        )
        return CourseSelection(course: course, selectedSubCourseIndices: [0])
    }

    private func fix(_ latitude: Double, at seconds: TimeInterval) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -97.0), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start.addingTimeInterval(seconds))
    }

    func testEntersAnyHolesGreen() {
        var tracker = GreenTracker(courseSelection: selection())
        XCTAssertNil(tracker.update(location: fix(33.005, at: 0), zoneMargin: 20))
        XCTAssertEqual(tracker.update(location: fix(33.010, at: 1), zoneMargin: 20), .entered(holeIndex: 1))
        XCTAssertEqual(tracker.holeIndex, 1)
    }

    func testEntersWithinTheZone() {
        var tracker = GreenTracker(courseSelection: selection())
        // About 17 m past the green's edge
        let nearEdge = 33.020 + 0.0001 + 0.00015
        XCTAssertNil(tracker.update(location: fix(nearEdge, at: 0), zoneMargin: 10))
        XCTAssertEqual(tracker.update(location: fix(nearEdge, at: 1), zoneMargin: 20), .entered(holeIndex: 2))
    }

    func testStaysThroughShortTripsOutOfTheZone() {
        var tracker = GreenTracker(courseSelection: selection())
        _ = tracker.update(location: fix(33.000, at: 0), zoneMargin: 20)
        XCTAssertNil(tracker.update(location: fix(33.002, at: 1), zoneMargin: 20))
        XCTAssertNil(tracker.update(location: fix(33.002, at: 9), zoneMargin: 20))
        XCTAssertNil(tracker.update(location: fix(33.000, at: 10), zoneMargin: 20))
        XCTAssertNil(tracker.update(location: fix(33.002, at: 11), zoneMargin: 20))
        XCTAssertEqual(tracker.holeIndex, 0)
    }

    func testLeavesAfterTheExitDelay() {
        var tracker = GreenTracker(courseSelection: selection())
        _ = tracker.update(location: fix(33.000, at: 0), zoneMargin: 20)
        XCTAssertNil(tracker.update(location: fix(33.002, at: 1), zoneMargin: 20))
        XCTAssertEqual(tracker.update(location: fix(33.002, at: 1 + GreenTracker.exitDelay), zoneMargin: 20), .left)
        XCTAssertNil(tracker.holeIndex)
        XCTAssertEqual(tracker.update(location: fix(33.010, at: 20), zoneMargin: 20), .entered(holeIndex: 1))
    }

    func testEntersAgainAfterLeave() {
        var tracker = GreenTracker(courseSelection: selection())
        _ = tracker.update(location: fix(33.000, at: 0), zoneMargin: 20)
        tracker.leave()
        XCTAssertEqual(tracker.update(location: fix(33.000, at: 1), zoneMargin: 20), .entered(holeIndex: 0))
    }

    func testHoleWithoutAGreenIsSkipped() {
        var tracker = GreenTracker(courseSelection: selection(missingGreen: true))
        XCTAssertNil(tracker.update(location: fix(33.010, at: 0), zoneMargin: 20))
        XCTAssertEqual(tracker.update(location: fix(33.020, at: 1), zoneMargin: 20), .entered(holeIndex: 2))
    }

    func testNoCourseNeverEnters() {
        var tracker = GreenTracker()
        XCTAssertNil(tracker.update(location: fix(33.000, at: 0), zoneMargin: 20))
    }
}
