import XCTest
@testable import SpotGolf

final class AppVersionTests: XCTestCase {

    func testTextShowsTheVersion() {
        XCTAssertEqual(AppVersion.text(["CFBundleShortVersionString": "0.1.0"]), "0.1.0")
    }

    func testTextShowsAQuestionMarkWithoutAVersion() {
        XCTAssertEqual(AppVersion.text(nil), "?")
    }
}
