import XCTest
@testable import SpotGolf

final class SplashTimelineTests: XCTestCase {

    func testShowsOnlyOnANormalLaunch() {
        XCTAssertTrue(SplashTimeline.shows(isUITesting: false, reducesMotion: false))
        XCTAssertFalse(SplashTimeline.shows(isUITesting: true, reducesMotion: false))
        XCTAssertFalse(SplashTimeline.shows(isUITesting: false, reducesMotion: true))
    }

    func testStartsOnTheLaunchColor() {
        XCTAssertEqual(SplashTimeline.launchColor(at: 0), 1)
        XCTAssertEqual(SplashTimeline.ballOpacity(at: 0), 0)
        XCTAssertEqual(SplashTimeline.launchColor(at: 0.25), 0)
        XCTAssertEqual(SplashTimeline.ballOpacity(at: 0.1), 1)
    }

    func testClockWaitsOutALongFrame() {
        XCTAssertEqual(SplashTimeline.advance(1, by: 1.0 / 60), 1 + 1.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(SplashTimeline.advance(1, by: 1.2), 1 + SplashTimeline.longestFrame, accuracy: 0.0001)
        XCTAssertEqual(SplashTimeline.advance(1, by: -0.5), 1)
    }

    func testBallLandsOnThePinsTip() {
        let start = SplashTimeline.ballCenter(at: 0)
        let landed = SplashTimeline.ballCenter(at: SplashTimeline.landing)

        XCTAssertEqual(start.x, 18, accuracy: 0.001)
        XCTAssertEqual(start.y, 400, accuracy: 0.001)
        XCTAssertEqual(landed.x, SplashTimeline.pinTip.x, accuracy: 0.001)
        XCTAssertEqual(landed.y + SplashTimeline.ballRadius(at: SplashTimeline.landing), SplashTimeline.pinTip.y,
                       accuracy: 0.001)
    }

    func testBallFliesOverThePin() {
        let highest = stride(from: 0.0, through: SplashTimeline.landing, by: 0.01)
            .map { SplashTimeline.ballCenter(at: $0).y }
            .min()!

        XCTAssertLessThan(highest, 150)
    }

    func testBallHopsOnceAfterLanding() {
        let landed = SplashTimeline.ballCenter(at: SplashTimeline.landing).y

        XCTAssertLessThan(SplashTimeline.ballCenter(at: SplashTimeline.landing + 0.1).y, landed - 7)
        XCTAssertEqual(SplashTimeline.ballCenter(at: SplashTimeline.landing + 0.3).y, landed, accuracy: 0.001)
    }

    func testTracerFollowsTheBallThenFades() {
        let flying = SplashTimeline.tracer(at: 0.5)
        XCTAssertEqual(flying.end, SplashTimeline.flight(at: 0.5), accuracy: 0.001)
        XCTAssertEqual(flying.opacity, 1)

        XCTAssertEqual(SplashTimeline.tracer(at: 1.4).opacity, 0)
    }

    func testPinGrowsOutOfTheBallAndSettles() {
        XCTAssertEqual(SplashTimeline.pinScale(at: SplashTimeline.landing), 0)
        XCTAssertEqual(SplashTimeline.pinScale(at: 1.0), 0)
        XCTAssertGreaterThan(SplashTimeline.pinScale(at: 1.25), 1)
        XCTAssertEqual(SplashTimeline.pinScale(at: 1.35), 1, accuracy: 0.001)
        XCTAssertEqual(SplashTimeline.ballOpacity(at: 1.15), 0)
    }

    func testRingsSpreadAndFade() {
        XCTAssertNil(SplashTimeline.ring(startingAt: SplashTimeline.landing, at: SplashTimeline.landing - 0.01))
        XCTAssertNil(SplashTimeline.ring(startingAt: SplashTimeline.landing, at: SplashTimeline.landing + 1))

        let early = SplashTimeline.ring(startingAt: SplashTimeline.landing, at: SplashTimeline.landing + 0.1)!
        let late = SplashTimeline.ring(startingAt: SplashTimeline.landing, at: SplashTimeline.landing + 0.8)!
        XCTAssertGreaterThan(late.radius, early.radius)
        XCTAssertLessThan(late.opacity, early.opacity)
    }

    func testTitleShowsBeforeTheEnd() {
        XCTAssertEqual(SplashTimeline.title(at: 1.2), 0)
        XCTAssertEqual(SplashTimeline.title(at: 1.6), 1)
        XCTAssertLessThan(1.6, SplashTimeline.end)
    }

}
