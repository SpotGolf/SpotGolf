import XCTest
@testable import SpotGolf

final class LaunchOptionsTests: XCTestCase {

    func testNoArgumentsIsANormalLaunch() {
        let options = LaunchOptions(arguments: ["SpotGolf"])

        XCTAssertFalse(options.isUITesting)
        XCTAssertFalse(options.keepsRounds)
        XCTAssertFalse(options.startsRound)
    }

    func testReadsEachArgument() {
        let options = LaunchOptions(arguments: ["SpotGolf", "--ui-testing", "--keep-rounds", "--start-round"])

        XCTAssertTrue(options.isUITesting)
        XCTAssertTrue(options.keepsRounds)
        XCTAssertTrue(options.startsRound)
    }

}
