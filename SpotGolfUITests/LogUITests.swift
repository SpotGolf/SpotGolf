import XCTest

/// The app log on the phone: the lines outside a round from Settings, a past round's lines
/// from its row, and the export.
@MainActor
final class LogUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    func testSettingsOpensTheLogAndExportsIt() throws {
        app.launch()

        openSettings()
        let openLog = app.buttons["OpenLog"]
        XCTAssertTrue(openLog.waitForExistence(timeout: 5), "Settings should have a Log link")
        openLog.tap()
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5), "The log should open")
        // The launch is logged before any round
        XCTAssertTrue(app.staticTexts["Phone app launched"].waitForExistence(timeout: 5), "The launch line should be listed")

        app.buttons["ExportLog"].tap()
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 10), "The share sheet should open")
        let fileName = shareSheet.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'spotgolf-log-'")).firstMatch
        XCTAssertTrue(fileName.waitForExistence(timeout: 10), "The share sheet should show the log file")
        shareSheet.buttons["Close"].tap()
        XCTAssertTrue(shareSheet.waitForNonExistence(timeout: 5), "The share sheet should close")
    }

    func testPastRoundHasItsOwnLog() throws {
        LocationTestHelper.setSimulatorLocation(latitude: 39.95545, longitude: -105.04220)
        app.launch()
        dismissLocationAlert()
        app.startRoundWithCourse()
        app.buttons["Back"].tap()
        let endRound = app.buttons["End Round"]
        XCTAssertTrue(endRound.waitForExistence(timeout: 5), "End Round button should exist")
        endRound.tap()
        XCTAssertTrue(app.buttons["New Round"].waitForExistence(timeout: 5), "The round should end")

        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Broadlands'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The past round should be listed")
        row.swipeRight()
        let log = app.buttons["Log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5), "The row should offer its log")
        log.tap()

        XCTAssertTrue(app.navigationBars["Round Log"].waitForExistence(timeout: 5), "The round's log should open")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'starting'")).firstMatch.waitForExistence(timeout: 5),
                      "The round's start should be in its log")
        app.navigationBars["Round Log"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Round Log"].waitForNonExistence(timeout: 5), "The log sheet should close")
    }

    private func openSettings() {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "The round list should have a Settings button")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings should open")
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
}
