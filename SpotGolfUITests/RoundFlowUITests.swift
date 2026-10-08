import XCTest

@MainActor
final class RoundFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
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

    // MARK: - Full Round

    func testFullRoundFlow() throws {
        // Broadlands only shows in the course list when the simulator is near it
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()

        let locations = LocationTestHelper.loadTestLocations()
        XCTAssertGreaterThanOrEqual(locations.count, 2, "Need at least 2 test locations")

        // ── Start a new round ──
        app.startRoundWithCourse()

        // Front and Back are both selected by default, so the header lists 18 holes
        XCTAssertTrue(app.holeButton(18).exists, "Header should list 18 holes")

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

        XCTAssertTrue(app.buttons["New Round"].waitForExistence(timeout: 5),
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
