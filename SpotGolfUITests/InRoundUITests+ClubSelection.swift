import XCTest

/// The club, penalty strokes and shot quality in a spot's edit sheet.
extension InRoundUITests {
    private var selectedClubs: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'Club-' AND selected == true"))
    }

    func testNewSpotHasAGuessedClubThatCanBeChangedAndKept() throws {
        _ = freshHole()
        app.addStroke(at: XCUIApplication.strokePressPoints[0])
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(), "The edit sheet should open for the new spot")
        XCTAssertTrue(app.buttons["Club-pu"].waitToExist(), "The bag's clubs should be listed")
        XCTAssertEqual(selectedClubs.count, 1, "One club should be guessed")

        let sevenIron = app.buttons["Club-7i"]
        sevenIron.tap()
        XCTAssertTrue(sevenIron.isSelected, "Tapping a club should select it")
        XCTAssertTrue(app.navigationBars["Edit Spot"].exists, "Picking a club should not close the sheet")
        saveInSheet()

        openStroke(1)
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
        saveInSheet()

        openStroke(1)
        XCTAssertTrue(app.buttons["Club-pw"].isSelected, "A penalty stroke keeps the club picked with it")
        XCTAssertEqual(app.staticTexts["PenaltyStrokes"].value as? String, "1", "Save should keep the penalty strokes")
        XCTAssertTrue(app.buttons["Quality-good"].isSelected, "Save should keep the shot quality")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToVanish())
    }

    func testPutterSubtitleSaysChipOffTheGreenAndPuttOnIt() throws {
        _ = freshHole()
        app.addStroke(at: XCUIApplication.strokePressPoints[0])
        let bar = app.navigationBars["Edit Spot"]
        XCTAssertTrue(bar.waitToExist(), "The edit sheet should open for the new spot")
        let chip = bar.staticTexts["Off the green: counts as a chip"]
        let putt = bar.staticTexts["On the green: counts as a putt"]
        app.buttons["Club-7i"].tap()
        XCTAssertFalse(chip.exists || putt.exists, "Only the putter should have the subtitle")
        app.buttons["Club-pu"].tap()
        XCTAssertTrue(chip.waitToExist(), "Picking the putter off the green should say it counts as a chip")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(bar.waitToVanish())

        app.buttons["GreenView"].tap()
        let ground = element("GreenViewGround")
        XCTAssertTrue(ground.waitToExist(), "Green View should open")
        ground.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55)).press(forDuration: 0.6)
        XCTAssertTrue(bar.waitToExist(), "A long press should add a spot and open it")
        XCTAssertTrue(app.buttons["Club-pu"].isSelected, "The putter should be guessed on the green")
        XCTAssertTrue(putt.waitToExist(), "The putter on the green should say it counts as a putt")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(bar.waitToVanish())
    }
}
