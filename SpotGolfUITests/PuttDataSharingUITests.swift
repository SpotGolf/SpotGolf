import XCTest

/// The Putt Data Sharing screen: reached from the round list, nothing set up before consent.
@MainActor
final class PuttDataSharingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    func testConsentOpensTheSetup() throws {
        app.launch()
        let open = app.buttons["Putt Data Sharing"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "The round list should have a Putt Data Sharing button")
        open.tap()
        XCTAssertTrue(app.navigationBars["Putt Data Sharing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start on your watch, on the Putting Drills page. Read the instructions for each task on your watch, do the task, then tap Done."].exists,
                      "The phone says the instructions are on the watch")

        let agree = app.buttons["PuttSharingAgree"]
        XCTAssertTrue(agree.exists)
        let cellular = app.switches["PuttSharingCellular"]
        for _ in 0..<6 where !cellular.exists { app.swipeUp() }
        XCTAssertFalse(cellular.isEnabled, "Nothing is set up before consent")
        for _ in 0..<6 where !agree.isHittable { app.swipeDown() }

        agree.tap()

        XCTAssertTrue(app.descendants(matching: .any)["PuttSharingAgreed"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !cellular.isHittable { app.swipeUp() }
        XCTAssertTrue(cellular.isEnabled)
        XCTAssertTrue(app.staticTexts["No sessions yet"].exists)
    }
}
