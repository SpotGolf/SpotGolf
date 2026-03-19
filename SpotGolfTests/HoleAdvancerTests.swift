import XCTest
import CoreLocation
import CourseData
@testable import SpotGolf

final class HoleAdvancerTests: XCTestCase {

    private var nextFeatureID = 1

    override func setUp() {
        super.setUp()
        nextFeatureID = 1
    }

    private func makeTeeFeature(latitude: Double, longitude: Double) -> Feature {
        let id = nextFeatureID
        nextFeatureID += 1
        return Feature(id: id, type: .tee, polygon: [
            Coordinate(latitude: latitude - 0.00005, longitude: longitude - 0.00005),
            Coordinate(latitude: latitude - 0.00005, longitude: longitude + 0.00005),
            Coordinate(latitude: latitude + 0.00005, longitude: longitude + 0.00005),
            Coordinate(latitude: latitude + 0.00005, longitude: longitude - 0.00005),
            Coordinate(latitude: latitude - 0.00005, longitude: longitude - 0.00005),
        ])
    }

    private func makeGreenFeature(latitude: Double, longitude: Double) -> Feature {
        let id = nextFeatureID
        nextFeatureID += 1
        return Feature(id: id, type: .green, polygon: [
            Coordinate(latitude: latitude - 0.0001, longitude: longitude - 0.0001),
            Coordinate(latitude: latitude - 0.0001, longitude: longitude + 0.0001),
            Coordinate(latitude: latitude + 0.0001, longitude: longitude + 0.0001),
            Coordinate(latitude: latitude + 0.0001, longitude: longitude - 0.0001),
            Coordinate(latitude: latitude - 0.0001, longitude: longitude - 0.0001),
        ])
    }

    private func makeSelection(holes: [Hole], features: [Feature]) -> CourseSelection {
        let subCourse = SubCourse(name: "Test", holes: holes)
        let course = Course(
            name: "Test Course", clubName: "Test Club",
            location: CourseLocation(address: "", city: "Test", state: "TX", country: "US",
                                     coordinate: Coordinate(latitude: 0, longitude: 0)),
            features: features, subCourses: [subCourse]
        )
        return CourseSelection(course: course, selectedSubCourseIndices: [0])
    }

    func testAdvancesToNextHoleWhenInsideTeePoly() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)
        let tee3 = makeTeeFeature(latitude: 33.002, longitude: -97.0)
        let green3 = makeGreenFeature(latitude: 33.007, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
            Hole(number: 3, par: 4, features: [tee3.id, green3.id], tees: ["Blue": tee3.id], centerline: []),
        ]
        let features = [tee1, green1, tee2, green2, tee3, green3]
        let selection = makeSelection(holes: holes, features: features)

        // Standing on hole 2's tee while on hole 1 → advance to hole 2
        let userLocation = CLLocation(latitude: 33.001, longitude: -97.0)
        let result = HoleAdvancer.detectHole(location: userLocation, courseSelection: selection, currentHoleIndex: 0)
        XCTAssertEqual(result, 1)
    }

    func testDoesNotAdvanceToNonSequentialHole() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)
        let tee3 = makeTeeFeature(latitude: 33.002, longitude: -97.0)
        let green3 = makeGreenFeature(latitude: 33.007, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
            Hole(number: 3, par: 4, features: [tee3.id, green3.id], tees: ["Blue": tee3.id], centerline: []),
        ]
        let features = [tee1, green1, tee2, green2, tee3, green3]
        let selection = makeSelection(holes: holes, features: features)

        // Standing on hole 3's tee while on hole 1 → should NOT advance (skips hole 2)
        let userLocation = CLLocation(latitude: 33.002, longitude: -97.0)
        let result = HoleAdvancer.detectHole(location: userLocation, courseSelection: selection, currentHoleIndex: 0)
        XCTAssertNil(result)
    }

    func testReturnsNilWhenNotInsideTeePoly() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
        ]
        let features = [tee1, green1, tee2, green2]
        let selection = makeSelection(holes: holes, features: features)

        // Far from any tee
        let userLocation = CLLocation(latitude: 34.0, longitude: -96.0)
        let result = HoleAdvancer.detectHole(location: userLocation, courseSelection: selection, currentHoleIndex: 0)
        XCTAssertNil(result)
    }

    func testReturnsNilWhenOnLastHole() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
        ]
        let features = [tee1, green1, tee2, green2]
        let selection = makeSelection(holes: holes, features: features)

        // On last hole — no next hole to advance to
        let result = HoleAdvancer.detectHole(location: CLLocation(latitude: 33.0, longitude: -97.0), courseSelection: selection, currentHoleIndex: 1)
        XCTAssertNil(result)
    }

    func testNearestHole() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.01, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.015, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
        ]
        let features = [tee1, green1, tee2, green2]
        let selection = makeSelection(holes: holes, features: features)

        let userLocation = CLLocation(latitude: 33.012, longitude: -97.0)
        let result = HoleAdvancer.nearestHole(location: userLocation, courseSelection: selection)
        XCTAssertEqual(result, 1)
    }

    func testManualOverridePausesAutoAdvance() {
        var advancer = HoleAdvancer()
        XCTAssertFalse(advancer.isPaused)
        advancer.pause()
        XCTAssertTrue(advancer.isPaused)
    }

    func testResumeReEnablesAutoAdvance() {
        var advancer = HoleAdvancer()
        advancer.pause()
        advancer.resume()
        XCTAssertFalse(advancer.isPaused)
    }
}
