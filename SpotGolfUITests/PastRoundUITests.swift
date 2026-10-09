import XCTest

/// A past round opens on the same screen as a round in play: the holes along the top,
/// one hole at a time on the map, and the same editing.
@MainActor
final class PastRoundUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    // MARK: - Layout

    func testPastRoundShowsHolesLikeARoundInPlay() throws {
        createPastRound()
        openPastRound()

        // The header: back button, every hole, and the score box
        XCTAssertTrue(app.buttons["Back"].exists, "Back button should be in the header")
        XCTAssertTrue(app.holeButton(18).exists, "Header should list 18 holes")
        XCTAssertTrue(app.waitForShownHole(1), "A past round should open on Hole 1")
        XCTAssertEqual(scoreTotal, "5", "Score box should count all 5 strokes")
        XCTAssertTrue((scoreBox.value as? String)?.contains(",") == true,
                      "Score box should compare every played hole to par, not leave one out as current")

        // No live location, so the par shows without yards, and there are no distance boxes
        let summary = app.staticTexts["HoleSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Par should appear under the hole circles")
        XCTAssertEqual(summary.label, "Par 4")
        XCTAssertFalse(element("DistanceToCenter").exists, "A past round has no distance to the green")
        XCTAssertFalse(element("ElevationChange").exists, "A past round has no elevation change")

        // The map shows only the strokes on the hole shown
        assertStrokeCount(3, onHole: 1)

        app.goToHole(2)
        assertStrokeCount(2, onHole: 2)

        app.goToHole(3)
        assertStrokeCount(0, onHole: 3)

        // Back returns to the round list
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["New Round"].waitForExistence(timeout: 5), "Back should return to the round list")
    }

    // MARK: - Editing

    func testPastRoundCanBeEdited() throws {
        createPastRound()
        openPastRound()

        // Hole times are offered while editing, as during a round
        XCTAssertFalse(app.buttons["Hole times"].exists, "Hole times should only show while editing")
        app.startEditing()
        let holeTimes = app.buttons["Hole times"]
        XCTAssertTrue(holeTimes.waitForExistence(timeout: 5), "Hole times should show while editing")
        holeTimes.tap()
        XCTAssertTrue(app.navigationBars["Hole Times"].waitForExistence(timeout: 5), "Hole times sheet should open")
        // The Edit button also reads "Done" while editing
        app.navigationBars["Hole Times"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Hole Times"].waitForNonExistence(timeout: 5), "Hole times sheet should close")

        // Move stroke 1 by dragging it
        let first = app.buttons["Stroke_1"]
        let firstFrame = first.frame
        let grab = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grab.press(forDuration: 0.6, thenDragTo: grab.withOffset(CGVector(dx: 60, dy: -60)))
        sleep(1)
        XCTAssertGreaterThan(distance(first.frame, firstFrame), 20, "Dragging should move stroke 1")

        // Make stroke 1 the second stroke: stroke 2 is then drawn where stroke 1 was
        let movedFrame = first.frame
        openStroke(1)
        app.steppers.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["Spot: 2"].exists, "The stepper should move the stroke to spot 2")
        app.buttons["Save"].tap()
        sleep(1)
        XCTAssertLessThan(distance(app.buttons["Stroke_2"].frame, movedFrame), 5,
                          "The moved stroke should now be stroke 2")

        // Delete stroke 3
        openStroke(3)
        app.buttons["Delete Spot"].tap()
        let delete = app.alerts["Delete Spot"].buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Delete confirmation should appear")
        delete.tap()
        assertStrokeCount(2, onHole: 1)
        let hole1Layout = strokeOffset()

        // Add two strokes on hole 3: a penalty, then one that is marked and cleared
        app.goToHole(3)
        app.addStroke(at: XCUIApplication.strokePressPoints[0])
        tapInSheet("Penalty stroke")
        app.addStroke(at: XCUIApplication.strokePressPoints[1])
        tapInSheet("Out of bounds")
        openStroke(2)
        tapInSheet("Clear penalty")
        assertStrokeCount(2, onHole: 3)

        // Changes survive leaving and reopening the round
        app.buttons["Back"].tap()
        openPastRound()
        XCTAssertTrue(app.waitForShownHole(1), "A past round should open on Hole 1")
        assertStrokeCount(2, onHole: 1)
        // The map re-centers on reopening, so compare where the strokes sit to each other
        let reopenedLayout = strokeOffset()
        XCTAssertLessThan(hypot(reopenedLayout.dx - hole1Layout.dx, reopenedLayout.dy - hole1Layout.dy), 5,
                          "Hole 1's moved and reordered strokes should be kept")

        app.goToHole(3)
        assertStrokeCount(2, onHole: 3)
        app.startEditing()
        openStroke(1)
        XCTAssertTrue(app.buttons["Clear penalty"].waitForExistence(timeout: 5), "Stroke 1 on hole 3 should still be a penalty")
        app.buttons["Cancel"].tap()
        openStroke(2)
        XCTAssertTrue(app.buttons["Penalty stroke"].waitForExistence(timeout: 5), "Stroke 2 on hole 3 should be a regular stroke")
        app.buttons["Cancel"].tap()

        // Hole 1: 2, hole 2: 2, hole 3: 2
        XCTAssertEqual(scoreTotal, "6", "Score box should count 6 strokes")
    }

    // MARK: - Scorecard

    func testScoreBoxOpensTheScorecard() throws {
        createPastRound()
        openPastRound()

        scoreBox.tap()
        let total = element("ScorecardTotal")
        XCTAssertTrue(total.waitForExistence(timeout: 5), "The score box should open the scorecard")
        let totalValue = total.value as? String ?? ""
        XCTAssertTrue(totalValue.hasPrefix("5"), "The scorecard total was '\(totalValue)'")
        XCTAssertTrue(app.staticTexts["Gold Tees · \(Date().formatted(date: .abbreviated, time: .omitted))"].exists,
                      "The scorecard should show the tee and the day")
        XCTAssertTrue(element("ScorecardOut").exists, "The front nine should have an Out column")
        XCTAssertTrue(element("ScorecardIn").exists, "The back nine should have an In column")
        XCTAssertTrue(element("ScorecardTot").exists, "The scorecard should have a total column")
        attachScreenshot("Scorecard portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element("ScorecardEdit-12").waitForExistence(timeout: 5))
        attachScreenshot("Scorecard landscape")
        XCUIDevice.shared.orientation = .portrait

        // Edit on hole 2 shows hole 2 in edit mode
        let editHole2 = app.buttons["ScorecardEdit-2"]
        XCTAssertTrue(editHole2.waitForExistence(timeout: 5))
        editHole2.tap()
        XCTAssertTrue(total.waitForNonExistence(timeout: 5), "Edit should close the scorecard")
        XCTAssertTrue(app.waitForShownHole(2), "Edit should show hole 2")
        XCTAssertEqual(app.buttons["EditHole"].label, "Done", "Hole 2 should be in edit mode")

        // Close goes back to the map
        scoreBox.tap()
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        app.buttons["CloseScorecard"].tap()
        XCTAssertTrue(total.waitForNonExistence(timeout: 5), "Close should close the scorecard")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Helpers

    private var scoreBox: XCUIElement {
        element("ScoreBox")
    }

    /// The total strokes, from the score box's "6" or "6, +1".
    private var scoreTotal: String? {
        (scoreBox.value as? String)?.split(separator: ",").first.map(String.init)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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

    /// Plays 3 strokes on hole 1 and 2 on hole 2 at Broadlands, then ends the round.
    private func createPastRound() {
        // Broadlands only shows in the course list when the simulator is near it
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()

        for hole in 1...2 {
            if hole != 1 {
                app.goToHole(hole)
            }
            for spot in 0..<(hole == 1 ? 3 : 2) {
                app.addStroke(at: XCUIApplication.strokePressPoints[spot])
                tapInSheet("Save")
            }
        }

        app.buttons["Back"].tap()
        let endRound = app.buttons["End Round"]
        XCTAssertTrue(endRound.waitForExistence(timeout: 5), "End Round button should exist")
        endRound.tap()
        XCTAssertTrue(app.buttons["New Round"].waitForExistence(timeout: 5), "The round should end")
    }

    /// Opens the only past round in the list.
    private func openPastRound() {
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Broadlands'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The past round should be in the list")
        row.tap()
        XCTAssertTrue(app.holeButton(1).waitForExistence(timeout: 5), "The past round should open")
    }

    /// Taps a stroke in edit mode, which opens its edit sheet.
    private func openStroke(_ number: Int, file: StaticString = #filePath, line: UInt = #line) {
        app.startEditing()
        let stroke = app.buttons["Stroke_\(number)"]
        XCTAssertTrue(stroke.waitForExistence(timeout: 5), "Stroke \(number) should exist", file: file, line: line)
        stroke.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForExistence(timeout: 5),
                      "Edit sheet should open for stroke \(number)", file: file, line: line)
    }

    /// Taps a button in the open edit sheet, which closes it.
    private func tapInSheet(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(label) should be in the edit sheet", file: file, line: line)
        button.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitForNonExistence(timeout: 5),
                      "Edit sheet should close after \(label)", file: file, line: line)
    }

    private func assertStrokeCount(_ count: Int, onHole hole: Int, file: StaticString = #filePath, line: UInt = #line) {
        if count > 0 {
            XCTAssertTrue(app.buttons["Stroke_\(count)"].waitForExistence(timeout: 5),
                          "Hole \(hole) should have \(count) strokes", file: file, line: line)
        }
        XCTAssertFalse(app.buttons["Stroke_\(count + 1)"].exists,
                       "Hole \(hole) should have no more than \(count) strokes", file: file, line: line)
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
}
