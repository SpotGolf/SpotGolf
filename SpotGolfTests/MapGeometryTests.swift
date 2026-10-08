import CoreLocation
import CourseDataSwift
import MapKit
import XCTest
@testable import SpotGolf

final class MapGeometryTests: XCTestCase {

    func testBearingPointsFromStartToEnd() {
        let origin = PathCourse.coordinate(north: 0, east: 0)

        XCTAssertEqual(MapGeometry.bearing(from: origin, to: PathCourse.coordinate(north: 100, east: 0)), 0, accuracy: 0.1)
        XCTAssertEqual(MapGeometry.bearing(from: origin, to: PathCourse.coordinate(north: 0, east: 100)), 90, accuracy: 0.1)
        XCTAssertEqual(MapGeometry.bearing(from: origin, to: PathCourse.coordinate(north: -100, east: 0)), 180, accuracy: 0.1)
        XCTAssertEqual(MapGeometry.bearing(from: origin, to: PathCourse.coordinate(north: 0, east: -100)), 270, accuracy: 0.1)
    }

    func testHeadingIsFromTeeToGreen() {
        let round = Round(courseSelection: PathCourse.selection)

        // Hole 1 plays north, hole 2 east
        XCTAssertEqual(try XCTUnwrap(MapGeometry.heading(of: round, holeIndex: 0)), 0, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(MapGeometry.heading(of: round, holeIndex: 1)), 90, accuracy: 0.1)
        XCTAssertNil(MapGeometry.heading(of: Round(courseSelection: .test), holeIndex: 0))
    }

    func testHoleCameraTurnsTheGreenToTheTopAndShowsTheWholeHole() throws {
        let round = Round(courseSelection: PathCourse.selection)

        let camera = try XCTUnwrap(MapGeometry.holeCamera(round, holeIndex: 1))

        XCTAssertEqual(camera.heading, 90, accuracy: 0.1)
        // The hole's only feature is its 30 m green: the camera is higher than that, and moved
        // from the green's middle toward the tee, to the west
        XCTAssertGreaterThan(camera.distance, 30)
        let green = PathCourse.coordinate(north: 300, east: 360)
        XCTAssertLessThan(camera.centerCoordinate.longitude, green.longitude)
        XCTAssertNil(MapGeometry.holeCamera(Round(courseSelection: .test), holeIndex: 0))
    }

    func testFollowingTurnsToTheHeadingWhenKnown() {
        let location = CLLocation(latitude: 40, longitude: -105)

        guard case .some(let camera) = MapGeometry.following(location, heading: 45).camera else {
            return XCTFail("Expected a camera")
        }
        XCTAssertEqual(camera.heading, 45)
        XCTAssertEqual(camera.distance, MapGeometry.followDistance)
        XCTAssertNotNil(MapGeometry.following(location, heading: nil).region)
    }

    func testMetersPerPointTakesTheTurnBackOut() throws {
        let size = CGSize(width: 400, height: 800)

        XCTAssertEqual(try XCTUnwrap(MapGeometry.metersPerPoint(mapSize: size, heading: 0, metersAcross: 200)), 0.5, accuracy: 1e-9)
        // Turned a quarter, the box around the map is as wide as the map is tall
        XCTAssertEqual(try XCTUnwrap(MapGeometry.metersPerPoint(mapSize: size, heading: 90, metersAcross: 400)), 0.5, accuracy: 1e-9)
        XCTAssertNil(MapGeometry.metersPerPoint(mapSize: .zero, heading: 0, metersAcross: 200))
    }

    func testLineEndStopsTheGapOutFromTheTarget() throws {
        let target = PathCourse.coordinate(north: 0, east: 0).clLocation.coordinate
        let other = PathCourse.coordinate(north: 100, east: 0).clLocation.coordinate

        let end = try XCTUnwrap(MapGeometry.lineEnd(at: target, toward: other, gap: 10))

        XCTAssertEqual(CLLocation(latitude: end.latitude, longitude: end.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)), 10, accuracy: 0.1)
        XCTAssertNil(MapGeometry.lineEnd(at: target, toward: other, gap: 150))
    }

    func testFlagGrowsWithZoomBetweenItsLimits() {
        XCTAssertEqual(MapGeometry.flagScale(metersPerPoint: 2), 1)
        XCTAssertEqual(MapGeometry.flagScale(metersPerPoint: MapGeometry.normalFlagMetersPerPoint), 1, accuracy: 1e-9)
        XCTAssertEqual(MapGeometry.flagScale(metersPerPoint: MapGeometry.largestFlagMetersPerPoint),
                       MapGeometry.largestFlagScale, accuracy: 1e-9)
        XCTAssertEqual(MapGeometry.flagScale(metersPerPoint: 0.01), MapGeometry.largestFlagScale)
        let halfway = MapGeometry.flagScale(metersPerPoint: sqrt(MapGeometry.normalFlagMetersPerPoint * MapGeometry.largestFlagMetersPerPoint))
        XCTAssertEqual(halfway, 1.25, accuracy: 1e-9)
    }

    func testHoleTrackKeepsTheFixesOnTheHole() {
        let round = Round(date: StreamFixtures.start, courseSelection: PathCourse.selection)
        round.startHole(1, at: StreamFixtures.start.addingTimeInterval(600), source: .stroke)
        let early = TrackPoint(location: StreamFixtures.location(60))
        let late = TrackPoint(location: StreamFixtures.location(700))

        XCTAssertEqual(HoleTrack.points([early, late], in: round, holeIndex: 0), [early])
        XCTAssertEqual(HoleTrack.points([early, late], in: round, holeIndex: 1), [late])
    }
}
