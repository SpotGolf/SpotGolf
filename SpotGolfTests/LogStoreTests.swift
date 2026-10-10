import SwiftData
import XCTest
@testable import SpotGolf

@MainActor
final class LogStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var store: LogStore!
    private let roundID = UUID()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        container = Storage.inMemoryContainer()
        store = LogStore(context: ModelContext(container), outsideLimit: 5)
    }

    override func tearDown() async throws {
        store = nil
        container = nil
        try await super.tearDown()
    }

    private func line(_ second: TimeInterval, _ message: String, device: LogDevice = .phone,
                      level: LogLevel = .notice, category: String = "sync") -> LogLine {
        LogLine(timestamp: start.addingTimeInterval(second), device: device, level: level,
                category: category, message: message)
    }

    // MARK: - Numbering

    func testLinesAreNumberedPerRoundAndDevice() {
        store.append([line(0, "p0"), line(1, "w0", device: .watch), line(2, "p1")], roundID: roundID)
        store.append([line(3, "w1", device: .watch)], roundID: roundID)
        store.append([line(4, "o0")], roundID: nil)

        XCTAssertEqual(store.count(for: roundID, device: .phone), 2)
        XCTAssertEqual(store.count(for: roundID, device: .watch), 2)
        XCTAssertEqual(store.count(for: nil, device: .phone), 1)
        XCTAssertEqual(store.lines(for: roundID, device: .watch, from: 0, limit: 10, maxBytes: 10_000).map(\.message), ["w0", "w1"])
        XCTAssertEqual(store.lines(for: roundID, device: .watch, from: 1, limit: 10, maxBytes: 10_000).map(\.message), ["w1"])
        XCTAssertTrue(store.hasLines(for: roundID))
        XCTAssertFalse(store.hasLines(for: UUID()))
    }

    func testNumberingSurvivesANewStore() {
        store.append([line(0, "w0", device: .watch)], roundID: roundID)

        let reopened = LogStore(context: ModelContext(container))
        reopened.append([line(1, "w1", device: .watch)], roundID: roundID)

        XCTAssertEqual(reopened.count(for: roundID, device: .watch), 2)
        XCTAssertEqual(reopened.lines(for: roundID, device: .watch, from: 1, limit: 10, maxBytes: 10_000).map(\.message), ["w1"])
    }

    // MARK: - Reading

    func testLinesAreReadInTimeOrderAcrossDevices() {
        store.append([line(2, "p2"), line(0, "p0")], roundID: roundID)
        store.append([line(1, "w1", device: .watch)], roundID: roundID)
        store.append([line(5, "outside")], roundID: nil)

        XCTAssertEqual(store.lines(for: roundID).map(\.message), ["p0", "w1", "p2"])
        XCTAssertEqual(store.lines(for: nil).map(\.message), ["outside"])
    }

    func testBatchLinesAreCappedByCountAndBytes() {
        store.append((0..<10).map { line(TimeInterval($0), String(repeating: "x", count: 100), device: .watch) }, roundID: roundID)

        XCTAssertEqual(store.lines(for: roundID, device: .watch, from: 0, limit: 3, maxBytes: 100_000).count, 3)
        // About 150 bytes a line: three fit, and the fourth goes over
        XCTAssertEqual(store.lines(for: roundID, device: .watch, from: 0, limit: 10, maxBytes: 450).count, 3)
        // At least one line always goes
        XCTAssertEqual(store.lines(for: roundID, device: .watch, from: 0, limit: 10, maxBytes: 1).count, 1)
    }

    // MARK: - Retention

    func testLinesOutsideARoundAreTrimmedToTheLimitAndKeepCountingUp() {
        store.append((0..<8).map { line(TimeInterval($0), "o\($0)") }, roundID: nil)

        XCTAssertEqual(store.count(for: nil, device: .phone), 5)
        XCTAssertEqual(store.lines(for: nil).map(\.message), ["o3", "o4", "o5", "o6", "o7"])

        store.append([line(8, "o8")], roundID: nil)

        XCTAssertEqual(store.lines(for: nil).map(\.message), ["o4", "o5", "o6", "o7", "o8"])
        XCTAssertEqual(store.count(for: nil, device: .phone), 5)
    }

    func testRoundLinesAreNotTrimmed() {
        store.append((0..<8).map { line(TimeInterval($0), "r\($0)") }, roundID: roundID)

        XCTAssertEqual(store.count(for: roundID, device: .phone), 8)
    }

    func testDeleteRemovesOnlyTheRoundsLines() {
        let other = UUID()
        store.append([line(0, "mine")], roundID: roundID)
        store.append([line(1, "theirs")], roundID: other)
        store.append([line(2, "outside")], roundID: nil)

        store.delete(roundID)

        XCTAssertFalse(store.hasLines(for: roundID))
        XCTAssertEqual(store.lines(for: other).map(\.message), ["theirs"])
        XCTAssertEqual(store.lines(for: nil).map(\.message), ["outside"])
        XCTAssertEqual(store.count(for: roundID, device: .phone), 0)
    }

    func testRecentLinesMoveIntoTheRoundAfterItsOwn() {
        let now = start.addingTimeInterval(600)
        store.append([line(0, "old"), line(500, "recent"), line(550, "newer")], roundID: nil)
        store.append([line(590, "first")], roundID: roundID)

        store.moveRecentLines(into: roundID, age: 120, now: now)

        XCTAssertEqual(store.lines(for: roundID).map(\.message), ["recent", "newer", "first"])
        XCTAssertEqual(store.lines(for: nil).map(\.message), ["old"])
        XCTAssertEqual(store.count(for: roundID, device: .phone), 3)
        XCTAssertEqual(store.count(for: nil, device: .phone), 1)
        // Numbered after the round's own line
        XCTAssertEqual(store.lines(for: roundID, device: .phone, from: 1, limit: 10, maxBytes: 10_000).map(\.message), ["recent", "newer"])
    }

    // MARK: - Sink

    func testEnqueuedLinesGetTheRoundInProgressAndAreSavedOnFlush() {
        var current: UUID? = roundID
        store.roundIDForNewLines = { current }
        var flushes = 0
        store.onFlush = { flushes += 1 }

        store.enqueue(line(0, "in round"))
        current = nil
        store.enqueue(line(1, "outside"))
        XCTAssertTrue(store.lines(for: roundID).isEmpty)

        store.flush()

        XCTAssertEqual(store.lines(for: roundID).map(\.message), ["in round"])
        XCTAssertEqual(store.lines(for: nil).map(\.message), ["outside"])
        XCTAssertEqual(flushes, 1)

        // Nothing waiting: no save, no callback
        store.flush()
        XCTAssertEqual(flushes, 1)
    }

    func testEnqueuedLinesAreSavedAfterTheFlushInterval() async throws {
        store.enqueue(line(0, "later"))

        try await Task.sleep(for: .seconds(LogStore.flushInterval + 0.5))

        XCTAssertEqual(store.lines(for: nil).map(\.message), ["later"])
    }

    // MARK: - Export

    func testExportIsOneLineEach() {
        let lines = [line(0, "one", device: .watch, level: .notice, category: "rounds"),
                     line(1.5, "two", level: .error)]

        XCTAssertEqual(LogStore.text(lines), """
            2023-11-14T22:13:20.000Z watch N rounds one
            2023-11-14T22:13:21.500Z phone E sync two

            """)
        XCTAssertEqual(LogStore.text([]), "")
    }
}
