import AVFAudio
import CoreLocation
import SensorSources
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

    func testSegmentStartsWithItsFilesAndDetails() throws {
        let directory = root.appendingPathComponent(PuttCapture.segmentFolder(1, hole: 2))
        let meta = meta()

        _ = try CaptureWriter(directory: directory, meta: meta, savesData: true, microphone: false)

        for name in [PuttCapture.metaFile, PuttCapture.marksFile, PuttCapture.contactsFile, PuttCapture.candidatesFile,
                     PuttCapture.eventsFile, PuttCapture.locationsFile, PuttCapture.accelFile, PuttCapture.motionFile] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path), name)
        }
        let written = try readMeta(in: directory)
        XCTAssertEqual(written.captureID, meta.captureID)
        XCTAssertEqual(written.roundID, meta.roundID)
        XCTAssertEqual(written.hole, 2)
        XCTAssertEqual(written.segment, 1)
        XCTAssertEqual(written.version, 3)
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

    /// meta.json's marks keep their milliseconds, so they match the round's stream.
    func testMarkDatesKeepTheirMilliseconds() throws {
        let directory = root.appendingPathComponent("segment")
        let writer = try CaptureWriter(directory: directory, meta: meta(), savesData: true, microphone: false)

        writer.mark(.putt, date: Date(timeIntervalSince1970: 1_700_000_010.123))
        _ = finish(writer, reason: .stopped)

        let mark = try XCTUnwrap(try readMeta(in: directory).marks.first)
        XCTAssertEqual(mark.date.timeIntervalSince1970, 1_700_000_010.123, accuracy: 0.001)
    }

    /// Version 2 wrote dates to the second.
    func testDetailsWithoutMillisecondsAreRead() throws {
        let json = #"{"id":"6E4D6F3A-58D5-4E44-9E3B-6E0A3C1D2B10","version":2,"startDate":"2026-10-13T20:17:40Z","startUptime":1,"accelCount":0,"motionCount":0,"audioFrames":0,"marks":[]}"#

        let meta = try PuttCapture.Meta(json: Data(json.utf8))

        XCTAssertEqual(meta.startDate, Date(timeIntervalSince1970: 1_791_922_660))
        XCTAssertNil(meta.wristLocation)
    }

    func testCandidatesAreWrittenWithTheGatesMeasures() throws {
        let directory = root.appendingPathComponent("segment")
        let writer = try CaptureWriter(directory: directory, meta: meta(), savesData: true, microphone: false)
        let features = StrokeGate.Features(still: 0.05, tilt: 1.5, backswing: 12, returnOffset: 0.01)

        writer.add(candidate: ContactDetector.Judged(time: writer.startUptime + 2, burst: 0.5, click: 20, onset: 8, score: 10,
                                                     features: features))
        writer.add(candidate: ContactDetector.Judged(time: writer.startUptime + 3, burst: 0.25, click: 4, onset: 5, score: 1,
                                                     features: nil))
        _ = finish(writer, reason: .stopped)

        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(PuttCapture.candidatesFile), encoding: .utf8),
                       "t,burst,click,onset,score,still,tilt,backswing,returnOffset,passed\n"
                       + "2.0,0.5,20.0,8.0,10.0,0.05,1.5,12.0,0.01,1\n3.0,0.25,4.0,5.0,1.0,,,,,0\n")
    }

    func testEventsAreWrittenAtTheSegmentsClock() throws {
        let directory = root.appendingPathComponent("segment")
        let writer = try CaptureWriter(directory: directory, meta: meta(), savesData: true, microphone: false)

        writer.add(event: "tap", value: 0, atUptime: writer.startUptime + 1.5)
        writer.add(event: "swing", value: 12.5, at: writer.startDate.addingTimeInterval(4.25))
        _ = finish(writer, reason: .stopped)

        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(PuttCapture.eventsFile), encoding: .utf8),
                       "t,event,value\n1.5,tap,0.0\n4.25,swing,12.5\n")
    }

    func testLocationsLeaveUnknownValuesBlank() throws {
        let directory = root.appendingPathComponent("segment")
        let writer = try CaptureWriter(directory: directory, meta: meta(), savesData: true, microphone: false)
        let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 39.25, longitude: -104.5), altitude: 2000,
                             horizontalAccuracy: 4.5, verticalAccuracy: -1, course: 90, speed: -1,
                             timestamp: writer.startDate.addingTimeInterval(2))

        writer.add(locations: [fix])
        _ = finish(writer, reason: .stopped)

        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(PuttCapture.locationsFile), encoding: .utf8),
                       PuttCapture.locationsHeader + "\n2.0,39.25,-104.5,,4.5,,,90.0\n")
    }

    func testAudioBuffersAreListedWithTheirFirstFrame() throws {
        let directory = root.appendingPathComponent("segment")
        let writer = try CaptureWriter(directory: directory, meta: meta(), savesData: true, microphone: true)
        let samples = [Float](repeating: 0.25, count: 4096)

        writer.add(audio: AudioSample(hostTime: writer.startUptime + 1, sampleRate: 48_000, samples: samples))
        writer.add(audio: AudioSample(hostTime: writer.startUptime + 2, sampleRate: 48_000, samples: samples))
        let meta = finish(writer, reason: .stopped)

        XCTAssertEqual(meta.audioFrames, 8192)
        let file = try AVAudioFile(forReading: directory.appendingPathComponent(PuttCapture.audioFile))
        XCTAssertEqual(file.length, 8192)
        XCTAssertEqual(file.fileFormat.sampleRate, 48_000)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent(PuttCapture.audioBuffersFile), encoding: .utf8),
                       "t,frames,firstFrame\n1.0,4096,0\n2.0,4096,4096\n")
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
        // JSON keeps dates to the millisecond
        let written = try readMeta(in: directory)
        XCTAssertEqual(written.endReason, .leftGreen)
        XCTAssertEqual(written.endBattery, 0.5)
        XCTAssertEqual(written.endDate?.timeIntervalSince1970 ?? 0, meta.endDate?.timeIntervalSince1970 ?? 1, accuracy: 0.001)
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
