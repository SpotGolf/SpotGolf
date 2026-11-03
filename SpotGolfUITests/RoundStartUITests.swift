import XCTest

/// Starting a round from the + tab: picking the course, nines and tee, leaving the questions,
/// and a round from start to end. Each test starts on the round list with no round, and ends any
/// round it starts.
final class RoundStartUITests: UITestGroup {
    /// On the round list, with no active round.
    override func isAtGroupStart() -> Bool {
        app.navigationBars["Rounds"].exists && app.buttons["New Round"].exists && !app.buttons["End Round"].exists
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

        // The round starts on the Rounds tab, and + opens its map
        app.buttons["Back"].tap()
        XCTAssertTrue(app.navigationBars["Rounds"].waitToExist(), "Back from the map should show the round list")
        XCTAssertTrue(app.staticTexts["Active"].exists, "The round should be at the top of the list")
        let currentRound = app.buttons["Current Round"]
        XCTAssertTrue(currentRound.exists, "+ should be for the round in progress")
        currentRound.tap()
        XCTAssertTrue(app.waitForShownHole(1), "+ should open the round's map")

        endRound()
    }

    func testAnotherTabLeavesTheNewRoundQuestions() throws {
        app.buttons["New Round"].tap()
        XCTAssertTrue(app.navigationBars["Select Course"].waitToExist(), "The new round questions should show")
        XCTAssertTrue(app.buttons["New Round"].isSelected, "+ should be the active tab")
        XCTAssertFalse(app.buttons["Cancel"].exists, "Another tab leaves, so there is no Cancel")

        showRounds()
        XCTAssertFalse(app.staticTexts["Active"].exists, "No round should start")
    }

    func testTheSearchFieldSitsAboveTheTabButtons() throws {
        let rounds = app.buttons["Rounds"]
        let buttons = rounds.frame
        app.buttons["New Round"].tap()
        XCTAssertTrue(app.navigationBars["Select Course"].waitToExist(), "The new round questions should show")
        let search = app.textFields["CourseSearch"]
        XCTAssertTrue(search.waitToExist(), "The search field should be in the tab bar")
        XCTAssertEqual(rounds.frame, buttons, "The tab buttons should not move")
        XCTAssertLessThanOrEqual(search.frame.maxY, rounds.frame.minY, "The search field should be above the tab buttons")

        search.tap()
        search.typeText("Broadlands")
        XCTAssertTrue(app.staticTexts["Search Results"].waitToExist(), "Typing should search the courses")
        XCTAssertTrue(app.staticTexts["Broadlands Golf Course"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(rounds.waitToExist(), "The tab buttons should show again when the keyboard goes away")
        XCTAssertEqual(rounds.frame, buttons, "The tab buttons should be where they were")
        XCTAssertEqual(search.value as? String, "Search courses", "Cancel should empty the search")

        showRounds()
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
