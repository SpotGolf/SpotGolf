import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

final class HoleOverviewTests: XCTestCase {

    private func strokes(_ count: Int) -> [Stroke] {
        (0..<count).map { _ in Stroke(coordinate: CLLocationCoordinate2D(latitude: 39.0, longitude: -105.0)) }
    }

    func testToParIsNilWithNoFinishedHoles() {
        var round = Round(courseSelection: .test)
        round.holes = [RoundHole(strokes: strokes(3))]

        // The only played hole is the one shown
        XCTAssertNil(HoleOverview.toPar(round))
    }

    func testToParLeavesOutTheDisplayHoleOfAnActiveRound() {
        var round = Round(courseSelection: .test)
        round.holes = [RoundHole(strokes: strokes(5)), RoundHole(strokes: strokes(3)), RoundHole(strokes: strokes(2))]
        round.setDisplayHole(2, at: Date())

        // 5 + 3 on two par 4s
        XCTAssertEqual(HoleOverview.toPar(round), 0)
    }

    func testToParCountsEveryPlayedHoleOfAnEndedRound() {
        var round = Round(holes: [RoundHole(strokes: strokes(5)), RoundHole(strokes: strokes(6))],
                          status: .ended, courseSelection: .test)
        round.setDisplayHole(1, at: Date())

        XCTAssertEqual(HoleOverview.toPar(round), 3)
    }

    func testToParCountsPenaltyStrokes() {
        var penalty = strokes(5)
        penalty[1].penaltyStrokes = 1
        var round = Round(holes: [RoundHole(strokes: penalty), RoundHole(strokes: strokes(4))],
                          status: .ended, courseSelection: .test)
        round.setDisplayHole(1, at: Date())

        // 5 strokes and a penalty stroke, then a par, on two par 4s
        XCTAssertEqual(HoleOverview.toPar(round), 2)
    }

    func testToParText() {
        XCTAssertEqual(HoleOverview.toParText(0), "E")
        XCTAssertEqual(HoleOverview.toParText(2), "+2")
        XCTAssertEqual(HoleOverview.toParText(-1), "-1")
    }

    func testYardsToPinIsToTheCenterWithoutAPin() {
        let round = Round(courseSelection: PathCourse.selection)
        // Hole 1's green is 300 m north of its tee
        let tee = PathCourse.coordinate(north: 0, east: 0)
        let location = CLLocation(latitude: tee.lat, longitude: tee.lon)

        let yards = HoleOverview.yardsToPin(round, holeIndex: 0, from: location)

        XCTAssertEqual(Double(yards ?? 0), 300 * 1.09361, accuracy: 2)
    }

    func testYardsToPinGoesToThePin() {
        var round = Round(courseSelection: PathCourse.selection)
        let pin = PathCourse.coordinate(north: 310, east: 0)
        round.setPin(pin.clLocation.coordinate, onHole: 0, at: round.date)
        let tee = PathCourse.coordinate(north: 0, east: 0)

        let yards = HoleOverview.yardsToPin(round, holeIndex: 0, from: CLLocation(latitude: tee.lat, longitude: tee.lon))

        XCTAssertEqual(Double(yards ?? 0), 310 * 1.09361, accuracy: 2)
    }

    func testYardsToPinIsNilWithoutALocationOrGreen() {
        let pathRound = Round(courseSelection: PathCourse.selection)
        XCTAssertNil(HoleOverview.yardsToPin(pathRound, holeIndex: 0, from: nil))

        let noGreens = Round(courseSelection: .test)
        let location = CLLocation(latitude: 39.0, longitude: -105.0)
        XCTAssertNil(HoleOverview.yardsToPin(noGreens, holeIndex: 0, from: location))
    }

    func testPreviousYardsIsFromTheLocationToTheLastStroke() {
        let tee = PathCourse.coordinate(north: 0, east: 0)
        let ball = PathCourse.coordinate(north: 100, east: 0)
        let strokes = [Stroke(coordinate: CLLocationCoordinate2D(latitude: tee.lat, longitude: tee.lon))]
        let location = CLLocation(latitude: ball.lat, longitude: ball.lon)

        let yards = HoleOverview.previousYards(strokes: strokes, from: location)

        XCTAssertEqual(Double(yards), 100 * 1.09361, accuracy: 2)
    }

    func testPreviousYardsWithoutALocationIsBetweenTheLastTwoStrokes() {
        let points = [PathCourse.coordinate(north: 0, east: 0), PathCourse.coordinate(north: 50, east: 0),
                      PathCourse.coordinate(north: 200, east: 0)]
        let strokes = points.map { Stroke(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)) }

        let yards = HoleOverview.previousYards(strokes: strokes, from: nil)

        XCTAssertEqual(Double(yards), 150 * 1.09361, accuracy: 2)
    }

    func testPreviousYardsIsZeroWithoutEnoughStrokes() {
        XCTAssertEqual(HoleOverview.previousYards(strokes: [], from: CLLocation(latitude: 40, longitude: -105)), 0)
        XCTAssertEqual(HoleOverview.previousYards(strokes: strokes(1), from: nil), 0)
    }

    func testSummaryShowsParAndTheHoleTee() {
        var course = CourseSelection.test.course
        course.tees = [TeeDefinition(name: "Blue", color: "#0000FF"), TeeDefinition(name: "White", color: "#FFFFFF")]
        course.comboTees = [ComboTeeDefinition(name: "Blue/White", tees: ["Blue", "White"])]
        course.subCourses[0].holes[0].comboTees = ["Blue/White": "White"]
        course.subCourses[0].holes[1].comboTees = ["Blue/White": "Blue"]
        let par = { (index: Int) in CourseSelection.test.orderedHoles[index].par }

        let combo = Round(courseSelection: CourseSelection(course: course, selectedSubCourseIndices: [0, 1], teeName: "Blue/White"))
        XCTAssertEqual(HoleOverview.summary(combo, holeIndex: 0), "Par \(par(0)) - White")
        XCTAssertEqual(HoleOverview.summary(combo, holeIndex: 1), "Par \(par(1)) - Blue")

        let blue = Round(courseSelection: CourseSelection(course: course, selectedSubCourseIndices: [0, 1], teeName: "Blue"))
        XCTAssertEqual(HoleOverview.summary(blue, holeIndex: 0), "Par \(par(0)) - Blue")
    }

    func testSummaryWithoutATeeIsParOnly() {
        let round = Round(courseSelection: PathCourse.selection)

        XCTAssertEqual(HoleOverview.summary(round, holeIndex: 0), "Par 4")
        XCTAssertNil(HoleOverview.summary(round, holeIndex: 5))
    }

    func testStrokeSummaryCountsTheHoleStrokesAndPutts() {
        var round = Round(courseSelection: .test)
        round.holes = [RoundHole(strokes: strokes(3), stats: HoleStats(putts: 1, fairway: true, green: false)),
                       RoundHole(strokes: strokes(4), stats: HoleStats(putts: 2, fairway: nil, green: true))]

        XCTAssertEqual(HoleOverview.strokeSummary(round, holeIndex: 0), "3 strokes · 1 putt")
        XCTAssertEqual(HoleOverview.strokeSummary(round, holeIndex: 1), "4 strokes · 2 putts")
        XCTAssertNil(HoleOverview.strokeSummary(round, holeIndex: 2), "A hole with no strokes has no summary")
    }

    func testStrokeSummaryCountsPenaltyStrokes() {
        var penalty = strokes(3)
        penalty[1].penaltyStrokes = 1
        var round = Round(courseSelection: .test)
        round.holes = [RoundHole(strokes: penalty, stats: HoleStats(putts: 1, fairway: false, green: false))]

        XCTAssertEqual(HoleOverview.strokeSummary(round, holeIndex: 0), "4 strokes · 1 putt")
    }

    func testStrokeSummaryWorksOutPuttsWhenNoneAreSaved() {
        var round = Round(courseSelection: .test)
        round.holes = [RoundHole(strokes: strokes(1))]

        // The stroke is off the test course's green
        XCTAssertEqual(HoleOverview.strokeSummary(round, holeIndex: 0), "1 stroke · 0 putts")
    }

    func testFeetToGreenCenterNeedsAnElevation() {
        let round = Round(courseSelection: PathCourse.selection)
        let tee = PathCourse.coordinate(north: 0, east: 0)

        // The path course's greens have no elevation
        XCTAssertNil(HoleOverview.feetToGreenCenter(round, holeIndex: 0, from: CLLocation(latitude: tee.lat, longitude: tee.lon)))
    }

    func testHazardsAheadOnlyDuringARoundWithALocation() {
        let round = Round(courseSelection: PathCourse.selection)
        let tee = PathCourse.coordinate(north: 0, east: 0)
        let location = CLLocation(latitude: tee.lat, longitude: tee.lon)

        // The path course has no hazards
        XCTAssertTrue(HoleOverview.hazardsAhead(round, holeIndex: 0, from: location).isEmpty)
        XCTAssertTrue(HoleOverview.hazardsAhead(round, holeIndex: 0, from: nil).isEmpty)
    }
}
