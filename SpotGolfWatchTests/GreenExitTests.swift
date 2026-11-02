import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolfWatch

final class GreenExitTests: XCTestCase {

    private static let metersPerDegreeLongitude = 111_320.0 * cos(33.0 * .pi / 180)
    /// The green is a square this many meters from its center to its east edge.
    private static let greenEdge = 0.0001 * metersPerDegreeLongitude
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private let green = HoleShape(green: [
        Coordinate(lat: 32.9999, lon: -97.0001),
        Coordinate(lat: 32.9999, lon: -96.9999),
        Coordinate(lat: 33.0001, lon: -96.9999),
        Coordinate(lat: 33.0001, lon: -97.0001),
        Coordinate(lat: 32.9999, lon: -97.0001),
    ])

    /// A point `east` meters from the green's center.
    private func point(east: Double) -> Coordinate {
        Coordinate(lat: 33.0, lon: -97.0 + east / Self.metersPerDegreeLongitude)
    }

    /// `count` fixes at the green's center, one a second.
    private func onGreen(_ exit: inout GreenExit, count: Int, from second: Int = 0) {
        for index in 0..<count {
            exit.update(point(east: 0), at: start.addingTimeInterval(TimeInterval(second + index)))
        }
    }

    func testLeavesAfterTwentyFixesOnTheGreenAndTwentyMetersFromItsEdge() {
        var exit = GreenExit(shape: green)
        onGreen(&exit, count: 20)

        XCTAssertEqual(exit.update(point(east: Self.greenEdge + 19), at: start.addingTimeInterval(30)) ?? 0, 19, accuracy: 0.5)
        XCTAssertFalse(exit.hasLeft)
        exit.update(point(east: Self.greenEdge + 21), at: start.addingTimeInterval(31))
        XCTAssertTrue(exit.hasLeft)
    }

    func testFewerThanTwentyFixesOnTheGreenNeverLeaves() {
        var exit = GreenExit(shape: green)
        onGreen(&exit, count: 19)

        exit.update(point(east: Self.greenEdge + 100), at: start.addingTimeInterval(30))

        XCTAssertFalse(exit.hasLeft)
    }

    func testFixesOnTheGreenCountAcrossVisits() {
        var exit = GreenExit(shape: green)
        onGreen(&exit, count: 10)
        exit.update(point(east: Self.greenEdge + 50), at: start.addingTimeInterval(10))
        XCTAssertFalse(exit.hasLeft)
        onGreen(&exit, count: 10, from: 11)

        exit.update(point(east: Self.greenEdge + 50), at: start.addingTimeInterval(21))

        XCTAssertTrue(exit.hasLeft)
    }

    func testRemembersTheLastFixOnTheGreen() {
        var exit = GreenExit(shape: green)
        XCTAssertNil(exit.lastOnGreenAt)
        onGreen(&exit, count: 25)

        exit.update(point(east: Self.greenEdge + 30), at: start.addingTimeInterval(40))

        XCTAssertEqual(exit.lastOnGreenAt, start.addingTimeInterval(24))
    }

    func testAHoleWithoutAGreenNeverLeaves() {
        var exit = GreenExit()

        for second in 0..<30 {
            XCTAssertNil(exit.update(point(east: 0), at: start.addingTimeInterval(TimeInterval(second))))
        }
        XCTAssertNil(exit.update(point(east: 100), at: start.addingTimeInterval(30)))
        XCTAssertFalse(exit.hasLeft)
        XCTAssertNil(exit.lastOnGreenAt)
    }
}
