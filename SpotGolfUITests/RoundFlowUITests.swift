import XCTest

final class RoundFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    // MARK: - Helpers

    private func dismissLocationAlert() {
        addUIInterruptionMonitor(withDescription: "Location Permission") { alert in
            let allow = alert.buttons["Allow While Using App"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        app.tap()
    }

    // MARK: - Skip Course Selection (No Course)

    func testFullRoundFlowWithSkip() throws {
        app.launch()
        dismissLocationAlert()

        let locations = LocationTestHelper.loadTestLocations()
        XCTAssertGreaterThanOrEqual(locations.count, 2, "Need at least 2 test locations")

        // Group locations by hole number, preserving order
        let holeNumbers = locations.map(\.hole)
        let uniqueHoles = holeNumbers.reduce(into: [Int]()) { result, hole in
            if result.last != hole { result.append(hole) }
        }

        // ── Start a new round (skip course selection) ──
        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5), "New Round button should exist")
        newRoundButton.tap()

        // CourseSelectionView should appear — tap Skip
        let skipButton = app.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Skip button should exist")
        skipButton.tap()

        // Should navigate directly to RoundMapView
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Hole 1 label should be visible")

        // Verify information panel is visible with defaults
        let informationPanel = app.descendants(matching: .any).matching(identifier: "InformationPanel").firstMatch
        XCTAssertTrue(informationPanel.waitForExistence(timeout: 5), "Information panel should be visible")

        // Previous and Strokes should show in the detail grid
        XCTAssertTrue(app.staticTexts["Previous"].waitForExistence(timeout: 5), "Previous label should exist")
        XCTAssertTrue(app.staticTexts["Strokes"].waitForExistence(timeout: 5), "Strokes label should exist")

        // No course data — Par label should NOT appear
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Par'")).firstMatch.exists,
                       "Par should not appear without course data")

        var currentHole = 1

        // ── Mark locations per hole ──
        for (index, location) in locations.enumerated() {
            let targetHole = location.hole

            while currentHole < targetHole {
                let nextButton = app.buttons["Next"]
                XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "Next button should exist")
                nextButton.tap()
                currentHole += 1
                sleep(1)

                let holeLabel = app.staticTexts["Hole \(currentHole)"]
                XCTAssertTrue(holeLabel.waitForExistence(timeout: 5),
                              "Hole \(currentHole) label should appear after navigating")
            }

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
        while currentHole > 1 {
            let prevButton = app.buttons["Prev"]
            XCTAssertTrue(prevButton.waitForExistence(timeout: 5), "Prev button should exist")
            prevButton.tap()
            currentHole -= 1
            sleep(1)
        }

        for hole in uniqueHoles {
            let holeLabel = app.staticTexts["Hole \(hole)"]
            XCTAssertTrue(holeLabel.waitForExistence(timeout: 5), "Hole \(hole) label should be visible")

            let markCount = locations.filter { $0.hole == hole }.count
            let expectedStrokes = max(markCount - 1, 0)
            let strokesText = app.staticTexts["\(expectedStrokes)"]
            XCTAssertTrue(strokesText.waitForExistence(timeout: 5),
                          "Hole \(hole) should show stroke count \(expectedStrokes)")

            if hole != uniqueHoles.last {
                let nextButton = app.buttons["Next"]
                nextButton.tap()
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

        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5),
                      "New Round button should reappear after ending round")
    }

    // MARK: - Cancel Course Selection

    func testCancelCourseSelection() throws {
        app.launch()
        dismissLocationAlert()

        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5))
        newRoundButton.tap()

        // CourseSelectionView should appear
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Cancel button should exist")
        cancelButton.tap()

        // Should return to list without starting a round
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5), "Should be back on list")
        XCTAssertFalse(app.staticTexts["Active"].exists, "No active round should exist")
    }
}
