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

    func testToParText() {
        XCTAssertEqual(HoleOverview.toParText(0), "E")
        XCTAssertEqual(HoleOverview.toParText(2), "+2")
        XCTAssertEqual(HoleOverview.toParText(-1), "-1")
    }

    func testYardsToPinIsToTheCenterWithoutAPin() {
        let round = Round(courseSelection: PathCourse.selection)
        // Hole 1's green is 300 m north of its tee
        let tee = PathCourse.coordinate(north: 0, east: 0)
        let location = CLLocation(latitude: tee.latitude, longitude: tee.longitude)

        let yards = HoleOverview.yardsToPin(round, holeIndex: 0, from: location)

        XCTAssertEqual(Double(yards ?? 0), 300 * 1.09361, accuracy: 2)
    }

    func testYardsToPinGoesToThePin() {
        var round = Round(courseSelection: PathCourse.selection)
        let pin = PathCourse.coordinate(north: 310, east: 0)
        round.setPin(pin.clLocation.coordinate, onHole: 0, at: round.date)
        let tee = PathCourse.coordinate(north: 0, east: 0)

        let yards = HoleOverview.yardsToPin(round, holeIndex: 0, from: CLLocation(latitude: tee.latitude, longitude: tee.longitude))

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
        let strokes = [Stroke(coordinate: CLLocationCoordinate2D(latitude: tee.latitude, longitude: tee.longitude))]
        let location = CLLocation(latitude: ball.latitude, longitude: ball.longitude)

        let yards = HoleOverview.previousYards(strokes: strokes, from: location)

        XCTAssertEqual(Double(yards), 100 * 1.09361, accuracy: 2)
    }

    func testPreviousYardsWithoutALocationIsBetweenTheLastTwoStrokes() {
        let points = [PathCourse.coordinate(north: 0, east: 0), PathCourse.coordinate(north: 50, east: 0),
                      PathCourse.coordinate(north: 200, east: 0)]
        let strokes = points.map { Stroke(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }

        let yards = HoleOverview.previousYards(strokes: strokes, from: nil)

        XCTAssertEqual(Double(yards), 150 * 1.09361, accuracy: 2)
    }

    func testPreviousYardsIsZeroWithoutEnoughStrokes() {
        XCTAssertEqual(HoleOverview.previousYards(strokes: [], from: CLLocation(latitude: 40, longitude: -105)), 0)
        XCTAssertEqual(HoleOverview.previousYards(strokes: strokes(1), from: nil), 0)
    }
}
