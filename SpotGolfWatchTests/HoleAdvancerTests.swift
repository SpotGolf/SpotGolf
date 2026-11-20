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
            Coordinate(lat: latitude - 0.00005, lon: longitude - 0.00005),
            Coordinate(lat: latitude - 0.00005, lon: longitude + 0.00005),
            Coordinate(lat: latitude + 0.00005, lon: longitude + 0.00005),
            Coordinate(lat: latitude + 0.00005, lon: longitude - 0.00005),
            Coordinate(lat: latitude - 0.00005, lon: longitude - 0.00005),
        ])
    }

    private func makeGreenFeature(latitude: Double, longitude: Double) -> Feature {
        let id = nextFeatureID
        nextFeatureID += 1
        return Feature(id: id, type: .green, polygon: [
            Coordinate(lat: latitude - 0.0001, lon: longitude - 0.0001),
            Coordinate(lat: latitude - 0.0001, lon: longitude + 0.0001),
            Coordinate(lat: latitude + 0.0001, lon: longitude + 0.0001),
            Coordinate(lat: latitude + 0.0001, lon: longitude - 0.0001),
            Coordinate(lat: latitude - 0.0001, lon: longitude - 0.0001),
        ])
    }

    private func makeSelection(holes: [Hole], features: [Feature]) -> CourseSelection {
        let subCourse = SubCourse(name: "Test", holes: holes)
        let course = Course(
            name: "Test Course", clubName: "Test Club",
            location: CourseLocation(address: "", city: "Test", state: "TX", country: "US",
                                     coordinate: Coordinate(lat: 0, lon: 0)),
            features: features, subCourses: [subCourse]
        )
        return CourseSelection(course: course, selectedSubCourseIndices: [0])
    }

    /// A new advancer's answer for one fix: the tee-box rule alone, which is the same for the
    /// phone's display hole and the watch's playing hole.
    private func detect(location: CLLocation, courseSelection: CourseSelection, holeIndex: Int,
                        file: StaticString = #filePath, line: UInt = #line) -> Int? {
        var display = HoleAdvancer(moving: .displayHole)
        var playing = HoleAdvancer(moving: .playingHole)
        let result = display.advance(location: location, courseSelection: courseSelection, holeIndex: holeIndex)
        XCTAssertEqual(playing.advance(location: location, courseSelection: courseSelection, holeIndex: holeIndex), result,
                       file: file, line: line)
        return result
    }

    func testAdvancesToNextHoleWhenInsideTeePoly() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)
        let tee3 = makeTeeFeature(latitude: 33.002, longitude: -97.0)
        let green3 = makeGreenFeature(latitude: 33.007, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id]),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id]),
            Hole(number: 3, par: 4, features: [tee3.id, green3.id]),
        ]
        let features = [tee1, green1, tee2, green2, tee3, green3]
        let selection = makeSelection(holes: holes, features: features)

        // Standing on hole 2's tee while on hole 1 → advance to hole 2
        let userLocation = CLLocation(latitude: 33.001, longitude: -97.0)
        let result = detect(location: userLocation, courseSelection: selection, holeIndex: 0)
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
            Hole(number: 1, par: 4, features: [tee1.id, green1.id]),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id]),
            Hole(number: 3, par: 4, features: [tee3.id, green3.id]),
        ]
        let features = [tee1, green1, tee2, green2, tee3, green3]
        let selection = makeSelection(holes: holes, features: features)

        // Standing on hole 3's tee while on hole 1 → should NOT advance (skips hole 2)
        let userLocation = CLLocation(latitude: 33.002, longitude: -97.0)
        let result = detect(location: userLocation, courseSelection: selection, holeIndex: 0)
        XCTAssertNil(result)
    }

    func testReturnsNilWhenNotInsideTeePoly() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id]),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id]),
        ]
        let features = [tee1, green1, tee2, green2]
        let selection = makeSelection(holes: holes, features: features)

        // Far from any tee
        let userLocation = CLLocation(latitude: 34.0, longitude: -96.0)
        let result = detect(location: userLocation, courseSelection: selection, holeIndex: 0)
        XCTAssertNil(result)
    }

    func testReturnsNilWhenOnLastHole() {
        let tee1 = makeTeeFeature(latitude: 33.0, longitude: -97.0)
        let green1 = makeGreenFeature(latitude: 33.005, longitude: -97.0)
        let tee2 = makeTeeFeature(latitude: 33.001, longitude: -97.0)
        let green2 = makeGreenFeature(latitude: 33.006, longitude: -97.0)

        let holes = [
            Hole(number: 1, par: 4, features: [tee1.id, green1.id]),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id]),
        ]
        let features = [tee1, green1, tee2, green2]
        let selection = makeSelection(holes: holes, features: features)

        // On last hole — no next hole to advance to
        let result = detect(location: CLLocation(latitude: 33.0, longitude: -97.0), courseSelection: selection, holeIndex: 1)
        XCTAssertNil(result)
    }

    /// Front and back nines numbered 1-9 each, as the course data numbers them. Every tee sits
    /// in its own spot along a line so a test can stand on any one of them.
    private func makeFrontBackSelection(frontOrder: [Int] = Array(1...9)) -> (CourseSelection, front: [Feature], back: [Feature]) {
        let frontTees = (0..<9).map { makeTeeFeature(latitude: 33.0 + Double($0) * 0.001, longitude: -97.0) }
        let backTees = (0..<9).map { makeTeeFeature(latitude: 33.0 + Double($0) * 0.001, longitude: -97.01) }
        let frontHoles = frontOrder.map { number in
            Hole(number: number, par: 4, features: [frontTees[number - 1].id])
        }
        let backHoles = (1...9).map { number in
            Hole(number: number, par: 4, features: [backTees[number - 1].id])
        }
        let course = Course(
            name: "Test Course", clubName: "Test Club",
            location: CourseLocation(address: "", city: "Test", state: "TX", country: "US",
                                     coordinate: Coordinate(lat: 0, lon: 0)),
            features: frontTees + backTees,
            subCourses: [SubCourse(name: "Front", holes: frontHoles), SubCourse(name: "Back", holes: backHoles)]
        )
        return (CourseSelection(course: course, selectedSubCourseIndices: [0, 1]), frontTees, backTees)
    }

    private func standing(on tee: Feature) -> CLLocation {
        CLLocation(latitude: tee.center.lat, longitude: tee.center.lon)
    }

    func testDoesNotJumpToAdjacentHoleFromTheOtherNine() {
        let (selection, _, back) = makeFrontBackSelection()

        // On the 4th, standing on the 16th's tee (back nine hole 7)
        let result = detect(location: standing(on: back[6]), courseSelection: selection, holeIndex: 3)
        XCTAssertNil(result)
    }

    func testShotgunStartAdvancesFromTheEighteenthToTheFirst() {
        let (nines, front, back) = makeFrontBackSelection()
        let shotgun = CourseSelection(course: nines.course, selectedSubCourseIndices: [0, 1], startHoleIndex: 8)

        // Started on the 9th: index 9 is the 18th, standing on the 1st's tee
        XCTAssertEqual(detect(location: standing(on: front[0]), courseSelection: shotgun, holeIndex: 9), 10)
        // The 9th to the 10th still works at the start of the round
        XCTAssertEqual(detect(location: standing(on: back[0]), courseSelection: shotgun, holeIndex: 0), 1)
        // The 8th is the last hole played: nothing after it, even on the 9th's tee
        XCTAssertNil(detect(location: standing(on: front[8]), courseSelection: shotgun, holeIndex: 17))
    }

    func testAdvancesFromFrontNineToBackNine() {
        let (selection, _, back) = makeFrontBackSelection()

        // On the 9th, standing on the 10th's tee (back nine hole 1)
        let result = detect(location: standing(on: back[0]), courseSelection: selection, holeIndex: 8)
        XCTAssertEqual(result, 9)
    }

    func testDoesNotJumpBackToAnEarlierHole() {
        let (selection, front, _) = makeFrontBackSelection()

        // On the 12th, standing on the 3rd's tee
        let result = detect(location: standing(on: front[2]), courseSelection: selection, holeIndex: 11)
        XCTAssertNil(result)
    }

    func testFollowsHoleNumbersWhenCourseDataIsOutOfOrder() {
        let (selection, front, _) = makeFrontBackSelection(frontOrder: [1, 3, 2, 4, 5, 6, 7, 8, 9])

        // On the 1st: the 2nd's tee advances, the 3rd's does not
        XCTAssertEqual(detect(location: standing(on: front[1]), courseSelection: selection, holeIndex: 0), 1)
        XCTAssertNil(detect(location: standing(on: front[2]), courseSelection: selection, holeIndex: 0))
    }

    // MARK: - Leaving the green: the phone's display hole

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
            Hole(number: 1, par: 4, features: [tee1.id, green1.id]),
            Hole(number: 2, par: 4, features: [tee2.id, green2.id]),
            Hole(number: 3, par: 4, features: [tee3.id, green3.id]),
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
    private func firstAdvance(_ fixes: [CLLocation], selection: CourseSelection, holeIndex: Int = 0,
                              moving target: HoleAdvancer.Target = .displayHole) -> (index: Int, east: Double)? {
        var advancer = HoleAdvancer(moving: target)
        for (index, location) in fixes.enumerated()
        where advancer.advance(location: location, courseSelection: selection, holeIndex: holeIndex) == holeIndex + 1 {
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
        var advancer = HoleAdvancer(moving: .displayHole)
        let fixes = path(onGreen: 30, walk: 50)
        for location in fixes.prefix(30) {
            _ = advancer.advance(location: location, courseSelection: selection, holeIndex: 0)
        }

        // The hole changed by hand, and back
        _ = advancer.advance(location: fixes[29], courseSelection: selection, holeIndex: 1)
        let advancedAt = fixes.dropFirst(30).firstIndex {
            advancer.advance(location: $0, courseSelection: selection, holeIndex: 0) == 1
        }

        // Only the tee box advances now
        let index = try XCTUnwrap(advancedAt)
        XCTAssertGreaterThanOrEqual(Self.greenEdge + Double(index - 29) * 1.5, 75 - Self.teeHalfWidth)
    }

    // MARK: - Walking to the next tee: the watch's playing hole

    /// Meters east of the green's center where the next tee, `teeEast` east, is 15 m away.
    private func nearTee(_ teeEast: Double = 75) -> Double {
        teeEast - Self.teeHalfWidth - HoleAdvancer.nearTeeDistance
    }

    func testPlayingHoleWaitsForFifteenMetersFromTheNextTee() throws {
        let selection = makeGreenExitSelection()

        let advance = try XCTUnwrap(firstAdvance(path(onGreen: 30, walk: 50), selection: selection, moving: .playingHole))

        // Not on leaving the green, as the display hole does, and before the tee box itself
        XCTAssertGreaterThanOrEqual(advance.east, nearTee())
        XCTAssertLessThan(advance.east, nearTee() + 3)
    }

    func testPlayingHoleAdvancesNearATeeOverOneHundredMetersAway() throws {
        let selection = makeGreenExitSelection(teeEast: 150)

        let advance = try XCTUnwrap(firstAdvance(path(onGreen: 30, walk: 100), selection: selection, moving: .playingHole))

        XCTAssertGreaterThanOrEqual(advance.east, nearTee(150))
        XCTAssertLessThan(advance.east, nearTee(150) + 3)
    }

    func testPlayingHoleStaysNearTheNextTeeWhenTheGreenWasNotPlayed() {
        let selection = makeGreenExitSelection()
        // Too few fixes on the green, then a walk that stops 5 m short of the tee box
        let fixes = path(onGreen: 19, walk: 40) + (0..<30).map { fix(east: 65, second: Double(60 + $0)) }

        XCTAssertNil(firstAdvance(fixes, selection: selection, moving: .playingHole))
    }

    func testPlayingHoleStaysWhenThePlayerStopsShortOfFifteenMeters() {
        let selection = makeGreenExitSelection()
        // Off the green toward the tee, then waiting 20 m from the tee box
        let stop = nearTee() - 5
        let walk = Int((stop - Self.greenEdge) / 1.5)
        let fixes = path(onGreen: 30, walk: walk) + (0..<60).map { fix(east: stop, second: Double(31 + walk + $0)) }

        XCTAssertNil(firstAdvance(fixes, selection: selection, moving: .playingHole))
    }

    func testPlayingHoleStaysWhenWalkingAwayFromTheNextTee() {
        let selection = makeGreenExitSelection()

        XCTAssertNil(firstAdvance(path(onGreen: 30, walk: 60, speed: -1.5), selection: selection, moving: .playingHole))
    }

    // MARK: - A hole picked on the watch

    /// An advancer the watch moved on to hole 2 by standing on its tee, 75 m east of the green.
    private func advancerOnHoleTwo(_ selection: CourseSelection) -> HoleAdvancer {
        var advancer = HoleAdvancer(moving: .playingHole)
        XCTAssertEqual(advancer.advance(location: fix(east: 75, second: 0), courseSelection: selection, holeIndex: 0), 1)
        XCTAssertNil(advancer.advance(location: fix(east: 75, second: 1), courseSelection: selection, holeIndex: 1))
        return advancer
    }

    func testAHolePickedOnTheNextTeeStaysWhileThePlayerIsThere() {
        let selection = makeGreenExitSelection()
        var advancer = advancerOnHoleTwo(selection)

        // The user goes back to hole 1, still standing on hole 2's tee
        for second in 2..<60 {
            XCTAssertNil(advancer.advance(location: fix(east: 75, second: Double(second)), courseSelection: selection, holeIndex: 0))
        }
    }

    func testAPickedHoleMovesOnAfterThePlayerHasBeenAwayFromTheNextTee() {
        let selection = makeGreenExitSelection()
        var advancer = advancerOnHoleTwo(selection)
        XCTAssertNil(advancer.advance(location: fix(east: 75, second: 2), courseSelection: selection, holeIndex: 0))

        // Off the tee to 20 m from it, which changes nothing by itself, and back onto it
        XCTAssertNil(advancer.advance(location: fix(east: nearTee() - 5, second: 20), courseSelection: selection, holeIndex: 0))
        XCTAssertEqual(advancer.advance(location: fix(east: 75, second: 40), courseSelection: selection, holeIndex: 0), 1)
    }

    func testAPickedHoleMovesOnAfterThePlayerHasBeenOnTheGreen() {
        // The tee box starts 6 m from the green's edge, so the player is never 15 m from it
        let teeEast = Self.greenEdge + 6 + Self.teeHalfWidth
        let selection = makeGreenExitSelection(teeEast: teeEast)
        var advancer = HoleAdvancer(moving: .playingHole)
        XCTAssertEqual(advancer.advance(location: fix(east: teeEast, second: 0), courseSelection: selection, holeIndex: 0), 1)
        XCTAssertNil(advancer.advance(location: fix(east: teeEast, second: 1), courseSelection: selection, holeIndex: 1))
        XCTAssertNil(advancer.advance(location: fix(east: teeEast, second: 2), courseSelection: selection, holeIndex: 0))

        // Putting, at the edge of the green nearest the tee
        for second in 3..<(3 + GreenExit.minGreenFixes) {
            XCTAssertNil(advancer.advance(location: fix(east: Self.greenEdge - 1, second: Double(second)),
                                          courseSelection: selection, holeIndex: 0))
        }
        XCTAssertEqual(advancer.advance(location: fix(east: teeEast, second: 60), courseSelection: selection, holeIndex: 0), 1)
    }

    func testAHoleTheAdvancerMovedOnToIsNotAPick() {
        let selection = makeGreenExitSelection()
        var advancer = HoleAdvancer(moving: .playingHole)
        XCTAssertEqual(advancer.advance(location: fix(east: 75, second: 0), courseSelection: selection, holeIndex: 0), 1)

        // On hole 2 now, and standing on hole 3's tee moves on at once
        let tee3 = CLLocation(latitude: 33.011, longitude: -97.0)
        XCTAssertEqual(advancer.advance(location: tee3, courseSelection: selection, holeIndex: 1), 2)
    }

    func testAPickOfTheLastHoleAndBackIsStillAPick() {
        let selection = makeGreenExitSelection()
        var advancer = HoleAdvancer(moving: .playingHole)
        let tee3 = CLLocation(latitude: 33.011, longitude: -97.0)
        XCTAssertNil(advancer.advance(location: tee3, courseSelection: selection, holeIndex: 0))

        // The user picks hole 3, the last, then hole 2, standing on hole 3's tee
        XCTAssertNil(advancer.advance(location: tee3, courseSelection: selection, holeIndex: 2))
        XCTAssertNil(advancer.advance(location: tee3, courseSelection: selection, holeIndex: 1))
    }

    func testThePhonesDisplayHoleMovesOnFromAPickedHoleAtOnce() {
        let selection = makeGreenExitSelection()
        var advancer = HoleAdvancer(moving: .displayHole)
        XCTAssertEqual(advancer.advance(location: fix(east: 75, second: 0), courseSelection: selection, holeIndex: 0), 1)
        XCTAssertNil(advancer.advance(location: fix(east: 75, second: 1), courseSelection: selection, holeIndex: 1))

        // Its hold is a timer kept with the round, not the advancer's
        XCTAssertEqual(advancer.advance(location: fix(east: 75, second: 2), courseSelection: selection, holeIndex: 0), 1)
    }
}
