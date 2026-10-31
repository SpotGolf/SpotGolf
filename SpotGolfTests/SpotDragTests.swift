import XCTest
@testable import SpotGolf

final class SpotDragTests: XCTestCase {
    private let press = CGPoint(x: 100, y: 200)

    func testANewSpotStartsUnderTheFinger() {
        let drag = SpotDrag(dot: press, press: press, lift: 70)
        XCTAssertEqual(drag.dot, press)
        XCTAssertFalse(drag.follows)
    }

    func testAHeldSpotStaysWhereItIs() {
        // The finger is on the head, above the dot
        var drag = SpotDrag(dot: CGPoint(x: 100, y: 230), press: press, lift: 70)
        XCTAssertFalse(drag.fingerMoved(to: CGPoint(x: 104, y: 205)), "A still finger's wobble should not move it")
        XCTAssertEqual(drag.dot, CGPoint(x: 100, y: 230))
        XCTAssertFalse(drag.follows)
    }

    func testAMovedFingerRaisesTheSpotAboveIt() {
        var drag = SpotDrag(dot: CGPoint(x: 100, y: 230), press: press, lift: 70)
        XCTAssertTrue(drag.fingerMoved(to: CGPoint(x: 100, y: 200 + SpotDrag.slop)))
        XCTAssertTrue(drag.follows)
        XCTAssertEqual(drag.dot, CGPoint(x: 100, y: 140))
    }

    func testTheSpotKeepsFollowingWhenTheFingerComesBack() {
        var drag = SpotDrag(dot: press, press: press, lift: 70)
        drag.fingerMoved(to: CGPoint(x: 150, y: 200))
        XCTAssertFalse(drag.fingerMoved(to: CGPoint(x: 102, y: 201)), "It only starts following once")
        XCTAssertEqual(drag.dot, CGPoint(x: 102, y: 131))
    }
}
