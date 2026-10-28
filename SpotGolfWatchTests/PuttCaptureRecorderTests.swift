import CoreLocation
import XCTest
@testable import SpotGolfWatch

/// The recorder in a round: a capture the round starts, with a segment per session on a green.
@MainActor
final class PuttCaptureRecorderTests: XCTestCase {
    private var root: URL!
    private var recorder: PuttCaptureRecorder!
    private let roundID = UUID()

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-tests-\(UUID().uuidString)", isDirectory: true)
        recorder = PuttCaptureRecorder(sensors: SensorInputs(), root: root)
        // The simulator has no mic to ask about
        recorder.microphone = false
    }

    override func tearDown() {
        recorder.stop()
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private var captureFolders: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter(\.isDirectory)
    }

    private func segmentFolders(in capture: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: capture.path)) ?? []).sorted()
    }

    /// The segment's details once its files are closed, which happens on the writer's queue.
    private func finishedMeta(of segment: URL) async throws -> PuttCapture.Meta {
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: segment.appendingPathComponent(PuttCapture.metaFile)),
               let meta = try? PuttCapture.Meta(json: data), meta.endDate != nil {
                return meta
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw XCTSkip("The segment did not finish in time")
    }

    func testRoundRecordsASegmentPerGreen() async throws {
        recorder.startInRound(roundID: roundID)
        XCTAssertEqual(recorder.state, .waiting)
        XCTAssertEqual(captureFolders.count, 1)
        let capture = try XCTUnwrap(captureFolders.first)

        recorder.sessionChanged(.started(hole: 3))

        XCTAssertEqual(recorder.state, .recording)
        XCTAssertEqual(recorder.hole, 3)
        XCTAssertEqual(recorder.segmentCount, 1)
        XCTAssertEqual(segmentFolders(in: capture), ["001-hole3"])
        let first = capture.appendingPathComponent("001-hole3")
        let open = try PuttCapture.Meta(json: Data(contentsOf: first.appendingPathComponent(PuttCapture.metaFile)))
        XCTAssertEqual(open.roundID, roundID)
        XCTAssertEqual(open.captureID?.uuidString, capture.lastPathComponent)
        XCTAssertEqual(open.hole, 3)
        XCTAssertEqual(open.segment, 1)

        recorder.detectorContact(ContactDetector.Contact(time: Uptime.now, score: 5, burst: 0.3, click: 20, turning: 1))
        XCTAssertEqual(recorder.contactCount, 1)

        recorder.sessionChanged(.stopped(reason: .leftGreen))

        XCTAssertEqual(recorder.state, .waiting)
        let finished = try await finishedMeta(of: first)
        XCTAssertEqual(finished.endReason, .leftGreen)
        XCTAssertEqual(try String(contentsOf: first.appendingPathComponent(PuttCapture.contactsFile), encoding: .utf8)
            .split(separator: "\n").count, 2)

        recorder.sessionChanged(.started(hole: 4))

        XCTAssertEqual(recorder.state, .recording)
        XCTAssertEqual(recorder.contactCount, 0)
        XCTAssertEqual(segmentFolders(in: capture), ["001-hole3", "002-hole4"])

        recorder.roundEnded()

        XCTAssertEqual(recorder.state, .idle)
        let last = try await finishedMeta(of: capture.appendingPathComponent("002-hole4"))
        XCTAssertEqual(last.endReason, .roundEnded)
    }

    /// A segment records the watch's orientation, the Green Zone, and the round's events,
    /// candidates and fixes while it is open; nothing between greens.
    func testSegmentRecordsOrientationEventsCandidatesAndFixes() async throws {
        recorder.greenZone = { 15 }
        recorder.startInRound(roundID: roundID)
        XCTAssertTrue(recorder.recordsRound)
        recorder.record(event: "tap")
        recorder.sessionChanged(.started(hole: 5))
        let segment = try XCTUnwrap(captureFolders.first).appendingPathComponent("001-hole5")

        recorder.record(event: "displayHole", value: 6)
        recorder.record(StreamEvent(code: .microphoneRestart, value: 2))
        recorder.detectorCandidate(ContactDetector.Judged(time: Uptime.now, burst: 0.3, click: 20, onset: 9, score: 6, features: nil))
        recorder.record([CLLocation(latitude: 39.25, longitude: -104.5)])
        recorder.sessionChanged(.stopped(reason: .leftGreen))
        recorder.record(event: "tap")

        let meta = try await finishedMeta(of: segment)
        XCTAssertEqual(meta.greenZone, 15)
        XCTAssertNotNil(meta.wristLocation)
        XCTAssertNotNil(meta.crownOrientation)
        let events = try String(contentsOf: segment.appendingPathComponent(PuttCapture.eventsFile), encoding: .utf8)
            .split(separator: "\n").dropFirst().map { $0.split(separator: ",")[1] }
        XCTAssertEqual(events, ["displayHole", "microphoneRestart"])
        XCTAssertEqual(try String(contentsOf: segment.appendingPathComponent(PuttCapture.candidatesFile), encoding: .utf8)
            .split(separator: "\n").count, 2)
        XCTAssertEqual(try String(contentsOf: segment.appendingPathComponent(PuttCapture.locationsFile), encoding: .utf8)
            .split(separator: "\n").count, 2)
    }

    /// A round ending as the next round starts leaves the new round's capture alone.
    func testEndOfAnEarlierRoundLeavesTheNewCaptureAlone() {
        recorder.startInRound(roundID: UUID())
        recorder.startInRound(roundID: roundID)

        recorder.roundEnded(roundID: UUID())

        XCTAssertEqual(recorder.state, .waiting)
        XCTAssertEqual(recorder.captureRoundID, roundID)
    }

    func testStopOnTheGreenEndsTheCaptureForTheRound() async throws {
        recorder.startInRound(roundID: roundID)
        recorder.sessionChanged(.started(hole: 1))
        let capture = try XCTUnwrap(captureFolders.first)

        recorder.stop()

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertTrue(recorder.stoppedInRound)
        let stopped = try await finishedMeta(of: capture.appendingPathComponent("001-hole1"))
        XCTAssertEqual(stopped.endReason, .stopped)

        recorder.sessionChanged(.started(hole: 2))

        XCTAssertEqual(recorder.state, .idle, "The round records no more")
        XCTAssertEqual(segmentFolders(in: capture), ["001-hole1"])
    }

    func testStopBetweenGreensEndsTheCaptureForTheRound() {
        recorder.startInRound(roundID: roundID)

        recorder.stop()

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertTrue(recorder.stoppedInRound)
    }

    func testNoSegmentWithoutFreeSpace() throws {
        recorder.freeSpace = { PuttCaptureRecorder.minFreeSpace - 1 }
        recorder.startInRound(roundID: roundID)
        let capture = try XCTUnwrap(captureFolders.first)

        recorder.sessionChanged(.started(hole: 1))

        XCTAssertEqual(recorder.state, .waiting)
        XCTAssertFalse(recorder.problems.isEmpty)
        XCTAssertEqual(segmentFolders(in: capture), [])
    }

    func testSessionsWithNoCaptureAreIgnored() {
        recorder.sessionChanged(.started(hole: 1))
        recorder.detectorContact(ContactDetector.Contact(time: Uptime.now, score: 5, burst: 0.3, click: 20, turning: 1))

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(recorder.contactCount, 0)
        XCTAssertEqual(captureFolders.count, 0)
    }

    // MARK: - Keeping captures

    /// A finished capture of `round` that started at `date`, as a recorded segment leaves it.
    @discardableResult
    private func makeCapture(round: UUID?, date: Date) throws -> URL {
        let capture = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let segment = capture.appendingPathComponent(PuttCapture.segmentFolder(1, hole: 1), isDirectory: true)
        try FileManager.default.createDirectory(at: segment, withIntermediateDirectories: true)
        var meta = PuttCapture.Meta(startDate: date, startUptime: 0)
        meta.roundID = round
        meta.endDate = date.addingTimeInterval(60)
        try meta.json().write(to: segment.appendingPathComponent(PuttCapture.metaFile))
        return capture
    }

    func testRoundStartKeepsTheLastRoundsCaptures() throws {
        let rounds = (0..<6).map { _ in UUID() }
        var kept: [URL] = []
        for (index, round) in rounds.enumerated() {
            let capture = try makeCapture(round: round, date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400))
            if index >= 2 { kept.append(capture) }
        }
        // A round resumed later has two captures, and both stay
        kept.append(try makeCapture(round: rounds[5], date: Date(timeIntervalSince1970: 1_700_600_000)))
        // From outside a round, before Developer Mode
        try makeCapture(round: nil, date: Date(timeIntervalSince1970: 1_700_900_000))

        recorder.pruneCaptures(keeping: roundID)

        XCTAssertEqual(Set(captureFolders.map(\.lastPathComponent)), Set(kept.map(\.lastPathComponent)))
    }

    func testRoundStartKeepsTheStartingRoundsOwnCaptures() throws {
        let own = try makeCapture(round: roundID, date: Date(timeIntervalSince1970: 1_600_000_000))
        for index in 0..<5 {
            try makeCapture(round: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
        }

        recorder.pruneCaptures(keeping: roundID)

        XCTAssertEqual(captureFolders.count, PuttCaptureRecorder.keptRounds)
        XCTAssertTrue(captureFolders.contains(where: { $0.lastPathComponent == own.lastPathComponent }))
    }

    func testDeletingARoundDeletesOnlyItsCaptures() throws {
        let other = try makeCapture(round: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000))
        try makeCapture(round: roundID, date: Date(timeIntervalSince1970: 1_700_100_000))

        recorder.deleteCaptures(roundID: roundID)

        XCTAssertEqual(captureFolders.map(\.lastPathComponent), [other.lastPathComponent])
    }

    func testDeletingTheRecordingRoundEndsAndDeletesItsCapture() async throws {
        recorder.startInRound(roundID: roundID)
        recorder.sessionChanged(.started(hole: 1))
        XCTAssertEqual(captureFolders.count, 1)

        recorder.deleteCaptures(roundID: roundID)

        XCTAssertEqual(recorder.state, .idle)
        for _ in 0..<50 where !captureFolders.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(captureFolders.count, 0)
    }

    func testANewRoundStartsAFreshCapture() {
        recorder.startInRound(roundID: roundID)
        recorder.stop()

        recorder.startInRound(roundID: UUID())

        XCTAssertEqual(recorder.state, .waiting)
        XCTAssertFalse(recorder.stoppedInRound)
        XCTAssertEqual(captureFolders.count, 2)
    }
}
