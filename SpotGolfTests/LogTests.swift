import os
import XCTest
@testable import SpotGolf

/// `Log` writes every line to its sink, with the round going, and holds lines until a sink is set.
final class LogTests: XCTestCase {

    /// Lines the sink received, from any thread. Only the test's own: the host app logs too.
    private final class Collector: Sendable {
        static let prefix = "LogTests: "
        private let lines = OSAllocatedUnfairLock(initialState: [LogLine]())
        func append(_ line: LogLine) {
            guard line.message.hasPrefix(Self.prefix) else { return }
            lines.withLock { $0.append(line) }
        }
        var all: [LogLine] { lines.withLock { $0 } }
    }

    private func text(_ message: String) -> String { Collector.prefix + message }

    private var collector: Collector!
    private var roundID: UUID?

    override func setUp() {
        super.setUp()
        roundID = Log.roundID
        Log.roundID = nil
        collector = Collector()
        let collector = collector!
        Log.setSink { collector.append($0) }
    }

    override func tearDown() {
        Log.setSink(nil)
        Log.roundID = roundID
        collector = nil
        super.tearDown()
    }

    func testEveryLevelReachesTheSinkWithItsCategoryAndDevice() {
        Log.sync.notice(text("a notice"))
        Log.sensors.error(text("an error"))
        Log.storage.fault(text("a fault"))

        let lines = collector.all
        XCTAssertEqual(lines.map(\.level), [.notice, .error, .fault])
        XCTAssertEqual(lines.map(\.category), ["sync", "sensors", "storage"])
        XCTAssertEqual(lines.map(\.message), ["a notice", "an error", "a fault"].map(text))
        XCTAssertEqual(lines.map(\.device), [.phone, .phone, .phone])
        XCTAssertLessThan(abs(lines[0].timestamp.timeIntervalSinceNow), 5)
    }

    func testDebugLinesAreAlwaysWritten() {
        Log.swings.debug(text("detail"))

        XCTAssertEqual(collector.all.map(\.message), [text("detail")])
        XCTAssertEqual(collector.all.map(\.level), [.debug])
    }

    func testLinesCarryTheRoundGoingWhenWritten() {
        let id = UUID()
        Log.rounds.notice(text("before"))
        Log.roundID = id
        Log.rounds.notice(text("during"))
        Log.roundID = nil
        Log.rounds.notice(text("after"))

        XCTAssertEqual(collector.all.map(\.roundID), [nil, id, nil])
    }

    func testLinesWrittenBeforeTheSinkIsSetAreHandedOverFirstInOrder() {
        Log.setSink(nil)
        Log.rounds.notice(text("first"))
        Log.rounds.notice(text("second"))
        XCTAssertTrue(collector.all.isEmpty)

        let collector = collector!
        Log.setSink { collector.append($0) }
        Log.rounds.notice(text("third"))

        XCTAssertEqual(collector.all.map(\.message), ["first", "second", "third"].map(text))
    }

    func testHeldLinesAreCapped() {
        Log.setSink(nil)
        for index in 0..<(Log.heldLineLimit + 10) {
            Log.rounds.notice(text("line \(index)"))
        }

        let collector = collector!
        Log.setSink { collector.append($0) }

        // The host app may slip a few lines of its own in among the held ones
        XCTAssertLessThanOrEqual(collector.all.count, Log.heldLineLimit)
        XCTAssertGreaterThan(collector.all.count, Log.heldLineLimit - 20)
        XCTAssertEqual(collector.all.last?.message, text("line \(Log.heldLineLimit + 9)"))
        XCTAssertFalse(collector.all.contains { $0.message == text("line 0") })
    }

    func testLineFormatOutsideARound() {
        let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_700_000_000.125), device: .watch, level: .error,
                           category: "sensors", roundID: nil, message: "accelerometer stopped on an error; restarting")

        XCTAssertEqual(line.text, "2023-11-14T22:13:20.125Z watch E sensors - accelerometer stopped on an error; restarting")
    }

    func testLineFormatInARound() {
        let id = UUID(uuidString: "6F1C2B3A-0000-4000-8000-0000000000A2")!
        let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_700_000_000.125), device: .phone, level: .notice,
                           category: "sync", roundID: id, message: "Watch reachable")

        XCTAssertEqual(line.text, "2023-11-14T22:13:20.125Z phone N sync 6F1C2B3A-0000-4000-8000-0000000000A2 Watch reachable")
    }

    func testNewlinesAndBackslashesInAMessageAreEscaped() {
        let line = LogLine(timestamp: Date(timeIntervalSince1970: 0), device: .phone, level: .error,
                           category: "sync", roundID: nil, message: "first\nsecond \\ third")

        XCTAssertEqual(line.text, "1970-01-01T00:00:00.000Z phone E sync - first\\nsecond \\\\ third")
        XCTAssertFalse(line.text.contains("\n"))
    }
}
