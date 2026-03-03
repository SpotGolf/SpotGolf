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

        // Group locations by hole number, preserving order
        let holeNumbers = locations.map(\.hole)
        let uniqueHoles = holeNumbers.reduce(into: [Int]()) { result, hole in
            if result.last != hole { result.append(hole) }
        }

        // ── Start a new round ──
        let startButton = app.buttons["Start Round"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Round button should exist")
        startButton.tap()

        // Verify Hole 1 is displayed
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Hole 1 label should be visible")

        var currentHole = 1
        let nextButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next'")).firstMatch
        let prevButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Prev'")).firstMatch

        // ── Mark locations per hole ──
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
                let strokesZero = app.staticTexts["Strokes: 0"]
                XCTAssertTrue(strokesZero.waitForExistence(timeout: 5),
                              "Strokes should reset to 0 on new hole \(currentHole)")
            }

            // Verify we're on the expected hole
            let holeLabel = app.staticTexts["Hole \(targetHole)"]
            XCTAssertTrue(holeLabel.exists, "Should be on Hole \(targetHole) for location \(index)")

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
        }

        // ── Verify stroke counts per hole ──
        // Navigate back to hole 1
        while currentHole > 1 {
            XCTAssertTrue(prevButton.waitForExistence(timeout: 5), "Prev hole button should exist")
            prevButton.tap()
            currentHole -= 1
            sleep(1)
        }

        for hole in uniqueHoles {
            let holeLabel = app.staticTexts["Hole \(hole)"]
            XCTAssertTrue(holeLabel.waitForExistence(timeout: 5), "Hole \(hole) label should be visible")

            let markCount = locations.filter { $0.hole == hole }.count
            let expectedStrokes = max(markCount - 1, 0)
            let strokesLabel = app.staticTexts["Strokes: \(expectedStrokes)"]
            XCTAssertTrue(strokesLabel.waitForExistence(timeout: 5),
                          "Hole \(hole) should show Strokes: \(expectedStrokes)")

            // Navigate to next hole for verification (unless it's the last)
            if hole != uniqueHoles.last {
                nextButton.tap()
                currentHole += 1
                sleep(1)
            }
        }

        // ── Navigate back to Hole 1 ──
        while currentHole > 1 {
            prevButton.tap()
            currentHole -= 1
            sleep(1)
        }
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
