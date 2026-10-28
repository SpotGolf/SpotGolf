import XCTest

/// Putt Data Sharing, opened from the round list.
extension OutsideRoundUITests {
    func testConsentOpensTheSetup() throws {
        let open = app.buttons["Putt Data Sharing"]
        XCTAssertTrue(open.waitToExist(), "The round list should have a Putt Data Sharing button")
        open.tap()
        XCTAssertTrue(app.navigationBars["Putt Data Sharing"].waitToExist())
        XCTAssertTrue(app.staticTexts["Start on your watch, on the Putting Drills page. Read the instructions for each task on your watch, do the task, then tap Done."].exists,
                      "The phone says the instructions are on the watch")

        let agree = app.buttons["PuttSharingAgree"]
        XCTAssertTrue(agree.exists)
        let cellular = app.switches["PuttSharingCellular"]
        for _ in 0..<6 where !cellular.exists { app.swipeUp() }
        XCTAssertFalse(cellular.isEnabled, "Nothing is set up before consent")
        for _ in 0..<6 where !agree.isHittable { app.swipeDown() }
        agree.tap()
        XCTAssertTrue(app.descendants(matching: .any)["PuttSharingAgreed"].waitToExist())
        for _ in 0..<6 where !cellular.isHittable { app.swipeUp() }
        XCTAssertTrue(cellular.isEnabled)
        XCTAssertTrue(app.staticTexts["No sessions yet"].exists)
        app.navigationBars["Putt Data Sharing"].buttons["Done"].tap()
        XCTAssertTrue(open.waitToExist(), "Done should close Putt Data Sharing")
    }
}
