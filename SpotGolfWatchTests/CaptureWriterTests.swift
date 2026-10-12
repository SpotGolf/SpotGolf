import XCTest
@testable import SpotGolfWatch

@MainActor
final class CaptureWriterTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-writer-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func meta(hole: Int = 2, segment: Int = 1) -> PuttCapture.Meta {
        // An exact start, so times since it print exactly
        var meta = PuttCapture.Meta(startDate: Date(timeIntervalSince1970: 1_700_000_000), startUptime: 1000)
        meta.captureID = UUID()
        meta.roundID = UUID()
        meta.hole = hole
        meta.segment = segment
        return meta
    }

    private func readMeta(in directory: URL) throws -> PuttCapture.Meta {
        try PuttCapture.Meta(json: Data(contentsOf: directory.appendingPathComponent(PuttCapture.metaFile)))
    }

    private func finish(_ writer: CaptureWriter, reason: PuttCapture.EndReason) -> PuttCapture.Meta {
        let done = expectation(description: "finished")
        var result: PuttCapture.Meta?
        writer.finish(reason: reason, battery: 0.5) { meta in
            result = meta
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result!
    }

    func testSegmentStartsWithItsSixFilesAndDetails() throws {
        let directory = root.appendingPathComponent(PuttCapture.segmentFolder(1, hole: 2))
        let meta = meta()

        _ = try CaptureWriter(directory: directory, meta: meta, savesData: true, microphone: false)

        for name in [PuttCapture.metaFile, PuttCapture.marksFile, PuttCapture.contactsFile, PuttCapture.accelFile, PuttCapture.motionFile] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path), name)
        }
        let written = try readMeta(in: directory)
        XCTAssertEqual(written.captureID, meta.captureID)
        XCTAssertEqual(written.roundID, meta.roundID)
        XCTAssertEqual(written.hole, 2)
        XCTAssertEqual(written.segment, 1)
        XCTAssertNil(written.endDate)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(PuttCapture.marksFile), encoding: .utf8), "t,label,date\n")
    }

    func testBatteryTestWritesNoReadings() throws {
        let directory = root.appendingPathComponent("segment")

        _ = try CaptureWriter(directory: directory, meta: meta(), savesData: false, microphone: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(PuttCapture.accelFile).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(PuttCapture.motionFile).path))
    }

    func testMarksAreWrittenAndTheLastOneUndone() throws {
        let directory = root.appendingPathComponent("segment")
        let writer = try CaptureWriter(directory: directory, meta: meta(), savesData: true, microphone: false)

        writer.mark(.putt, date: Date(timeIntervalSince1970: 1_700_000_010))
        writer.mark(.practice, date: Date(timeIntervalSince1970: 1_700_000_020))
        writer.undoLastMark()
        let meta = finish(writer, reason: .stopped)

        XCTAssertEqual(meta.marks.map(\.label), [.putt])
        let lines = try String(contentsOf: directory.appendingPathComponent(PuttCapture.marksFile), encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasSuffix(",putt,2023-11-14T22:13:30.000Z"), String(lines[1]))
    }

    func testContactsAreWrittenAtTheSegmentsClock() throws {
        let directory = root.appendingPathComponent("segment")
        let writer = try CaptureWriter(directory: directory, meta: meta(), savesData: true, microphone: false)

        writer.add(contact: ContactDetector.Contact(time: writer.startUptime + 1.5, score: 3.25, burst: 0.5, click: 6.5, turning: 1))
        _ = finish(writer, reason: .stopped)

        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(PuttCapture.contactsFile), encoding: .utf8),
                       "t,score,burst,click,turning\n1.5,3.25,0.5,6.5,1.0\n")
    }

    func testFinishCompletesTheDetails() throws {
        let directory = root.appendingPathComponent("segment")
        let writer = try CaptureWriter(directory: directory, meta: meta(), savesData: true, microphone: false)

        let meta = finish(writer, reason: .leftGreen)

        XCTAssertEqual(meta.endReason, .leftGreen)
        XCTAssertEqual(meta.endBattery, 0.5)
        XCTAssertNotNil(meta.endDate)
        XCTAssertGreaterThanOrEqual(meta.duration ?? -1, 0)
        XCTAssertEqual(meta.accelCount, 0)
        // JSON keeps dates to the second
        let written = try readMeta(in: directory)
        XCTAssertEqual(written.endReason, .leftGreen)
        XCTAssertEqual(written.endBattery, 0.5)
        XCTAssertEqual(written.endDate?.timeIntervalSince1970 ?? 0, meta.endDate?.timeIntervalSince1970 ?? 1, accuracy: 1)
    }

    func testSegmentLeftOpenIsFinishedFromItsFiles() throws {
        let capture = root.appendingPathComponent(UUID().uuidString)
        let open = capture.appendingPathComponent(PuttCapture.segmentFolder(1, hole: 3))
        let closed = capture.appendingPathComponent(PuttCapture.segmentFolder(2, hole: 4))
        _ = try CaptureWriter(directory: open, meta: meta(hole: 3), savesData: true, microphone: false)
        // Forty readings' worth of accelerometer bytes, written as if by the sensor
        try Data(count: 40 * PuttCapture.AccelSample.size).write(to: open.appendingPathComponent(PuttCapture.accelFile))
        try Data(count: 7 * PuttCapture.MotionSample.size).write(to: open.appendingPathComponent(PuttCapture.motionFile))
        _ = finish(try CaptureWriter(directory: closed, meta: meta(hole: 4, segment: 2), savesData: true, microphone: false),
                   reason: .stopped)
        let finished = try readMeta(in: closed)

        CaptureWriter.finishUnfinished(under: root)

        let recovered = try readMeta(in: open)
        XCTAssertEqual(recovered.endReason, .appTerminated)
        XCTAssertEqual(recovered.accelCount, 40)
        XCTAssertEqual(recovered.motionCount, 7)
        XCTAssertNotNil(recovered.endDate)
        XCTAssertEqual(try readMeta(in: closed), finished, "A finished segment is left alone")
    }
}
