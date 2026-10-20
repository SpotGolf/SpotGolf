import CoreLocation
import CourseDataSwift
import XCTest
@testable import SpotGolf

final class GreenProjectionTests: XCTestCase {
    /// Hole 2's 30 m green, which plays east.
    private let green = PathCourse.square(north: 300, east: 360, half: 15)
    private let size = CGSize(width: 400, height: 600)

    private func projection(heading: Double = 90) throws -> GreenProjection {
        try XCTUnwrap(GreenProjection(green: green, heading: heading, size: size))
    }

    private func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    func testGroundToScreenAndBackLandsWithinACentimeter() throws {
        var projection = try projection(heading: 37)
        projection.zoom(by: 3, at: CGPoint(x: 120, y: 200))
        let coordinate = PathCourse.coordinate(north: 309, east: 351).clCoordinate

        let back = projection.coordinate(at: projection.point(for: coordinate))

        XCTAssertLessThan(meters(back, coordinate), 0.01)
    }

    func testOpensFittedToTheGreenWithItsMarginAndCentered() throws {
        let projection = try projection()

        // The green is 30 m wide; the 400 pt width is the tighter side
        XCTAssertEqual(projection.pointsPerMeter, 400 / (30 + 2 * GreenProjection.openMargin), accuracy: 0.01)
        let center = projection.point(for: PathCourse.coordinate(north: 300, east: 360).clCoordinate)
        XCTAssertEqual(center.x, 200, accuracy: 0.5)
        XCTAssertEqual(center.y, 300, accuracy: 0.5)
        XCTAssertNil(GreenProjection(green: [], heading: 0, size: size))
        XCTAssertNil(GreenProjection(green: green, heading: 0, size: .zero))
    }

    func testTurnsTheDirectionOfPlayUp() throws {
        let projection = try projection(heading: 90)

        // Hole 2 plays east: east of the center is up, north of it is left
        let center = projection.point(for: PathCourse.coordinate(north: 300, east: 360).clCoordinate)
        let east = projection.point(for: PathCourse.coordinate(north: 300, east: 365).clCoordinate)
        let north = projection.point(for: PathCourse.coordinate(north: 305, east: 360).clCoordinate)
        XCTAssertLessThan(east.y, center.y - 10)
        XCTAssertEqual(east.x, center.x, accuracy: 0.5)
        XCTAssertLessThan(north.x, center.x - 10)
        XCTAssertEqual(north.y, center.y, accuracy: 0.5)
    }

    func testZoomStopsAtItsLimits() throws {
        var projection = try projection()

        projection.zoom(by: 1000, at: CGPoint(x: 200, y: 300))
        XCTAssertEqual(projection.pointsPerMeter, GreenProjection.maxPointsPerMeter)

        projection.zoom(by: 0.0001, at: CGPoint(x: 200, y: 300))
        XCTAssertEqual(projection.pointsPerMeter, 400 / (30 + 2 * GreenProjection.zoomOutMargin), accuracy: 0.01)
    }

    func testZoomKeepsTheGroundUnderTheFingers() throws {
        var projection = try projection()
        let anchor = CGPoint(x: 250, y: 280)
        let held = projection.coordinate(at: anchor)

        projection.zoom(by: 2, at: anchor)

        let after = projection.point(for: held)
        XCTAssertEqual(after.x, anchor.x, accuracy: 0.5)
        XCTAssertEqual(after.y, anchor.y, accuracy: 0.5)
    }

    func testPanMovesTheGroundWithTheFingerAndStopsPastTheGreen() throws {
        var projection = try projection()
        projection.zoom(by: 4, at: CGPoint(x: 200, y: 300))
        let coordinate = projection.coordinate(at: CGPoint(x: 200, y: 300))

        projection.pan(by: CGSize(width: 30, height: -20))
        let moved = projection.point(for: coordinate)
        XCTAssertEqual(moved.x, 230, accuracy: 0.5)
        XCTAssertEqual(moved.y, 280, accuracy: 0.5)

        projection.pan(by: CGSize(width: -100_000, height: 0))
        XCTAssertEqual(projection.focus.x, 15 + GreenProjection.zoomOutMargin, accuracy: 0.01)
    }
}

final class GreenViewStateTests: XCTestCase {
    func testOpensWhenThePlayerWalksOntoTheGreen() {
        var state = GreenViewState()

        state.playerMoved(metersOffGreen: 30)
        XCTAssertFalse(state.isShown)

        state.playerMoved(metersOffGreen: 0)
        XCTAssertTrue(state.isShown)
    }

    func testDoesNotOpenWithoutAGreen() {
        var state = GreenViewState()

        state.playerMoved(metersOffGreen: nil)

        XCTAssertFalse(state.isShown)
    }

    func testWalkingOffTheGreenKeepsItOpen() {
        var state = GreenViewState()
        state.playerMoved(metersOffGreen: 0)

        state.playerMoved(metersOffGreen: 50)

        XCTAssertTrue(state.isShown, "Only X or a hole change closes Green View")
    }

    func testClosedWithXStaysClosedOnThatHole() {
        var state = GreenViewState()
        state.playerMoved(metersOffGreen: 0)
        state.close()

        state.playerMoved(metersOffGreen: 20)
        state.playerMoved(metersOffGreen: 0)
        XCTAssertFalse(state.isShown)

        state.holeChanged()
        state.playerMoved(metersOffGreen: 0)
        XCTAssertTrue(state.isShown)
    }

    func testHoleChangeCloses() {
        var state = GreenViewState()
        state.open()

        state.holeChanged()

        XCTAssertFalse(state.isShown)
    }

    func testMetersOffGreen() {
        let round = Round(courseSelection: PathCourse.selection)

        XCTAssertEqual(round.metersOffGreen(PathCourse.coordinate(north: 300, east: 0).clCoordinate, holeIndex: 0), 0)
        // Course outlines are kept to about 30 cm
        XCTAssertEqual(try XCTUnwrap(round.metersOffGreen(PathCourse.coordinate(north: 255, east: 0).clCoordinate,
                                                          holeIndex: 0)), 30, accuracy: 0.3)
        XCTAssertNil(Round(courseSelection: .test).metersOffGreen(PathCourse.coordinate(north: 0, east: 0).clCoordinate,
                                                                   holeIndex: 0))
    }
}
