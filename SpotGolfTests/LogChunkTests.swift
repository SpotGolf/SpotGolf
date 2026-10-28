import XCTest
@testable import SpotGolf

/// The watch closes its log into chunks and sends them; the phone adds each chunk once.
@MainActor
final class LogChunkTests: XCTestCase {
    private var folder: URL!
    private var transport: FakeTransport!
    private var file: LogFile!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        transport = FakeTransport()
        file = LogFile(directory: folder.appendingPathComponent("log"), maxFileBytes: LogChunkSender.maxFileBytes, keptFiles: 0)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        try await super.tearDown()
    }

    private func sender(maxChunkAge: TimeInterval = LogChunkSender.maxChunkAge) -> LogChunkSender {
        LogChunkSender(file: file, transport: transport, outbox: folder.appendingPathComponent("outbox"),
                       maxChunkAge: maxChunkAge)
    }

    private func line(_ message: String) -> LogLine {
        LogLine(timestamp: Date(timeIntervalSince1970: 1_700_000_000), device: .watch, level: .notice,
                category: "sensors", roundID: nil, message: message)
    }

    // MARK: - Watch

    func testAChunkClosesOnceItIsFull() {
        let sender = sender()
        let message = String(repeating: "x", count: 1_000)
        while file.currentSize < LogChunkSender.maxChunkBytes - 1_100 {
            file.write(line(message))
            sender.lineWritten()
        }
        XCTAssertTrue(sender.chunks().isEmpty)

        file.write(line(message))
        file.write(line(message))
        sender.lineWritten()

        XCTAssertEqual(sender.chunks().count, 1)
        XCTAssertEqual(transport.outstandingFileTransfers.count, 1)
        XCTAssertEqual(file.currentSize, 0)
    }

    func testAChunkClosesOnceItsFirstLineIsOldEnough() async throws {
        let sender = sender(maxChunkAge: 0.05)
        file.write(line("a"))
        sender.lineWritten()
        XCTAssertTrue(sender.chunks().isEmpty)

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(sender.chunks().count, 1)
    }

    func testAnEmptyLogSendsNothing() {
        let sender = sender()

        sender.closeChunk()

        XCTAssertTrue(sender.chunks().isEmpty)
        XCTAssertTrue(transport.outstandingFileTransfers.isEmpty)
    }

    func testAChunkIsSentWithItsName() {
        let sender = sender()
        file.write(line("a"))

        sender.closeChunk(now: Date(timeIntervalSince1970: 1_700_000_000))

        let name = sender.chunks().first?.lastPathComponent
        XCTAssertTrue(name?.hasPrefix("20231114-221320-") ?? false, name ?? "no chunk")
        XCTAssertEqual(transport.outstandingFileTransfers.map { $0[LogChunk.FileKey.chunk] as? String }, [name])
    }

    func testAnArrivedChunkIsDeletedAndAFailedOneKept() {
        let sender = sender()
        file.write(line("a"))
        sender.closeChunk(now: Date(timeIntervalSince1970: 1))
        file.write(line("b"))
        sender.closeChunk(now: Date(timeIntervalSince1970: 2))
        let names = sender.chunks().map(\.lastPathComponent)

        XCTAssertTrue(sender.transferFinished([LogChunk.FileKey.chunk: names[0]], error: FakeTransportError()))
        XCTAssertTrue(sender.transferFinished([LogChunk.FileKey.chunk: names[1]], error: nil))

        XCTAssertEqual(sender.chunks().map(\.lastPathComponent), [names[0]])
    }

    func testAnotherFilesTransferIsNotTheSenders() {
        XCTAssertFalse(sender().transferFinished([PuttSharing.FileKey.sessionID: "abc"], error: nil))
    }

    func testTheOldestChunksGoPastTheOutboxLimit() {
        let sender = sender()
        let message = String(repeating: "x", count: 1_000)
        let chunkCount = LogChunkSender.maxOutboxBytes / 200_000 + 2
        for index in 0..<chunkCount {
            for _ in 0..<200 {
                file.write(line(message))
            }
            sender.closeChunk(now: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        let total = sender.chunks().reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        XCTAssertLessThanOrEqual(total, LogChunkSender.maxOutboxBytes)
        XCTAssertLessThan(sender.chunks().count, chunkCount)
        XCTAssertTrue(sender.chunks().last?.lastPathComponent.hasPrefix(String(format: "19700101-0000%02d-", chunkCount - 1)) ?? false,
                      "The newest is kept")
    }

    // MARK: - Phone

    private func receiver() -> (LogChunkReceiver, LogFile) {
        let phoneFile = LogFile(directory: folder.appendingPathComponent("phone"))
        return (LogChunkReceiver(file: phoneFile, defaults: UserDefaults(suiteName: UUID().uuidString)!), phoneFile)
    }

    private func chunk(_ text: String) throws -> URL {
        let url = folder.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testAChunkIsAddedToThePhoneLogAndItsFileDeleted() throws {
        let (receiver, phoneFile) = receiver()
        let url = try chunk("a\nb\n")

        receiver.receive(url, name: "1.log")

        XCTAssertEqual(String(decoding: phoneFile.allData(), as: UTF8.self), "a\nb\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAChunkReceivedTwiceIsAddedOnce() throws {
        let (receiver, phoneFile) = receiver()

        receiver.receive(try chunk("a\n"), name: "1.log")
        receiver.receive(try chunk("a\n"), name: "1.log")

        XCTAssertEqual(String(decoding: phoneFile.allData(), as: UTF8.self), "a\n")
    }

    func testAChunkWithNoLastNewlineGetsOne() throws {
        let (receiver, phoneFile) = receiver()

        receiver.receive(try chunk("a"), name: "1.log")
        receiver.receive(try chunk("b\n"), name: "2.log")

        XCTAssertEqual(String(decoding: phoneFile.allData(), as: UTF8.self), "a\nb\n")
    }

    func testOnlyTheLastNamesAreRemembered() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let receiver = LogChunkReceiver(file: LogFile(directory: folder.appendingPathComponent("phone")), defaults: defaults)

        for index in 0...LogChunkReceiver.seenLimit {
            receiver.receive(try chunk("\(index)\n"), name: "\(index).log")
        }

        let seen = defaults.stringArray(forKey: LogChunkReceiver.seenKey) ?? []
        XCTAssertEqual(seen.count, LogChunkReceiver.seenLimit)
        XCTAssertFalse(seen.contains("0.log"))
        XCTAssertTrue(seen.contains("\(LogChunkReceiver.seenLimit).log"))
    }
}
