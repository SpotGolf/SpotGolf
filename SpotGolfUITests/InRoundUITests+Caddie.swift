import XCTest

/// The dot menu's Caddie item, which shows the club and aim the Caddie picks with its shot
/// pattern. See plans/2026-11-02-caddie-club-and-aim.md, section 1, and
/// plans/2026-11-11-shot-dispersion.md, section 6.
extension InRoundUITests {
    /// Broadlands hole 1's tee box.
    private static let holeOneTee = (latitude: 39.95545, longitude: -105.04220)

    func testShowsAndHidesTheCaddieFromTheMenu() throws {
        // Holes 1 and 2 never get strokes, so this is a tee shot
        app.goToHole(1)
        moveTo(latitude: Self.holeOneTee.latitude, longitude: Self.holeOneTee.longitude)
        let aim = element("CaddieAim")
        XCTAssertTrue(app.buttons["MapMenu"].waitToExist())
        XCTAssertFalse(aim.exists, "No Caddie before it is picked")

        tapMapMenuItem("CaddieAdvice")
        XCTAssertTrue(aim.waitToExist(), "Caddie should show the club and aim")
        XCTAssertNotNil(aim.label.range(of: #"^Caddie: .+, \d+ yards$"#, options: .regularExpression),
                        "The aim should say the club and its yards: \(aim.label)")
        let toPin = element("CaddieToPin")
        XCTAssertTrue(toPin.exists, "The line on to the pin should have its yards")
        XCTAssertNotNil(toPin.label.range(of: #"^\d+ yards$"#, options: .regularExpression), toPin.label)

        // The shot's chances, which open the stats sheet
        let outcome = app.buttons["CaddieOutcome"]
        XCTAssertTrue(outcome.waitToExist(), "The pattern should come with its chances")
        XCTAssertNotNil(outcome.label.range(of: #"^Caddie: .+, \d+% (fairway or green|green), \d+% hazard$"#,
                                            options: .regularExpression), outcome.label)
        outcome.tap()
        let fairway = element("CaddieStatsFairway")
        XCTAssertTrue(fairway.waitToExist(), "The capsule should open the stats")
        XCTAssertNotNil(fairway.label.range(of: #"\d+%$"#, options: .regularExpression), fairway.label)
        let spread = element("CaddieStatsLateral")
        XCTAssertTrue(spread.waitToExist(), "The stats should have the spread")
        XCTAssertNotNil(spread.label.range(of: #"±\d+ yards$"#, options: .regularExpression), spread.label)
        XCTAssertTrue(element("CaddieStatsDownrange").exists)

        // Higher scores spread wider
        func yards(_ label: String) -> Int {
            Int(label.filter(\.isNumber)) ?? 0
        }
        let mine = yards(spread.label)
        let skill = app.buttons["CaddieSkill"]
        skill.tap()
        app.buttons["High scores"].tap()
        XCTAssertTrue(UIWait.until { yards(spread.label) > mine }, "High scores should spread wider: \(spread.label)")
        skill.tap()
        app.buttons["My scores"].tap()
        XCTAssertTrue(UIWait.until { yards(spread.label) == mine }, "Back to the player's own: \(spread.label)")
        app.buttons["CloseCaddieStats"].tap()
        XCTAssertTrue(spread.waitToVanish())

        tapMapMenuItem("CaddieAdvice")
        XCTAssertTrue(aim.waitToVanish(), "Picking Caddie again should hide it")
        XCTAssertFalse(toPin.exists)
        XCTAssertFalse(outcome.exists)
    }

    func testDraggingThePatternMovesTheAimAndNotTheMap() throws {
        app.goToHole(1)
        moveTo(latitude: Self.holeOneTee.latitude, longitude: Self.holeOneTee.longitude)
        let aim = element("CaddieAim")
        let target = element("Target")
        let map = app.maps.firstMatch
        tapMapMenuItem("CaddieAdvice")
        XCTAssertTrue(aim.waitToExist())
        let caddiesPick = aim.label
        let reset = app.buttons["ResetCaddie"]
        XCTAssertFalse(reset.exists, "Nothing to reset before the pattern is dragged")
        // A target off the pattern, which moves with the map
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.45)).tap()
        XCTAssertTrue(target.waitToExist())
        let targetFrame = target.frame

        // Toward the player, so a shorter club. The map holds still under the drag.
        func dragTowardThePlayer() {
            let from = aim.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: -30, dy: 160)))
            XCTAssertTrue(UIWait.until { aim.label != caddiesPick }, "The club should follow the distance: \(aim.label)")
        }
        dragTowardThePlayer()
        XCTAssertEqual(target.frame.midX, targetFrame.midX, accuracy: 2, "A drag on the pattern should not pan the map")
        XCTAssertEqual(target.frame.midY, targetFrame.midY, accuracy: 2, "A drag on the pattern should not pan the map")

        // Reset Caddie goes back to its pick
        XCTAssertTrue(reset.waitToExist(), "Reset Caddie should show once the pattern is dragged")
        reset.tap()
        XCTAssertTrue(UIWait.until { aim.label == caddiesPick }, "Back to the Caddie's pick: \(aim.label)")
        XCTAssertTrue(reset.waitToVanish())

        // So does turning the Caddie off and on
        dragTowardThePlayer()
        tapMapMenuItem("CaddieAdvice")
        XCTAssertTrue(aim.waitToVanish())
        tapMapMenuItem("CaddieAdvice")
        XCTAssertTrue(UIWait.until { aim.exists && aim.label == caddiesPick }, "Back to the Caddie's pick: \(aim.label)")

        // Off the pattern, a drag still pans the map
        let side = map.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.7))
        side.press(forDuration: 0.05, thenDragTo: side.withOffset(CGVector(dx: 120, dy: 0)))
        XCTAssertTrue(UIWait.until { abs(target.frame.midX - targetFrame.midX) > 20 }, "A drag off the pattern should pan the map")

        app.buttons["ClearTarget"].tap()
        XCTAssertTrue(target.waitToVanish())
        tapMapMenuItem("CaddieAdvice")
        XCTAssertTrue(aim.waitToVanish())
    }
}
