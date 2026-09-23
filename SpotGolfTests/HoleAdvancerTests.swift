import XCTest
import CoreLocation
import CourseDataSwift
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

    /// Front and back nines numbered 1-9 each, as the course data numbers them. Every tee sits
    /// in its own spot along a line so a test can stand on any one of them.
    private func makeFrontBackSelection(frontOrder: [Int] = Array(1...9)) -> (CourseSelection, front: [Feature], back: [Feature]) {
        let frontTees = (0..<9).map { makeTeeFeature(latitude: 33.0 + Double($0) * 0.001, longitude: -97.0) }
        let backTees = (0..<9).map { makeTeeFeature(latitude: 33.0 + Double($0) * 0.001, longitude: -97.01) }
        let frontHoles = frontOrder.map { number in
            Hole(number: number, par: 4, features: [frontTees[number - 1].id], tees: ["Blue": frontTees[number - 1].id], centerline: [])
        }
        let backHoles = (1...9).map { number in
            Hole(number: number, par: 4, features: [backTees[number - 1].id], tees: ["Blue": backTees[number - 1].id], centerline: [])
        }
        let course = Course(
            name: "Test Course", clubName: "Test Club",
            location: CourseLocation(address: "", city: "Test", state: "TX", country: "US",
                                     coordinate: Coordinate(latitude: 0, longitude: 0)),
            features: frontTees + backTees,
            subCourses: [SubCourse(name: "Front", holes: frontHoles), SubCourse(name: "Back", holes: backHoles)]
        )
        return (CourseSelection(course: course, selectedSubCourseIndices: [0, 1]), frontTees, backTees)
    }

    private func standing(on tee: Feature) -> CLLocation {
        CLLocation(latitude: tee.center.latitude, longitude: tee.center.longitude)
    }

    func testDoesNotJumpToAdjacentHoleFromTheOtherNine() {
        let (selection, _, back) = makeFrontBackSelection()

        // On the 4th, standing on the 16th's tee (back nine hole 7)
        let result = HoleAdvancer.detectHole(location: standing(on: back[6]), courseSelection: selection, currentHoleIndex: 3)
        XCTAssertNil(result)
    }

    func testAdvancesFromFrontNineToBackNine() {
        let (selection, _, back) = makeFrontBackSelection()

        // On the 9th, standing on the 10th's tee (back nine hole 1)
        let result = HoleAdvancer.detectHole(location: standing(on: back[0]), courseSelection: selection, currentHoleIndex: 8)
        XCTAssertEqual(result, 9)
    }

    func testDoesNotJumpBackToAnEarlierHole() {
        let (selection, front, _) = makeFrontBackSelection()

        // On the 12th, standing on the 3rd's tee
        let result = HoleAdvancer.detectHole(location: standing(on: front[2]), courseSelection: selection, currentHoleIndex: 11)
        XCTAssertNil(result)
    }

    func testFollowsHoleNumbersWhenCourseDataIsOutOfOrder() {
        let (selection, front, _) = makeFrontBackSelection(frontOrder: [1, 3, 2, 4, 5, 6, 7, 8, 9])

        // On the 1st: the 2nd's tee advances, the 3rd's does not
        XCTAssertEqual(HoleAdvancer.detectHole(location: standing(on: front[1]), courseSelection: selection, currentHoleIndex: 0), 1)
        XCTAssertNil(HoleAdvancer.detectHole(location: standing(on: front[2]), courseSelection: selection, currentHoleIndex: 0))
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
