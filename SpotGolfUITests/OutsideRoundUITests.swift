import XCTest

/// Everything outside a round: the round list, Settings, Putt Data Sharing and past rounds. Each
/// test starts on the round list, and leaves the app there.
final class OutsideRoundUITests: UITestGroup {
    /// On the round list, with nothing over it.
    override func isAtGroupStart() -> Bool {
        app.buttons["Settings"].exists
    }

    /// Plays 3 strokes on hole 1 and 2 on hole 2 at Broadlands, then ends the round, unless the
    /// list already has that past round.
    func ensurePastRound() {
        guard !broadlandsRow.exists else { return }
        app.startRoundWithCourse()
        for spot in 0..<3 {
            addStroke(at: XCUIApplication.strokePressPoints[spot])
        }
        app.goToHole(2)
        for spot in 0..<2 {
            addStroke(at: XCUIApplication.strokePressPoints[spot])
        }
        endRound()
    }

    /// Opens the only past round in the list.
    func openPastRound(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(broadlandsRow.waitToExist(), "The past round should be in the list", file: file, line: line)
        broadlandsRow.tap()
        XCTAssertTrue(app.holeButton(1).waitToExist(), "The past round should open", file: file, line: line)
    }
}
