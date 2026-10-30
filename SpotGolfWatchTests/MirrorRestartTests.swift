import XCTest
@testable import SpotGolfWatch

final class MirrorRestartTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func shouldStart(_ trigger: MirrorRestart.Trigger, isAttached: Bool = true, isConnected: Bool = false,
                             startedSecondsAgo: TimeInterval? = 300, disconnectedSecondsAgo: TimeInterval?) -> Bool {
        MirrorRestart.shouldStart(trigger, at: now, isAttached: isAttached, isConnected: isConnected,
                                  startedAt: startedSecondsAgo.map { now - $0 },
                                  disconnectedSince: disconnectedSecondsAgo.map { now - $0 })
    }

    func testNewWorkoutStartsAtOnce() {
        XCTAssertTrue(shouldStart(.check, isAttached: false, startedSecondsAgo: nil, disconnectedSecondsAgo: nil))
        XCTAssertTrue(shouldStart(.phoneReachable, isAttached: false, startedSecondsAgo: nil, disconnectedSecondsAgo: nil))
    }

    func testConnectedNeverRestarts() {
        XCTAssertFalse(shouldStart(.check, isConnected: true, disconnectedSecondsAgo: nil))
        XCTAssertFalse(shouldStart(.phoneReachable, isConnected: true, disconnectedSecondsAgo: 300))
    }

    func testCheckWaitsAMinuteDisconnected() {
        XCTAssertFalse(shouldStart(.check, disconnectedSecondsAgo: 59))
        XCTAssertTrue(shouldStart(.check, disconnectedSecondsAgo: 60))
    }

    func testPhoneReachableWaits15SecondsDisconnected() {
        XCTAssertFalse(shouldStart(.phoneReachable, disconnectedSecondsAgo: 14))
        XCTAssertTrue(shouldStart(.phoneReachable, disconnectedSecondsAgo: 15))
    }

    func testRecentStartResetsTheWait() {
        XCTAssertFalse(shouldStart(.check, startedSecondsAgo: 10, disconnectedSecondsAgo: 120))
        XCTAssertFalse(shouldStart(.phoneReachable, startedSecondsAgo: 10, disconnectedSecondsAgo: 120))
        XCTAssertTrue(shouldStart(.phoneReachable, startedSecondsAgo: 15, disconnectedSecondsAgo: 120))
    }

    func testNeverConnectedRestartsAMinuteAfterTheStart() {
        // As on simulators: started, but never connected
        XCTAssertFalse(shouldStart(.check, startedSecondsAgo: 59, disconnectedSecondsAgo: nil))
        XCTAssertTrue(shouldStart(.check, startedSecondsAgo: 60, disconnectedSecondsAgo: nil))
    }
}
