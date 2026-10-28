import XCTest

/// Penalty strokes counted on spots added by hand.
extension InRoundUITests {
    func testPenaltyAndOutOfBoundsStrokes() throws {
        let locations = LocationTestHelper.loadTestLocations(from: "test-locations-penalties")
        XCTAssertEqual(locations.count, 14, "Penalty test CSV should have 14 locations")

        // The CSV's holes 1 and 2 are played on holes of their own
        var holes: [Int: Int] = [:]
        var strokesOnHole: [Int: Int] = [:]
        for (index, location) in locations.enumerated() {
            if holes[location.hole] == nil {
                holes[location.hole] = freshHole()
            } else if !app.holeButton(holes[location.hole]!).isSelected {
                app.goToHole(holes[location.hole]!)
            }

            // Strokes are placed by hand, so the spot comes from the press and not from GPS
            let spot = strokesOnHole[location.hole, default: 0]
            strokesOnHole[location.hole] = spot + 1
            app.addStroke(at: XCUIApplication.strokePressPoints[spot])
            XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(),
                          "Edit sheet should open for the new stroke at location \(index)")

            // Counting a penalty stroke keeps the sheet open; Save applies it
            saveInSheet(tapping: location.type == .penalty ? ["PenaltyPlus"] : [])
        }

        // CSV hole 1: 8 strokes (tee, out of bounds, re-tee, 5 more)
        app.goToHole(holes[1]!)
        assertStrokeCount(8, onHole: holes[1]!)

        // CSV hole 2: 6 strokes (tee, 2nd shot, penalty, drop, shot, putt)
        app.goToHole(holes[2]!)
        assertStrokeCount(6, onHole: holes[2]!)
    }
}
