import XCTest

/// Developer Mode: hidden in Settings until Version is tapped 7 times in a row.
@MainActor
final class DeveloperModeUITests: XCTestCase {

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

    func testVersionTapsTurnDeveloperModeOnAndTheSwitchTurnsItOff() throws {
        app.launch()
        openSettings()
        let version = app.descendants(matching: .any)["AppVersion"].firstMatch
        scrollTo(version)
        let toggle = app.switches["DeveloperMode"]
        // Settings outlive the app, so an earlier run may have left it on
        if toggle.exists {
            scrollTo(toggle)
            toggle.switches.firstMatch.tap()
            XCTAssertFalse(toggle.waitForExistence(timeout: 2), "Turning it off hides the section")
            scrollTo(version)
        }

        for _ in 0..<6 {
            version.tap()
        }
        XCTAssertFalse(toggle.waitForExistence(timeout: 1), "6 taps are not enough")

        version.tap()
        let alert = app.alerts["Developer Mode On"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "The seventh tap turns it on")
        alert.buttons["OK"].tap()

        scrollTo(toggle)
        XCTAssertEqual(toggle.value as? String, "1", "The switch shows, on")

        toggle.switches.firstMatch.tap()
        XCTAssertFalse(toggle.waitForExistence(timeout: 2), "Turning it off hides the section again")
    }
}
