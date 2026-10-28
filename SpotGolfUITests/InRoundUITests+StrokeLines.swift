import XCTest

/// The ruler, which shows the lines and yards between a hole's strokes.
extension InRoundUITests {
    /// Adds a spot in Green View at `point` on its ground and saves it.
    private func addSpotInGreenView(at point: CGVector) {
        element("GreenViewGround").coordinate(withNormalizedOffset: point).press(forDuration: 0.6)
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "A long press should add a spot")
        saveInSheet()
    }

    func testRulerShowsAndHidesTheLinesBetweenStrokes() throws {
        // Three strokes, so two lines. Left of center, clear of the flag Green View centers on.
        _ = freshHole()
        app.buttons["GreenView"].tap()
        XCTAssertTrue(element("GreenViewGround").waitToExist())
        for y in [0.35, 0.5, 0.65] {
            addSpotInGreenView(at: CGVector(dx: 0.3, dy: y))
        }
        app.buttons["CloseGreenView"].tap()

        let ruler = app.buttons["StrokeLines"]
        let firstDistance = element("StrokeDistance_1")
        XCTAssertTrue(ruler.waitToExist(), "The ruler should be in the left capsule")
        XCTAssertFalse(firstDistance.exists, "No distances before the ruler is tapped")

        ruler.tap()
        XCTAssertTrue(firstDistance.waitToExist(), "The ruler should show the yards between strokes")
        XCTAssertTrue(element("StrokeDistance_2").exists, "There should be a line from stroke 2 to stroke 3")
        XCTAssertFalse(element("StrokeDistance_3").exists, "There should be no line past the last stroke")
        XCTAssertNotNil(Int(firstDistance.label.split(separator: " ").first ?? ""), "The label should be yards")

        ruler.tap()
        XCTAssertTrue(firstDistance.waitToVanish(), "Tapping the ruler again should hide the lines")
    }
}
