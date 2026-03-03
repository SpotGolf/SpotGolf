import XCTest

final class WatchRoundFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    func testFullRoundFlow() throws {
        app.launch()

        let locations = LocationTestHelper.loadTestLocations()
        XCTAssertEqual(locations.count, 6, "Expected 6 test locations in CSV")

        // ── Start a new round ──
        let startButton = app.buttons["Start Round"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Round button should exist")
        startButton.tap()

        // ── Mark each location ──
        for (index, location) in locations.enumerated() {
            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            // Wait for CLLocationManager to pick up the new position.
            sleep(2)

            let atMyBall = app.buttons["At my ball"]
            XCTAssertTrue(atMyBall.waitForExistence(timeout: 10), "At my ball button should exist")
            atMyBall.tap()

            // Wait for "Swing away" to dismiss (~15s) — "At my ball" reappears.
            let atMyBallAgain = app.buttons["At my ball"]
            XCTAssertTrue(atMyBallAgain.waitForExistence(timeout: 25),
                          "At my ball should reappear after Swing away clears")

            // Verify stroke count (strokes = number of marks - 1).
            if index > 0 {
                let expectedStrokes = "Strokes: \(index)"
                let strokesLabel = app.staticTexts[expectedStrokes]
                XCTAssertTrue(strokesLabel.waitForExistence(timeout: 5),
                              "Expected \(expectedStrokes) after mark \(index)")
            }
        }

        // ── End the round ──
        let endRoundButton = app.buttons["End Round"]
        XCTAssertTrue(endRoundButton.waitForExistence(timeout: 5), "End Round button should exist")
        endRoundButton.tap()

        // Verify we're back to the idle state.
        XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                      "Start Round button should reappear after ending round")
    }
}
