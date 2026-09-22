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
        startRoundWithCourse()

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

    // MARK: - Resume Round Detects Nearest Hole

    func testResumeRoundDetectsHole() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        startRoundWithCourse()
        sleep(2)

        // Verify starting on Hole 1
        XCTAssertTrue(app.waitForCurrentHole(1))

        // Manually navigate to Hole 2 (pauses auto-advance)
        app.goToHole(2)

        // Resume round button should appear (since we manually navigated)
        let resumeButton = app.buttons["Resume round"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5), "Resume round button should appear")

        // Move location to Hole 1 tee area and resume
        setLocationToHole1Tee()
        sleep(2)

        resumeButton.tap()
        sleep(2)

        // Should detect we're near Hole 1 and switch back
        XCTAssertTrue(app.waitForCurrentHole(1), "Resume should detect Hole 1 from GPS location")

        // Resume button should be gone
        XCTAssertFalse(app.buttons["Resume round"].exists, "Resume button should disappear after resuming")
    }

    // MARK: - Resume Round Detects Hole 2 When Near Hole 2

    func testResumeRoundDetectsHole2() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        startRoundWithCourse()
        sleep(2)

        // Manually navigate to Hole 2, then back to Hole 1
        app.goToHole(2)
        app.goToHole(1)

        // Resume button should appear since we used manual navigation
        let resumeButton = app.buttons["Resume round"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5), "Resume round button should appear")

        // Move to Hole 2 tee area
        setLocationToHole2Tee()
        sleep(2)

        resumeButton.tap()
        sleep(2)

        // Should detect we're near Hole 2
        XCTAssertTrue(app.waitForCurrentHole(2), "Resume should detect Hole 2 from GPS location")
    }

    // MARK: - Header and Hazards Update on Hole Change

    func testHeaderAndHazardsUpdateOnHoleChange() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        startRoundWithCourse()
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

    // MARK: - Helpers

    private func startRoundWithCourse() {
        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5))
        newRoundButton.tap()

        // Select Broadlands
        let broadlands = app.staticTexts["Broadlands Golf Course"]
        XCTAssertTrue(broadlands.waitForExistence(timeout: 10))
        broadlands.tap()

        // Start Round with default sub-course selection
        let startButton = app.buttons["Start Round"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        // Wait for map to load
        XCTAssertTrue(app.waitForCurrentHole(1))
    }
}
