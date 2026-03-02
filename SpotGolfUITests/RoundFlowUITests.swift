import XCTest

final class RoundFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    func testFullRoundFlow() throws {
        app.launch()

        // Dismiss the system location permission alert if it appears.
        addUIInterruptionMonitor(withDescription: "Location Permission") { alert in
            let allow = alert.buttons["Allow While Using App"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        // Interaction is needed to trigger the interruption monitor.
        app.tap()

        let locations = LocationTestHelper.loadTestLocations()
        XCTAssertEqual(locations.count, 6, "Expected 6 test locations in CSV")

        // ── Start a new round ──
        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5), "New Round button should exist")
        newRoundButton.tap()

        // Tap the Active row to navigate into RoundMapView.
        let activeText = app.staticTexts["Active"]
        XCTAssertTrue(activeText.waitForExistence(timeout: 5), "Active round row should appear")
        activeText.tap()

        // ── Mark each location ──
        for (index, location) in locations.enumerated() {
            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            // Wait for CLLocationManager to pick up the new position.
            sleep(2)

            let atMyBall = app.buttons["At my ball"]
            XCTAssertTrue(atMyBall.waitForExistence(timeout: 5), "At my ball button should exist")
            atMyBall.tap()

            // Brief pause for the mark to register.
            sleep(2)

            // After placing marks 0…index, strokes = index (fencepost: marks - 1).
            if index > 0 {
                let expectedStrokes = "Strokes: \(index)"
                let strokesLabel = app.staticTexts[expectedStrokes]
                XCTAssertTrue(strokesLabel.waitForExistence(timeout: 5),
                              "Expected \(expectedStrokes) after mark \(index)")
            }
        }

        // ── End the round ──
        app.navigationBars.buttons.element(boundBy: 0).tap() // back
        sleep(1)

        let endRoundButton = app.buttons["End Round"]
        XCTAssertTrue(endRoundButton.waitForExistence(timeout: 5), "End Round button should exist")
        endRoundButton.tap()

        // Verify we're back to the idle state.
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5),
                      "New Round button should reappear after ending round")
    }
}
