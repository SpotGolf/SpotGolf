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
        XCTAssertGreaterThanOrEqual(locations.count, 2, "Need at least 2 test locations")

        // Group locations by hole number, preserving order
        let holeNumbers = locations.map(\.hole)
        let uniqueHoles = holeNumbers.reduce(into: [Int]()) { result, hole in
            if result.last != hole { result.append(hole) }
        }

        // ── Start a new round ──
        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5), "New Round button should exist")
        newRoundButton.tap()

        // Tap the Active row to navigate into RoundMapView.
        let activeText = app.staticTexts["Active"]
        XCTAssertTrue(activeText.waitForExistence(timeout: 5), "Active round row should appear")
        activeText.tap()

        // Verify stats bar is visible immediately with defaults
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Hole 1 label should be visible immediately")
        let previousDefault = app.staticTexts["Previous: 0 yds"]
        XCTAssertTrue(previousDefault.waitForExistence(timeout: 5), "Previous should default to 0 yds")

        var currentHole = 1

        // ── Mark locations per hole ──
        for (index, location) in locations.enumerated() {
            let targetHole = location.hole

            // Navigate to the correct hole if needed
            while currentHole < targetHole {
                let nextHoleButton = app.buttons["Next Hole"]
                XCTAssertTrue(nextHoleButton.waitForExistence(timeout: 5), "Next Hole button should exist")
                nextHoleButton.tap()
                currentHole += 1
                sleep(1)

                let holeLabel = app.staticTexts["Hole \(currentHole)"]
                XCTAssertTrue(holeLabel.waitForExistence(timeout: 5),
                              "Hole \(currentHole) label should appear after navigating")
            }

            // Verify we're on the expected hole
            let holeLabel = app.staticTexts["Hole \(targetHole)"]
            XCTAssertTrue(holeLabel.exists, "Should be on Hole \(targetHole) for location \(index)")

            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            sleep(2)

            let atMyBall = app.buttons["At my ball"]
            XCTAssertTrue(atMyBall.waitForExistence(timeout: 5), "At my ball button should exist")
            atMyBall.tap()
            sleep(2)
        }

        // ── Verify stroke counts per hole ──
        // Navigate back to hole 1
        while currentHole > 1 {
            let prevHoleButton = app.buttons["Prev Hole"]
            XCTAssertTrue(prevHoleButton.waitForExistence(timeout: 5), "Prev Hole button should exist")
            prevHoleButton.tap()
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
                let nextHoleButton = app.buttons["Next Hole"]
                nextHoleButton.tap()
                currentHole += 1
                sleep(1)
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
