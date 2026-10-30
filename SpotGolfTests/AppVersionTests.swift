import XCTest
@testable import SpotGolf

final class AppVersionTests: XCTestCase {

    func testTextShowsTheVersion() {
        XCTAssertEqual(AppVersion.text(["CFBundleShortVersionString": "0.1.0"]), "0.1.0")
    }

    func testTextShowsAQuestionMarkWithoutAVersion() {
        XCTAssertEqual(AppVersion.text(nil), "?")
    }

    func testBuildInstantShowsTheInstant() {
        XCTAssertEqual(AppVersion.buildInstant(["SpotGolfBuildInstant": "2026-10-29T23:10:05Z"]), "2026-10-29T23:10:05Z")
    }

    func testBuildInstantShowsAQuestionMarkWithoutOne() {
        XCTAssertEqual(AppVersion.buildInstant(nil), "?")
    }
}
