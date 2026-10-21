import XCTest
@testable import SpotGolf

final class HoleHoldTests: XCTestCase {
    func testNoHoldShowsTheDisplayHole() {
        XCTAssertNil(HoleHold().holeIndex(lastHoleIndex: 17))
    }

    func testAnEditHoldsTheHoleItStartedOnUntilItEnds() {
        var hold = HoleHold()
        hold.editChanged(isEditing: true, shownHoleIndex: 3)
        XCTAssertEqual(hold.holeIndex(lastHoleIndex: 17), 3)

        hold.editChanged(isEditing: false, shownHoleIndex: 3)
        XCTAssertNil(hold.holeIndex(lastHoleIndex: 17))
    }

    func testReleaseEndsTheHold() {
        var hold = HoleHold()
        hold.editChanged(isEditing: true, shownHoleIndex: 2)
        hold.release()
        XCTAssertNil(hold.holeIndex(lastHoleIndex: 17))
    }

    func testAHolePastTheLastIsDropped() {
        var hold = HoleHold()
        hold.editChanged(isEditing: true, shownHoleIndex: 12)
        XCTAssertNil(hold.holeIndex(lastHoleIndex: 8))
    }
}
