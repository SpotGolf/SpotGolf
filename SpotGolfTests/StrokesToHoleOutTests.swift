import XCTest
@testable import SpotGolf

/// Broadie's strokes to hole out, by lie and distance. See
/// plans/2026-11-02-caddie-club-and-aim.md, section 3.
final class StrokesToHoleOutTests: XCTestCase {
    func testTheTablesRows() {
        XCTAssertEqual(StrokesToHoleOut.strokes(.fairway, yards: 100), 2.80, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.strokes(.rough, yards: 140), 3.15, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.strokes(.sand, yards: 20), 2.53, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.strokes(.fairway, yards: 600), 4.94, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.putts(feet: 30), 2.00, accuracy: 1e-9)
    }

    func testBetweenRowsIsAStraightLine() {
        XCTAssertEqual(StrokesToHoleOut.strokes(.fairway, yards: 110), 2.825, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.strokes(.rough, yards: 150), 3.19, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.putts(feet: 12.5), 1.695, accuracy: 1e-9)
    }

    func testPastTheEndsIsTheEndRow() {
        XCTAssertEqual(StrokesToHoleOut.strokes(.fairway, yards: 5), 2.40, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.strokes(.sand, yards: 700), 5.52, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.putts(feet: 0.5), 1.00, accuracy: 1e-9)
        XCTAssertEqual(StrokesToHoleOut.putts(feet: 150), 2.45, accuracy: 1e-9)
    }

    func testTheGreenGoesByFeet() {
        XCTAssertEqual(StrokesToHoleOut.strokes(.green, yards: 10), StrokesToHoleOut.putts(feet: 30), accuracy: 1e-9)
    }

    func testWaterIsAPenaltyStrokeAndTheRough() {
        XCTAssertEqual(StrokesToHoleOut.strokes(.water, yards: 100), 1 + 3.02, accuracy: 1e-9)
    }
}
