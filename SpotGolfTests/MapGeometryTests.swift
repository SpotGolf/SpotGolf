import CoreLocation
import CourseDataSwift
import MapKit
import SwiftUI
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

        let camera = MapGeometry.following(location, heading: 45)
        XCTAssertEqual(camera.heading, 45)
        XCTAssertEqual(camera.distance, MapGeometry.followDistance)
        XCTAssertEqual(MapGeometry.following(location, heading: nil).heading, 0)
    }

    func testMovedAwayIsAPanZoomOrTurnPastTheTolerances() {
        let location = CLLocation(latitude: 40, longitude: -105)
        let follow = MapGeometry.following(location, heading: 45)
        func camera(north: Double = 0, distance: Double = MapGeometry.followDistance, heading: Double = 45) -> MapCamera {
            let center = CLLocationCoordinate2D(latitude: location.coordinate.latitude + north / 111_320,
                                                longitude: location.coordinate.longitude)
            return MapCamera(centerCoordinate: center, distance: distance, heading: heading, pitch: 0)
        }

        XCTAssertFalse(MapGeometry.isMovedAway(follow, from: follow))
        // The next GPS fix, or MapKit's own rounding, is within the tolerances
        XCTAssertFalse(MapGeometry.isMovedAway(camera(north: 3), from: follow))
        XCTAssertFalse(MapGeometry.isMovedAway(camera(distance: MapGeometry.followDistance * 1.02), from: follow))
        XCTAssertFalse(MapGeometry.isMovedAway(camera(heading: 45.5), from: follow))
        // A pan, a pinch, or a turn is not
        XCTAssertTrue(MapGeometry.isMovedAway(camera(north: 12), from: follow))
        XCTAssertTrue(MapGeometry.isMovedAway(camera(distance: MapGeometry.followDistance * 0.8), from: follow))
        XCTAssertTrue(MapGeometry.isMovedAway(camera(heading: 50), from: follow))
        // Headings wrap around north
        XCTAssertFalse(MapGeometry.isMovedAway(camera(heading: 359.5), from: MapGeometry.following(location, heading: 0)))
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

    func testStrokeLinesJoinEachStrokeToTheNextWithTheirYards() {
        let tee = Stroke(coordinate: PathCourse.coordinate(north: 0, east: 0).clLocation.coordinate)
        let fairway = Stroke(coordinate: PathCourse.coordinate(north: 200, east: 0).clLocation.coordinate)
        let green = Stroke(coordinate: PathCourse.coordinate(north: 200, east: 100).clLocation.coordinate)

        let lines = MapGeometry.strokeLines([tee, fairway, green])

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].start.latitude, tee.latitude)
        XCTAssertEqual(lines[0].end.latitude, fairway.latitude)
        XCTAssertEqual(lines[1].start.longitude, fairway.longitude)
        XCTAssertEqual(lines[1].end.longitude, green.longitude)
        // 200 m is 219 yards, 100 m is 109
        XCTAssertEqual(lines[0].yards, 219, accuracy: 1)
        XCTAssertEqual(lines[1].yards, 109, accuracy: 1)
        // The yards sit halfway along the line
        XCTAssertEqual(lines[0].midpoint.latitude, (tee.latitude + fairway.latitude) / 2, accuracy: 1e-9)
        XCTAssertEqual(lines[1].midpoint.longitude, (fairway.longitude + green.longitude) / 2, accuracy: 1e-9)

        XCTAssertEqual(MapGeometry.strokeLines([tee]), [])
        XCTAssertEqual(MapGeometry.strokeLines([]), [])
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
