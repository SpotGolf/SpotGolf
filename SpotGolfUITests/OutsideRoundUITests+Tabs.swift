import XCTest

/// The tab bar at the bottom of the home screen.
extension OutsideRoundUITests {
    func testEachTabShowsItsScreen() throws {
        XCTAssertTrue(app.buttons["Rounds"].isSelected, "The app starts on the Rounds tab")

        for (tab, title) in [("Caddie", "Caddie"), ("New Round", "Select Course"),
                             ("Putt Data Sharing", "Putt Data Sharing"), ("Settings", "Settings"), ("Rounds", "Rounds")] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitToExist(), "The tab bar should have \(tab)")
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitToExist(), "\(tab) should show \(title)")
            XCTAssertTrue(button.isSelected, "\(tab) should be the active tab")
        }
    }

    func testTheBarStaysPutWhileTheScreenScrolls() throws {
        openSettings()
        let bar = app.buttons["Rounds"].frame
        let firstRow = element("GreenZone")
        XCTAssertTrue(firstRow.waitToExist())
        let rowBefore = firstRow.frame

        app.swipeUp()

        XCTAssertTrue(!firstRow.exists || firstRow.frame != rowBefore, "Settings should scroll")
        XCTAssertEqual(app.buttons["Rounds"].frame, bar, "The tab bar should not move")
        showRounds()
    }
}
