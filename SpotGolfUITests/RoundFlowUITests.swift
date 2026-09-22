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

        // ── Start a new round (skip course selection) ──
        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5), "New Round button should exist")
        newRoundButton.tap()

        // CourseSelectionView should appear — tap Skip
        let skipButton = app.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Skip button should exist")
        skipButton.tap()

        // Should navigate directly to RoundMapView with hole 1 current in the header
        XCTAssertTrue(app.waitForCurrentHole(1), "Hole 1 should be the current hole")

        // Without a course the header lists 18 holes
        XCTAssertTrue(app.holeButton(18).exists, "Header should list 18 holes without a course")

        // No course data — no par and distance line, and no key information boxes
        XCTAssertFalse(app.staticTexts["HoleSummary"].exists, "Par and distance should not appear without course data")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "DistanceToCenter").firstMatch.exists,
                       "Distance box should not appear without course data")

        var currentHole = 1

        // ── Process locations per hole ──
        for (index, location) in locations.enumerated() {
            let targetHole = location.hole

            if currentHole != targetHole {
                app.goToHole(targetHole)
                currentHole = targetHole
            }

            XCTAssertTrue(app.holeButton(targetHole).isSelected, "Should be on Hole \(targetHole) for location \(index)")

            LocationTestHelper.setSimulatorLocation(latitude: location.latitude,
                                                    longitude: location.longitude)
            sleep(2)
        }

        // ── Navigate back to Hole 1 ──
        app.goToHole(1)

        // ── End the round ──
        app.buttons["Back"].tap()
        sleep(1)

        let endRoundButton = app.buttons["End Round"]
        XCTAssertTrue(endRoundButton.waitForExistence(timeout: 5), "End Round button should exist")
        endRoundButton.tap()

        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5),
                      "New Round button should reappear after ending round")
    }

    // MARK: - Resume Round Hidden Without Course

    func testResumeRoundNotShownWithoutCourse() throws {
        app.launch()
        dismissLocationAlert()

        // Start round without course (skip)
        let newRoundButton = app.buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5))
        newRoundButton.tap()

        let skipButton = app.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        XCTAssertTrue(app.waitForCurrentHole(1))

        // Manually navigate to Hole 2 (would normally pause auto-advance)
        app.goToHole(2)

        // Resume round button should NOT appear since there is no course
        XCTAssertFalse(app.buttons["Resume round"].exists,
                       "Resume round should not appear without a course selected")
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
