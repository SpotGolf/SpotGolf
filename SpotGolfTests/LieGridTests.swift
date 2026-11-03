import CourseDataSwift
import XCTest
@testable import SpotGolf

/// The lie anywhere near a hole. See plans/2026-11-02-caddie-club-and-aim.md, section 3.
final class LieGridTests: XCTestCase {
    /// Hole 1's green is at 150 m, with a fairway from 60 to 130 m, a bunker on the fairway's
    /// right edge and a pond on the left that overlaps the bunker at its top. Hole 2, to the
    /// east, has a fairway and a pond of its own.
    private let lies = PlayCourse.lies(PlayCourse.selection(
        greenNorth: 150,
        features: [
            (.fairway, PlayCourse.rectangle(north: 60...130, east: -15...15)),
            (.bunker, PlayCourse.rectangle(north: 90...100, east: 5...15)),
            (.water, PlayCourse.rectangle(north: 70...110, east: -60...(-20))),
            (.bunker, PlayCourse.rectangle(north: 105...115, east: -25...(-15))),
        ],
        otherHole: [
            (.fairway, PlayCourse.rectangle(north: 60...130, east: 185...215)),
            (.water, PlayCourse.rectangle(north: 60...80, east: 230...260)),
        ]))

    private func lie(north: Double, east: Double) -> Lie {
        lies.lie(at: GroundPoint(x: east, y: north))
    }

    func testEachLie() {
        XCTAssertEqual(lie(north: 150, east: 0), .green)
        XCTAssertEqual(lie(north: 80, east: 0), .fairway)
        XCTAssertEqual(lie(north: 95, east: 10), .sand)
        XCTAssertEqual(lie(north: 90, east: -40), .water)
        XCTAssertEqual(lie(north: 40, east: 0), .rough)
    }

    func testOverlapsGoWaterThenSandThenGreenThenFairway() {
        XCTAssertEqual(lie(north: 95, east: 10), .sand, "A bunker on the fairway is sand")
        XCTAssertEqual(lie(north: 107, east: -22), .water, "Water wins over a bunker it overlaps")
    }

    func testAnotherHolesWaterIsWaterAndItsFairwayAndGreenAreRough() {
        XCTAssertEqual(lie(north: 70, east: 245), .water)
        XCTAssertEqual(lie(north: 100, east: 200), .rough)
        XCTAssertEqual(lie(north: 150, east: 200), .rough)
    }

    func testEachSquaresLieIsKept() {
        _ = lie(north: 79, east: 0.2)
        _ = lie(north: 79.5, east: 0.6)
        XCTAssertEqual(lies.cellCount, 1, "Both points are in one 2-yard square")
    }

    func testTheDropIsWhereTheLineLastWentIntoTheWater() {
        // Hit from the rough east of the pond, stopping 15 m inside its east edge at -20 m
        let entry = lies.waterEntry(from: GroundPoint(x: 0, y: 90), to: GroundPoint(x: -35, y: 90))

        XCTAssertEqual(entry.y, 90, accuracy: 1e-9)
        XCTAssertEqual(entry.x, -20, accuracy: LieGrid.cellSize, "The pond's edge, to within a square")
        XCTAssertEqual(lies.lie(at: entry), .water)
    }

    func testAllWaterDropsAtTheStart() {
        let start = GroundPoint(x: -40, y: 80)

        XCTAssertEqual(lies.waterEntry(from: start, to: GroundPoint(x: -40, y: 100)), start)
    }
}
