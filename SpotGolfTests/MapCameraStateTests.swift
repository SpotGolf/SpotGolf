import CoreLocation
import MapKit
import SwiftUI
import XCTest
@testable import SpotGolf

final class MapCameraStateTests: XCTestCase {
    private let location = CLLocation(latitude: 40, longitude: -105)

    private func zoomedIn() -> MapCamera {
        MapCamera(centerCoordinate: location.coordinate, distance: MapGeometry.followDistance / 2, heading: 45, pitch: 0)
    }

    func testFollowPointsAtThePlayerAndShowLeavesThem() {
        var camera = MapCameraState()
        camera.follow(location, heading: 45)

        XCTAssertTrue(camera.followsUserLocation)
        XCTAssertEqual(camera.followCamera?.heading, 45)
        XCTAssertFalse(camera.isAtFollowCamera)

        camera.show(zoomedIn())

        XCTAssertFalse(camera.followsUserLocation)
        XCTAssertNil(camera.followCamera)
    }

    func testTheMapSettlingOnThePlayerKeepsFollowing() throws {
        var camera = MapCameraState()
        camera.follow(location, heading: 45)

        // Frames of the move toward the player do not count, however far off they are
        camera.mapMoved(to: zoomedIn(), ended: false)
        XCTAssertTrue(camera.followsUserLocation)

        camera.mapMoved(to: try XCTUnwrap(camera.followCamera), ended: true)
        XCTAssertTrue(camera.followsUserLocation)
        XCTAssertTrue(camera.isAtFollowCamera)
    }

    func testAPinchAfterSettlingEndsFollowingAtOnce() throws {
        var camera = MapCameraState()
        camera.follow(location, heading: 45)
        camera.mapMoved(to: try XCTUnwrap(camera.followCamera), ended: true)

        camera.mapMoved(to: zoomedIn(), ended: false)

        XCTAssertFalse(camera.followsUserLocation)
    }

    func testStoppingOffThePlayerEndsFollowing() {
        var camera = MapCameraState()
        camera.follow(location, heading: 45)

        camera.mapMoved(to: zoomedIn(), ended: true)

        XCTAssertFalse(camera.followsUserLocation)
    }

    func testTheNextFixStartsTheMoveOver() throws {
        var camera = MapCameraState()
        camera.follow(location, heading: 45)
        camera.mapMoved(to: try XCTUnwrap(camera.followCamera), ended: true)

        camera.follow(CLLocation(latitude: 40.00001, longitude: -105), heading: 45)

        XCTAssertFalse(camera.isAtFollowCamera)
        XCTAssertTrue(camera.followsUserLocation)
    }
}
