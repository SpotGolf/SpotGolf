import XCTest

/// The active round's own log, opened from the map or from its row in the round list.
extension InRoundUITests {
    /// Checks the open Round Log sheet lists the round's start, and closes it.
    private func assertRoundLogShowsTheStart(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars["Round Log"].waitToExist(), "The round's log should open", file: file, line: line)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'starting'")).firstMatch.waitToExist(),
                      "The round's start should be in its log", file: file, line: line)
        app.navigationBars["Round Log"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Round Log"].waitToVanish(), "The log sheet should close", file: file, line: line)
    }

    func testActiveRoundHasItsOwnLogFromTheMap() throws {
        let log = app.buttons["RoundLog"]
        XCTAssertTrue(log.waitToExist(), "The map should offer the round's log")
        log.tap()
        assertRoundLogShowsTheStart()
    }

    func testActiveRoundHasItsOwnLogFromTheList() throws {
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["End Round"].waitToExist(), "The round should be active")
        XCTAssertTrue(broadlandsRow.waitToExist(), "The active round should be listed")
        broadlandsRow.swipeRight()
        let log = app.buttons["Log"]
        XCTAssertTrue(log.waitToExist(), "The active round's row should offer its log")
        log.tap()
        assertRoundLogShowsTheStart()
        XCTAssertTrue(app.buttons["End Round"].exists, "The round should still be active")

        // Back to the round screen. A first tap closes the row's swipe actions, if they stayed open.
        if log.exists {
            broadlandsRow.tap()
        }
        broadlandsRow.tap()
        XCTAssertTrue(app.buttons["MapStyle"].waitToExist(), "The round should open again")
    }
}
