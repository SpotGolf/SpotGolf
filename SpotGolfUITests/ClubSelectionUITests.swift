import XCTest

/// The club picked for a spot in the Edit Spot sheet.
@MainActor
final class ClubSelectionUITests: XCTestCase {

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

    private var selectedClubs: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'Club-' AND selected == true"))
    }

    func testNewSpotHasAGuessedClubThatCanBeChangedAndKept() throws {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        // A first launch after an install takes longer to show the round list
        XCTAssertTrue(app.buttons["New Round"].waitForExistence(timeout: 20), "The round list should show")
        app.startRoundWithCourse()

        app.addStroke(at: XCUIApplication.strokePressPoints[0])
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5), "The edit sheet should open for the new spot")
        XCTAssertTrue(app.buttons["Club-pu"].waitForExistence(timeout: 5), "The bag's clubs should be listed")
        XCTAssertEqual(selectedClubs.count, 1, "One club should be guessed")

        let sevenIron = app.buttons["Club-7i"]
        sevenIron.tap()
        XCTAssertTrue(sevenIron.isSelected, "Tapping a club should select it")
        XCTAssertTrue(app.navigationBars["Edit Spot"].exists, "Picking a club should not close the sheet")
        app.buttons["Save"].tap()

        let spot = app.buttons["Stroke_1"]
        XCTAssertTrue(spot.waitForExistence(timeout: 5))
        spot.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Club-7i"].isSelected, "Save should keep the club")

        app.buttons["Club-pw"].tap()
        let plus = app.buttons["PenaltyPlus"]
        let minus = app.buttons["PenaltyMinus"]
        let count = app.staticTexts["PenaltyStrokes"]
        XCTAssertEqual(count.value as? String, "0", "A new spot has no penalty strokes")
        XCTAssertFalse(minus.isEnabled, "Minus is disabled at 0")
        plus.tap()
        XCTAssertEqual(count.value as? String, "1", "Plus adds a penalty stroke")
        XCTAssertTrue(app.navigationBars["Edit Spot"].exists, "Counting a penalty stroke should not close the sheet")
        plus.tap()
        plus.tap()
        plus.tap()
        XCTAssertEqual(count.value as? String, "4", "Plus counts up to 4")
        XCTAssertFalse(plus.isEnabled, "Plus is disabled at 4")
        minus.tap()
        minus.tap()
        minus.tap()
        XCTAssertEqual(count.value as? String, "1", "Minus removes a penalty stroke")

        let good = app.buttons["Quality-good"]
        let okay = app.buttons["Quality-okay"]
        XCTAssertTrue(good.isSelected, "A new spot is a good shot")
        okay.tap()
        XCTAssertTrue(okay.isSelected && !good.isSelected, "One quality is selected at a time")
        okay.tap()
        XCTAssertTrue(okay.isSelected, "Tapping the selected quality keeps it; a rating cannot be cleared")
        good.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForNonExistence(timeout: 5))
        spot.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Club-pw"].isSelected, "A penalty stroke keeps the club picked with it")
        XCTAssertEqual(app.staticTexts["PenaltyStrokes"].value as? String, "1", "Save should keep the penalty strokes")
        XCTAssertTrue(app.buttons["Quality-good"].isSelected, "Save should keep the shot quality")
        app.buttons["Cancel"].tap()
    }

}
