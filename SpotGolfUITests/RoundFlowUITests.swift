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

        // ── Hole 1: Mark first 3 locations ──
        for (index, location) in locations.prefix(3).enumerated() {
            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            sleep(2)

            let atMyBall = app.buttons["At my ball"]
            XCTAssertTrue(atMyBall.waitForExistence(timeout: 5), "At my ball button should exist")
            atMyBall.tap()

            sleep(2)

            if index > 0 {
                let expectedStrokes = "Strokes: \(index)"
                let strokesLabel = app.staticTexts[expectedStrokes]
                XCTAssertTrue(strokesLabel.waitForExistence(timeout: 5),
                              "Expected \(expectedStrokes) after mark \(index)")
            }
        }

        // Verify Hole 1 is displayed
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Hole 1 label should be visible")

        // ── Navigate to Hole 2 ──
        let nextHoleButton = app.buttons["Next Hole"]
        XCTAssertTrue(nextHoleButton.waitForExistence(timeout: 5), "Next Hole button should exist")
        nextHoleButton.tap()
        sleep(1)

        let hole2Label = app.staticTexts["Hole 2"]
        XCTAssertTrue(hole2Label.waitForExistence(timeout: 5), "Hole 2 label should appear after next hole")

        // Strokes should reset to 0 on new hole
        let strokesZero = app.staticTexts["Strokes: 0"]
        XCTAssertTrue(strokesZero.waitForExistence(timeout: 5), "Strokes should reset to 0 on new hole")

        // ── Hole 2: Mark remaining 3 locations ──
        for (index, location) in locations.suffix(3).enumerated() {
            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            sleep(2)

            let atMyBall = app.buttons["At my ball"]
            XCTAssertTrue(atMyBall.waitForExistence(timeout: 5), "At my ball button should exist")
            atMyBall.tap()

            sleep(2)

            if index > 0 {
                let expectedStrokes = "Strokes: \(index)"
                let strokesLabel = app.staticTexts[expectedStrokes]
                XCTAssertTrue(strokesLabel.waitForExistence(timeout: 5),
                              "Expected \(expectedStrokes) after mark \(index) on hole 2")
            }
        }

        // ── Navigate back to Hole 1 to verify data ──
        let prevHoleButton = app.buttons["Prev Hole"]
        XCTAssertTrue(prevHoleButton.waitForExistence(timeout: 5), "Prev Hole button should exist")
        prevHoleButton.tap()
        sleep(1)

        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Should be back on Hole 1")
        let strokes2 = app.staticTexts["Strokes: 2"]
        XCTAssertTrue(strokes2.waitForExistence(timeout: 5), "Hole 1 should still show 2 strokes")

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
