import XCTest
@testable import SpotGolfWatch

final class RestartWatchdogTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // MARK: - Errors

    func testErrorRightAfterAStartIsLeftToTheCheck() {
        let watchdog = RestartWatchdog(startedAt: start, checksData: true)
        XCTAssertFalse(watchdog.shouldRestartAfterError(at: at(1)))
    }

    func testErrorLongAfterAStartRestarts() {
        let watchdog = RestartWatchdog(startedAt: start, checksData: true)
        XCTAssertTrue(watchdog.shouldRestartAfterError(at: at(60)))
    }

    func testErrorRightAfterARestartIsLeftToTheCheck() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: true)
        watchdog.started(at: at(60))
        XCTAssertFalse(watchdog.shouldRestartAfterError(at: at(61)))
    }

    // MARK: - Data

    func testDataArrivingDoesNotRestart() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: true)
        watchdog.dataReceived(at: at(25))
        XCTAssertFalse(watchdog.shouldRestart(at: at(30), isActive: true))
    }

    func testNewStartGetsAFullIntervalForItsFirstData() {
        let watchdog = RestartWatchdog(startedAt: start, checksData: true)
        XCTAssertFalse(watchdog.shouldRestart(at: at(RestartWatchdog.interval), isActive: true))
    }

    func testNoDataForAnIntervalRestarts() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: true)
        watchdog.dataReceived(at: at(5))
        XCTAssertTrue(watchdog.shouldRestart(at: at(16), isActive: true))
    }

    func testRestartResetsTheDataTimer() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: true)
        watchdog.started(at: at(30))
        XCTAssertFalse(watchdog.shouldRestart(at: at(35), isActive: true))
    }

    func testNoDataIsIgnoredWhenDataIsNotChecked() {
        let watchdog = RestartWatchdog(startedAt: start, checksData: false)
        XCTAssertFalse(watchdog.shouldRestart(at: at(60), isActive: true))
    }

    // MARK: - Active

    func testInactiveRestarts() {
        let watchdog = RestartWatchdog(startedAt: start, checksData: false)
        XCTAssertTrue(watchdog.shouldRestart(at: at(10), isActive: false))
    }

    func testInactiveRightAfterAStartIsGivenTimeToStart() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: false)
        watchdog.started(at: at(30))
        XCTAssertFalse(watchdog.shouldRestart(at: at(35), isActive: false))
    }

    // MARK: - Stalls

    func testFirstStartIsNotARestart() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: true)
        watchdog.started(at: at(1))
        XCTAssertEqual(watchdog.restartsWithoutData, 0)
        XCTAssertFalse(watchdog.isStalled)
    }

    func testRestartsWithNoDataBetweenThemStall() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: true)
        watchdog.started(at: at(1))
        watchdog.started(at: at(11))
        watchdog.started(at: at(21))
        XCTAssertEqual(watchdog.restartsWithoutData, 2)
        XCTAssertFalse(watchdog.isStalled)
        watchdog.started(at: at(31))
        XCTAssertEqual(watchdog.restartsWithoutData, RestartWatchdog.stallRestarts)
        XCTAssertTrue(watchdog.isStalled)
    }

    func testDataBetweenRestartsResetsTheCount() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: true)
        watchdog.started(at: at(1))
        watchdog.started(at: at(11))
        watchdog.started(at: at(21))
        watchdog.dataReceived(at: at(22))
        watchdog.started(at: at(40))
        XCTAssertEqual(watchdog.restartsWithoutData, 0)
    }

    func testReportedStallCountsAgainFromZero() {
        var watchdog = RestartWatchdog(startedAt: start, checksData: true)
        for second in stride(from: 1, through: 31, by: 10) {
            watchdog.started(at: at(TimeInterval(second)))
        }
        XCTAssertTrue(watchdog.isStalled)
        watchdog.stallReported()
        XCTAssertFalse(watchdog.isStalled)
        watchdog.started(at: at(41))
        XCTAssertEqual(watchdog.restartsWithoutData, 1)
    }
}
