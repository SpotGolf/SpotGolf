import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolfWatch

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

    /// A new advancer's answer for one fix: the tee-box rule alone.
    private func detect(location: CLLocation, courseSelection: CourseSelection, displayHoleIndex: Int) -> Int? {
        var advancer = HoleAdvancer()
        return advancer.advance(location: location, courseSelection: courseSelection, displayHoleIndex: displayHoleIndex)
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
        let result = detect(location: userLocation, courseSelection: selection, displayHoleIndex: 0)
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
        let result = detect(location: userLocation, courseSelection: selection, displayHoleIndex: 0)
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
        let result = detect(location: userLocation, courseSelection: selection, displayHoleIndex: 0)
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
        let result = detect(location: CLLocation(latitude: 33.0, longitude: -97.0), courseSelection: selection, displayHoleIndex: 1)
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
        let result = detect(location: standing(on: back[6]), courseSelection: selection, displayHoleIndex: 3)
        XCTAssertNil(result)
    }

    func testAdvancesFromFrontNineToBackNine() {
        let (selection, _, back) = makeFrontBackSelection()

        // On the 9th, standing on the 10th's tee (back nine hole 1)
        let result = detect(location: standing(on: back[0]), courseSelection: selection, displayHoleIndex: 8)
        XCTAssertEqual(result, 9)
    }

    func testDoesNotJumpBackToAnEarlierHole() {
        let (selection, front, _) = makeFrontBackSelection()

        // On the 12th, standing on the 3rd's tee
        let result = detect(location: standing(on: front[2]), courseSelection: selection, displayHoleIndex: 11)
        XCTAssertNil(result)
    }

    func testFollowsHoleNumbersWhenCourseDataIsOutOfOrder() {
        let (selection, front, _) = makeFrontBackSelection(frontOrder: [1, 3, 2, 4, 5, 6, 7, 8, 9])

        // On the 1st: the 2nd's tee advances, the 3rd's does not
        XCTAssertEqual(detect(location: standing(on: front[1]), courseSelection: selection, displayHoleIndex: 0), 1)
        XCTAssertNil(detect(location: standing(on: front[2]), courseSelection: selection, displayHoleIndex: 0))
    }

    // MARK: - Leaving the green

    private static let metersPerDegreeLatitude = 111_320.0
    private static let metersPerDegreeLongitude = 111_320.0 * cos(33.005 * .pi / 180)
    private static let greenEdge = 0.0001 * metersPerDegreeLongitude
    private static let teeHalfWidth = 0.00005 * metersPerDegreeLongitude
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Hole 1's green is centered at (33.005, -97), with its east and west edges `greenEdge` from
    /// the center. Hole 2's tee is `teeEast` meters east of the green's center, and hole 3 exists
    /// so hole 2 has a next hole.
    private func makeGreenExitSelection(teeEast: Double = 75) -> CourseSelection {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.005, longitude: -97.0 + teeEast / Self.metersPerDegreeLongitude)
        let green2 = makeGreenFeature(latitude: 33.010, longitude: -97.0)
        let tee3 = makeTeeFeature(latitude: 33.011, longitude: -97.0)
        let green3 = makeGreenFeature(latitude: 33.015, longitude: -97.0)
        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id], tees: ["Blue": tee1.id], centerline: []),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id], tees: ["Blue": tee2.id], centerline: []),
            Hole(number: 3, par: 4, features: [tee3.id, green3.id], tees: ["Blue": tee3.id], centerline: []),
        ]
        return makeSelection(holes: holes, features: [tee1, green1, tee2, green2, tee3, green3])
    }

    /// A fix `east` and `north` meters from the green's center, `second` seconds in.
    private func fix(east: Double, north: Double = 0, second: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 33.005 + north / Self.metersPerDegreeLatitude,
                                                      longitude: -97.0 + east / Self.metersPerDegreeLongitude),
                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start.addingTimeInterval(second))
    }

    /// Fixes once a second: `onGreen` at the green's center, then walking east from its edge
    /// at 1.5 m/s for `walk` seconds (west when `speed` is negative).
    private func path(onGreen: Int, walk: Int, speed: Double = 1.5) -> [CLLocation] {
        let edge = speed < 0 ? -Self.greenEdge : Self.greenEdge
        return (0..<onGreen).map { fix(east: 0, second: Double($0)) } +
            (1...walk).map { fix(east: edge + Double($0) * speed, second: Double(onGreen + $0)) }
    }

    /// The first fix that advances, as (index, meters east of the green's center), or nil.
    private func firstAdvance(_ fixes: [CLLocation], selection: CourseSelection, holeIndex: Int = 0) -> (index: Int, east: Double)? {
        var advancer = HoleAdvancer()
        for (index, location) in fixes.enumerated()
        where advancer.advance(location: location, courseSelection: selection, displayHoleIndex: holeIndex) == holeIndex + 1 {
            return (index, (location.coordinate.longitude + 97.0) * Self.metersPerDegreeLongitude)
        }
        return nil
    }

    func testAdvancesAfterLeavingTheGreenTowardTheNextTee() throws {
        let selection = makeGreenExitSelection()

        let advance = try XCTUnwrap(firstAdvance(path(onGreen: 30, walk: 50), selection: selection))

        // 20 m off the green, and well short of the tee
        XCTAssertGreaterThanOrEqual(advance.east, Self.greenEdge + 20)
        XCTAssertLessThan(advance.east, 50)
    }

    func testFewerThanTwentyFixesOnTheGreenWaitsForTheTee() throws {
        let selection = makeGreenExitSelection()

        let advance = try XCTUnwrap(firstAdvance(path(onGreen: 19, walk: 50), selection: selection))

        XCTAssertGreaterThanOrEqual(advance.east, 75 - Self.teeHalfWidth)
    }

    func testFixesOnTheGreenCountAcrossSeveralVisits() throws {
        let selection = makeGreenExitSelection()
        // 10 on the green, 5 just off its edge, 10 back on, then the walk to the tee
        let visits = (0..<10).map { fix(east: 0, second: Double($0)) } +
            (10..<15).map { fix(east: 15, second: Double($0)) } +
            (15..<25).map { fix(east: 0, second: Double($0)) }
        let walk = (1...50).map { fix(east: Self.greenEdge + Double($0) * 1.5, second: Double(25 + $0)) }

        let advance = try XCTUnwrap(firstAdvance(visits + walk, selection: selection))

        XCTAssertLessThan(advance.east, 50)
    }

    func testDoesNotAdvanceWithinTwentyMetersOfTheGreen() {
        let selection = makeGreenExitSelection()
        // Off to the bag 15 m past the green's edge, toward the tee, and waiting there
        let bag = Self.greenEdge + 15
        let fixes = path(onGreen: 30, walk: 10) + (0..<60).map { fix(east: bag, second: Double(41 + $0)) }

        XCTAssertNil(firstAdvance(fixes, selection: selection))
    }

    func testDoesNotAdvanceWhenWalkingAwayFromTheNextTee() {
        let selection = makeGreenExitSelection()

        XCTAssertNil(firstAdvance(path(onGreen: 30, walk: 60, speed: -1.5), selection: selection))
    }

    func testDoesNotLeaveTheGreenForATeeOverOneHundredMetersAway() throws {
        let selection = makeGreenExitSelection(teeEast: 150)

        let advance = try XCTUnwrap(firstAdvance(path(onGreen: 30, walk: 100), selection: selection))

        XCTAssertGreaterThanOrEqual(advance.east, 150 - Self.teeHalfWidth)
    }

    func testAChangeOfHoleClearsTheFixesOnTheGreen() throws {
        let selection = makeGreenExitSelection()
        var advancer = HoleAdvancer()
        let fixes = path(onGreen: 30, walk: 50)
        for location in fixes.prefix(30) {
            _ = advancer.advance(location: location, courseSelection: selection, displayHoleIndex: 0)
        }

        // The hole changed by hand, and back
        _ = advancer.advance(location: fixes[29], courseSelection: selection, displayHoleIndex: 1)
        let advancedAt = fixes.dropFirst(30).firstIndex {
            advancer.advance(location: $0, courseSelection: selection, displayHoleIndex: 0) == 1
        }

        // Only the tee box advances now
        let index = try XCTUnwrap(advancedAt)
        XCTAssertGreaterThanOrEqual(Self.greenEdge + Double(index - 29) * 1.5, 75 - Self.teeHalfWidth)
    }
}
