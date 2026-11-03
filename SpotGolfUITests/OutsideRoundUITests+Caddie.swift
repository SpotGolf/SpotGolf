import XCTest

/// The Caddie tab: how far the player hits each club in the bag.
extension OutsideRoundUITests {
    /// The standard bag, in bag order, without the putter.
    private static let caddieClubs = ["dr", "3w", "5w", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "pw", "sw", "lw"]

    func testCaddieShowsEachBagClubFromItsShotsOrItsBagDistance() throws {
        // A round of its own, with one 7 iron shot that counts: the hole's last stroke does not
        app.startRoundWithCourse()
        app.addStroke(at: XCUIApplication.strokePressPoints[0])
        saveInSheet(tapping: ["Club-7i"])
        addStroke(at: XCUIApplication.strokePressPoints[1])
        endRound()
        // The other tests expect the past round they make, not this one
        resetGroup()

        let caddie = app.buttons["Caddie"]
        XCTAssertTrue(caddie.waitToExist(), "The tab bar should have a Caddie button")
        caddie.tap()
        XCTAssertTrue(app.navigationBars["Caddie"].waitToExist(), "The Caddie should open")

        // Checked on the way down the list, since rows that scroll off may leave it
        for id in Self.caddieClubs {
            let row = element("Caddie-\(id)")
            scrollTo(row)
            if id == "7i" {
                XCTAssertTrue(row.label.hasSuffix("1 shot"), "The 7 iron's shot should count, not '\(row.label)'")
            } else if id == "lw" {
                XCTAssertTrue(row.label.hasPrefix("Lob Wedge, 75 yd, 66 to 81 yd"),
                              "A club with no shots starts at its bag distance, not '\(row.label)'")
                XCTAssertTrue(row.label.hasSuffix("No shots yet"))
            }
        }
        XCTAssertFalse(element("Caddie-pu").exists, "The putter is left out")

        showRounds()
    }
}
