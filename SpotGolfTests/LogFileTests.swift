import CourseDataSwift
import XCTest
@testable import SpotGolf

/// `LogFile` appends lines, rotates by size, keeps a set number of older files, and reads
/// them back oldest first. `LogShare` gzips them into one file.
final class LogFileTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func line(_ message: String) -> LogLine {
        LogLine(timestamp: Date(timeIntervalSince1970: 1_700_000_000), device: .phone, level: .notice,
                category: "sync", roundID: nil, message: message)
    }

    private func text(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testLinesAreAppendedOnePerLine() {
        let file = LogFile(directory: folder)
        file.write(line("a"))
        file.write(line("b"))

        XCTAssertEqual(text(file.currentURL), line("a").text + "\n" + line("b").text + "\n")
        XCTAssertEqual(file.files(), [file.currentURL])
    }

    func testAFileThatWouldGoPastTheLimitRotates() {
        let size = line("a").text.utf8.count + 1
        let file = LogFile(directory: folder, maxFileBytes: size * 2, keptFiles: 2)

        file.write(line("a"))
        file.write(line("b"))
        file.write(line("c"))

        XCTAssertEqual(text(file.url(index: 1)), line("a").text + "\n" + line("b").text + "\n")
        XCTAssertEqual(text(file.currentURL), line("c").text + "\n")
    }

    func testOnlyKeptFilesStayAndTheOldestGoes() {
        let file = LogFile(directory: folder, maxFileBytes: 10, keptFiles: 2)

        for message in ["a", "b", "c", "d"] {
            file.write(line(message))
        }

        XCTAssertEqual(file.files(), [file.url(index: 2), file.url(index: 1), file.currentURL])
        XCTAssertEqual(String(decoding: file.allData(), as: UTF8.self),
                       ["b", "c", "d"].map { line($0).text + "\n" }.joined())
    }

    func testWithNoKeptFilesAFullFileStartsOver() {
        let file = LogFile(directory: folder, maxFileBytes: 10, keptFiles: 0)

        file.write(line("a"))
        file.write(line("b"))

        XCTAssertEqual(file.files(), [file.currentURL])
        XCTAssertEqual(text(file.currentURL), line("b").text + "\n")
    }

    func testAFileLeftFullByTheLastLaunchRotatesBeforeTheNextLine() {
        let size = line("a").text.utf8.count + 1
        LogFile(directory: folder, maxFileBytes: size, keptFiles: 1).write(line("a"))

        let relaunched = LogFile(directory: folder, maxFileBytes: size, keptFiles: 1)
        relaunched.write(line("b"))

        XCTAssertEqual(text(relaunched.url(index: 1)), line("a").text + "\n")
        XCTAssertEqual(text(relaunched.currentURL), line("b").text + "\n")
    }

    func testTheSizeContinuesFromWhatTheLastLaunchWrote() {
        LogFile(directory: folder).write(line("a"))

        XCTAssertEqual(LogFile(directory: folder).currentSize, line("a").text.utf8.count + 1)
    }

    func testMovingTheCurrentFileStartsANewOne() throws {
        let file = LogFile(directory: folder)
        let destination = folder.appendingPathComponent("outbox/chunk.log")
        file.write(line("a"))

        XCTAssertTrue(file.moveCurrent(to: destination))
        file.write(line("b"))

        XCTAssertEqual(text(destination), line("a").text + "\n")
        XCTAssertEqual(text(file.currentURL), line("b").text + "\n")
        XCTAssertEqual(file.currentSize, line("b").text.utf8.count + 1)
    }

    func testAnEmptyFileIsNotMoved() {
        let file = LogFile(directory: folder)

        XCTAssertFalse(file.moveCurrent(to: folder.appendingPathComponent("outbox/chunk.log")))
    }

    func testSharedLogIsEveryFileGzipped() throws {
        let file = LogFile(directory: folder, maxFileBytes: 10, keptFiles: 4)
        for message in ["a", "b", "c"] {
            file.write(line(message))
        }

        let url = try LogShare.gzip(file, into: folder, now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(url.lastPathComponent.hasPrefix("SpotGolf-log-2023-11-"))
        XCTAssertEqual(url.pathExtension, "gz")
        XCTAssertEqual(try Data(contentsOf: url).gzipDecompressed(), file.allData())
    }
}
