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

        // Verify Hole 1 is displayed
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Hole 1 label should be visible")

        // ── Hole 1: Mark first 3 locations ──
        for (index, location) in locations.prefix(3).enumerated() {
            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            sleep(2)

            let atMyBall = app.buttons["At my ball"]
            XCTAssertTrue(atMyBall.waitForExistence(timeout: 10), "At my ball button should exist")
            atMyBall.tap()

            // Wait for "Swing away" to dismiss (~5s) — "At my ball" reappears.
            let atMyBallAgain = app.buttons["At my ball"]
            XCTAssertTrue(atMyBallAgain.waitForExistence(timeout: 15),
                          "At my ball should reappear after Swing away clears")

            if index > 0 {
                let expectedStrokes = "Strokes: \(index)"
                let strokesLabel = app.staticTexts[expectedStrokes]
                XCTAssertTrue(strokesLabel.waitForExistence(timeout: 5),
                              "Expected \(expectedStrokes) after mark \(index)")
            }
        }

        // ── Navigate to Hole 2 ──
        let nextButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Forward'")).firstMatch
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Next hole button should exist")
        nextButton.tap()
        sleep(1)

        let hole2Label = app.staticTexts["Hole 2"]
        XCTAssertTrue(hole2Label.waitForExistence(timeout: 5), "Hole 2 label should appear")

        // Strokes should reset to 0 on new hole
        let strokesZero = app.staticTexts["Strokes: 0"]
        XCTAssertTrue(strokesZero.waitForExistence(timeout: 5), "Strokes should reset to 0 on new hole")

        // ── Hole 2: Mark remaining 3 locations ──
        for (index, location) in locations.suffix(3).enumerated() {
            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            sleep(2)

            let atMyBall = app.buttons["At my ball"]
            XCTAssertTrue(atMyBall.waitForExistence(timeout: 10), "At my ball button should exist")
            atMyBall.tap()

            let atMyBallAgain = app.buttons["At my ball"]
            XCTAssertTrue(atMyBallAgain.waitForExistence(timeout: 15),
                          "At my ball should reappear after Swing away clears")

            if index > 0 {
                let expectedStrokes = "Strokes: \(index)"
                let strokesLabel = app.staticTexts[expectedStrokes]
                XCTAssertTrue(strokesLabel.waitForExistence(timeout: 5),
                              "Expected \(expectedStrokes) after mark \(index) on hole 2")
            }
        }

        // ── Navigate back to Hole 1 ──
        let prevButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Back'")).firstMatch
        XCTAssertTrue(prevButton.waitForExistence(timeout: 5), "Prev hole button should exist")
        prevButton.tap()
        sleep(1)

        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Should be back on Hole 1")

        // ── End the round (swipe left to second page) ──
        app.swipeLeft()
        let endRoundButton = app.buttons["End Round"]
        XCTAssertTrue(endRoundButton.waitForExistence(timeout: 5), "End Round button should exist on second page")
        endRoundButton.tap()

        // Verify we're back to the idle state.
        XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                      "Start Round button should reappear after ending round")
    }
}
