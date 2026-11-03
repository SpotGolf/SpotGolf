import CoreLocation
import XCTest
@testable import SpotGolf

/// Which shots count toward a club's distances, and how far each went. Hole 1 of `PathCourse`
/// has its tee at 0 m and a 30 m green centered 300 m north, so the green's edge is at 285 m.
@MainActor
final class ShotDistancesTests: XCTestCase {
    private let driver = Club.named("dr")!
    private let sevenIron = Club.named("7i")!
    private let lobWedge = Club.named("lw")!
    private let putter = Club.named("pu")!

    private func stroke(north: Double, east: Double = 0, club: Club?, penaltyStrokes: Int = 0,
                        quality: ShotQuality = .good) -> Stroke {
        let coordinate = PathCourse.coordinate(north: north, east: east)
        return Stroke(coordinate: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon),
                      penaltyStrokes: penaltyStrokes, quality: quality, club: club)
    }

    /// A round on hole 1 with `strokes`, ended unless `status` says otherwise.
    private func round(_ strokes: [Stroke], status: RoundStatus = .ended,
                       courseSelection: CourseSelection = PathCourse.selection) -> Round {
        let round = Round(status: status, courseSelection: courseSelection)
        round.holes = [RoundHole(strokes: strokes)]
        return round
    }

    private func shots(_ round: Round, greenZone: CLLocationDistance = 10) -> [Club: [Double]] {
        ShotDistances.shots(in: [round], greenZone: greenZone)
    }

    private func yards(meters: Double) -> Double {
        meters * 1.09361
    }

    func testEachShotGoesFromItsSpotToTheNext() throws {
        let result = shots(round([stroke(north: 0, club: driver), stroke(north: 200, club: sevenIron),
                                  stroke(north: 300, club: putter)]))

        XCTAssertEqual(Set(result.keys), [driver, sevenIron], "The putt is left out")
        XCTAssertEqual(try XCTUnwrap(result[driver]?.first), yards(meters: 200), accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(result[sevenIron]?.first), yards(meters: 100), accuracy: 1)
    }

    func testARoundInProgressDoesNotCount() {
        let strokes = [stroke(north: 0, club: driver), stroke(north: 200, club: sevenIron)]

        XCTAssertTrue(shots(round(strokes, status: .active)).isEmpty)
        XCTAssertTrue(shots(round(strokes, status: .ending)).isEmpty)
    }

    func testTheLastStrokeOfAHoleDoesNotCount() {
        XCTAssertTrue(shots(round([stroke(north: 0, club: driver)])).isEmpty, "Where the ball went is not known")
    }

    func testPuttsAndStrokesWithNoClubDoNotCount() {
        let result = shots(round([stroke(north: 0, club: nil), stroke(north: 100, club: putter),
                                  stroke(north: 200, club: sevenIron), stroke(north: 300, club: putter)]))

        XCTAssertEqual(Set(result.keys), [sevenIron])
    }

    func testShotsWithPenaltyStrokesDoNotCount() {
        let result = shots(round([stroke(north: 0, club: driver, penaltyStrokes: 1),
                                  stroke(north: 150, club: sevenIron)]))

        XCTAssertTrue(result.isEmpty, "The next spot is a drop or a re-tee")
    }

    func testThumbsDownShotsDoNotCount() {
        let result = shots(round([stroke(north: 0, club: driver, quality: .bad), stroke(north: 50, club: driver, quality: .okay),
                                  stroke(north: 100, club: driver, quality: .unrated), stroke(north: 150, club: driver, quality: .good),
                                  stroke(north: 200, club: sevenIron)]))

        XCTAssertEqual(result[driver]?.count, 3, "Thumbs up, meh and unrated count")
    }

    func testShotsFromTheGreenZoneDoNotCount() {
        // 5 m and 15 m short of the green's edge
        let strokes = [stroke(north: 270, club: lobWedge), stroke(north: 280, club: lobWedge), stroke(north: 300, club: putter)]

        XCTAssertEqual(shots(round(strokes), greenZone: 10)[lobWedge]?.count, 1, "Only the shot from outside the zone counts")
        XCTAssertNil(shots(round(strokes), greenZone: 20)[lobWedge], "A wider zone takes both")
    }

    func testShotsOnAHoleWithNoGreenCount() {
        let strokes = [stroke(north: 0, club: lobWedge), stroke(north: 10, club: lobWedge)]

        XCTAssertEqual(shots(round(strokes, courseSelection: .test))[lobWedge]?.count, 1,
                       "The Green Zone can't be checked")
    }

    func testShotsAddUpAcrossRoundsAndHoles() {
        let first = round([stroke(north: 0, club: driver), stroke(north: 200, club: sevenIron)])
        let second = round([stroke(north: 0, club: driver), stroke(north: 210, club: sevenIron)])
        second.holes.append(RoundHole(strokes: [stroke(north: 300, east: 60, club: driver),
                                                stroke(north: 300, east: 260, club: sevenIron)]))

        XCTAssertEqual(ShotDistances.shots(in: [first, second], greenZone: 10)[driver]?.count, 3)
    }
}
