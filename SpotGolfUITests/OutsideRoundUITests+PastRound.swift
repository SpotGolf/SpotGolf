import XCTest

/// A past round opens on the same screen as a round in play: the holes along the top, one hole
/// at a time on the map, and the same stroke editing. The tests share one past round, made by
/// the first of them; a test that changes it makes the next one start over.
extension OutsideRoundUITests {
    private var scoreBox: XCUIElement { element("ScoreBox") }

    /// The total strokes, from the score box's "6" or "6, +1".
    private var scoreTotal: String? {
        (scoreBox.value as? String)?.split(separator: ",").first.map(String.init)
    }

    /// Leaves the past round, back on the round list.
    private func closePastRound() {
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["New Round"].waitToExist(), "Back should return to the round list")
    }

    /// Where stroke 2 is drawn relative to stroke 1.
    private func strokeOffset() -> CGVector {
        let one = app.buttons["Stroke_1"].frame
        let two = app.buttons["Stroke_2"].frame
        return CGVector(dx: two.midX - one.midX, dy: two.midY - one.midY)
    }

    /// How far apart the centers of two frames are.
    private func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Layout

    func testPastRoundShowsHolesLikeARoundInPlay() throws {
        ensurePastRound()
        openPastRound()

        // The header: back button, every hole, and the score box
        XCTAssertTrue(app.buttons["Back"].exists, "Back button should be in the header")
        XCTAssertTrue(app.holeButton(18).exists, "Header should list 18 holes")
        XCTAssertTrue(app.waitForShownHole(1), "A past round should open on Hole 1")
        XCTAssertEqual(scoreTotal, "5", "Score box should count all 5 strokes")
        XCTAssertTrue((scoreBox.value as? String)?.contains(",") == true,
                      "Score box should compare every played hole to par, not leave one out as current")

        // The par and tee show, and with no live location there are no distance boxes
        let summary = app.staticTexts["HoleSummary"]
        XCTAssertTrue(summary.waitToExist(), "Par should appear under the hole circles")
        XCTAssertEqual(summary.label, "Par 4 - Gold")
        XCTAssertFalse(element("DistanceToCenter").exists, "A past round has no distance to the green")
        XCTAssertFalse(element("ElevationChange").exists, "A past round has no elevation change")

        // The map shows only the strokes on the hole shown
        assertStrokeCount(3, onHole: 1)
        app.goToHole(2)
        assertStrokeCount(2, onHole: 2)
        app.goToHole(3)
        assertStrokeCount(0, onHole: 3)

        closePastRound()
    }

    // MARK: - Editing

    func testPastRoundCanBeEdited() throws {
        ensurePastRound()
        openPastRound()
        // The edits below change the round the other tests share
        resetGroup()

        // Move stroke 1 by dragging it. Stroke 2 stays put: the map must not pan under the drag,
        // which would move every stroke on screen and leave stroke 1 where it was
        let first = app.buttons["Stroke_1"]
        let firstFrame = first.frame
        let secondFrame = app.buttons["Stroke_2"].frame
        let grab = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grab.press(forDuration: 0.4, thenDragTo: grab.withOffset(CGVector(dx: 60, dy: -60)))
        XCTAssertTrue(UIWait.until { distance(first.frame, firstFrame) > 20 }, "Dragging should move stroke 1")
        XCTAssertLessThan(distance(app.buttons["Stroke_2"].frame, secondFrame), 5,
                          "Dragging stroke 1 should not move stroke 2 or the map")

        // Make stroke 1 the second stroke: stroke 2 is then drawn where stroke 1 was
        let movedFrame = first.frame
        openStroke(1)
        app.steppers.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["Spot: 2"].exists, "The stepper should move the stroke to spot 2")
        saveInSheet()
        XCTAssertTrue(UIWait.until { distance(app.buttons["Stroke_2"].frame, movedFrame) < 5 },
                      "The moved stroke should now be stroke 2")

        // Delete stroke 3
        openStroke(3)
        app.buttons["Delete Spot"].tap()
        let delete = app.alerts["Delete Spot"].buttons["Delete"]
        XCTAssertTrue(delete.waitToExist(), "Delete confirmation should appear")
        delete.tap()
        assertStrokeCount(2, onHole: 1)
        let hole1Layout = strokeOffset()

        // Add two strokes on hole 3: one with a penalty stroke, then one whose penalty stroke is taken back
        app.goToHole(3)
        app.addStroke(at: XCUIApplication.strokePressPoints[0])
        saveInSheet(tapping: ["PenaltyPlus"])
        app.addStroke(at: XCUIApplication.strokePressPoints[1])
        saveInSheet(tapping: ["PenaltyPlus"])
        openStroke(2)
        saveInSheet(tapping: ["PenaltyMinus"], "Minus takes the penalty stroke back")
        assertStrokeCount(2, onHole: 3)

        // Changes survive leaving and reopening the round
        closePastRound()
        openPastRound()
        XCTAssertTrue(app.waitForShownHole(1), "A past round should open on Hole 1")
        assertStrokeCount(2, onHole: 1)
        // The map re-centers on reopening, so compare where the strokes sit to each other
        let reopenedLayout = strokeOffset()
        XCTAssertLessThan(hypot(reopenedLayout.dx - hole1Layout.dx, reopenedLayout.dy - hole1Layout.dy), 5,
                          "Hole 1's moved and reordered strokes should be kept")

        app.goToHole(3)
        assertStrokeCount(2, onHole: 3)
        let penaltyStrokes = app.staticTexts["PenaltyStrokes"]
        openStroke(1)
        XCTAssertTrue(penaltyStrokes.waitToExist())
        XCTAssertEqual(penaltyStrokes.value as? String, "1", "Stroke 1 on hole 3 should still have a penalty stroke")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToVanish())
        openStroke(2)
        XCTAssertTrue(penaltyStrokes.waitToExist())
        XCTAssertEqual(penaltyStrokes.value as? String, "0", "Stroke 2 on hole 3 should have no penalty strokes")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToVanish())

        // Hole 1: 2, hole 2: 2, hole 3: 2 plus the penalty stroke
        XCTAssertEqual(scoreTotal, "7", "Score box should count 6 strokes and a penalty stroke")
    }

    // MARK: - Scorecard

    func testScoreBoxOpensTheScorecard() throws {
        // A round of its own, so nothing the earlier tests did with theirs can change it
        launch()
        ensurePastRound()
        openPastRound()

        scoreBox.tap()
        let total = element("ScorecardTotal")
        XCTAssertTrue(total.waitToExist(), "The score box should open the scorecard")
        let totalValue = total.value as? String ?? ""
        XCTAssertTrue(totalValue.hasPrefix("5"), "The scorecard total was '\(totalValue)'")
        XCTAssertTrue(app.staticTexts["Gold Tees · \(Date().formatted(date: .abbreviated, time: .omitted))"].exists,
                      "The scorecard should show the tee and the day")
        XCTAssertTrue(element("ScorecardOut").exists, "The front nine should have an Out column")
        XCTAssertTrue(element("ScorecardIn").exists, "The back nine should have an In column")
        XCTAssertTrue(element("ScorecardTot").exists, "The scorecard should have a total column")
        attachScreenshot("Scorecard portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element("ScorecardHole-12").waitToExist())
        attachScreenshot("Scorecard landscape")
        XCUIDevice.shared.orientation = .portrait
        // Hole 12's column only fits in landscape, so it leaving the screen means portrait is laid out
        let hole12 = element("ScorecardHole-12")
        XCTAssertTrue(UIWait.until { !hole12.exists || !hole12.isHittable }, "The scorecard should turn back to portrait")

        // A tap on hole 2's column shows hole 2. A tap aims at where the column was last reported,
        // which lags the turn back to portrait, so this waits for the column to stay put.
        let hole2 = element("ScorecardHole-2")
        var lastFrame = CGRect.null
        XCTAssertTrue(UIWait.until(timeout: UIWait.slow) {
            let frame = hole2.exists ? hole2.frame : .null
            defer { lastFrame = frame }
            return hole2.isHittable && frame == lastFrame
        }, "Hole 2's column should settle in portrait")
        hole2.tap()
        XCTAssertTrue(total.waitToVanish(), "A tap on a hole should close the scorecard")
        XCTAssertTrue(app.waitForShownHole(2), "A tap on hole 2 should show hole 2")

        // Close goes back to the map
        scoreBox.tap()
        XCTAssertTrue(total.waitToExist())
        app.buttons["CloseScorecard"].tap()
        XCTAssertTrue(total.waitToVanish(), "Close should close the scorecard")

        closePastRound()
    }
}
