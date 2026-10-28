import XCTest

/// The golf bag and club distances in Settings.
extension OutsideRoundUITests {
    /// Opens the golf bag from Settings.
    private func openGolfBag() -> XCUIElement {
        openSettings()
        let openBag = app.buttons["OpenGolfBag"]
        XCTAssertTrue(openBag.waitToExist(), "Settings should have a Golf Bag link")
        return openBag
    }

    /// Closes Settings, back on the round list.
    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitToExist(), "Settings should close")
    }

    func testBagStartsStandardAndHoldsFourteen() throws {
        let openBag = openGolfBag()
        XCTAssertTrue(openBag.label.contains("14 clubs"), "Settings should show the club count, not '\(openBag.label)'")
        openBag.tap()
        XCTAssertTrue(app.navigationBars["Golf Bag"].waitToExist(), "The bag should open")

        let count = app.staticTexts["BagCount"]
        XCTAssertEqual(count.label, "14 of 14 clubs")
        let driver = app.buttons["Club-dr"]
        let fiveWood = app.buttons["Club-5w"]
        let twoWood = app.buttons["Club-2w"]
        XCTAssertTrue(driver.isSelected, "The driver is in the standard bag")
        XCTAssertFalse(twoWood.isSelected, "The 2 wood is not in the standard bag")
        XCTAssertFalse(twoWood.isEnabled, "A full bag takes no more clubs")

        fiveWood.tap()
        XCTAssertFalse(fiveWood.isSelected, "Tapping a club in the bag takes it out")
        XCTAssertEqual(count.label, "13 of 14 clubs")
        XCTAssertTrue(twoWood.isEnabled, "A bag with room takes a club")
        twoWood.tap()
        XCTAssertTrue(twoWood.isSelected, "Tapping a club out of the bag adds it")
        XCTAssertEqual(count.label, "14 of 14 clubs")

        app.navigationBars["Golf Bag"].buttons.firstMatch.tap()
        XCTAssertTrue(openBag.waitToExist(), "Settings should show again")
        XCTAssertTrue(openBag.label.contains("14 clubs"), "Settings should show the new count, not '\(openBag.label)'")
        closeSettings()
    }

    func testEditDistance() throws {
        openGolfBag().tap()
        let editDistances = app.buttons["EditDistances"]
        XCTAssertTrue(editDistances.waitToExist(), "The bag should have a Distances button")
        editDistances.tap()
        XCTAssertTrue(app.navigationBars["Club Distances"].waitToExist(), "The distances should open")

        let driver = app.textFields["Distance-dr"]
        XCTAssertEqual(driver.value as? String, "230", "The driver starts at its default")
        XCTAssertFalse(app.textFields["Distance-pu"].exists, "The putter has no distance")

        // The field empties on focus, so typing replaces the distance
        driver.tap()
        driver.typeText("245")
        XCTAssertEqual(driver.value as? String, "245")
        app.navigationBars["Club Distances"].buttons["Done"].tap()
        app.navigationBars["Club Distances"].buttons.firstMatch.tap()
        XCTAssertTrue(editDistances.waitToExist(), "The bag should show again")
        editDistances.tap()
        XCTAssertTrue(app.textFields["Distance-dr"].waitToExist())
        XCTAssertEqual(app.textFields["Distance-dr"].value as? String, "245", "The new distance should be saved")

        app.navigationBars["Club Distances"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Golf Bag"].waitToExist())
        app.navigationBars["Golf Bag"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitToExist())
        closeSettings()
    }
}
