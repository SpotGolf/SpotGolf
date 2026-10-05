import XCTest

/// Starting a round, which always needs a course.
extension XCUIApplication {
    /// Starts a round at Broadlands with the default nines and waits for the round screen.
    /// Broadlands only shows in the course list when the simulator is near it.
    func startRoundWithCourse(file: StaticString = #filePath, line: UInt = #line) {
        let newRoundButton = buttons["New Round"]
        XCTAssertTrue(newRoundButton.waitForExistence(timeout: 5), "New Round button should exist", file: file, line: line)
        newRoundButton.tap()

        let broadlands = staticTexts["Broadlands Golf Course"]
        XCTAssertTrue(broadlands.waitForExistence(timeout: 10), "Broadlands should be in the course list", file: file, line: line)
        broadlands.tap()

        let startButton = buttons["Start Round"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Round button should exist", file: file, line: line)
        startButton.tap()

        XCTAssertTrue(waitForShownHole(1), "The round should start on Hole 1", file: file, line: line)
    }
}
