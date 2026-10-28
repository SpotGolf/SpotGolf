import XCTest

/// Settings: Developer Mode, iCloud Sync, the update notice and the app's log.
extension OutsideRoundUITests {
    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitToExist(), "Settings should close")
    }

    func testVersionTapsTurnDeveloperModeOnAndTheSwitchTurnsItOff() throws {
        openSettings()
        let version = app.descendants(matching: .any)["AppVersion"].firstMatch
        scrollTo(version)
        let toggle = app.switches["DeveloperMode"]
        XCTAssertFalse(toggle.exists, "A launch starts with Developer Mode off")

        for _ in 0..<6 {
            version.tap()
        }
        XCTAssertFalse(toggle.exists, "6 taps are not enough")
        version.tap()
        let alert = app.alerts["Developer Mode On"]
        XCTAssertTrue(alert.waitToExist(), "The seventh tap turns it on")
        alert.buttons["OK"].tap()
        scrollTo(toggle)
        XCTAssertEqual(toggle.value as? String, "1", "The switch shows, on")
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(toggle.waitToVanish(), "Turning it off hides the section again")
        closeSettings()
    }

    func testICloudSyncIsOnByDefaultAndCanBeTurnedOff() throws {
        openSettings()
        let toggle = app.switches["iCloudSync"]
        scrollTo(toggle)
        XCTAssertEqual(toggle.value as? String, "1", "iCloud Sync should be on by default")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0", "iCloud Sync should turn off")
        closeSettings()
    }

    func testTheUpdateNoticeShowsOnceAndStaysInSettings() throws {
        launch(["--needs-app-update"], waitForList: false)
        let alert = app.alerts["Update SpotGolf"]
        XCTAssertTrue(alert.waitToExist(timeout: UIWait.slow), "The notice should show over the round list")
        XCTAssertFalse(alert.buttons["Open App Store"].exists, "No App Store link before the app is published")
        alert.buttons["OK"].tap()

        openSettings()
        XCTAssertTrue(app.staticTexts["UpdateNoticeMessage"].waitToExist(), "Settings should keep the notice at the top")
        closeSettings()
        XCTAssertFalse(alert.exists, "The alert shows once per launch")
    }

    func testNoNoticeWithoutANewerFormat() throws {
        // The notice would show as the round list did
        XCTAssertFalse(app.alerts["Update SpotGolf"].exists)
    }

    func testShareLogsShowsTheGzippedLog() throws {
        openSettings()
        // The Log section is below the fold: Settings only makes the rows on screen
        let shareLogs = app.buttons["ShareLogs"]
        for _ in 0..<8 where !shareLogs.exists {
            app.swipeUp()
        }
        XCTAssertTrue(shareLogs.waitToExist(), "Settings should have Share logs…")
        XCTAssertFalse(app.switches["DebugLogging"].exists, "Debug Logging is gone")

        shareLogs.tap()
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitToExist(timeout: UIWait.slow), "The share sheet should open")
        let fileName = shareSheet.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'SpotGolf-log-'")).firstMatch
        XCTAssertTrue(fileName.waitToExist(timeout: UIWait.slow), "The share sheet should show the log file")
        shareSheet.buttons["Close"].tap()
        XCTAssertTrue(shareSheet.waitToVanish(timeout: UIWait.slow), "The share sheet should close")

        XCTAssertTrue(app.navigationBars["Settings"].waitToExist())
        closeSettings()
    }
}
