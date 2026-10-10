import os
import XCTest
@testable import SpotGolf

/// `Log` writes every line to its sink, holds lines until a sink is set, and drops debug
/// lines unless debug logging is on.
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
    private var wasDebugEnabled = false

    override func setUp() {
        super.setUp()
        wasDebugEnabled = Log.isDebugEnabled
        Log.isDebugEnabled = false
        collector = Collector()
        let collector = collector!
        Log.setSink { collector.append($0) }
    }

    override func tearDown() {
        Log.setSink(nil)
        Log.isDebugEnabled = wasDebugEnabled
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

    func testDebugLinesAreDroppedUnlessDebugLoggingIsOn() {
        var built = 0
        func detail() -> String {
            built += 1
            return text("detail")
        }

        Log.swings.debug(detail())
        XCTAssertTrue(collector.all.isEmpty)
        // The text is not even built
        XCTAssertEqual(built, 0)

        Log.isDebugEnabled = true
        Log.swings.debug(detail())

        XCTAssertEqual(collector.all.map(\.message), [text("detail")])
        XCTAssertEqual(collector.all.map(\.level), [.debug])
        XCTAssertEqual(built, 1)
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

    func testExportedLineFormat() {
        let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_700_000_000.125), device: .watch,
                           level: .error, category: "sensors", message: "accelerometer stopped on an error; restarting")

        XCTAssertEqual(line.text, "2023-11-14T22:13:20.125Z watch E sensors accelerometer stopped on an error; restarting")
    }
}
