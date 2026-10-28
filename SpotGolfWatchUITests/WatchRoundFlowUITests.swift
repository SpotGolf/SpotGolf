import XCTest

@MainActor
final class WatchRoundFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    func testFullRoundFlow() throws {
        app.launchArguments.append("--start-round")
        app.launch()

        let locations = LocationTestHelper.loadTestLocations()
        XCTAssertGreaterThanOrEqual(locations.count, 2, "Need at least 2 test locations")
 
        // An alert left open by an earlier run outlives the app and would swallow the first tap
        dismissHealthAccessAlerts()

        // Verify the round started on Hole 1
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitToExist(), "Hole 1 label should be visible")

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
                XCTAssertTrue(nextButton.waitToExist(), "Next hole button should exist")
                nextButton.tap()
                currentHole += 1

                let holeLabel = app.staticTexts["Hole \(currentHole)"]
                XCTAssertTrue(holeLabel.waitToExist(),
                              "Hole \(currentHole) label should appear after navigating")

                // Verify strokes reset on new hole
                XCTAssertTrue(app.staticTexts["Strokes"].waitToExist(), "Strokes row should exist")
                XCTAssertTrue(app.staticTexts["0"].waitToExist(),
                              "Strokes should reset to 0 on new hole \(currentHole)")
            }

            // Verify we're on the expected hole
            let holeLabel = app.staticTexts["Hole \(targetHole)"]
            XCTAssertTrue(holeLabel.exists, "Should be on Hole \(targetHole) for location \(index)")

            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
        }

        // ── Navigate back to Hole 1 ──
        while currentHole > 1 {
            XCTAssertTrue(prevButton.waitToExist(), "Prev hole button should exist")
            prevButton.tap()
            currentHole -= 1
            XCTAssertTrue(app.staticTexts["Hole \(currentHole)"].waitToExist(), "Hole \(currentHole) should be shown")
        }
        XCTAssertTrue(hole1Label.waitToExist(), "Should be back on Hole 1")

        // ── End the round (swipe left to the last page) ──
        endRound()
    }

    func testArrowsChangeTheHoleShownWithNothingToConfirm() throws {
        app.launchArguments.append("--start-round")
        app.launch()
        dismissHealthAccessAlerts()
        XCTAssertTrue(app.staticTexts["Hole 1"].waitToExist(), "Hole 1 label should be visible")

        // The arrow shows hole 2; there is nothing to confirm or go back to
        app.buttons["Next hole"].tap()
        XCTAssertTrue(app.staticTexts["Hole 2"].waitToExist(), "Hole 2 should be shown")
        XCTAssertFalse(app.buttons["Resume round"].exists, "There is no round position to go back to")
        XCTAssertFalse(app.buttons["Play this hole"].exists, "Showing a hole is all there is to do")

        // And back to hole 1
        app.buttons["Previous hole"].tap()
        XCTAssertTrue(app.staticTexts["Hole 1"].waitToExist(), "Hole 1 should be shown")
        XCTAssertFalse(app.buttons["Resume round"].exists, "There is no round position to go back to")

        // ── End the round so no workout is left running ──
        endRound()
    }

    func testWorkoutRecoveredAfterAppQuits() throws {
        // ── Start a round, which starts the workout ──
        app.launchArguments.append("--start-round")
        app.launch()
        dismissHealthAccessAlerts()

        let workoutStatus = app.staticTexts["workoutStatus"]
        XCTAssertTrue(workoutStatus.waitToExist(), "Workout status should be visible")
        // "recovered" means a workout left running by an earlier run was taken over
        XCTAssertTrue(waitForLabel(of: workoutStatus, in: ["started", "recovered"]),
                      "Workout should start with the round, but was \(workoutStatus.label)")

        // ── Quit mid-round, then relaunch ──
        app.terminate()
        app.launchArguments = ["--ui-testing", "--keep-rounds"]
        app.launch()

        // The round resumes and the running workout is taken over, not restarted
        XCTAssertTrue(app.staticTexts["Hole 1"].waitToExist(), "The round should resume on Hole 1")
        XCTAssertFalse(app.staticTexts["No active round"].exists, "The round should still be active")
        XCTAssertTrue(waitForLabel(of: workoutStatus, in: ["recovered"]),
                      "Workout should be recovered, but was \(workoutStatus.label)")

        // ── End the round so no workout is left running ──
        endRound()
    }

    func testDeveloperModePageShowsOnlyWithDeveloperModeOn() throws {
        // ── Developer Mode off, the default: the end page is the last ──
        app.launchArguments.append("--start-round")
        app.launch()
        dismissHealthAccessAlerts()
        XCTAssertTrue(app.staticTexts["Hole 1"].waitToExist(), "The round should start on Hole 1")
        app.swipeLeft()
        XCTAssertTrue(app.buttons["End Round"].waitToExist())
        app.swipeLeft()
        XCTAssertFalse(app.staticTexts["Developer Mode"].exists, "No Developer Mode page")
        endRound()
        app.terminate()

        // ── Developer Mode on, as the phone's last round setting left it ──
        app.launchArguments = ["--ui-testing", "--start-round", "-developerMode", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hole 1"].waitToExist(), "The round should start on Hole 1")
        XCTAssertFalse(app.staticTexts["Developer Mode"].exists, "The round opens on its info page")
        app.swipeLeft()
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Developer Mode"].waitToExist(), "The Developer Mode page is last")
        XCTAssertTrue(app.staticTexts["Waiting for a green"].exists)
        // Back to the info page, which `endRound` starts from
        app.swipeRight()
        app.swipeRight()
        endRound()
    }

    func testPuttingDrillsShowOneTaskAtATimeAndSendTheSession() throws {
        // ── Without consent from the phone, the page says where to give it ──
        app.launch()
        XCTAssertTrue(app.staticTexts["No active round"].waitToExist())
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Open Putt Data Sharing on your iPhone to start."].waitToExist())
        XCTAssertFalse(app.buttons["StartDrills"].exists)
        app.terminate()

        // ── With consent: the start page, then the paused screen before the first drill ──
        app.launchArguments = ["--ui-testing", "--drill-consent"]
        app.launch()
        XCTAssertTrue(app.staticTexts["No active round"].waitToExist())
        app.swipeLeft()
        let start = app.buttons["StartDrills"]
        XCTAssertTrue(start.waitToExist())
        start.tap()
        dismissHealthAccessAlerts()
        let ready = app.buttons["DrillReady"]
        XCTAssertTrue(ready.waitToExist(timeout: UIWait.slow), "The paused screen shows once the workout runs")
        XCTAssertTrue(app.staticTexts["Next: 3 foot putts"].exists)
        XCTAssertFalse(app.staticTexts["Collect your balls."].exists, "Nothing to collect before the first drill")

        // ── One task at a time: Done shows the next at once ──
        ready.tap()
        XCTAssertTrue(app.staticTexts["Hit a 3 foot putt, then tap Done."].waitToExist())
        XCTAssertTrue(app.staticTexts["Drill 1 · 1 of 5"].exists)
        app.buttons["DrillDone"].tap()
        let saved = app.descendants(matching: .any)["DrillSaved"]
        XCTAssertTrue(saved.waitToExist(), "Done shows Saved over the page")
        XCTAssertTrue(saved.waitToVanish(timeout: 4), "Saved goes away by itself")
        XCTAssertTrue(app.staticTexts["Drill 1 · 2 of 5"].waitToExist())

        // ── Skip and Stop are on the next page ──
        app.swipeLeft()
        let skip = app.buttons["SkipDrill"]
        XCTAssertTrue(skip.waitToExist())
        skip.tap()
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["Next: 10 foot putts with a practice stroke"].waitToExist())
        app.swipeLeft()
        app.buttons["StopDrills"].tap()

        // ── The session is packed and sent; the start page comes back ──
        XCTAssertTrue(app.staticTexts["Sent to your iPhone"].waitToExist(timeout: 30))
        // Quitting before the workout is saved makes the system relaunch the app to recover it
        app.swipeRight()
        let workoutStatus = app.staticTexts["workoutStatus"]
        XCTAssertTrue(workoutStatus.waitToExist())
        XCTAssertTrue(waitForLabel(of: workoutStatus, in: ["ended"]),
                      "The workout should be saved, but was \(workoutStatus.label)")
    }

    // MARK: - Helpers

    /// Ends the round from its last page and waits for the workout to be saved. Quitting
    /// before then makes the system relaunch the app, without the test's launch arguments,
    /// to recover the workout, and the next test finds that app instead of its own.
    private func endRound() {
        app.swipeLeft()
        let endRoundButton = app.buttons["End Round"]
        XCTAssertTrue(endRoundButton.waitToExist(), "End Round button should exist on last page")
        endRoundButton.tap()
        XCTAssertTrue(app.staticTexts["No active round"].waitToExist(),
                      "No active round should show after ending round")
        let workoutStatus = app.staticTexts["workoutStatus"]
        XCTAssertTrue(waitForLabel(of: workoutStatus, in: ["ended"]),
                      "The workout should be saved, but was \(workoutStatus.label)")
    }

    /// Waits for an element's label to become one of the expected texts.
    private func waitForLabel(of element: XCUIElement, in labels: [String], timeout: TimeInterval = 10) -> Bool {
        UIWait.until(timeout: timeout) { element.exists && labels.contains(element.label) }
    }

    /// Closes the Health Access alerts the system shows when the workout session starts.
    /// They cover the whole screen and swallow taps. None appear once access has been decided.
    private func dismissHealthAccessAlerts() {
        let carousel = XCUIApplication(bundleIdentifier: "com.apple.Carousel")
        let closeButton = carousel.buttons["Close"]
        while closeButton.waitToExist(timeout: 1) {
            closeButton.tap()
            _ = closeButton.waitToVanish()
        }
        // The Motion & Fitness prompt for swing detection
        for source in [app!, carousel] {
            for label in ["Allow", "OK"] where source.buttons[label].exists {
                source.buttons[label].tap()
                _ = source.buttons[label].waitToVanish()
            }
        }
    }
}
