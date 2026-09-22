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
        XCTAssertGreaterThanOrEqual(locations.count, 2, "Need at least 2 test locations")

        // An alert left open by an earlier run outlives the app and would swallow the first tap
        dismissHealthAccessAlerts()

        // ── Start a new round ──
        let startButton = app.buttons["Start Round"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Round button should exist")
        startButton.tap()
        dismissHealthAccessAlerts()

        // Verify Hole 1 is displayed
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Hole 1 label should be visible")

        var currentHole = 1
        // The arrows on either side of the hole's name
        let nextButton = app.buttons["Next hole"]
        let prevButton = app.buttons["Previous hole"]
        XCTAssertFalse(prevButton.isEnabled, "There is no hole before Hole 1")

        // ── Process locations per hole ──
        for (index, location) in locations.enumerated() {
            let targetHole = location.hole

            // Navigate to the correct hole if needed
            while currentHole < targetHole {
                XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Next hole button should exist")
                nextButton.tap()
                currentHole += 1
                sleep(1)

                let holeLabel = app.staticTexts["Hole \(currentHole)"]
                XCTAssertTrue(holeLabel.waitForExistence(timeout: 5),
                              "Hole \(currentHole) label should appear after navigating")

                // Verify strokes reset on new hole
                XCTAssertTrue(app.staticTexts["Strokes"].waitForExistence(timeout: 5), "Strokes row should exist")
                XCTAssertTrue(app.staticTexts["0"].waitForExistence(timeout: 5),
                              "Strokes should reset to 0 on new hole \(currentHole)")
            }

            // Verify we're on the expected hole
            let holeLabel = app.staticTexts["Hole \(targetHole)"]
            XCTAssertTrue(holeLabel.exists, "Should be on Hole \(targetHole) for location \(index)")

            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            sleep(2)
        }

        // ── Navigate back to Hole 1 ──
        while currentHole > 1 {
            XCTAssertTrue(prevButton.waitForExistence(timeout: 5), "Prev hole button should exist")
            prevButton.tap()
            currentHole -= 1
            sleep(1)
        }
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Should be back on Hole 1")

        // ── End the round (swipe left to the last page) ──
        app.swipeLeft()
        let endRoundButton = app.buttons["End Round"]
        XCTAssertTrue(endRoundButton.waitForExistence(timeout: 5), "End Round button should exist on last page")
        endRoundButton.tap()

        // Verify we're back to the idle state.
        XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                      "Start Round button should reappear after ending round")
    }

    // MARK: - Helpers

    /// Closes the Health Access alerts the system shows when the workout session starts.
    /// They cover the whole screen and swallow taps. None appear once access has been decided.
    private func dismissHealthAccessAlerts() {
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let closeButton = carousel.buttons["Close"]
        while closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
            sleep(1)
        }
    }
}
