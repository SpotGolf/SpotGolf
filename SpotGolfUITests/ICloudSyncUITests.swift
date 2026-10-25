import XCTest

/// The iCloud Sync setting, and the notice shown when iCloud has a format this build can't read.
/// UI tests run without iCloud, so nothing here syncs.
@MainActor
final class ICloudSyncUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    private func openSettings() {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "The round list should have a Settings button")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings should open")
    }

    /// Scrolls Settings until `element` shows.
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(element) should show in Settings")
    }

    func testICloudSyncIsOnByDefaultAndCanBeTurnedOff() throws {
        app.launch()
        openSettings()

        let toggle = app.switches["iCloudSync"]
        scrollTo(toggle)
        XCTAssertEqual(toggle.value as? String, "1", "iCloud Sync should be on by default")

        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0", "iCloud Sync should turn off")
    }

    func testTheUpdateNoticeShowsOnceAndStaysInSettings() throws {
        app.launchArguments.append("--needs-app-update")
        app.launch()

        let alert = app.alerts["Update SpotGolf"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "The notice should show over the round list")
        XCTAssertFalse(alert.buttons["Open App Store"].exists, "No App Store link before the app is published")
        alert.buttons["OK"].tap()

        openSettings()
        XCTAssertTrue(app.staticTexts["UpdateNoticeMessage"].waitForExistence(timeout: 5),
                      "Settings should keep the notice at the top")
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(alert.waitForExistence(timeout: 2), "The alert shows once per launch")
    }

    func testNoNoticeWithoutANewerFormat() throws {
        app.launch()

        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Update SpotGolf"].waitForExistence(timeout: 2))
    }
}
