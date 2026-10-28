import XCTest

/// A group of UI tests that share one launch of the app. `beforeGroup` launches it and brings it
/// to the screen every test in the group starts from, once, before the group's first test.
///
/// XCTest has no such hook that can drive the app: `class func setUp` is not on the main actor,
/// where `XCUIApplication` lives. So the first test's `setUp` runs `beforeGroup`. It runs again
/// when a test fails, when a test calls `resetGroup()` because it changed what the others rely
/// on, and when a test leaves the app away from the group's start (`isAtGroupStart`), so one
/// test's leftovers never break the next.
///
/// A group is a subclass. Its tests live in extensions, one file per feature, named
/// `<Group>+<Feature>.swift`. XCTest runs a class's tests in name order.
@MainActor
class UITestGroup: XCTestCase {
    /// Near the Broadlands clubhouse, off hole 1. Broadlands only shows in the course list when
    /// the simulator is near it.
    static let broadlands = (latitude: 39.95545, longitude: -105.04220)

    /// The app all groups drive. Moving to another group launches it again.
    private static var sharedApp: XCUIApplication?
    /// The group whose `beforeGroup` set up `sharedApp`, or nil when it must run again.
    private static var preparedGroup: ObjectIdentifier?

    var app: XCUIApplication {
        guard let app = Self.sharedApp else { fatalError("beforeGroup must launch the app") }
        return app
    }

    /// Launches the app and brings it to the screen the group's tests start from.
    func beforeGroup() {
        launch()
    }

    /// Whether the app is on the screen the group's tests start from. When it is not, the next
    /// test runs `beforeGroup` again.
    func isAtGroupStart() -> Bool {
        true
    }

    /// Runs `beforeGroup` again before the next test, for a test that changed what the others
    /// rely on.
    func resetGroup() {
        Self.preparedGroup = nil
    }

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        LocationTestHelper.setSimulatorLocation(latitude: Self.broadlands.latitude, longitude: Self.broadlands.longitude)
        let group = ObjectIdentifier(type(of: self))
        if Self.preparedGroup != group || !isAtGroupStart() {
            Self.preparedGroup = nil
            beforeGroup()
            Self.preparedGroup = group
        }
    }

    override func tearDown() async throws {
        // `hasSucceeded` is false until the run stops, which is after tearDown
        if let run = testRun, run.totalFailureCount > 0 {
            resetGroup()
        }
        try await super.tearDown()
    }

    /// Launches the app for UI testing, with any extra launch arguments, and waits for the round
    /// list unless something will cover it. A launch empties the saved rounds and resets the settings.
    func launch(_ arguments: [String] = [], waitForList: Bool = true) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        Self.sharedApp = app
        app.launch()
        addUIInterruptionMonitor(withDescription: "Location Permission") { alert in
            let allow = alert.buttons["Allow While Using App"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        // A first launch after an install takes longer to show the round list
        guard waitForList else { return }
        XCTAssertTrue(app.buttons["New Round"].waitToExist(timeout: UIWait.slow), "The round list should show")
    }

    // MARK: - Helpers

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The first round in the round list.
    var broadlandsRow: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Broadlands'")).firstMatch
    }

    /// Opens Settings from the round list.
    func openSettings(file: StaticString = #filePath, line: UInt = #line) {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitToExist(), "The round list should have a Settings button", file: file, line: line)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitToExist(), "Settings should open", file: file, line: line)
    }

    /// Scrolls until `element` can be tapped.
    func scrollTo(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(element) should show", file: file, line: line)
    }

    /// Leaves the round screen and ends the round, back on the round list.
    func endRound(file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["Back"].tap()
        let endRound = app.buttons["End Round"]
        XCTAssertTrue(endRound.waitToExist(), "End Round button should exist", file: file, line: line)
        endRound.tap()
        XCTAssertTrue(app.buttons["New Round"].waitToExist(), "The round should end", file: file, line: line)
    }

    /// Taps a stroke, which opens its edit sheet.
    func openStroke(_ number: Int, file: StaticString = #filePath, line: UInt = #line) {
        let stroke = app.buttons["Stroke_\(number)"]
        XCTAssertTrue(stroke.waitToExist(), "Stroke \(number) should exist", file: file, line: line)
        stroke.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToExist(),
                      "Edit sheet should open for stroke \(number)", file: file, line: line)
    }

    /// Taps the given buttons in the open edit sheet, in order, and saves.
    func saveInSheet(tapping identifiers: [String] = [], _ note: String = "", file: StaticString = #filePath, line: UInt = #line) {
        for identifier in identifiers {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitToExist(), "\(identifier) should be in the edit sheet", file: file, line: line)
            button.tap()
        }
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitToExist(), "Save should be in the edit sheet", file: file, line: line)
        save.tap()
        XCTAssertTrue(app.navigationBars["Edit Spot"].waitToVanish(),
                      "Edit sheet should close after Save. \(note)", file: file, line: line)
    }

    /// Long-presses the map at `point`, which adds a stroke there and opens it, and saves it.
    func addStroke(at point: CGVector, file: StaticString = #filePath, line: UInt = #line) {
        app.addStroke(at: point)
        saveInSheet(file: file, line: line)
    }

    func assertStrokeCount(_ count: Int, onHole hole: Int, file: StaticString = #filePath, line: UInt = #line) {
        if count > 0 {
            XCTAssertTrue(app.buttons["Stroke_\(count)"].waitToExist(),
                          "Hole \(hole) should have \(count) strokes", file: file, line: line)
        }
        XCTAssertFalse(app.buttons["Stroke_\(count + 1)"].exists,
                       "Hole \(hole) should have no more than \(count) strokes", file: file, line: line)
    }
}
