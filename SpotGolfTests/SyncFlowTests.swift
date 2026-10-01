import XCTest
import CoreLocation
import CourseDataSwift
@testable import SpotGolf

/// A phone and a watch talking through fake transports: every flow in the messaging plan,
/// with lost, repeated, late, and out-of-order messages.
@MainActor
final class SyncFlowTests: XCTestCase {

    private var pair: SyncPair!

    override func setUp() {
        super.setUp()
        pair = SyncPair()
    }

    override func tearDown() {
        pair.cleanUp()
        pair = nil
        super.tearDown()
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

        XCTAssertEqual(ack, StreamAck(roundID: id, have: 0))
        XCTAssertEqual(pair.phoneStreams.count(for: id), 0)
    }

    func testRelaunchedWatchLearnsWhereToContinue() {
        let id = pair.startRound()
        pair.watch.record(locations(0..<5))

        // A relaunch loses the cursor; the empty batch asks the phone for it
        let relaunched = WatchSync(sync: pair.watchSync, rounds: pair.watchRounds, streams: pair.watchStreams)
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

    func testStreamedPathStartsTheNextHoleWhenThePlayerLeavesTheGreen() throws {
        let id = pair.startRound(PathCourse.selection)
        // The round starts when the fixtures do. A higher version, so the watch takes it too.
        pair.phoneRounds.update(id) { round in
            round.holeTimeline[0].startedAt = StreamFixtures.start
            round.holeTimeline[0].version += 1
        }
        let path = pathToSecondTee()

        pair.watch.record(path)

        let round = try XCTUnwrap(phoneRound(id))
        XCTAssertEqual(round.holeTimeline.map(\.holeIndex), [0, 1])
        // Green 1 is 30 m wide, so the last fix within 10 m of its edge is 25 m east of its center
        let leftGreen = try XCTUnwrap(path.first { $0.coordinate.longitude > PathCourse.coordinate(north: 300, east: 25).longitude })
        XCTAssertEqual(round.holeTimeline[1].startedAt, leftGreen.timestamp)
        XCTAssertEqual(watchRound(id)?.holeTimeline.map(\.holeIndex), [0, 1])
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
        XCTAssertEqual(watch.strokes.first?.latitude, 39.91)
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

    // MARK: - Hole timeline

    func testHoleChangeOnWatchReachesPhone() {
        let id = pair.startRound()

        pair.watchRounds.startHole(1, source: .autoAdvance)

        XCTAssertEqual(phoneRound(id)?.currentHoleIndex, 1)
        XCTAssertEqual(phoneRound(id)?.holeTimeline, watchRound(id)?.holeTimeline)
    }

    func testEarlierHoleCannotBePlayed() {
        let id = pair.startRound()
        pair.phoneRounds.startHole(5, source: .playHole)

        pair.phoneRounds.startHole(3, source: .playHole)
        pair.watchRounds.startHole(2, source: .autoAdvance)

        XCTAssertEqual(phoneRound(id)?.currentHoleIndex, 5)
        XCTAssertEqual(watchRound(id)?.currentHoleIndex, 5)
    }

    func testHoleChangesAtTheSameTimeEndTheSameOnBoth() {
        let id = pair.startRound()
        let now = Date()
        pair.phoneTransport.holdsSends = true
        pair.watchTransport.holdsSends = true

        pair.phoneRounds.startHole(6, at: now, source: .playHole)
        pair.watchRounds.startHole(1, at: now.addingTimeInterval(1), source: .autoAdvance)
        pair.phoneTransport.holdsSends = false
        pair.watchTransport.holdsSends = false
        pair.phoneTransport.releaseHeld()
        pair.watchTransport.releaseHeld()

        XCTAssertEqual(phoneRound(id)?.holeTimeline.map(\.holeIndex), [0, 6])
        XCTAssertEqual(watchRound(id)?.holeTimeline.map(\.holeIndex), [0, 6])
    }

    func testTimelineContextReachesPhone() {
        let id = pair.startRound()
        pair.setReachable(false)
        pair.watchRounds.startHole(1, source: .autoAdvance)

        pair.watchTransport.deliverContext()

        XCTAssertEqual(phoneRound(id)?.currentHoleIndex, 1)
    }

    // MARK: - Import

    private func importedRound() -> (round: Round, records: [StreamRecord]) {
        var round = Round(date: StreamFixtures.start, courseSelection: .test)
        round.ensureHole(0)
        let records = locations(0..<10).map { StreamRecord.fix(TrackPoint(location: $0)) } +
            [StreamRecord.swing(StrokeSuggestion.swing(at: StreamFixtures.start.addingTimeInterval(9.5), peakG: 13))]
        return (round, records.sorted { $0.timestamp < $1.timestamp })
    }

    func testImportedRoundStaysActiveAndGetsItsHoleStartsFromThePath() {
        let round = Round(date: StreamFixtures.start, courseSelection: PathCourse.selection)
        let records = pathToSecondTee().map { StreamRecord.fix(TrackPoint(location: $0)) }

        XCTAssertTrue(pair.phone.importRound(round, records: records))

        XCTAssertEqual(phoneRound(round.id)?.status, .active)
        XCTAssertEqual(pair.phoneStreams.count(for: round.id), records.count)
        XCTAssertEqual(phoneRound(round.id)?.holeTimeline.map(\.holeIndex), [0, 1])
    }

    func testImportIsRefusedWhileAnotherRoundIsInProgress() {
        pair.startRound()
        let (round, records) = importedRound()

        XCTAssertFalse(pair.phone.importRound(round, records: records))

        XCTAssertNil(phoneRound(round.id))
        XCTAssertFalse(pair.phoneStreams.hasStream(for: round.id))
    }
}
