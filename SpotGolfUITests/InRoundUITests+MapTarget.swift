import XCTest

/// The target dropped by a tap on the map, and its yards.
extension InRoundUITests {
    private var target: XCUIElement { app.descendants(matching: .any)["Target"] }
    private var clearTargetButton: XCUIElement { app.buttons["ClearTarget"] }
    /// The yards from the player to the target, in the box on the left.
    private var distanceToTarget: XCUIElement { app.descendants(matching: .any)["DistanceToTarget"] }
    /// The yards from the target to the center of the green, in the box under it.
    private var targetToGreen: XCUIElement { app.descendants(matching: .any)["TargetToGreen"] }

    private func assertShowsYards(_ box: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(box.exists, "\(name) should show with a target", file: file, line: line)
        XCTAssertNotNil(box.label.range(of: #"^\d+"#, options: .regularExpression),
                        "\(name) should show its yards: \(box.label)", file: file, line: line)
    }

    func testTapShowsTargetWithYardsAndClearRemovesIt() throws {
        app.goToHole(1)
        XCTAssertFalse(target.exists, "No target before a tap")
        XCTAssertFalse(distanceToTarget.exists, "No distance boxes before a tap")
        XCTAssertFalse(clearTargetButton.exists, "No clear button before a tap")

        // A little above the map's center, away from the player's own location
        app.maps.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(target.waitToExist(), "A tap should show the target")
        assertShowsYards(distanceToTarget, "The yards to the point")
        assertShowsYards(targetToGreen, "The yards from the point to the green")
        XCTAssertTrue(clearTargetButton.exists, "The clear button should show with a target")

        clearTargetButton.tap()
        XCTAssertTrue(target.waitToVanish(), "Clear should remove the target")
        XCTAssertFalse(distanceToTarget.exists, "The distance boxes should go away with the target")
        XCTAssertFalse(targetToGreen.exists, "The distance boxes should go away with the target")
        XCTAssertFalse(clearTargetButton.exists, "The clear button should go away with the target")
    }

    func testTapOnASpotOpensItAndShowsNoTarget() throws {
        _ = freshHole()
        addStroke(at: XCUIApplication.strokePressPoints[0])
        openStroke(1)
        XCTAssertFalse(target.exists, "A tap on a spot should not drop a target")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToVanish())
    }
}
