import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// A phone and a watch talking through fake transports: every flow in the messaging plan,
/// with lost, repeated, late, and out-of-order messages.
@MainActor
final class SyncFlowTests: XCTestCase {

    private var pair: SyncPair!

    override func setUp() async throws {
        try await super.setUp()
        pair = SyncPair()
    }

    override func tearDown() async throws {
        pair.cleanUp()
        pair = nil
        try await super.tearDown()
    }

    private func phoneRound(_ id: UUID) -> Round? { pair.phoneRounds.round(id) }
    private func watchRound(_ id: UUID) -> Round? { pair.watchRounds.round(id) }

    private func locations(_ seconds: Range<Int>, from start: Date = StreamFixtures.start) -> [CLLocation] {
        seconds.map { second in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 39.95545, longitude: -105.0422),
                       altitude: 1620, horizontalAccuracy: 5, verticalAccuracy: 3,
                       timestamp: start.addingTimeInterval(TimeInterval(second)))
        }
    }

    // MARK: - Start round

    func testStartRoundBecomesActiveWhenWatchConfirms() throws {
        let id = pair.startRound()

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertNil(pair.phone.startStates[id])
        let watch = try XCTUnwrap(watchRound(id))
        XCTAssertEqual(watch.status, .active)
        XCTAssertEqual(watch.course.name, "Test Course")
        XCTAssertEqual(watch.holeTimeline, phoneRound(id)?.holeTimeline)
        XCTAssertEqual(watch.displayHole, phoneRound(id)?.displayHole)
        XCTAssertEqual(pair.watchAppLaunches, 1)
    }

    func testStartWaitsForUnreachableWatchThenSendsWhenReachable() {
        pair.setReachable(false)

        let id = pair.startRound()

        XCTAssertEqual(phoneRound(id)?.status, .starting)
        XCTAssertEqual(pair.phone.startStates[id], .waiting)
        XCTAssertNil(watchRound(id))

        pair.setReachable(true)

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(watchRound(id)?.status, .active)
    }

    func testStartTimesOutThenRetryWorks() {
        pair.cleanUp()
        pair = SyncPair(startTimeout: 0.05)
        pair.setReachable(false)
        let id = pair.startRound()

        let timedOut = expectation(description: "start timed out")
        Task { @MainActor in
            while pair.phone.startStates[id] != .timedOut {
                try? await Task.sleep(for: .milliseconds(10))
            }
            timedOut.fulfill()
        }
        wait(for: [timedOut], timeout: 2)

        // Once timed out, the phone waits for the user
        pair.setReachable(true)
        XCTAssertEqual(phoneRound(id)?.status, .starting)

        pair.phone.retryStart(id)

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(pair.watchAppLaunches, 2)
    }

    func testWatchOnAnotherVersionRefusesTheRound() {
        pair.watch.version = "0.4.0"

        let id = pair.startRound()

        XCTAssertEqual(phoneRound(id)?.status, .starting)
        XCTAssertEqual(pair.phone.startStates[id], .needsWatchUpdate(watchVersion: "0.4.0"))
        XCTAssertNil(watchRound(id))
    }

    func testRetryAfterUpdatingTheWatchStartsTheRound() {
        pair.watch.version = "0.4.0"
        let id = pair.startRound()
        XCTAssertEqual(pair.phone.startStates[id], .needsWatchUpdate(watchVersion: "0.4.0"))

        pair.watch.version = pair.phone.version
        pair.phone.retryStart(id)

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(watchRound(id)?.status, .active)
        XCTAssertNil(pair.phone.startStates[id])
    }

    func testVersionIsCheckedBeforePermissions() {
        pair.watch.version = "0.4.0"
        pair.watch.missingPermissions = { [.motion] }

        let id = pair.startRound()

        XCTAssertEqual(pair.phone.startStates[id], .needsWatchUpdate(watchVersion: "0.4.0"))
    }

    func testWatchMissingPermissionsRefusesTheRound() {
        pair.watch.missingPermissions = { [.motion, .health] }

        let id = pair.startRound()

        XCTAssertEqual(phoneRound(id)?.status, .starting)
        XCTAssertEqual(pair.phone.startStates[id], .needsPermissions([.motion, .health]))
        XCTAssertNil(watchRound(id))
        XCTAssertFalse(pair.watchStreams.hasStream(for: id))
    }

    func testRetryAfterGrantingPermissionsStartsTheRound() {
        pair.watch.missingPermissions = { [.location] }
        let id = pair.startRound()
        XCTAssertEqual(pair.phone.startStates[id], .needsPermissions([.location]))

        // A refused round waits for the user, even when the watch comes back in range
        pair.watch.missingPermissions = { [] }
        pair.setReachable(false)
        pair.setReachable(true)
        XCTAssertEqual(phoneRound(id)?.status, .starting)

        pair.phone.retryStart(id)

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(watchRound(id)?.status, .active)
        XCTAssertNil(pair.phone.startStates[id])
    }

    func testRefusedStartDoesNotTimeOut() {
        pair.cleanUp()
        pair = SyncPair(startTimeout: 0.05)
        pair.watch.missingPermissions = { [.motion] }
        let id = pair.startRound()

        let waited = expectation(description: "past the start timeout")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            waited.fulfill()
        }
        wait(for: [waited], timeout: 2)

        XCTAssertEqual(pair.phone.startStates[id], .needsPermissions([.motion]))
    }

    func testRoundAlreadyRecordingIsConfirmedWithoutAPermissionCheck() {
        let id = pair.startRound()
        XCTAssertEqual(watchRound(id)?.status, .active)
        var checks = 0
        pair.watch.missingPermissions = {
            checks += 1
            return [.motion]
        }

        // A repeat of the same start, after its confirmation was lost
        pair.phoneRounds.update(id) { $0.status = .starting }
        pair.phone.retryStart(id)

        XCTAssertEqual(checks, 0)
        XCTAssertEqual(phoneRound(id)?.status, .active)
    }

    func testRepeatedStartIsSafe() {
        // The watch starts the round, but its confirmation is lost
        pair.phoneTransport.dropsReplies = true
        let id = pair.startRound()
        XCTAssertEqual(watchRound(id)?.status, .active)
        XCTAssertEqual(phoneRound(id)?.status, .starting)

        pair.phoneTransport.dropsReplies = false
        pair.phone.retryStart(id)

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(pair.watchRounds.rounds.count, 1)
    }

    func testCancelDeletesRoundTheWatchDidStart() {
        pair.phoneTransport.dropsReplies = true
        let id = pair.startRound()
        XCTAssertNotNil(watchRound(id))

        pair.phoneTransport.dropsReplies = false
        pair.phone.cancelStart(id)

        XCTAssertNil(phoneRound(id))
        XCTAssertNil(watchRound(id))
        XCTAssertNil(pair.phone.startStates[id])
    }

    func testCancelReachesWatchThroughQueueWhenUnreachable() {
        pair.phoneTransport.dropsReplies = true
        let id = pair.startRound()
        pair.setReachable(false)

        pair.phone.cancelStart(id)
        XCTAssertNotNil(watchRound(id))

        pair.phoneTransport.deliverQueued()
        XCTAssertNil(watchRound(id))
    }

    func testLargeCourseIsSentInChunks() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Broadlands-Golf-Course.json", withExtension: "gz"))
        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: url).gzipDecompressed())
        let selection = CourseSelection(course: course, selectedSubCourseIndices: [0, 1])
        let size = try JSONEncoder().encode(selection.trimmed).gzipCompressed().count
        print("Broadlands trimmed, gzipped course: \(size) bytes")

        let id = pair.startRound(selection)

        let chunks = pair.phoneTransport.sentMessages { message -> SyncChunk? in
            if case .chunk(let chunk) = message { return chunk }
            return nil
        }
        XCTAssertEqual(chunks.count > 1, size > SyncCodec.maxMessageBytes)
        XCTAssertEqual(watchRound(id)?.course.name, course.name)
        XCTAssertEqual(phoneRound(id)?.status, .active)
    }

    func testLostChunkMeansNoConfirmationUntilRetry() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Broadlands-Golf-Course.json", withExtension: "gz"))
        let course = try JSONDecoder().decode(Course.self, from: Data(contentsOf: url).gzipDecompressed())
        let selection = CourseSelection(course: course, selectedSubCourseIndices: [0, 1])
        try XCTSkipUnless(try JSONEncoder().encode(selection.trimmed).gzipCompressed().count > SyncCodec.maxMessageBytes,
                          "The course fits in one message")

        pair.phoneTransport.holdsSends = true
        let id = pair.startRound(selection)
        XCTAssertGreaterThan(pair.phoneTransport.heldCount, 1)
        pair.phoneTransport.discardHeld(at: 0)
        pair.phoneTransport.releaseHeld(reversed: true)

        XCTAssertNil(watchRound(id))
        XCTAssertEqual(phoneRound(id)?.status, .starting)

        pair.phoneTransport.holdsSends = false
        pair.phone.retryStart(id)

        XCTAssertEqual(phoneRound(id)?.status, .active)
    }

    func testStartEndsAnotherRoundStillRecordingOnWatch() {
        let old = pair.watchRounds.startRound(courseSelection: .test).id
        // The watch can't send, so its stream for the round the phone doesn't know stays put
        pair.watchTransport.isReachable = false
        pair.watch.record(locations(0..<3))

        let id = pair.startRound()

        XCTAssertEqual(watchRound(old)?.status, .ended)
        XCTAssertEqual(watchRound(old)?.lastSeq, 2)
        XCTAssertEqual(watchRound(id)?.status, .active)
        XCTAssertEqual(pair.watchRounds.activeRound?.id, id)
    }

    func testResumedRoundContinuesStreamIndexes() throws {
        let id = pair.startRound()
        pair.watch.record(locations(0..<5))
        pair.phone.endRound(id)
        XCTAssertEqual(phoneRound(id)?.status, .ended)
        // Fully acknowledged, so the watch deleted its copy
        XCTAssertFalse(pair.watchStreams.hasStream(for: id))

        pair.phone.resumeRound(id)
        pair.watch.record(locations(10..<13))

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(watchRound(id)?.streamBase, 5)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 8)
    }

    // MARK: - Stream

    func testFixesStreamToPhoneAsRecorded() {
        let id = pair.startRound()

        pair.watch.record(locations(0..<10))

        XCTAssertEqual(pair.phoneStreams.records(for: id), pair.watchStreams.records(for: id))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 10)
        XCTAssertEqual(pair.watch.sender.cursors[id], 10)
    }

    func testRecordsWhileUnreachableCatchUpOnReconnect() {
        let id = pair.startRound()
        pair.setReachable(false)

        pair.watch.record(locations(0..<100))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 0)

        pair.setReachable(true)

        XCTAssertEqual(pair.phoneStreams.count(for: id), 100)
    }

    func testLargeBacklogIsSentInCappedBatches() {
        let id = pair.startRound()
        pair.setReachable(false)
        pair.watch.record(locations(0..<5_000))

        pair.setReachable(true)

        XCTAssertEqual(pair.phoneStreams.count(for: id), 5_000)
        let batches = pair.watchTransport.sentMessages { message -> StreamBatch? in
            if case .streamBatch(let batch) = message, !batch.records.isEmpty { return batch }
            return nil
        }
        XCTAssertGreaterThanOrEqual(batches.count, 4)
        XCTAssertTrue(batches.allSatisfy { $0.records.count <= StreamSender.maxBatchBytes })
    }

    func testLostBatchIsSentAgain() {
        let id = pair.startRound()
        pair.watchTransport.dropsSends = true
        pair.watch.record(locations(0..<5))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 0)

        pair.watchTransport.dropsSends = false
        pair.watch.record(locations(5..<6))

        XCTAssertEqual(pair.phoneStreams.records(for: id), pair.watchStreams.records(for: id))
    }

    func testLostReplyIsSentAgainAndOverlapIsSkipped() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<2))
        pair.watchTransport.dropsReplies = true
        pair.watch.record(locations(2..<5))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
        XCTAssertEqual(pair.watch.sender.cursors[id], 2)

        pair.watchTransport.dropsReplies = false
        pair.watch.record(locations(5..<6))

        XCTAssertEqual(pair.phoneStreams.count(for: id), 6)
        XCTAssertEqual(pair.phoneStreams.records(for: id), pair.watchStreams.records(for: id))
    }

    func testGapIsDiscardedAndFixedInOneRoundTrip() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<10))
        // The phone loses records it had already acknowledged
        pair.phoneStreams.truncate(id, to: 4)

        pair.watch.record(locations(10..<11))

        let batches = pair.watchTransport.sentMessages { message -> StreamBatch? in
            if case .streamBatch(let batch) = message { return batch }
            return nil
        }
        XCTAssertEqual(batches.suffix(2).map(\.from), [10, 4])
        XCTAssertEqual(pair.phoneStreams.records(for: id), pair.watchStreams.records(for: id))
    }

    func testPhoneRejectsBatchAfterGap() {
        let id = pair.phoneRounds.startRound(courseSelection: .test).id
        let batch = StreamBatch(roundID: id, from: 5, records: StreamRecord.data(for: StreamFixtures.fixes(5..<8)))

        let ack = pair.phone.receiver.receive(batch)

        XCTAssertEqual(ack, StreamAck(roundID: id, have: 0, haveLogs: 0))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 0)
    }

    func testRelaunchedWatchLearnsWhereToContinue() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<5))

        // A relaunch loses the cursor; the empty batch asks the phone for it
        let relaunched = WatchSync(sync: pair.watchSync, rounds: pair.watchRounds, streams: pair.watchStreams, logs: pair.watchLogs)
        XCTAssertNil(relaunched.sender.cursors[id])
        relaunched.sender.pump()

        XCTAssertEqual(relaunched.sender.cursors[id], 5)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
    }

    func testPhoneReachabilityTellsWatchWhereToContinue() {
        let id = pair.startRound()
        pair.watchTransport.dropsSends = true
        pair.watch.record(locations(0..<3))
        pair.watchTransport.dropsSends = false
        XCTAssertEqual(pair.phoneStreams.count(for: id), 0)

        // No new fix, but the phone's message restarts the watch's sending
        pair.phoneTransport.isReachable = false
        pair.phoneTransport.isReachable = true

        XCTAssertEqual(pair.phoneStreams.count(for: id), 3)
    }

    func testStreamForRoundPhoneDoesNotKnowIsDeleted() {
        let id = pair.watchRounds.startRound(courseSelection: .test).id

        pair.watch.record(locations(0..<3))

        XCTAssertFalse(pair.watchStreams.hasStream(for: id))
    }

    // MARK: - Log lines

    private func logLine(_ second: TimeInterval, _ message: String, device: LogDevice = .watch) -> LogLine {
        LogLine(timestamp: StreamFixtures.start.addingTimeInterval(second), device: device, level: .notice,
                category: "sensors", message: message)
    }

    private func logBatches() -> [StreamBatch] {
        pair.watchTransport.sentMessages { message -> StreamBatch? in
            if case .streamBatch(let batch) = message, batch.logs?.isEmpty == false { return batch }
            return nil
        }
    }

    func testWatchLogLinesReachThePhoneInOrder() {
        let id = pair.startRound()

        pair.watchLogs.append([logLine(0, "accelerometer on"), logLine(1, "first batch")], roundID: id)
        pair.watch.sender.pump()
        pair.watchLogs.append([logLine(2, "swing")], roundID: id)
        pair.watch.sender.pump()

        XCTAssertEqual(pair.phoneLogs.lines(for: id).map(\.message), ["accelerometer on", "first batch", "swing"])
        XCTAssertEqual(pair.phoneLogs.lines(for: id), pair.watchLogs.lines(for: id))
        XCTAssertEqual(pair.watch.sender.logCursors[id], 3)
    }

    func testLinesGoWithTheNextBatchAfterAFlush() {
        let id = pair.startRound()

        pair.watchLogs.enqueue(logLine(0, "queued"))
        XCTAssertTrue(pair.phoneLogs.lines(for: id).isEmpty)
        pair.watchLogs.flush()

        XCTAssertEqual(pair.phoneLogs.lines(for: id).map(\.message), [])
        // The flush assigns the round in progress, which the pair's store does not know; a line
        // for the round goes at once
        pair.watchLogs.roundIDForNewLines = { id }
        pair.watchLogs.enqueue(logLine(1, "in the round"))
        pair.watchLogs.flush()

        XCTAssertEqual(pair.phoneLogs.lines(for: id).map(\.message), ["in the round"])
    }

    func testLinesSentWhileUnreachableCatchUpOnReconnect() {
        let id = pair.startRound()
        pair.setReachable(false)
        pair.watchLogs.append((0..<500).map { logLine(TimeInterval($0), "line \($0)") }, roundID: id)
        pair.watch.sender.pump()
        XCTAssertTrue(pair.phoneLogs.lines(for: id).isEmpty)

        pair.setReachable(true)

        XCTAssertEqual(pair.phoneLogs.count(for: id, device: .watch), 500)
        XCTAssertEqual(pair.phoneLogs.lines(for: id), pair.watchLogs.lines(for: id))
        XCTAssertTrue(logBatches().allSatisfy { ($0.logs?.count ?? 0) <= StreamSender.maxBatchLines })
        XCTAssertGreaterThanOrEqual(logBatches().count, 3)
    }

    func testLostLogReplyIsSentAgainWithoutDuplicates() {
        let id = pair.startRound()
        pair.watchLogs.append([logLine(0, "a"), logLine(1, "b")], roundID: id)
        pair.watch.sender.pump()
        pair.watchTransport.dropsReplies = true
        pair.watchLogs.append([logLine(2, "c")], roundID: id)
        pair.watch.sender.pump()
        XCTAssertEqual(pair.phoneLogs.count(for: id, device: .watch), 3)
        XCTAssertEqual(pair.watch.sender.logCursors[id], 2)

        pair.watchTransport.dropsReplies = false
        pair.watchLogs.append([logLine(3, "d")], roundID: id)
        pair.watch.sender.pump()

        XCTAssertEqual(pair.phoneLogs.lines(for: id).map(\.message), ["a", "b", "c", "d"])
    }

    func testLogGapIsDiscardedAndFixedInOneRoundTrip() {
        let id = pair.startRound()
        pair.watchLogs.append((0..<5).map { logLine(TimeInterval($0), "line \($0)") }, roundID: id)
        pair.watch.sender.pump()
        // The phone loses lines it had already acknowledged
        pair.phoneLogs.delete(id)

        pair.watchLogs.append([logLine(5, "line 5")], roundID: id)
        pair.watch.sender.pump()

        XCTAssertEqual(logBatches().suffix(2).map(\.logsFrom), [5, 0])
        XCTAssertEqual(pair.phoneLogs.lines(for: id), pair.watchLogs.lines(for: id))
    }

    func testLinesAfterTheLastRecordStillArriveAndTheWatchThenDeletesBoth() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<3))
        pair.watchTransport.dropsSends = true
        pair.watchLogs.append([logLine(3, "workout ended")], roundID: id)
        pair.watch.sender.pump()

        pair.phone.endRound(id)
        XCTAssertEqual(phoneRound(id)?.status, .ended)
        // Every record is there, but not the line: the watch keeps both until the phone has all
        XCTAssertTrue(pair.watchLogs.hasLines(for: id))
        XCTAssertTrue(pair.watchStreams.hasStream(for: id))

        pair.watchTransport.dropsSends = false
        pair.watch.sender.pump()

        XCTAssertEqual(pair.phoneLogs.lines(for: id).map(\.message), ["workout ended"])
        XCTAssertFalse(pair.watchLogs.hasLines(for: id))
        XCTAssertFalse(pair.watchStreams.hasStream(for: id))
    }

    func testAckWithoutHaveLogsCountsTheLinesAsComplete() {
        let id = pair.startRound()
        pair.watchTransport.dropsSends = true
        pair.watchLogs.append([logLine(0, "a"), logLine(1, "b")], roundID: id)
        pair.watch.sender.pump()
        XCTAssertNil(pair.watch.sender.logCursors[id])

        // A phone from before the app log
        pair.watch.sender.handle(StreamAck(roundID: id, have: 0))

        XCTAssertEqual(pair.watch.sender.logCursors[id], 2)
    }

    func testResumedRoundContinuesLogNumbering() {
        let id = pair.startRound()
        pair.watchLogs.append([logLine(0, "a"), logLine(1, "b")], roundID: id)
        pair.watch.sender.pump()
        pair.phone.endRound(id)
        XCTAssertFalse(pair.watchLogs.hasLines(for: id))

        pair.phone.resumeRound(id)
        pair.watchLogs.append([logLine(10, "c")], roundID: id)
        pair.watch.sender.pump()

        XCTAssertEqual(watchRound(id)?.logBase, 2)
        XCTAssertEqual(pair.phoneLogs.lines(for: id).map(\.message), ["a", "b", "c"])
        XCTAssertEqual(pair.phoneLogs.count(for: id, device: .watch), 3)
    }

    func testWatchLinesFromJustBeforeTheRoundGoWithIt() {
        pair.watchLogs.append([LogLine(timestamp: Date().addingTimeInterval(-10 * 60), device: .watch, level: .notice,
                                       category: "workout", message: "old"),
                               LogLine(timestamp: Date().addingTimeInterval(-30), device: .watch, level: .notice,
                                       category: "workout", message: "launched by the phone")], roundID: nil)

        let id = pair.startRound()

        XCTAssertEqual(pair.phoneLogs.lines(for: id).map(\.message), ["launched by the phone"])
        XCTAssertEqual(pair.watchLogs.lines(for: nil).map(\.message), ["old"])
    }

    func testDebugLoggingSettingReachesTheWatch() {
        let was = Log.isDebugEnabled
        defer {
            Log.isDebugEnabled = was
            UserDefaults.standard.removeObject(forKey: WatchSync.debugLoggingKey)
        }
        pair.phone.debugLogging = { true }

        pair.startRound()

        XCTAssertTrue(Log.isDebugEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: WatchSync.debugLoggingKey))
    }

    func testCancelledRoundsLinesAreDeletedOnBothDevices() {
        let pair = SyncPair(startTimeout: 0.05)
        pair.phoneTransport.isReachable = false
        let id = pair.startRound()
        pair.phoneLogs.append([logLine(0, "starting", device: .phone)], roundID: id)
        // The watch did get a start from an earlier try that the phone never heard back from
        pair.watchLogs.append([logLine(0, "started")], roundID: id)

        pair.phone.cancelStart(id)
        pair.phoneTransport.isReachable = true
        pair.phoneTransport.deliverQueued()

        XCTAssertFalse(pair.phoneLogs.hasLines(for: id))
        XCTAssertFalse(pair.watchLogs.hasLines(for: id))
    }

    // MARK: - Swings

    func testSwingReachesThePhoneInTheStream() {
        let id = pair.startRound()
        let swing = StrokeSuggestion.swing(at: StreamFixtures.start.addingTimeInterval(2.5), peakG: 13)
        pair.watch.record(locations(0..<3))
        pair.watch.record(swing)
        pair.watch.record(locations(3..<5))

        XCTAssertEqual(pair.phoneStreams.swings(for: id), [swing])
    }

    /// The GPS path from hole 1's tee to its green, then to hole 2's tee.
    private func pathToSecondTee() -> [CLLocation] {
        var seconds: TimeInterval = 0
        func at(_ north: Double, _ east: Double) -> CLLocation {
            defer { seconds += 1 }
            let point = PathCourse.coordinate(north: north, east: east)
            return CLLocation(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                              altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 3,
                              timestamp: StreamFixtures.start.addingTimeInterval(seconds))
        }
        var path: [CLLocation] = []
        path += (0..<30).map { _ in at(0, 0) }                            // tee 1
        path += stride(from: 2.0, through: 300, by: 2).map { at($0, 0) }  // walk to green 1
        path += (0..<60).map { _ in at(300, 0) }                          // putting
        path += stride(from: 2.0, through: 60, by: 2).map { at(300, $0) } // walk to tee 2
        path += (0..<30).map { _ in at(300, 60) }                         // tee 2
        return path
    }

    // MARK: - End round: phone starts it

    func testPhoneEndWaitsForStreamThenEnds() {
        let id = pair.startRound()
        pair.watchTransport.dropsSends = true
        pair.watch.record(locations(0..<5))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 0)

        pair.phone.endRound(id)

        XCTAssertEqual(watchRound(id)?.status, .ended)
        XCTAssertEqual(phoneRound(id)?.status, .ending)
        XCTAssertEqual(phoneRound(id)?.lastSeq, 4)

        pair.watchTransport.dropsSends = false
        pair.watch.sender.pump()

        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
        XCTAssertFalse(pair.watchStreams.hasStream(for: id))
    }

    func testPhoneEndWithNoRecordsEndsAtOnce() {
        let id = pair.startRound()

        pair.phone.endRound(id)

        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertNil(phoneRound(id)?.lastSeq)
    }

    func testPhoneEndDropsWatchRecordsAfterEndTime() {
        let id = pair.startRound()
        let now = Date()
        pair.watch.record(locations(-5..<0, from: now))
        // The watch keeps recording past the phone's end time before it hears about it
        pair.phoneTransport.dropsSends = true
        pair.phone.endRound(id)
        pair.watch.record(locations(30..<35, from: now))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 10)

        pair.phoneTransport.dropsSends = false
        pair.setReachable(false)
        pair.setReachable(true)

        XCTAssertEqual(watchRound(id)?.lastSeq, 4)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
        XCTAssertEqual(phoneRound(id)?.status, .ended)
    }

    func testPhoneEndReachesUnreachableWatchThroughQueueAndCanBeForced() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<3))
        pair.setReachable(false)
        pair.watch.record(locations(3..<6))

        pair.phone.endRound(id)
        XCTAssertEqual(phoneRound(id)?.status, .ending)

        pair.phone.forceEnd(id)
        XCTAssertEqual(phoneRound(id)?.status, .ended)

        // The watch gets the end later; its remaining records up to the end time still arrive
        pair.phoneTransport.deliverQueued()
        XCTAssertEqual(watchRound(id)?.status, .ended)
        pair.setReachable(true)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 6)
    }

    func testRepeatedEndRequestGetsTheSameLastSeq() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<4))
        pair.phone.endRound(id)
        let request = EndRequest(roundID: id, endedAt: phoneRound(id)!.endedAt!)

        var replies: [SyncMessage] = []
        pair.phoneSync.send(.endRequest(request), reply: { replies.append($0) })
        pair.phoneSync.send(.endRequest(request), reply: { replies.append($0) })

        XCTAssertEqual(replies, Array(repeating: .endAck(EndAck(roundID: id, lastSeq: 3)), count: 2))
    }

    // MARK: - End round: watch starts it

    func testWatchEndTellsPhoneLastSeqAndPhoneDrains() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<3))
        pair.watchTransport.holdsSends = true
        pair.watch.record(locations(3..<6))

        pair.watch.endRound()

        XCTAssertEqual(watchRound(id)?.status, .ended)
        XCTAssertEqual(watchRound(id)?.lastSeq, 5)
        pair.watchTransport.holdsSends = false
        pair.watchTransport.releaseHeld(reversed: true)

        XCTAssertEqual(watchRound(id)?.endConfirmed, true)
        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 6)
        XCTAssertFalse(pair.watchStreams.hasStream(for: id))
    }

    func testWatchEndWhilePhoneUnreachableIsSentOnReconnect() {
        let id = pair.startRound()
        pair.setReachable(false)
        pair.watch.record(locations(0..<3))

        pair.watch.endRound()

        XCTAssertEqual(watchRound(id)?.status, .ended)
        XCTAssertEqual(watchRound(id)?.endConfirmed, false)
        XCTAssertEqual(phoneRound(id)?.status, .active)

        pair.setReachable(true)

        XCTAssertEqual(watchRound(id)?.endConfirmed, true)
        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 3)
    }

    func testWatchEndReachesPhoneThroughQueue() {
        let id = pair.startRound()
        pair.setReachable(false)
        pair.watch.endRound()

        pair.watchTransport.deliverQueued()

        XCTAssertEqual(phoneRound(id)?.status, .ended)
    }

    func testBothEndAtTheSameTime() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<4))
        pair.phoneTransport.holdsSends = true
        pair.watchTransport.holdsSends = true

        pair.phone.endRound(id)
        pair.watch.endRound()
        pair.phoneTransport.holdsSends = false
        pair.watchTransport.holdsSends = false
        pair.phoneTransport.releaseHeld()
        pair.watchTransport.releaseHeld()

        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertEqual(phoneRound(id)?.lastSeq, 3)
        XCTAssertEqual(watchRound(id)?.status, .ended)
        XCTAssertEqual(watchRound(id)?.endConfirmed, true)
    }

    func testEndForRoundWatchNoLongerKnowsKeepsPhoneRecords() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<5))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
        // The watch lost the round, for example because its saved rounds could not be read
        pair.watchRounds.deleteRound(id)

        pair.phone.endRound(id)

        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
    }

    func testQueuedEndRequestTellsPhoneTheLastRecord() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<3))
        pair.setReachable(false)
        pair.phone.endRound(id)
        XCTAssertEqual(phoneRound(id)?.status, .ending)

        // The request reaches the watch through the queue, which has no reply
        pair.phoneTransport.deliverQueued()
        XCTAssertEqual(watchRound(id)?.status, .ended)
        pair.watchTransport.deliverQueued()

        XCTAssertEqual(phoneRound(id)?.lastSeq, 2)
        XCTAssertEqual(phoneRound(id)?.status, .ended)
    }

    func testFailedEndRequestIsSentAgain() {
        pair.cleanUp()
        pair = SyncPair(retryDelay: 0.05)
        let id = pair.startRound()
        pair.watch.record(locations(0..<3))
        pair.phoneTransport.dropsSends = true

        pair.phone.endRound(id)
        XCTAssertEqual(phoneRound(id)?.status, .ending)
        pair.phoneTransport.dropsSends = false

        let ended = expectation(description: "round ended")
        Task { @MainActor in
            while phoneRound(id)?.status != .ended {
                try? await Task.sleep(for: .milliseconds(10))
            }
            ended.fulfill()
        }
        wait(for: [ended], timeout: 2)
        XCTAssertEqual(phoneRound(id)?.lastSeq, 2)
    }

    func testReplyWithNoMessageDoesNotStopTheStream() {
        _ = pair.startRound()
        // The phone answers with nothing
        pair.phoneSync.handler = { _ in nil }

        pair.watch.record(locations(0..<3))

        XCTAssertFalse(pair.watch.sender.isInFlight)
    }

    func testWatchDeletesRoundsThePhoneHasFullyAfterADay() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<3))
        pair.phone.endRound(id)
        XCTAssertFalse(pair.watchStreams.hasStream(for: id))

        pair.watch.pruneFinishedRounds()
        XCTAssertNotNil(watchRound(id))

        pair.watch.pruneFinishedRounds(now: Date().addingTimeInterval(WatchSync.finishedRoundKeepTime + 60))
        XCTAssertNil(watchRound(id))
    }

    // MARK: - Resume

    func testCancelledResumeKeepsTheRound() throws {
        let id = pair.startRound()
        pair.watch.record(locations(0..<5))
        pair.phone.endRound(id)
        let endedAt = try XCTUnwrap(phoneRound(id)?.endedAt)
        pair.setReachable(false)

        pair.phone.resumeRound(id)
        XCTAssertEqual(phoneRound(id)?.status, .starting)
        pair.phone.cancelStart(id)

        XCTAssertEqual(phoneRound(id)?.status, .ended)
        XCTAssertEqual(phoneRound(id)?.endedAt, endedAt)
        XCTAssertNil(phoneRound(id)?.resumedFromEnd)
        XCTAssertEqual(pair.phoneStreams.count(for: id), 5)
        XCTAssertTrue(pair.phoneTransport.sentMessages { message -> CancelRound? in
            if case .cancelRound(let cancel) = message { return cancel }
            return nil
        }.isEmpty)
    }

    // MARK: - Strokes

    func testStrokesReachWatchAndOlderSnapshotIsIgnored() throws {
        let id = pair.startRound()
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: -105.0))
        pair.phoneTransport.holdsSends = true

        pair.phoneRounds.addStroke(to: id, holeIndex: 0, stroke: stroke)
        pair.phoneRounds.moveStroke(stroke, to: CLLocationCoordinate2D(latitude: 39.91, longitude: -105.0), in: id)
        pair.phoneTransport.holdsSends = false
        pair.phoneTransport.releaseHeld(reversed: true)

        let watch = try XCTUnwrap(watchRound(id))
        XCTAssertEqual(watch.strokesVersion, 2)
        XCTAssertEqual(watch.displayHoleStrokes.first?.latitude, 39.91)
    }

    func testDeleteBeforeAddCannotBringStrokeBack() {
        let id = pair.startRound()
        let stroke = Stroke(coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: -105.0))
        pair.phoneTransport.holdsSends = true

        pair.phoneRounds.addStroke(to: id, holeIndex: 0, stroke: stroke)
        pair.phoneRounds.removeStroke(stroke, from: id)
        pair.phoneTransport.holdsSends = false
        pair.phoneTransport.releaseHeld(reversed: true)

        XCTAssertEqual(watchRound(id)?.allStrokes, [])
        XCTAssertEqual(watchRound(id)?.strokesVersion, 2)
    }

    func testLostSnapshotIsFixedByTheNext() {
        let id = pair.startRound()
        pair.phoneTransport.dropsSends = true
        pair.phoneRounds.addStroke(to: id, holeIndex: 0, stroke: Stroke(coordinate: .init(latitude: 39.9, longitude: -105)))
        XCTAssertEqual(watchRound(id)?.allStrokes.count, 0)

        pair.phoneTransport.dropsSends = false
        pair.phoneRounds.addStroke(to: id, holeIndex: 1, stroke: Stroke(coordinate: .init(latitude: 39.8, longitude: -105)))

        XCTAssertEqual(watchRound(id)?.allStrokes.count, 2)
    }

    func testContextDeliversStrokesWhileUnreachable() {
        let id = pair.startRound()
        pair.setReachable(false)
        pair.phoneRounds.addStroke(to: id, holeIndex: 0, stroke: Stroke(coordinate: .init(latitude: 39.9, longitude: -105)))

        pair.phoneTransport.deliverContext()

        XCTAssertEqual(watchRound(id)?.allStrokes.count, 1)
    }

    // MARK: - Display hole

    func testDisplayHoleChangeOnWatchReachesPhone() {
        let id = pair.startRound()

        pair.watchRounds.setDisplayHole(1)

        XCTAssertEqual(phoneRound(id)?.displayHoleIndex, 1)
        XCTAssertEqual(phoneRound(id)?.displayHole, watchRound(id)?.displayHole)
        // The timeline is set by strokes, not by the hole shown
        XCTAssertEqual(phoneRound(id)?.holeTimeline.count, 1)
    }

    func testDisplayHoleChangeOnPhoneReachesWatch() {
        let id = pair.startRound()

        pair.phoneRounds.setDisplayHole(3, roundID: id)

        XCTAssertEqual(watchRound(id)?.displayHoleIndex, 3)
    }

    func testLaterDisplayHoleChangeWinsOnBoth() {
        let id = pair.startRound()
        let now = Date()
        pair.phoneTransport.holdsSends = true
        pair.watchTransport.holdsSends = true

        pair.phoneRounds.setDisplayHole(6, roundID: id, at: now)
        pair.watchRounds.setDisplayHole(1, at: now.addingTimeInterval(1))
        pair.phoneTransport.holdsSends = false
        pair.watchTransport.holdsSends = false
        pair.phoneTransport.releaseHeld()
        pair.watchTransport.releaseHeld()

        XCTAssertEqual(phoneRound(id)?.displayHoleIndex, 1)
        XCTAssertEqual(watchRound(id)?.displayHoleIndex, 1)
    }

    func testDisplayHoleContextReachesPhone() {
        let id = pair.startRound()
        pair.setReachable(false)
        pair.watchRounds.setDisplayHole(1)

        pair.watchTransport.deliverContext()

        XCTAssertEqual(phoneRound(id)?.displayHoleIndex, 1)
    }

    func testResumedRoundShowsTheSameHoleOnTheWatch() {
        let id = pair.startRound()
        pair.phone.endRound(id)
        pair.phoneRounds.setDisplayHole(4, roundID: id)

        pair.phone.resumeRound(id)

        XCTAssertEqual(phoneRound(id)?.status, .active)
        XCTAssertEqual(watchRound(id)?.displayHoleIndex, 4)
    }

    // MARK: - Pins

    private func onGreen(_ hole: Int, east: Double = 0) -> CLLocationCoordinate2D {
        let green = PathCourse.greens[hole]
        return PathCourse.coordinate(north: green.north, east: green.east + east).clLocation.coordinate
    }

    func testStartedRoundHasCenterPinsOnBothDevices() {
        let id = pair.startRound(PathCourse.selection)

        XCTAssertEqual(phoneRound(id)?.pins.map(\.source), [.center, .center, .center])
        XCTAssertEqual(watchRound(id)?.pins, phoneRound(id)?.pins)
    }

    func testPinSetOnWatchReachesPhone() {
        let id = pair.startRound(PathCourse.selection)

        pair.watchRounds.setPin(onGreen(1), holeIndex: 1)

        XCTAssertNotNil(phoneRound(id)?.pin(onHole: 1))
        XCTAssertEqual(phoneRound(id)?.pins, watchRound(id)?.pins)
    }

    func testPinSetOnPhoneReachesWatch() {
        let id = pair.startRound(PathCourse.selection)

        pair.phoneRounds.setPin(onGreen(2), holeIndex: 2, roundID: id)

        XCTAssertNotNil(watchRound(id)?.pin(onHole: 2))
        XCTAssertEqual(watchRound(id)?.pins, phoneRound(id)?.pins)
    }

    func testPinContextReachesPhone() {
        let id = pair.startRound(PathCourse.selection)
        pair.setReachable(false)
        pair.watchRounds.setPin(onGreen(0), holeIndex: 0)

        pair.watchTransport.deliverContext()

        XCTAssertEqual(phoneRound(id)?.pins, watchRound(id)?.pins)
    }

    func testResumedRoundKeepsItsPinsOnTheWatch() {
        let id = pair.startRound(PathCourse.selection)
        pair.watchRounds.setPin(onGreen(2), holeIndex: 2)
        pair.phone.endRound(id)
        pair.watchRounds.deleteRound(id)

        pair.phone.resumeRound(id)

        XCTAssertEqual(watchRound(id)?.pins, phoneRound(id)?.pins)
        XCTAssertNotNil(watchRound(id)?.pin(onHole: 2))
    }

    // MARK: - Hole timeline

    private func stroke() -> Stroke {
        Stroke(coordinate: .init(latitude: 39.9, longitude: -105))
    }

    func testFirstStrokeOnAHoleStartsItOnBothDevices() {
        let id = pair.startRound()
        let hitAt = Date().addingTimeInterval(600)

        pair.phoneRounds.addStroke(to: id, holeIndex: 1, stroke: stroke(), hitAt: hitAt)

        XCTAssertEqual(watchRound(id)?.holeTimeline.map(\.holeIndex), [0, 1])
        XCTAssertEqual(watchRound(id)?.holeTimeline.last?.startedAt, hitAt)
        XCTAssertEqual(watchRound(id)?.holeTimeline, phoneRound(id)?.holeTimeline)
        XCTAssertEqual(watchRound(id)?.allStrokes.count, 1)
    }

    func testStartTimeSetByHandReachesWatch() throws {
        let id = pair.startRound()
        let hitAt = Date().addingTimeInterval(600)
        pair.phoneRounds.addStroke(to: id, holeIndex: 1, stroke: stroke(), hitAt: hitAt)
        let entry = try XCTUnwrap(phoneRound(id)?.holeTimeline.last)

        pair.phoneRounds.setStartTime(hitAt.addingTimeInterval(-60), entryID: entry.id, roundID: id)

        XCTAssertEqual(watchRound(id)?.holeTimeline.last?.startedAt, hitAt.addingTimeInterval(-60))
        XCTAssertEqual(watchRound(id)?.holeTimeline.last?.source, .userSet)
    }

    func testTimelineContextReachesWatch() {
        let id = pair.startRound()
        pair.setReachable(false)
        pair.phoneRounds.addStroke(to: id, holeIndex: 1, stroke: stroke(), hitAt: Date().addingTimeInterval(600))

        pair.phoneTransport.deliverContext()

        XCTAssertEqual(watchRound(id)?.holeTimeline.map(\.holeIndex), [0, 1])
    }

    // MARK: - Import

    private func importedRound() -> (round: Round, records: [StreamRecord]) {
        var round = Round(date: StreamFixtures.start, courseSelection: .test)
        round.ensureHole(0)
        let records = locations(0..<10).map { StreamRecord.fix(TrackPoint(location: $0)) } +
            [StreamRecord.swing(StrokeSuggestion.swing(at: StreamFixtures.start.addingTimeInterval(9.5), peakG: 13))]
        return (round, records.sorted { $0.timestamp < $1.timestamp })
    }

    func testImportedRoundStaysActiveAndKeepsItsTimeline() {
        var round = Round(date: StreamFixtures.start, courseSelection: PathCourse.selection)
        round.startHole(1, at: StreamFixtures.start.addingTimeInterval(400), source: .estimated)
        let records = pathToSecondTee().map { StreamRecord.fix(TrackPoint(location: $0)) }

        XCTAssertTrue(pair.phone.importRound(round, records: records))

        XCTAssertEqual(phoneRound(round.id)?.status, .active)
        XCTAssertEqual(pair.phoneStreams.count(for: round.id), records.count)
        XCTAssertEqual(phoneRound(round.id)?.holeTimeline, round.holeTimeline)
    }

    func testImportIsRefusedWhileAnotherRoundIsInProgress() {
        pair.startRound()
        let (round, records) = importedRound()

        XCTAssertFalse(pair.phone.importRound(round, records: records))

        XCTAssertNil(phoneRound(round.id))
        XCTAssertFalse(pair.phoneStreams.hasStream(for: round.id))
    }
}
