import XCTest

final class CourseFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

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

    /// Sets the simulator location to the Hole 1 tee box area at Broadlands.
    private func setLocationToHole1Tee() {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
    }

    /// Sets the simulator location to the Hole 2 tee box area at Broadlands.
    private func setLocationToHole2Tee() {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95501, longitude: -105.04718)
    }

    // MARK: - Course Selection Flow

    func testSelectCourseAndStartRound() throws {
        // Set location near Broadlands so it shows in nearby list
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5))
        newRoundButton.tap()

        // CourseSelectionView should appear with Broadlands in the list
        let broadlands = app.staticTexts["Broadlands Golf Course"]
        XCTAssertTrue(broadlands.waitForExistence(timeout: 10), "Broadlands should appear in nearby courses")

        // Tap to select the course
        broadlands.tap()

        // Sub-course selection should appear since Broadlands has Front and Back
        let selectNinesTitle = app.navigationBars["Select Nines"]
        XCTAssertTrue(selectNinesTitle.waitForExistence(timeout: 5), "Sub-course selection should appear")

        // Front and Back should be listed
        let frontText = app.staticTexts["Front"]
        let backText = app.staticTexts["Back"]
        XCTAssertTrue(frontText.waitForExistence(timeout: 5), "Front nine should be listed")
        XCTAssertTrue(backText.waitForExistence(timeout: 5), "Back nine should be listed")

        // Tap Start Round
        let startButton = app.buttons["Start Round"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        // Should navigate directly to the map view
        XCTAssertTrue(app.waitForCurrentHole(1), "Should navigate to map showing Hole 1")

        // Front and Back are both selected by default, so the header lists 18 holes
        XCTAssertTrue(app.holeButton(18).exists, "Header should list all 18 holes")
        XCTAssertFalse(app.holeButton(19).exists, "Header should stop at hole 18")
    }

    // MARK: - Header and Key Information with Course Data

    func testHeaderAndKeyInformationShowCourseData() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        // Start round with course
        app.startRoundWithCourse()

        // Wait for location to register
        sleep(3)

        // Under the hole circles: par, then yards to the center of the green
        let summary = app.staticTexts["HoleSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "Par and distance should appear under the hole circles")
        XCTAssertNotNil(summary.label.range(of: #"^Par 4 - \d+ yds$"#, options: .regularExpression),
                        "Header line was '\(summary.label)'")

        // Key information boxes on the right of the map
        let distance = app.descendants(matching: .any).matching(identifier: "DistanceToCenter").firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout: 5), "Distance to center box should exist")
        XCTAssertNotNil(distance.label.range(of: #"^\d+"#, options: .regularExpression),
                        "Distance box was '\(distance.label)'")

        let elevation = app.descendants(matching: .any).matching(identifier: "ElevationChange").firstMatch
        XCTAssertTrue(elevation.exists, "Elevation change box should exist")
    }

    // MARK: - Selecting a Hole Keeps the Current Hole

    func testSelectingHoleKeepsCurrentHoleAndPausesAutoAdvance() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        app.startRoundWithCourse()
        sleep(2)
        XCTAssertTrue(app.waitForCurrentHole(1))

        // Look at Hole 3 while the round is on Hole 1
        app.goToHole(3)
        XCTAssertEqual(app.holeButton(1).value as? String, "Current hole", "Selecting a hole should not change the current hole")
        XCTAssertTrue(app.buttons["Resume round"].waitForExistence(timeout: 5), "Resume round button should appear")
        XCTAssertTrue(app.buttons["Play hole"].exists, "Play hole button should appear")

        // Standing on the Hole 2 tee would normally move the round to Hole 2
        setLocationToHole2Tee()
        sleep(3)

        XCTAssertTrue(app.waitForCurrentHole(3), "Hole 3 should stay shown while automatic hole changes are paused")
        XCTAssertEqual(app.holeButton(1).value as? String, "Current hole", "Automatic hole changes should be paused")
    }

    // MARK: - Resume Round Returns to the Current Hole

    func testResumeRoundReturnsToCurrentHole() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        app.startRoundWithCourse()
        sleep(2)

        app.goToHole(3)
        let resumeButton = app.buttons["Resume round"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5), "Resume round button should appear")

        resumeButton.tap()

        XCTAssertTrue(app.waitForCurrentHole(1), "Resume round should show the current hole")
        XCTAssertFalse(app.buttons["Resume round"].exists, "Resume round button should disappear")
        XCTAssertFalse(app.buttons["Play hole"].exists, "Play hole button should disappear")

        // Automatic hole changes are back on
        setLocationToHole2Tee()
        XCTAssertTrue(app.waitForCurrentHole(2, timeout: 10), "Automatic hole changes should resume")
    }

    // MARK: - Play This Hole Changes the Current Hole

    func testPlayThisHoleChangesCurrentHole() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        app.startRoundWithCourse()
        sleep(2)

        app.goToHole(3)
        let playButton = app.buttons["Play hole"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5), "Play hole button should appear")

        playButton.tap()
        sleep(1)

        XCTAssertTrue(app.waitForCurrentHole(3), "Hole 3 should stay shown")
        XCTAssertEqual(app.holeButton(3).value as? String, "Current hole", "Play hole should make Hole 3 the current hole")
        XCTAssertFalse(app.buttons["Play hole"].exists, "Play hole button should disappear")
        XCTAssertFalse(app.buttons["Resume round"].exists, "Resume round button should disappear")
    }

    // MARK: - Earlier Holes Can't Be Played Again

    func testPlayThisHoleIsNotOfferedForEarlierHole() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        app.startRoundWithCourse()
        sleep(2)

        app.goToHole(3)
        app.buttons["Play hole"].tap()
        XCTAssertEqual(app.holeButton(3).value as? String, "Current hole")

        // Golf is played in order, so hole 1 can be viewed but not played again
        app.goToHole(1)
        XCTAssertTrue(app.buttons["Resume round"].waitForExistence(timeout: 5), "Resume round button should appear")
        XCTAssertFalse(app.buttons["Play hole"].exists, "Play hole should not be offered for an earlier hole")
        XCTAssertEqual(app.holeButton(3).value as? String, "Current hole", "Viewing hole 1 should not change the current hole")
    }

    // MARK: - Header and Hazards Update on Hole Change

    func testHeaderAndHazardsUpdateOnHoleChange() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        app.startRoundWithCourse()
        sleep(3)

        // Should show Par 4 for hole 1
        let summary = app.staticTexts["HoleSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Par and distance should appear for hole 1")
        XCTAssertTrue(summary.label.hasPrefix("Par 4"), "Header line was '\(summary.label)'")
        let hole1Summary = summary.label

        // Navigate to hole 2 first (pauses auto-advance), then move location
        app.goToHole(2)

        // Move location to hole 2 tee so distances update
        setLocationToHole2Tee()
        sleep(3)

        // Hole 2 is also par 4 in test data, but its green is a different distance away
        XCTAssertTrue(summary.label.hasPrefix("Par 4"), "Header line was '\(summary.label)'")
        XCTAssertNotEqual(summary.label, hole1Summary, "Distance should change on hole 2")

        // Hole 2 has bunkers between the tee and the green: each gets a yardage bubble on the map
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Hazard in '")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "Hazard bubbles should appear for hole 2")
    }
}
