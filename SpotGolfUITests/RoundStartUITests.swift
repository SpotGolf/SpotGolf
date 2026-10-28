import XCTest

/// Starting a round: picking the course, nines and tee, cancelling, and a round from start to end.
/// Each test starts on the round list with no round, and ends any round it starts.
final class RoundStartUITests: UITestGroup {
    /// On the round list, with no active round.
    override func isAtGroupStart() -> Bool {
        app.buttons["New Round"].exists && !app.buttons["End Round"].exists
    }

    func testSelectCourseAndStartRound() throws {
        app.buttons["New Round"].tap()

        // CourseSelectionView should appear with Broadlands in the list
        let broadlands = app.staticTexts["Broadlands Golf Course"]
        XCTAssertTrue(broadlands.waitToExist(timeout: UIWait.slow), "Broadlands should appear in nearby courses")
        broadlands.tap()

        // Sub-course selection should appear since Broadlands has Front and Back
        XCTAssertTrue(app.navigationBars["Select Nines"].waitToExist(), "Sub-course selection should appear")
        XCTAssertTrue(app.staticTexts["Front"].waitToExist(), "Front nine should be listed")
        XCTAssertTrue(app.staticTexts["Back"].exists, "Back nine should be listed")
        app.buttons["Next"].tap()

        // Then the tee, which starts the round
        XCTAssertTrue(app.navigationBars["Select Tee"].waitToExist(), "Tee selection should appear")
        let tee = app.buttons["Tee-Gold"]
        XCTAssertTrue(tee.waitToExist(), "The Gold tee should be listed")
        tee.tap()

        // Should navigate directly to the map view
        XCTAssertTrue(app.waitForShownHole(1), "Should navigate to map showing Hole 1")

        // Front and Back are both selected by default, so the header lists 18 holes
        XCTAssertTrue(app.holeButton(18).exists, "Header should list all 18 holes")
        XCTAssertFalse(app.holeButton(19).exists, "Header should stop at hole 18")

        endRound()
    }

    func testCancelCourseSelection() throws {
        let newRoundButton = app.buttons["New Round"]
        newRoundButton.tap()

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitToExist(), "Cancel button should exist")
        cancelButton.tap()

        // Should return to list without starting a round
        XCTAssertTrue(newRoundButton.waitToExist(), "Should be back on list")
        XCTAssertFalse(app.staticTexts["Active"].exists, "No active round should exist")
    }

    func testFullRoundFlow() throws {
        let locations = LocationTestHelper.loadTestLocations()
        XCTAssertGreaterThanOrEqual(locations.count, 2, "Need at least 2 test locations")

        app.startRoundWithCourse()
        XCTAssertTrue(app.holeButton(18).exists, "Header should list 18 holes")

        var currentHole = 1
        for (index, location) in locations.enumerated() {
            if currentHole != location.hole {
                app.goToHole(location.hole)
                currentHole = location.hole
            }
            XCTAssertTrue(app.holeButton(location.hole).isSelected, "Should be on Hole \(location.hole) for location \(index)")
            LocationTestHelper.setSimulatorLocation(latitude: location.latitude, longitude: location.longitude)
        }

        app.goToHole(1)
        endRound()
    }
}
