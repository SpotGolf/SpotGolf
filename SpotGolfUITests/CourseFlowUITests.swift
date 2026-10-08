import XCTest

@MainActor
final class CourseFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
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
        XCTAssertTrue(app.waitForShownHole(1), "Should navigate to map showing Hole 1")

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

    // MARK: - Selecting a Hole Shows It

    func testSelectingHoleShowsItWithNothingToConfirm() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        app.startRoundWithCourse()
        sleep(2)
        XCTAssertTrue(app.waitForShownHole(1))

        // Any hole can be shown, forward or back, with nothing to confirm or go back to
        app.goToHole(3)
        XCTAssertFalse(app.buttons["Resume round"].exists, "There is no round position to go back to")
        XCTAssertFalse(app.buttons["Play hole"].exists, "Showing a hole is all there is to do")

        app.goToHole(1)
        XCTAssertTrue(app.waitForShownHole(1), "An earlier hole can be shown again")
    }

    // MARK: - The Phone's Location Never Changes the Hole

    func testPhoneLocationDoesNotChangeHole() throws {
        setLocationToHole1Tee()
        app.launch()
        dismissLocationAlert()

        app.startRoundWithCourse()
        sleep(2)
        XCTAssertTrue(app.waitForShownHole(1))

        // Only the watch's GPS changes the hole
        setLocationToHole2Tee()
        sleep(3)

        XCTAssertTrue(app.waitForShownHole(1), "Hole 1 should stay shown")
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

        // Show hole 2, then move the location there
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
