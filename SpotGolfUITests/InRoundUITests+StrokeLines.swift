import XCTest

/// The dot menu's Distances item, which shows the lines and yards between a hole's strokes.
extension InRoundUITests {
    /// Adds a spot in Green View at `point` on its ground and saves it.
    private func addSpotInGreenView(at point: CGVector) {
        element("GreenViewGround").coordinate(withNormalizedOffset: point).press(forDuration: 0.6)
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "A long press should add a spot")
        saveInSheet()
    }

    func testShowsAndHidesTheLinesBetweenStrokesFromTheMenu() throws {
        // Three strokes, so two lines. Left of center, clear of the flag Green View centers on.
        _ = freshHole()
        tapMapMenuItem("GreenView")
        XCTAssertTrue(element("GreenViewGround").waitToExist())
        for y in [0.35, 0.5, 0.65] {
            addSpotInGreenView(at: CGVector(dx: 0.3, dy: y))
        }
        app.buttons["CloseGreenView"].tap()

        let firstDistance = element("StrokeDistance_1")
        XCTAssertTrue(app.buttons["MapMenu"].waitToExist())
        XCTAssertFalse(firstDistance.exists, "No distances before Distances is picked")

        tapMapMenuItem("StrokeLines")
        XCTAssertTrue(firstDistance.waitToExist(), "Distances should show the yards between strokes")
        XCTAssertTrue(element("StrokeDistance_2").exists, "There should be a line from stroke 2 to stroke 3")
        XCTAssertFalse(element("StrokeDistance_3").exists, "There should be no line past the last stroke")
        XCTAssertNotNil(Int(firstDistance.label.split(separator: " ").first ?? ""), "The label should be yards")

        tapMapMenuItem("StrokeLines")
        XCTAssertTrue(firstDistance.waitToVanish(), "Picking Distances again should hide the lines")
    }
}
