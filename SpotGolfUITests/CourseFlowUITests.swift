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
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Should navigate to map showing Hole 1")
    }

    // MARK: - Information Panel with Course Data

    func testInformationPanelShowsCourseData() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        // Start round with course
        startRoundWithCourse()

        // Wait for location to register and panel to update
        sleep(3)

        // Information panel should be visible
        let informationPanel = app.descendants(matching: .any).matching(identifier: "InformationPanel").firstMatch
        XCTAssertTrue(informationPanel.waitForExistence(timeout: 10), "Information panel should be visible")

        // Par should display for hole 1
        let parLabel = app.staticTexts["Par 4"]
        XCTAssertTrue(parLabel.waitForExistence(timeout: 5), "Par 4 should appear for hole 1")

        // Green distance labels should appear
        XCTAssertTrue(app.staticTexts["Front"].waitForExistence(timeout: 5), "Front distance label should exist")
        XCTAssertTrue(app.staticTexts["Mid"].waitForExistence(timeout: 5), "Mid distance label should exist")
        XCTAssertTrue(app.staticTexts["Back"].waitForExistence(timeout: 5), "Back distance label should exist")

        // Previous and Strokes should also be in the panel
        XCTAssertTrue(app.staticTexts["Previous"].waitForExistence(timeout: 5), "Previous label should exist")
        XCTAssertTrue(app.staticTexts["Strokes"].waitForExistence(timeout: 5), "Strokes label should exist")
    }

    // MARK: - Resume Round Detects Nearest Hole

    func testResumeRoundDetectsHole() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        startRoundWithCourse()
        sleep(2)

        // Verify starting on Hole 1
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5))

        // Manually navigate to Hole 2 (pauses auto-advance)
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        sleep(1)

        let hole2Label = app.staticTexts["Hole 2"]
        XCTAssertTrue(hole2Label.waitForExistence(timeout: 5), "Should be on Hole 2")

        // Resume round button should appear (since we manually navigated)
        let resumeButton = app.buttons["Resume round"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5), "Resume round button should appear")

        // Move location to Hole 1 tee area and resume
        setLocationToHole1Tee()
        sleep(2)

        resumeButton.tap()
        sleep(2)

        // Should detect we're near Hole 1 and switch back
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5),
                      "Resume should detect Hole 1 from GPS location")

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
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        sleep(1)

        let prevButton = app.buttons["Prev"]
        XCTAssertTrue(prevButton.waitForExistence(timeout: 5))
        prevButton.tap()
        sleep(1)

        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5), "Should be on Hole 1")

        // Resume button should appear since we used manual navigation
        let resumeButton = app.buttons["Resume round"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 5), "Resume round button should appear")

        // Move to Hole 2 tee area
        setLocationToHole2Tee()
        sleep(2)

        resumeButton.tap()
        sleep(2)

        // Should detect we're near Hole 2
        let hole2Label = app.staticTexts["Hole 2"]
        XCTAssertTrue(hole2Label.waitForExistence(timeout: 5),
                      "Resume should detect Hole 2 from GPS location")
    }

    // MARK: - Information Panel Updates on Hole Change

    func testInformationPanelUpdatesOnHoleChange() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        startRoundWithCourse()
        sleep(3)

        // Should show Par 4 for hole 1
        let par4 = app.staticTexts["Par 4"]
        XCTAssertTrue(par4.waitForExistence(timeout: 5), "Par 4 should appear for hole 1")

        // Navigate to hole 2 first (pauses auto-advance), then move location
        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        sleep(1)

        let hole2Label = app.staticTexts["Hole 2"]
        XCTAssertTrue(hole2Label.waitForExistence(timeout: 5), "Should be on Hole 2")

        // Move location to hole 2 tee so distances update
        setLocationToHole2Tee()
        sleep(3)

        // Par should still show (hole 2 is also par 4 in test data)
        XCTAssertTrue(par4.waitForExistence(timeout: 5), "Par 4 should appear for hole 2")

        // Bunker should appear for hole 2 (4 bunkers between tee and green)
        let bunkerLabel = app.staticTexts["Bunker"]
        XCTAssertTrue(bunkerLabel.waitForExistence(timeout: 5), "Bunker should appear for hole 2")
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
        let hole1Label = app.staticTexts["Hole 1"]
        XCTAssertTrue(hole1Label.waitForExistence(timeout: 5))
    }
}
